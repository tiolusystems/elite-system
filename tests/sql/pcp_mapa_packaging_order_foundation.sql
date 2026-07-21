\set ON_ERROR_STOP on

begin;

do $smoke$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000069';
  v_unit_un bigint;
  v_material_id bigint;
  v_product_id bigint;
  v_package_id bigint;
  v_sale_item_id bigint;
  v_package_version_id bigint;
  v_formula_id bigint;
  v_pi_lot_id bigint;
  v_mp_lot_id bigint;
  v_packaging_order_id bigint;
  v_packaging_plan_id bigint;
  v_pi_movement_count integer;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Packaging Order Smoke Actor', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor from public.permission_actions action
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform public.set_system_runtime_environment('test', 'test_reset', 'Smoke transacional da migration 0069');

  select id into v_unit_un from public.cad_unidades_medida where upper(codigo) = 'UN' and status = 'active';
  if v_unit_un is null then raise exception 'canonical UN unit not found'; end if;

  v_material_id := public.create_cad_materia_prima_governada(
    p_nome => 'Embalagem sintetica 0069',
    p_nome_norm => 'EMBALAGEM SINTETICA 0069',
    p_sku_corrigido => 'MP-0069-EMB',
    p_unidade_base_estoque_id => v_unit_un,
    p_status => 'active'
  );
  v_product_id := public.create_cad_produto_base(
    p_codigo_produto => '0691', p_nome => 'Produto sintetico 0069',
    p_nome_norm => 'PRODUTO SINTETICO 0069', p_status => 'active',
    p_prazo_validade_meses => 24
  );
  v_package_id := public.create_cad_embalagem(
    p_descricao => 'Galao sintetico 5 L 0069',
    p_descricao_norm => 'GALAO SINTETICO 5 L 0069',
    p_unidade => 'UN', p_status => 'active', p_volume_litros => 5,
    p_controla_estoque => true, p_materia_prima_id => v_material_id
  );
  v_sale_item_id := public.create_cad_produto_embalagem(
    v_product_id, v_package_id, '0691-5L', 'active'
  );
  v_package_version_id := public.create_cad_embalagem_versao_un_l(
    v_package_id, date '2026-01-01', null, 0.25, 0.02,
    'Composicao sintetica da ordem de envase'
  );
  perform public.add_cad_embalagem_componente_un_l(
    v_package_version_id, v_material_id, 0.2,
    'Uma embalagem para cada cinco litros'
  );
  perform public.review_cad_embalagem_versao(
    v_package_version_id, 'approved', 'Composicao sintetica conferida'
  );
  perform public.activate_cad_embalagem_versao(
    v_package_version_id, true, 'Ativacao sintetica para envase'
  );

  v_formula_id := public.create_pcp_formula_versao(
    v_product_id, 'mapa', 'Formula MAPA documental sintetica', '[]'::jsonb,
    'Sem consumo fisico de MP'
  );
  perform public.activate_pcp_formula_versao(v_formula_id, 'Formula MAPA aprovada para o smoke');

  v_pi_lot_id := public.create_est_lote_pi(
    p_produto_id => v_product_id,
    p_quantidade_entrada => 100,
    p_tipo_entrada => 'entrada_producao',
    p_status => 'disponivel',
    p_origem_ref => 'pcp-smoke-0069'
  );
  v_mp_lot_id := public.create_est_lote_mp(
    p_materia_prima_id => v_material_id,
    p_quantidade_entrada => 10,
    p_codigo_lote => 'MP-ENV-0069',
    p_tipo_entrada => 'importacao_inicial',
    p_status => 'disponivel',
    p_origem_ref => 'pcp-smoke-0069'
  );
  select count(*) into v_pi_movement_count
    from public.est_movimentos_pi where lote_pi_id = v_pi_lot_id;

  v_packaging_order_id := public.emitir_pcp_op_mapa_com_envase(
    v_formula_id, v_pi_lot_id, v_sale_item_id, 20,
    'elite-validation-0069', 'Emissao sintetica controlada'
  );

  if not exists (
    select 1
      from public.pcp_ordens_envase packaging_order
      join public.pcp_ordens_producao mapa_op on mapa_op.id = packaging_order.op_mapa_id
     where packaging_order.id = v_packaging_order_id
       and packaging_order.status = 'emitida'
       and packaging_order.quantidade_pa_planejada = 4
       and mapa_op.tipo_op = 'mapa_documental'
       and mapa_op.status = 'completed'
  ) then raise exception 'MAPA OP and packaging order were not emitted atomically'; end if;

  if not exists (
    select 1 from public.pcp_ordem_envase_embalagens component
     where component.ordem_envase_id = v_packaging_order_id
       and component.materia_prima_id = v_material_id
       and component.quantidade_planejada = 4
  ) then raise exception 'governed packaging BOM was not snapshotted'; end if;
  select id into v_packaging_plan_id
    from public.pcp_ordem_envase_embalagens
   where ordem_envase_id = v_packaging_order_id and materia_prima_id = v_material_id;

  if (select count(*) from public.est_movimentos_pi where lote_pi_id = v_pi_lot_id) <> v_pi_movement_count then
    raise exception 'emission moved PI stock before reservation/finalization contract';
  end if;
  if exists (
    select 1 from public.est_movimentos_mp movement
     where movement.origem_tabela = 'pcp_ordens_envase'
       and movement.origem_id = v_packaging_order_id::text
  ) then raise exception 'emission moved packaging stock prematurely'; end if;

  begin
    perform public.emitir_pcp_op_mapa_com_envase(
      v_formula_id, v_pi_lot_id, v_sale_item_id, 90,
      'elite-validation-0069', 'Tentativa acima do saldo restante'
    );
    raise exception 'overcommitted PI volume was accepted';
  exception when others then
    if sqlerrm = 'overcommitted PI volume was accepted' then raise; end if;
    if position('insufficient available PI balance after issued packaging orders' in sqlerrm) = 0 then raise; end if;
  end;

  perform public.reservar_pcp_ordem_envase_embalagem(v_packaging_plan_id, v_mp_lot_id, 4);
  perform public.iniciar_pcp_ordem_envase(v_packaging_order_id);
  perform public.finalizar_pcp_ordem_envase(
    v_packaging_order_id,
    '[{"quantidade": 2, "observacao": "Lote PA sintetico A"}, {"quantidade": 2, "observacao": "Lote PA sintetico B"}]'::jsonb,
    'Finalizacao sintetica controlada'
  );

  if (select status from public.pcp_ordens_envase where id = v_packaging_order_id) <> 'finalizada' then
    raise exception 'packaging order did not finish';
  end if;
  if (select saldo_fisico from public.est_lotes_pi_saldos where lote_pi_id = v_pi_lot_id) <> 80 then
    raise exception 'PI consumption does not match 20 liters';
  end if;
  if (select saldo_fisico from public.est_lotes_mp_saldos where lote_mp_id = v_mp_lot_id) <> 6 then
    raise exception 'packaging consumption does not match four units';
  end if;
  if (select coalesce(sum(quantidade), 0) from public.pcp_ordem_envase_lotes_pa where ordem_envase_id = v_packaging_order_id) <> 4 then
    raise exception 'PA outputs do not match planned finished packages';
  end if;
  if (select count(*) from public.pcp_ordem_envase_lotes_pa where ordem_envase_id = v_packaging_order_id) <> 2 then
    raise exception 'multiple destination PA lots were not preserved';
  end if;
  if exists (
    select 1 from public.pcp_ordem_envase_reservas
     where ordem_envase_id = v_packaging_order_id and status = 'ativa'
  ) then raise exception 'active reservations remained after packaging completion'; end if;

  if not exists (
    select 1 from public.action_logs log
     where log.action_key = 'pcp.envase.issue'
       and log.entity_id = v_packaging_order_id::text
       and log.status = 'success'
  ) then raise exception 'packaging order audit event was not recorded'; end if;
end;
$smoke$;

do $privileges$
begin
  if has_function_privilege(
    'anon',
    'public.emitir_pcp_op_mapa_com_envase(bigint,bigint,bigint,numeric,text,text)',
    'EXECUTE'
  ) then raise exception 'anon retained packaging order execution'; end if;
  if exists (
    select 1
      from pg_proc function_definition
      cross join lateral aclexplode(coalesce(function_definition.proacl, acldefault('f', function_definition.proowner))) function_acl
     where function_definition.oid = to_regprocedure(
       'public.emitir_pcp_op_mapa_com_envase(bigint,bigint,bigint,numeric,text,text)'
     )
       and function_acl.grantee = 0
       and function_acl.privilege_type = 'EXECUTE'
  ) then raise exception 'PUBLIC retained packaging order execution'; end if;
  if has_table_privilege('authenticated', 'public.pcp_ordens_envase', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retained direct packaging order writes';
  end if;
  if has_table_privilege('authenticated', 'public.pcp_ordem_envase_embalagens', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retained direct packaging component writes';
  end if;
end;
$privileges$;

rollback;

select 'PG_VALIDATE_0069_WITH_SMOKE_OK' as result;
