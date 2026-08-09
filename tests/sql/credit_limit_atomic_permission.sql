\set ON_ERROR_STOP on
begin;

do $catalog$
begin
  if not exists (
    select 1
      from public.permission_actions action
     where action.action_key = 'financeiro.credit_limits.adjust'
       and action.module = 'financeiro'
       and action.description = 'Alterar limite de crédito de cliente'
       and action.default_allowed = false
       and action.runtime_module_key = 'financeiro'
       and action.runtime_access_kind = 'write'
  ) then
    raise exception 'canonical credit limit permission is invalid';
  end if;

  if not exists (
    select 1
      from public.permission_actions action
     where action.action_key = 'pedidos.credit.limit.adjust'
       and action.default_allowed = false
       and action.description like 'LEGADA%'
  ) then
    raise exception 'legacy credit limit permission remains operational';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.ajustar_com_limite_credito_cliente(bigint,numeric,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'public',
       'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)',
       'EXECUTE'
     ) then
    raise exception 'credit limit RPC grants are invalid';
  end if;

  if pg_get_functiondef(
       'public.ajustar_com_limite_credito_cliente(bigint,numeric,text)'::regprocedure
     ) like '%pedidos.credit.limit.adjust%'
     or pg_get_functiondef(
       'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)'::regprocedure
     ) like '%pedidos.credit.limit.adjust%'
     or pg_get_functiondef(
       'public.ajustar_com_limite_credito_cliente(bigint,numeric,text)'::regprocedure
     ) like '%current_user_manages_seller%'
  then
    raise exception 'credit limit RPC still infers authority from legacy permission or role';
  end if;
end
$catalog$;

insert into auth.users(id, email) values
  ('10400000-0000-4000-8000-000000000001', 'manager-0104@test.invalid'),
  ('10400000-0000-4000-8000-000000000002', 'finance-0104@test.invalid'),
  ('10400000-0000-4000-8000-000000000003', 'admin-0104@test.invalid'),
  ('10400000-0000-4000-8000-000000000004', 'holder-0104@test.invalid');

insert into public.user_profiles(id, display_name, role, status) values
  ('10400000-0000-4000-8000-000000000001', 'Gerente sem alcada financeira', 'comercial', 'active'),
  ('10400000-0000-4000-8000-000000000002', 'Financeiro sem alcada de limite', 'auditoria', 'active'),
  ('10400000-0000-4000-8000-000000000003', 'Administrador sem alcada financeira', 'admin', 'active'),
  ('10400000-0000-4000-8000-000000000004', 'Pessoa com alcada individual', 'estoque', 'active');

insert into public.cad_pessoas_comerciais(
  nome,
  nome_norm,
  tipo_comercial,
  papeis_json,
  status,
  user_profile_id,
  created_by
) values (
  'Gerente sem alcada financeira',
  'gerente sem alcada financeira',
  'gerente',
  '["gerente"]',
  'active',
  '10400000-0000-4000-8000-000000000001',
  '10400000-0000-4000-8000-000000000003'
);

-- The financial operator is identified by another financial grant, not by a
-- hard-coded role. Neither this grant nor the admin/manager labels imply the
-- atomic credit-limit authority.
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  ('10400000-0000-4000-8000-000000000001', 'pedidos.credit.review', true, '10400000-0000-4000-8000-000000000003'),
  ('10400000-0000-4000-8000-000000000001', 'pedidos.credit.limit.adjust', true, '10400000-0000-4000-8000-000000000003'),
  ('10400000-0000-4000-8000-000000000002', 'financeiro.receipts.view', true, '10400000-0000-4000-8000-000000000003'),
  ('10400000-0000-4000-8000-000000000003', 'system.admin', true, '10400000-0000-4000-8000-000000000003'),
  ('10400000-0000-4000-8000-000000000004', 'financeiro.credit_limits.adjust', true, '10400000-0000-4000-8000-000000000003'),
  ('10400000-0000-4000-8000-000000000004', 'pedidos.credit.review', false, '10400000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke 0104')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
values (
  'Cliente sintetico 0104',
  'cliente sintetico 0104',
  'Campinas',
  'SP',
  'active',
  '10400000-0000-4000-8000-000000000004'
);

set local role authenticated;

select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000001', true);
do $manager_denied$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  if not public.can_current_user('pedidos.credit.review') then
    raise exception 'manager review permission was not preserved';
  end if;
  if public.can_current_user('financeiro.credit_limits.adjust') then
    raise exception 'manager inherited credit limit authority';
  end if;
  begin
    perform public.ajustar_com_limite_credito_cliente_idempotente(
      '10400000-0000-4000-8000-000000000011',
      v_client,
      1000,
      'Tentativa do gerente sem alcada'
    );
    raise exception 'manager changed credit limit without atomic permission';
  exception when others then
    if sqlerrm = 'manager changed credit limit without atomic permission' then
      raise;
    end if;
    if sqlerrm not like 'not allowed: financeiro.credit_limits.adjust%' then
      raise;
    end if;
  end;
end
$manager_denied$;

