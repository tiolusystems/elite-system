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
  v_payment bigint;
begin
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

  perform public.registrar_com_pedido_decisao_gerencial(
    v_order, 'liberado', 'Limite e cadastro aprovados no smoke integrado'
  );
  if (select status from public.com_pedidos where id = v_order) <> 'open' then
    raise exception 'manager approval did not open the order';
  end if;

  v_assignment := public.definir_com_pedido_comissao(
    v_order, v_person, 'vendedor', 2.5, 'Comissao aprovada no smoke integrado'
  );
  if (select valor_previsto from public.com_pedido_comissionados where id = v_assignment) <> 25 then
    raise exception 'expected commission was not calculated';
  end if;

  v_receipt := public.registrar_com_recebimento(
    v_order, 400, current_date, 'pix', 'Recebimento parcial do smoke integrado'
  );
  if (select coalesce(sum(valor_liberado), 0) from public.com_comissao_liberacoes
       where recebimento_id = v_receipt and comissionado_id = v_assignment) <> 10 then
    raise exception 'partial receipt did not release proportional commission';
  end if;
  if (select saldo_aberto from public.fin_recebimento_saldos_pedido where pedido_id = v_order) <> 600 then
    raise exception 'order receivable balance is inconsistent';
  end if;

  v_payment := public.registrar_fin_comissao_pagamento(
    v_person, 10, current_date, 'pix', 'Pagamento do smoke comercial integrado'
  );
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
