begin;
do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000776';
  v_readonly uuid := '00000000-0000-4000-8000-000000007776';
  v_output bigint; v_input bigint; v_unit bigint; v_formula bigint;
  v_op_manual bigint; v_op_auto bigint; v_component_manual bigint; v_component_auto bigint;
  v_old_lot bigint; v_new_lot bigint; v_reservation bigint; v_count integer;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'FIFO reviewer', 'admin', 'active') on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
    (v_actor, 'system.admin', true, v_actor), (v_actor, 'pcp.formula.create', true, v_actor),
    (v_actor, 'pcp.formula.change', true, v_actor), (v_actor, 'pcp.op.create', true, v_actor),
    (v_actor, 'pcp.op.reserve_components', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', '0076 disposable FIFO smoke');
  elsif public.current_system_environment() <> 'test' then raise exception '0076 smoke requires test environment'; end if;
  delete from public.user_permission_overrides
    where user_id = v_actor and action_key = 'system.admin';

  insert into public.cad_produtos_base(codigo_produto,nome,nome_norm,status,payload_origem_json,created_by,updated_by,origem_dados)
  values ('9876','FIFO output','fifo output','active','{}',v_actor,v_actor,'sistema') returning id into v_output;
  insert into public.cad_produtos_base(codigo_produto,nome,nome_norm,status,payload_origem_json,created_by,updated_by,origem_dados)
  values ('9877','FIFO input','fifo input','active','{}',v_actor,v_actor,'sistema') returning id into v_input;
  select id into v_unit from public.cad_unidades_medida where codigo = 'l_l_produzido';
  v_formula := public.create_pcp_formula_versao(v_output,'producao','FIFO formula',jsonb_build_array(
    jsonb_build_object('tipo_componente','PI','produto_id',v_input,'quantidade',0.012,'unidade_id',v_unit)),null);

  insert into public.est_lotes_pi(produto_id,codigo_lote,status,created_by,updated_by,created_at)
  values (v_input,'FIFO-OLD','disponivel',v_actor,v_actor,'2026-01-01') returning id into v_old_lot;
  insert into public.est_movimentos_pi(lote_pi_id,produto_id,tipo_movimento,quantidade,origem_modulo,created_by,created_at)
  values (v_old_lot,v_input,'entrada_producao',10,'test',v_actor,'2026-01-01');
  insert into public.est_lotes_pi(produto_id,codigo_lote,status,created_by,updated_by,created_at)
  values (v_input,'FIFO-NEW','disponivel',v_actor,v_actor,'2026-02-01') returning id into v_new_lot;
  insert into public.est_movimentos_pi(lote_pi_id,produto_id,tipo_movimento,quantidade,origem_modulo,created_by,created_at)
  values (v_new_lot,v_input,'entrada_producao',10,'test',v_actor,'2026-02-01');

  v_op_manual := public.create_pcp_op(v_formula,'estoque',416.6666666667,null);
  select id into v_component_manual from public.pcp_op_componentes_planejados where op_id = v_op_manual;
  begin
    perform public.reservar_pcp_op_componente(v_component_manual,null,null,v_new_lot,5,'Tentativa sem alcada');
    raise exception 'FIFO override without permission should fail';
  exception when others then
    if sqlerrm not like 'not allowed:%' then raise; end if;
  end;
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  values(v_actor,'pcp.op.reserve_override_fifo',true,v_actor)
  on conflict(user_id,action_key) do update set allowed=true,updated_by=excluded.updated_by;
  v_reservation := public.reservar_pcp_op_componente(
    v_component_manual,null,null,v_new_lot,5,'Lote novo exigido por teste controlado');
  if not exists(select 1 from public.pcp_op_reservas_componentes
    where id=v_reservation and fifo_desviado and ordem_fifo=2 and fifo_justificativa is not null) then
    raise exception 'governed FIFO override evidence not recorded'; end if;

  v_op_auto := public.create_pcp_op(v_formula,'estoque',1000,null);
  select id into v_component_auto from public.pcp_op_componentes_planejados where op_id = v_op_auto;
  v_count := public.reservar_pcp_op_componente_fifo(v_component_auto);
  if v_count <> 2 then raise exception 'FIFO should distribute over 2 lots, got %',v_count; end if;
  if (select sum(quantidade_reservada) from public.pcp_op_reservas_componentes
      where op_componente_id=v_component_auto and status='ativa') <> 12 then
    raise exception 'FIFO total reservation mismatch'; end if;
  if not exists(select 1 from public.action_logs where action='pcp.op_fifo_override' and entity_id=v_reservation::text) then
    raise exception 'FIFO override audit not found'; end if;

  insert into auth.users(id) values (v_readonly) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_readonly, 'FIFO read-only reviewer', 'admin', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
    (v_readonly, 'pcp.op.create', false, v_actor),
    (v_readonly, 'pcp.op.reserve_components', false, v_actor),
    (v_readonly, 'pcp.op.reserve_override_fifo', false, v_actor),
    (v_readonly, 'pcp.op.start', false, v_actor),
    (v_readonly, 'pcp.op.cancel', false, v_actor)
  on conflict (user_id, action_key) do update set allowed = false, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_readonly::text, true);

  if not exists(select 1 from public.pcp_ordens_producao where id = v_op_auto) then
    raise exception 'read-only actor cannot consult the production order';
  end if;
  if public.can_current_user('pcp.op.create')
     or public.can_current_user('pcp.op.reserve_components')
     or public.can_current_user('pcp.op.reserve_override_fifo')
     or public.can_current_user('pcp.op.start')
     or public.can_current_user('pcp.op.cancel') then
    raise exception 'read-only actor received an operational production capability';
  end if;

  begin
    perform public.create_pcp_op_idempotente(
      '76000000-0000-4000-8000-000000007776', v_formula, 'estoque', 1, 'Tentativa sem alcada'
    );
    raise exception 'read-only actor created a production order';
  exception when others then
    if sqlerrm not like 'not allowed:%' then raise; end if;
  end;
  begin
    perform public.reservar_pcp_op_componente_fifo(v_component_auto);
    raise exception 'read-only actor reserved a production component';
  exception when others then
    if sqlerrm not like 'not allowed:%' then raise; end if;
  end;
  begin
    perform public.iniciar_pcp_op(v_op_auto, 'Tentativa sem alcada');
    raise exception 'read-only actor started a production order';
  exception when others then
    if sqlerrm not like 'not allowed:%' then raise; end if;
  end;
  begin
    perform public.cancelar_pcp_op(v_op_auto, 'Tentativa sem alcada');
    raise exception 'read-only actor cancelled a production order';
  exception when others then
    if sqlerrm not like 'not allowed:%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if has_function_privilege('authenticated','public.reservar_pcp_op_componente_impl_0076(bigint,bigint,bigint,bigint,numeric,text)','EXECUTE')
    or has_function_privilege('anon','public.reservar_pcp_op_componente_fifo(bigint)','EXECUTE') then
    raise exception 'internal implementation or anonymous FIFO RPC remains exposed'; end if;
end;
$$;
rollback;
select 'PG_VALIDATE_0076_PCP_FIFO_COMPONENT_RESERVATION_OK' result;
