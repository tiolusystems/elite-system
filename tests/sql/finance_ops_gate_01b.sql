\set ON_ERROR_STOP on
begin transaction isolation level repeatable read;

do $catalog$
declare
  v_signature text;
begin
  if not exists (
    select 1
    from public.permission_actions action
    where action.action_key = 'financeiro.dashboard.view'
      and action.module = 'financeiro'
      and action.default_allowed = false
      and action.runtime_access_kind = 'read'
  ) then
    raise exception 'financial dashboard permission is invalid';
  end if;
  if not exists (
    select 1
    from public.permission_actions action
    where action.action_key = 'financeiro.commissions.export'
      and action.default_allowed = false
  ) then
    raise exception 'commission export permission is invalid';
  end if;
  if has_function_privilege(
       'authenticated',
       'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'public',
       'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'receipt RPC grants are invalid';
  end if;
  if has_table_privilege('authenticated', 'public.com_recebimentos', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_recebimentos', 'UPDATE')
     or has_table_privilege('authenticated', 'public.com_recebimentos', 'DELETE')
     or has_table_privilege('authenticated', 'public.fin_recebimento_alocacoes', 'INSERT')
     or has_table_privilege('authenticated', 'public.fin_recebimento_alocacoes', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fin_recebimento_alocacoes', 'DELETE')
     or has_table_privilege('authenticated', 'public.com_comissao_liberacoes', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_comissao_liberacoes', 'UPDATE')
     or has_table_privilege('authenticated', 'public.com_comissao_liberacoes', 'DELETE')
     or has_table_privilege('authenticated', 'public.fin_comissao_movimentos', 'INSERT')
     or has_table_privilege('authenticated', 'public.fin_comissao_movimentos', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fin_comissao_movimentos', 'DELETE') then
    raise exception 'direct financial write is available';
  end if;
  foreach v_signature in array array[
    'public.consultar_fin_dashboard(date,date,date)',
    'public.buscar_fin_pedidos_recebimento(text,integer,integer)',
    'public.buscar_fin_pedidos_comissionamento(text,integer,integer)',
    'public.buscar_fin_pessoas_comissionaveis(text,integer)',
    'public.consultar_fin_comissoes(text,text,text,date,integer,integer)',
    'public.consultar_fin_comissao_movimentos(bigint,date,date,integer)'
  ] loop
    if not has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or has_function_privilege('anon', v_signature, 'EXECUTE')
       or has_function_privilege('public', v_signature, 'EXECUTE') then
      raise exception 'invalid grants for %', v_signature;
    end if;
  end loop;
end
$catalog$;

insert into auth.users(id, email) values
  ('11800000-0000-4000-8000-000000000001', 'finance-0118@test.invalid'),
  ('11800000-0000-4000-8000-000000000002', 'denied-0118@test.invalid')
on conflict (id) do nothing;

insert into public.user_profiles(id, display_name, role, status) values
  ('11800000-0000-4000-8000-000000000001', 'Financeiro sintetico 0118', 'admin', 'active'),
  ('11800000-0000-4000-8000-000000000002', 'Sem alcada 0118', 'auditoria', 'active')
on conflict (id) do update set status = 'active';

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  ('11800000-0000-4000-8000-000000000001', 'system.admin', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.dashboard.view', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.receipts.view', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.receipts.register', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.commissions.view', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.commissions.release', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.commissions.pay', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'financeiro.commissions.adjust', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000001', 'pedidos.commissions.assign', true, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000002', 'financeiro.receipts.view', false, '11800000-0000-4000-8000-000000000001'),
  ('11800000-0000-4000-8000-000000000002', 'financeiro.receipts.register', false, '11800000-0000-4000-8000-000000000001')
on conflict (user_id, action_key) do update
set allowed = excluded.allowed, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '11800000-0000-4000-8000-000000000001', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke Financeiro 0118')
where public.current_system_environment() = 'unconfigured';

do $exercise$
declare
  v_client bigint;
  v_person bigint;
  v_first_order bigint;
  v_romaneio bigint;
  v_receipt bigint;
  v_dashboard_baseline jsonb;
  v_dashboard jsonb;
  v_expected_orders_with_balance bigint;
  v_expected_open_receivables numeric;
  v_expected_received_period numeric;
  v_expected_commission_balance numeric;
  v_commission record;
  v_search_count integer;
begin
  -- The dashboard is intentionally global. A stable baseline keeps this smoke
  -- valid both on clean CI and on configured persistent staging.
  perform pg_advisory_xact_lock(hashtextextended('tests/sql/finance_ops_gate_01b', 0));
  v_dashboard_baseline := public.consultar_fin_dashboard(current_date, current_date, current_date);
  v_expected_orders_with_balance := (v_dashboard_baseline->>'orders_with_balance')::bigint + 305;
  v_expected_open_receivables := (v_dashboard_baseline->>'open_receivables')::numeric + 30500;
  v_expected_received_period := (v_dashboard_baseline->>'received_period')::numeric + 40;
  v_expected_commission_balance := (v_dashboard_baseline->>'commission_balance')::numeric + 4;

  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
  values (
    'Cliente Financeiro HOM 0118',
    'cliente financeiro hom 0118',
    'Campinas',
    'SP',
    'active',
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  ) returning id into v_client;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, created_by, updated_by
  ) values (
    'Agente Financeiro HOM 0118',
    'agente financeiro hom 0118',
    '["agente"]',
    'active',
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  ) returning id into v_person;

  for v_index in 1..305 loop
    insert into public.com_pedidos(
      codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
      valor_total, created_by, updated_by
    ) values (
      'HOM-FIN-0118-' || lpad(v_index::text, 3, '0'),
      v_client,
      'venda',
      'open',
      current_date,
      100,
      '11800000-0000-4000-8000-000000000001',
      '11800000-0000-4000-8000-000000000001'
    ) returning id into v_first_order;
    exit when v_index = 1;
  end loop;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    valor_total, created_by, updated_by
  )
  select
    'HOM-FIN-0118-' || lpad(v_index::text, 3, '0'),
    v_client,
    'venda',
    'open',
    current_date,
    100,
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  from generate_series(2, 305) v_index;

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, created_by, updated_by
  ) values (
    'HOM-ROM-FIN-0118',
    v_first_order,
    'parcial',
    'confirmado',
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  ) returning id into v_romaneio;

  insert into public.fat_notas_fiscais(
    pedido_id, romaneio_id, numero, data_emissao, valor_nf, tipo,
    status_atual, origem_registro, created_by, updated_by
  ) values
  (
    v_first_order, null, 'NF-SIMP-FIN-0118', current_date, 100,
    'simples_faturamento', 'emitida', 'externa',
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  ),
  (
    v_first_order, v_romaneio, 'NF-REM-FIN-0118', current_date, 0,
    'remessa_total', 'emitida', 'externa',
    '11800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000001'
  );

  v_dashboard := public.consultar_fin_dashboard(current_date, current_date, current_date);
  if (v_dashboard->>'orders_with_balance')::bigint <> v_expected_orders_with_balance
     or (v_dashboard->>'open_receivables')::numeric <> v_expected_open_receivables then
    raise exception 'integral dashboard was truncated by a list limit: %', v_dashboard;
  end if;

  select count(*) into v_search_count
  from public.buscar_fin_pedidos_recebimento('Cliente Financeiro HOM 0118', 20, 0);
  if v_search_count <> 20 then
    raise exception 'receipt search pagination is invalid';
  end if;
  select count(*) into v_search_count
  from public.buscar_fin_pedidos_recebimento('NF-SIMP-FIN-0118', 20, 0)
  where pedido_id = v_first_order
    and jsonb_array_length(referencias_fiscais) = 2;
  if v_search_count <> 1 then
    raise exception 'simple billing reference duplicated or did not resolve the order';
  end if;
  select count(*) into v_search_count
  from public.buscar_fin_pedidos_recebimento('NF-REM-FIN-0118', 20, 0)
  where pedido_id = v_first_order
    and jsonb_array_length(referencias_fiscais) = 2;
  if v_search_count <> 1 then
    raise exception 'remittance reference duplicated or did not resolve the parent order';
  end if;

  perform public.definir_com_pedido_comissao_idempotente(
    '11800000-0000-4000-8000-000000000011',
    v_first_order,
    v_person,
    'agente',
    10,
    'Comissionamento sintetico 0118'
  );

  begin
    perform public.registrar_com_recebimento_idempotente(
      '11800000-0000-4000-8000-000000000012',
      v_first_order,
      40,
      current_date,
      'pix',
      null,
      ''
    );
    raise exception 'receipt without document reference was accepted';
  exception when others then
    if sqlerrm = 'receipt without document reference was accepted'
       or sqlerrm <> 'receipt document reference is required' then
      raise;
    end if;
  end;

  v_receipt := public.registrar_com_recebimento_idempotente(
    '11800000-0000-4000-8000-000000000013',
    v_first_order,
    40,
    current_date,
    'pix',
    null,
    'PIX-HOM-0118'
  );
  if public.registrar_com_recebimento_idempotente(
    '11800000-0000-4000-8000-000000000013',
    v_first_order,
    40,
    current_date,
    'pix',
    null,
    'PIX-HOM-0118'
  ) <> v_receipt then
    raise exception 'receipt retry did not return the original event';
  end if;
  if not exists (
    select 1 from public.com_recebimentos receipt
    where receipt.id = v_receipt
      and receipt.referencia_documental = 'PIX-HOM-0118'
  ) then
    raise exception 'receipt document reference was not stored';
  end if;
  begin
    perform public.registrar_com_recebimento_idempotente(
      '11800000-0000-4000-8000-000000000013',
      v_first_order,
      41,
      current_date,
      'pix',
      null,
      'PIX-HOM-0118'
    );
    raise exception 'divergent receipt retry was accepted';
  exception when others then
    if sqlerrm = 'divergent receipt retry was accepted'
       or sqlerrm <> 'idempotency key reused with different receipt request' then
      raise;
    end if;
  end;

  v_dashboard := public.consultar_fin_dashboard(current_date, current_date, current_date);
  if (v_dashboard->>'orders_with_balance')::bigint <> v_expected_orders_with_balance
     or (v_dashboard->>'open_receivables')::numeric <> v_expected_open_receivables - 40
     or (v_dashboard->>'received_period')::numeric <> v_expected_received_period
     or (v_dashboard->>'commission_balance')::numeric <> v_expected_commission_balance then
    raise exception 'dashboard did not reconcile receipt and commission: %', v_dashboard;
  end if;

  select * into v_commission
  from public.consultar_fin_comissoes(
    'Agente Financeiro HOM 0118',
    'agente',
    'positive',
    current_date,
    30,
    0
  );
  if v_commission.comissoes_previstas <> 10
     or v_commission.creditos_liberados <> 4
     or v_commission.saldo <> 4 then
    raise exception 'commission account did not reconcile';
  end if;

  if not exists (
    select 1 from public.action_logs log
    where log.entity_type = 'com_recebimentos'
      and log.entity_id = v_receipt::text
      and log.action = 'financeiro.referencia_documental_registrada'
      and log.after_json #>> '{recebimento,referencia_documental}' = 'PIX-HOM-0118'
  ) then
    raise exception 'receipt reference audit is missing';
  end if;
end
$exercise$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11800000-0000-4000-8000-000000000002', true);

do $denied$
begin
  if public.can_current_user('financeiro.receipts.view')
     or public.can_current_user('financeiro.receipts.register') then
    raise exception 'denied user inherited a financial permission from role';
  end if;
  if exists (select 1 from public.com_recebimentos) then
    raise exception 'RLS exposed receipts to denied user';
  end if;
  if exists (select 1 from public.fin_recebimento_alocacoes)
     or exists (select 1 from public.com_comissao_liberacoes)
     or exists (select 1 from public.fin_comissao_movimentos) then
    raise exception 'RLS exposed financial ledgers to denied user';
  end if;
  begin
    perform public.buscar_fin_pedidos_recebimento(null, 20, 0);
    raise exception 'denied user searched financial orders';
  exception when others then
    if sqlerrm = 'denied user searched financial orders'
       or sqlerrm <> 'not allowed: financeiro.receipts.view' then
      raise;
    end if;
  end;
  begin
    perform public.consultar_fin_comissoes(null, null, 'all', current_date, 30, 0);
    raise exception 'denied user searched commission accounts';
  exception when others then
    if sqlerrm = 'denied user searched commission accounts'
       or sqlerrm <> 'not allowed: financeiro.commissions.view' then
      raise;
    end if;
  end;
end
$denied$;

rollback;
select 'PG_FINANCE_OPS_GATE_01B_OK' as result;