select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000002', true);
do $finance_denied$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  if not public.can_current_user('financeiro.receipts.view') then
    raise exception 'financial operator fixture is invalid';
  end if;
  begin
    perform public.ajustar_com_limite_credito_cliente_idempotente(
      '10400000-0000-4000-8000-000000000012',
      v_client,
      2000,
      'Tentativa do financeiro sem alcada'
    );
    raise exception 'financial operator changed limit without atomic permission';
  exception when others then
    if sqlerrm = 'financial operator changed limit without atomic permission' then
      raise;
    end if;
    if sqlerrm not like 'not allowed: financeiro.credit_limits.adjust%' then
      raise;
    end if;
  end;
end
$finance_denied$;

select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000003', true);
do $admin_denied$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  begin
    perform public.ajustar_com_limite_credito_cliente_idempotente(
      '10400000-0000-4000-8000-000000000013',
      v_client,
      3000,
      'Tentativa do administrador sem alcada'
    );
    raise exception 'administrator changed limit without atomic permission';
  exception when others then
    if sqlerrm = 'administrator changed limit without atomic permission' then
      raise;
    end if;
    if sqlerrm not like 'not allowed: financeiro.credit_limits.adjust%' then
      raise;
    end if;
  end;
end
$admin_denied$;

select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000004', true);
do $holder_allowed$
declare
  v_client bigint;
  v_first bigint;
  v_second bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  if not public.can_current_user('financeiro.credit_limits.adjust') then
    raise exception 'individual override did not grant credit limit authority';
  end if;
  if public.can_current_user('pedidos.credit.review') then
    raise exception 'credit limit authority implied order review';
  end if;

  v_first := public.ajustar_com_limite_credito_cliente_idempotente(
    '10400000-0000-4000-8000-000000000021',
    v_client,
    5000,
    'Limite inicial autorizado no smoke 0104'
  );
  if public.ajustar_com_limite_credito_cliente_idempotente(
    '10400000-0000-4000-8000-000000000021',
    v_client,
    5000,
    'Limite inicial autorizado no smoke 0104'
  ) <> v_first then
    raise exception 'idempotent retry returned another event';
  end if;

  v_second := public.ajustar_com_limite_credito_cliente_idempotente(
    '10400000-0000-4000-8000-000000000022',
    v_client,
    6500,
    'Aumento individual autorizado no smoke 0104'
  );
  if v_second = v_first then
    raise exception 'distinct authorized request reused the first event';
  end if;

end
$holder_allowed$;

reset role;
do $ledger_checks$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  if (select count(*) from public.cad_limite_credito_eventos event where event.cliente_id = v_client) <> 2 then
    raise exception 'credit limit ledger count is invalid';
  end if;
  if not exists (
    select 1
      from public.cad_limite_credito_eventos event
     where event.cliente_id = v_client
       and event.limite_anterior = 5000
       and event.limite_novo = 6500
       and event.justificativa = 'Aumento individual autorizado no smoke 0104'
       and event.created_by = '10400000-0000-4000-8000-000000000004'
  ) then
    raise exception 'credit limit audit event lost before/after, reason or actor';
  end if;
  if not exists (
    select 1
      from public.action_logs log
     where log.action_key = 'financeiro.credit_limits.adjust'
       and log.action = 'financeiro.limite_credito_ajustado'
       and log.actor_user_id = '10400000-0000-4000-8000-000000000004'
  ) then
    raise exception 'standard audit log is missing';
  end if;
end
$ledger_checks$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000004', true);
do $direct_write$
begin
  begin
    insert into public.cad_limite_credito_eventos(
      limite_credito_id,
      cliente_id,
      tipo_evento,
      limite_novo,
      status_novo,
      justificativa,
      created_by
    ) values (
      1,
      1,
      'aumento',
      1,
      'liberado',
      'Tentativa direta deve falhar',
      '10400000-0000-4000-8000-000000000004'
    );
    raise exception 'direct credit event write was accepted';
  exception when insufficient_privilege then
    null;
  end;
end
$direct_write$;

reset role;
delete from public.user_permission_overrides
 where user_id = '10400000-0000-4000-8000-000000000004'
   and action_key = 'financeiro.credit_limits.adjust';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10400000-0000-4000-8000-000000000004', true);

do $revoked_denied$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  begin
    perform public.ajustar_com_limite_credito_cliente_idempotente(
      '10400000-0000-4000-8000-000000000023',
      v_client,
      7000,
      'Tentativa depois da retirada da alcada'
    );
    raise exception 'revoked user changed credit limit';
  exception when others then
    if sqlerrm = 'revoked user changed credit limit' then
      raise;
    end if;
    if sqlerrm not like 'not allowed: financeiro.credit_limits.adjust%' then
      raise;
    end if;
  end;
end
$revoked_denied$;

reset role;
do $denied_ledger_unchanged$
declare
  v_client bigint;
begin
  select id into v_client from public.cad_clientes where nome_norm = 'cliente sintetico 0104';
  if (select count(*) from public.cad_limite_credito_eventos event where event.cliente_id = v_client) <> 2 then
    raise exception 'denied request changed the append-only ledger';
  end if;
end
$denied_ledger_unchanged$;
rollback;
select 'PG_VALIDATE_0104_CREDIT_LIMIT_ATOMIC_PERMISSION_OK';
