\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_definition text;
begin
  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'pcp_op_reservas_componentes'
       and column_name = 'observacao'
  ) then
    raise exception 'PCP reservation observation column is missing';
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.pcp_op_reservas_componentes'::regclass
       and conname = 'pcp_op_reservas_observacao_length_check'
       and convalidated
  ) then
    raise exception 'PCP reservation observation constraint is missing or not validated';
  end if;

  if (select provolatile from pg_proc where oid = 'public.normalize_audit_axis(text)'::regprocedure) <> 's' then
    raise exception 'normalize_audit_axis must be STABLE';
  end if;
  if (select provolatile from pg_proc where oid = 'public.list_system_module_runtime(text)'::regprocedure) <> 'v' then
    raise exception 'list_system_module_runtime must be VOLATILE';
  end if;
  if (select provolatile from pg_proc where oid = 'public.get_current_route_module_access(text)'::regprocedure) <> 'v' then
    raise exception 'get_current_route_module_access must be VOLATILE';
  end if;

  if has_function_privilege('anon', 'public.next_com_pedido_sequencia(bigint,bigint)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.next_com_pedido_sequencia(bigint,bigint)', 'EXECUTE') then
    raise exception 'internal order sequence allocator is executable by a web role';
  end if;

  select pg_get_functiondef('public.next_com_pedido_sequencia(bigint,bigint)'::regprocedure)
    into v_definition;
  if position('order sequence allocation reached an invalid state' in v_definition) = 0 then
    raise exception 'order sequence allocator has no explicit terminal failure';
  end if;

  select pg_get_functiondef(
    'public.reservar_pcp_op_componente(bigint,bigint,bigint,bigint,numeric,text)'::regprocedure
  ) into v_definition;
  if position('reservar_pcp_op_componente_impl_0076' in v_definition) = 0
     or position('pcp_fifo_component:' in v_definition) = 0 then
    raise exception 'PCP reservation wrapper no longer enforces the FIFO contract';
  end if;

  select pg_get_functiondef(
    'public.reservar_pcp_op_componente_impl_0076(bigint,bigint,bigint,bigint,numeric,text)'::regprocedure
  ) into v_definition;
  if position('observacao = coalesce(v_observacao, reserva.observacao)' in v_definition) = 0
     or position('''observacao'', v_observacao_final' in v_definition) = 0 then
    raise exception 'PCP reservation observation is not persisted and audited';
  end if;
end;
$contract$;

do $behavior$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000043';
  v_materia_prima_id bigint;
  v_produto_id bigint;
  v_lote_mp_id bigint;
  v_unidade_formula_id bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_componente_id bigint;
  v_reserva_id bigint;
  v_observacao text;
begin
  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Schema Lint Smoke Actor', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor
    from public.permission_actions action
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'Smoke comportamental da migration 0043'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'schema lint behavior smoke requires unconfigured or test environment';
  end if;

  v_materia_prima_id := public.create_cad_materia_prima(
    'Materia Prima Smoke 0043',
    'MATERIA PRIMA SMOKE 0043',
    'MP-SMOKE-0043',
    'KG'
  );
  v_produto_id := public.create_cad_produto_base(
    '9943',
    'Produto Smoke 0043',
    'PRODUTO SMOKE 0043'
  );
  v_lote_mp_id := public.create_est_lote_mp(
    v_materia_prima_id,
    100,
    null,
    'importacao_inicial',
    'disponivel',
    current_date,
    current_date + 365,
    'smoke-0043',
    'Lote do smoke de observacao'
  );
  select id
    into v_unidade_formula_id
    from public.cad_unidades_medida
   where codigo = 'kg_l_produzido'
     and status = 'active';
  if v_unidade_formula_id is null then
    raise exception 'governed per-liter unit is missing from schema lint fixture';
  end if;
  v_formula_id := public.create_pcp_formula_versao(
    v_produto_id,
    'producao',
    'Formula do smoke 0043',
    jsonb_build_array(
      jsonb_build_object(
        'tipo_componente', 'MP',
        'materia_prima_id', v_materia_prima_id,
        'quantidade', 10,
        'unidade_id', v_unidade_formula_id,
        'unidade', 'kg_l_produzido'
      )
    )
  );
  perform public.activate_pcp_formula_versao(v_formula_id, 'Ativacao do smoke 0043');
  v_op_id := public.create_pcp_op(v_formula_id, 'estoque', 1, 'OP do smoke 0043');

  select componente.id
    into v_componente_id
    from public.pcp_op_componentes_planejados componente
   where componente.op_id = v_op_id
     and componente.tipo_componente = 'MP';

  v_reserva_id := public.reservar_pcp_op_componente(
    v_componente_id,
    v_lote_mp_id,
    null,
    null,
    10,
    'Reserva observada no smoke 0043'
  );

  select reserva.observacao
    into v_observacao
    from public.pcp_op_reservas_componentes reserva
   where reserva.id = v_reserva_id;
  if v_observacao <> 'Reserva observada no smoke 0043' then
    raise exception 'PCP reservation observation was not persisted';
  end if;

  if not exists (
    select 1
      from public.action_logs log
     where log.entity_type = 'pcp_op_reservas_componentes'
       and log.entity_id = v_reserva_id::text
       and log.action = 'pcp.op_componente_reservado'
       and log.after_json->>'observacao' = 'Reserva observada no smoke 0043'
  ) then
    raise exception 'PCP reservation observation was not audited';
  end if;

  perform public.reservar_pcp_op_componente(
    v_componente_id,
    v_lote_mp_id,
    null,
    null,
    10,
    '   '
  );
  select reserva.observacao
    into v_observacao
    from public.pcp_op_reservas_componentes reserva
   where reserva.id = v_reserva_id;
  if v_observacao <> 'Reserva observada no smoke 0043' then
    raise exception 'blank update erased the existing PCP reservation observation';
  end if;

  begin
    perform public.reservar_pcp_op_componente(
      v_componente_id,
      v_lote_mp_id,
      null,
      null,
      10,
      repeat('x', 2001)
    );
    raise exception 'oversized PCP reservation observation was accepted';
  exception
    when others then
      if sqlerrm <> 'observacao must have at most 2000 characters' then
        raise;
      end if;
  end;
end;
$behavior$;

rollback;

\echo PG_SCHEMA_LINT_HARDENING_OK
