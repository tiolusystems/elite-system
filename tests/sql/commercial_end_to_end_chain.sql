\set ON_ERROR_STOP on
begin;

do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000089';
  v_client bigint;
  v_person bigint;
  v_order bigint;
  v_assignment bigint;
  v_receipt bigint;
  v_receipt_retry bigint;
  v_payment bigint;
  v_payment_retry bigint;
  v_adjustment bigint;
  v_adjustment_retry bigint;
  v_credit_event bigint;
  v_manager_decision bigint;
begin
  if has_function_privilege('authenticated', 'public.registrar_com_pedido_decisao_gerencial(bigint,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.registrar_com_pedido_decisao_credito(bigint,text,text,numeric,numeric,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.registrar_com_pedido_decisao_gerencial_idempotente(uuid,bigint,text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.registrar_com_pedido_decisao_gerencial_idempotente(uuid,bigint,text,text)', 'EXECUTE') then
    raise exception 'manager decision grants are broader than the idempotent contract';
  end if;
  if has_function_privilege('authenticated', 'public.ajustar_com_limite_credito_cliente(bigint,numeric,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.ajustar_com_limite_credito_cliente_idempotente(uuid,bigint,numeric,text)', 'EXECUTE') then
    raise exception 'credit limit grants are broader than the idempotent contract';
  end if;
  insert into auth.users(id, email)
  values (v_actor, 'commercial-chain-0089@test.invalid')
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Commercial Chain 0089', 'admin', 'active')
  on conflict (id) do update set status = 'active';

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor
    from public.permission_actions action
  on conflict (user_id, action_key) do update
    set allowed = true, updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'Commercial chain smoke');
  end if;

  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
  values ('Cliente Cadeia Comercial', 'cliente cadeia comercial', 'Campinas', 'SP', 'active', v_actor, v_actor)
  returning id into v_client;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, user_profile_id, created_by, updated_by
  ) values (
    'Vendedor Cadeia Comercial', 'vendedor cadeia comercial', '["vendedor"]',
    'active', v_actor, v_actor, v_actor
  ) returning id into v_person;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, vendedor_gerador_id, tipo_pedido, status,
    data_pedido, valor_total, created_by, updated_by
  ) values (
    'PED-CHAIN-0089', v_client, v_person, 'venda', 'blocked',
    current_date, 1000, v_actor, v_actor
  ) returning id into v_order;

  v_credit_event := public.ajustar_com_limite_credito_cliente_idempotente(
    '89000000-0000-4000-8000-000000000010', v_client, 5000,
    'Limite sintetico aprovado no smoke integrado'
  );
  if public.ajustar_com_limite_credito_cliente_idempotente(
    '89000000-0000-4000-8000-000000000010', v_client, 5000,
    'Limite sintetico aprovado no smoke integrado'
  ) <> v_credit_event then raise exception 'credit limit retry duplicated the event'; end if;

  v_manager_decision := public.registrar_com_pedido_decisao_gerencial_idempotente(
    '89000000-0000-4000-8000-000000000011', v_order, 'liberado',
    'Limite e cadastro aprovados no smoke integrado'
  );
  if public.registrar_com_pedido_decisao_gerencial_idempotente(
    '89000000-0000-4000-8000-000000000011', v_order, 'liberado',
    'Limite e cadastro aprovados no smoke integrado'
  ) <> v_manager_decision then raise exception 'manager decision retry duplicated the event'; end if;
  if (select status from public.com_pedidos where id = v_order) <> 'open' then
    raise exception 'manager approval did not open the order';
  end if;

  v_assignment := public.definir_com_pedido_comissao(
    v_order, v_person, 'vendedor', 2.5, 'Comissao aprovada no smoke integrado'
  );
  if (select valor_previsto from public.com_pedido_comissionados where id = v_assignment) <> 25 then
    raise exception 'expected commission was not calculated';
  end if;

  v_receipt := public.registrar_com_recebimento_idempotente(
    '89000000-0000-4000-8000-000000000001',
    v_order, 400, current_date, 'pix', 'Recebimento parcial do smoke integrado'
  );
  v_receipt_retry := public.registrar_com_recebimento_idempotente(
    '89000000-0000-4000-8000-000000000001',
    v_order, 400, current_date, 'pix', 'Recebimento parcial do smoke integrado'
  );
  if v_receipt_retry is distinct from v_receipt then
    raise exception 'receipt retry did not return the original event';
  end if;
  if (select count(*) from public.fin_recebimento_requisicoes
       where idempotency_key = '89000000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'receipt request key was not recorded exactly once';
  end if;
  begin
    perform public.registrar_com_recebimento_idempotente(
      '89000000-0000-4000-8000-000000000001',
      v_order, 401, current_date, 'pix', 'Recebimento parcial do smoke integrado'
    );
    raise exception 'changed receipt reused the same idempotency key';
  exception when others then
    if sqlerrm = 'changed receipt reused the same idempotency key'
       or sqlerrm not like 'idempotency key reused with different receipt request%' then
      raise;
    end if;
  end;
  if (select coalesce(sum(valor_liberado), 0) from public.com_comissao_liberacoes
       where recebimento_id = v_receipt and comissionado_id = v_assignment) <> 10 then
    raise exception 'partial receipt did not release proportional commission';
  end if;
  if (select saldo_aberto from public.fin_recebimento_saldos_pedido where pedido_id = v_order) <> 600 then
    raise exception 'order receivable balance is inconsistent';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.registrar_com_recebimento(bigint,numeric,date,text,text)',
    'EXECUTE'
  ) then
    raise exception 'unkeyed receipt entrypoint remains executable';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.registrar_com_recebimento_idempotente(uuid,bigint,numeric,date,text,text)',
    'EXECUTE'
  ) then
    raise exception 'idempotent receipt privileges are incorrect';
  end if;

  v_payment := public.registrar_fin_comissao_pagamento_idempotente(
    '89000000-0000-4000-8000-000000000002',
    v_person, 10, current_date, 'pix', 'Pagamento do smoke comercial integrado'
  );
  v_payment_retry := public.registrar_fin_comissao_pagamento_idempotente(
    '89000000-0000-4000-8000-000000000002',
    v_person, 10, current_date, 'pix', 'Pagamento do smoke comercial integrado'
  );
  if v_payment_retry is distinct from v_payment then
    raise exception 'commission payment retry did not return the original movement';
  end if;
  begin
    perform public.registrar_fin_comissao_pagamento_idempotente(
      '89000000-0000-4000-8000-000000000002',
      v_person, 9, current_date, 'pix', 'Pagamento do smoke comercial integrado'
    );
    raise exception 'changed commission payment reused the same idempotency key';
  exception when others then
    if sqlerrm = 'changed commission payment reused the same idempotency key'
       or sqlerrm not like 'idempotency key reused with different commission request%' then
      raise;
    end if;
  end;
  if not exists (
    select 1 from public.fin_comissao_movimentos
     where id = v_payment and pessoa_id = v_person
       and tipo_movimento = 'debito_pagamento' and valor = -10
  ) then
    raise exception 'commission payment movement is inconsistent';
  end if;
  if (select saldo_comissao from public.fin_comissao_saldos where pessoa_id = v_person) <> 0 then
    raise exception 'commission current account did not close after payment';
  end if;

  v_adjustment := public.registrar_fin_comissao_ajuste_idempotente(
    '89000000-0000-4000-8000-000000000003',
    v_person, 5, 'correcao_calculo', jsonb_build_object('motivo_detalhe', 'Smoke integrado')
  );
  v_adjustment_retry := public.registrar_fin_comissao_ajuste_idempotente(
    '89000000-0000-4000-8000-000000000003',
    v_person, 5, 'correcao_calculo', jsonb_build_object('motivo_detalhe', 'Smoke integrado')
  );
  if v_adjustment_retry is distinct from v_adjustment then
    raise exception 'commission adjustment retry did not return the original movement';
  end if;
  if (select saldo_comissao from public.fin_comissao_saldos where pessoa_id = v_person) <> 5 then
    raise exception 'idempotent commission adjustment duplicated the balance';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.registrar_fin_comissao_pagamento(bigint,numeric,date,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.registrar_fin_comissao_ajuste(bigint,numeric,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'unkeyed commission entrypoint remains executable';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.registrar_fin_comissao_pagamento_idempotente(uuid,bigint,numeric,date,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.registrar_fin_comissao_pagamento_idempotente(uuid,bigint,numeric,date,text,text)',
    'EXECUTE'
  ) then
    raise exception 'idempotent commission payment privileges are incorrect';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.registrar_fin_comissao_ajuste_idempotente(uuid,bigint,numeric,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.registrar_fin_comissao_ajuste_idempotente(uuid,bigint,numeric,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'idempotent commission adjustment privileges are incorrect';
  end if;

  if not exists (
    select 1 from public.action_logs
     where action_key = 'pedidos.commissions.assign'
       and metadata_json->>'pedido_id' = v_order::text
  ) or not exists (
    select 1 from public.action_logs
     where action_key = 'financeiro.receipts.register'
       and metadata_json->>'cliente_id' = v_client::text
  ) or not exists (
    select 1 from public.action_logs
     where action_key = 'financeiro.commissions.pay'
       and metadata_json->>'pessoa_id' = v_person::text
  ) then
    raise exception 'commercial chain audit trail is incomplete';
  end if;
end;
$$;

rollback;
select 'PG_COMMERCIAL_END_TO_END_CHAIN_OK' as result;
