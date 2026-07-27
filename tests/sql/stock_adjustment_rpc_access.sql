\set ON_ERROR_STOP on

begin;

do $stock_adjustment_access$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000111';
  v_denied uuid := '00000000-0000-4000-8000-000000000112';
  v_product_id bigint;
  v_lot_id bigint;
  v_movement_id bigint;
  v_before_count bigint;
begin
  if not has_function_privilege(
    'authenticated',
    'public.registrar_est_ajuste_mp(bigint,numeric,text)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.registrar_est_ajuste_pi(bigint,numeric,text)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.registrar_est_ajuste_pa(bigint,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute every governed stock adjustment RPC';
  end if;

  if has_function_privilege(
    'anon',
    'public.registrar_est_ajuste_pi(bigint,numeric,text)',
    'EXECUTE'
  ) or exists (
    select 1
      from pg_proc function_definition
      cross join lateral aclexplode(
        coalesce(
          function_definition.proacl,
          acldefault('f', function_definition.proowner)
        )
      ) privilege
     where function_definition.oid =
       'public.registrar_est_ajuste_pi(bigint,numeric,text)'::regprocedure
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception 'anon or PUBLIC can execute governed PI stock adjustment';
  end if;

  if has_table_privilege('authenticated', 'public.est_movimentos_mp', 'INSERT')
     or has_table_privilege('authenticated', 'public.est_movimentos_pi', 'INSERT')
     or has_table_privilege('authenticated', 'public.est_movimentos_pa', 'INSERT') then
    raise exception 'authenticated retains direct stock movement write access';
  end if;

  insert into auth.users(id)
  values (v_actor), (v_denied)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor, 'Stock Adjustment Actor', 'admin', 'active'),
    (v_denied, 'Stock Adjustment Denied', 'auditoria', 'active')
  on conflict (id) do update set status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'estoque.pi.adjust', true, v_actor),
    (v_actor, 'system.admin', true, v_actor),
    (v_denied, 'estoque.pi.adjust', false, v_actor)
  on conflict (user_id, action_key) do update
    set allowed = excluded.allowed,
        updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'Governed stock adjustment access smoke'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'stock adjustment smoke requires unconfigured or test environment';
  end if;

  insert into public.cad_produtos_base(
    codigo_produto,
    nome,
    nome_norm,
    status,
    created_by,
    updated_by
  )
  values (
    '9211',
    'Produto PI smoke 0111',
    'produto pi smoke 0111',
    'active',
    v_actor,
    v_actor
  )
  returning id into v_product_id;

  insert into public.est_lotes_pi(
    produto_id,
    codigo_lote,
    status,
    origem_ref,
    created_by,
    updated_by
  )
  values (
    v_product_id,
    'PI-SMOKE-0111',
    'disponivel',
    'smoke:0111',
    v_actor,
    v_actor
  )
  returning id into v_lot_id;

  insert into public.est_movimentos_pi(
    lote_pi_id,
    produto_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    v_lot_id,
    v_product_id,
    'entrada_producao',
    10,
    'pcp',
    'pcp_ordens',
    'smoke-0111',
    'Entrada sintética do smoke 0111',
    v_actor
  );

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  v_movement_id := public.registrar_est_ajuste_pi(
    v_lot_id,
    -4,
    'Neutralização sintética auditada no smoke 0111'
  );

  if v_movement_id is null or (
    select saldo_fisico
      from public.est_lotes_pi_saldos
     where lote_pi_id = v_lot_id
  ) <> 6 then
    raise exception 'governed PI adjustment did not update the derived balance';
  end if;

  if not exists (
    select 1
      from public.action_logs
     where entity_type = 'est_lotes_pi'
       and entity_id = v_lot_id::text
       and action = 'estoque.pi_ajuste_registrado'
       and action_key = 'estoque.pi.adjust'
  ) then
    raise exception 'governed PI adjustment did not create its audit event';
  end if;

  select count(*)
    into v_before_count
    from public.est_movimentos_pi
   where lote_pi_id = v_lot_id;

  perform set_config('request.jwt.claim.sub', v_denied::text, true);
  begin
    perform public.registrar_est_ajuste_pi(
      v_lot_id,
      -1,
      'Tentativa sintética sem alçada no smoke 0111'
    );
    raise exception 'user without permission adjusted PI stock';
  exception
    when others then
      if sqlerrm = 'user without permission adjusted PI stock'
         or sqlerrm not like '%not allowed: estoque.pi.adjust%' then
        raise;
      end if;
  end;

  if (
    select count(*)
      from public.est_movimentos_pi
     where lote_pi_id = v_lot_id
  ) <> v_before_count then
    raise exception 'denied PI adjustment left a partial stock effect';
  end if;
end;
$stock_adjustment_access$;

rollback;

\echo PG_STOCK_ADJUSTMENT_RPC_ACCESS_OK
