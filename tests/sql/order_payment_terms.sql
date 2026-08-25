\set ON_ERROR_STOP on
begin;

do $$
declare
  v_authorized uuid := '12600000-0000-4000-8000-000000000001';
  v_denied uuid := '12600000-0000-4000-8000-000000000002';
  v_client bigint;
  v_order bigint;
  v_plan bigint;
  v_commissions_before integer;
  v_receipts_before integer;
  v_credit_before integer;
  v_lists_before integer;
begin
  if has_function_privilege('anon', 'public.replace_com_pedido_condicao_financeira_idempotente(uuid,bigint,jsonb,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.replace_com_pedido_condicao_financeira_idempotente(uuid,bigint,jsonb,text)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.fin_pedido_planos_pagamento', 'INSERT')
     or has_table_privilege('authenticated', 'public.fin_pedido_parcelas', 'INSERT') then
    raise exception 'grants da condicao financeira excedem o contrato governado';
  end if;

  insert into auth.users(id, email) values
    (v_authorized, 'payment-terms-authorized-0126@test.invalid'),
    (v_denied, 'payment-terms-denied-0126@test.invalid');
  insert into public.user_profiles(id, display_name, role, status) values
    (v_authorized, 'Condicao financeira autorizada 0126', 'admin', 'active'),
    (v_denied, 'Condicao financeira sem alcada 0126', 'comercial', 'active');
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_authorized, 'pedidos.payment_terms.manage', true, v_authorized),
    (v_authorized, 'system.admin', true, v_authorized)
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_authorized::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'Smoke de condicao financeira 0126');
  end if;

  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
  values ('Cliente condicao financeira 0126', 'cliente condicao financeira 0126', 'Campinas', 'SP', 'active', v_authorized, v_authorized)
  returning id into v_client;
  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by
  ) values (
    'PED-0126-TERMOS', v_client, 'venda', 'blocked', date '2026-08-16', 100.00, v_authorized, v_authorized
  ) returning id into v_order;

  select count(*) into v_commissions_before from public.com_pedido_comissionados;
  select count(*) into v_receipts_before from public.com_recebimentos;
  select count(*) into v_credit_before from public.cad_limites_credito_cliente;
  select count(*) into v_lists_before from public.com_listas_preco;

  if to_regprocedure('public.replace_com_pedido_condicao_financeira_idempotente(uuid,bigint,date,jsonb,text)') is not null then
    raise exception 'RPC ainda permite data base escolhida pelo chamador';
  end if;

  v_plan := public.replace_com_pedido_condicao_financeira_idempotente(
    '12600000-0000-4000-8000-000000000010', v_order,
    '[{"numero_parcela":1,"forma_pagamento":"pix","valor_centavos":10000,"data_vencimento":"2026-08-16"}]',
    'Condicao a vista para validar PMP zero'
  );
  if (select pmp_dias from public.fin_pedido_planos_pagamento where id = v_plan) <> 0 then
    raise exception 'parcela a vista nao calculou PMP zero';
  end if;
  if public.replace_com_pedido_condicao_financeira_idempotente(
    '12600000-0000-4000-8000-000000000010', v_order,
    '[{"numero_parcela":1,"forma_pagamento":"pix","valor_centavos":10000,"data_vencimento":"2026-08-16"}]',
    'Condicao a vista para validar PMP zero'
  ) <> v_plan
     or (select count(*) from public.fin_pedido_condicao_requisicoes where idempotency_key = '12600000-0000-4000-8000-000000000010') <> 1 then
    raise exception 'retry idempotente duplicou condicao financeira';
  end if;

  v_plan := public.replace_com_pedido_condicao_financeira_idempotente(
    '12600000-0000-4000-8000-000000000011', v_order,
    '[{"numero_parcela":1,"forma_pagamento":"boleto","valor_centavos":10000,"data_vencimento":"2026-09-15"}]',
    'Condicao boleto trinta dias para validar PMP'
  );
  if (select pmp_dias from public.fin_pedido_planos_pagamento where id = v_plan) <> 30 then
    raise exception 'parcela trinta dias nao calculou PMP trinta';
  end if;

  v_plan := public.replace_com_pedido_condicao_financeira_idempotente(
    '12600000-0000-4000-8000-000000000012', v_order,
    '[{"numero_parcela":1,"forma_pagamento":"boleto","valor_centavos":5000,"data_vencimento":"2026-09-15"},{"numero_parcela":2,"forma_pagamento":"ted","valor_centavos":5000,"data_vencimento":"2026-10-15"}]',
    'Parcelas iguais trinta e sessenta dias para PMP'
  );
  if (select pmp_dias from public.fin_pedido_planos_pagamento where id = v_plan) <> 45 then
    raise exception 'parcelas iguais nao calcularam PMP quarenta e cinco';
  end if;

  v_plan := public.replace_com_pedido_condicao_financeira_idempotente(
    '12600000-0000-4000-8000-000000000013', v_order,
    '[{"numero_parcela":1,"forma_pagamento":"pix","valor_centavos":2500,"data_vencimento":"2026-09-15"},{"numero_parcela":2,"forma_pagamento":"boleto","valor_centavos":7500,"data_vencimento":"2026-10-15"}]',
    'PIX e boleto com media ponderada por valor'
  );
  if (select pmp_dias from public.fin_pedido_planos_pagamento where id = v_plan) <> 52.5
     or (select count(distinct forma_pagamento) from public.fin_pedido_parcelas where plano_pagamento_id = v_plan) <> 2 then
    raise exception 'combinacao PIX e boleto nao preservou PMP ponderado';
  end if;

  begin
    perform public.replace_com_pedido_condicao_financeira_idempotente(
      '12600000-0000-4000-8000-000000000014', v_order,
      '[{"numero_parcela":1,"forma_pagamento":"pix","valor_centavos":9999,"data_vencimento":"2026-08-16"}]',
      'Soma divergente deve ser bloqueada'
    );
    raise exception 'soma divergente foi aceita';
  exception when others then
    if sqlerrm = 'soma divergente foi aceita' then raise; end if;
    if sqlerrm <> 'soma das parcelas nao reconcilia com o valor financeiro do pedido' then raise; end if;
  end;
  begin
    perform public.replace_com_pedido_condicao_financeira_idempotente(
      '12600000-0000-4000-8000-000000000015', v_order,
      '[{"numero_parcela":1,"forma_pagamento":"ted","valor_centavos":0,"data_vencimento":"2026-08-16"}]',
      'Valor zero deve ser bloqueado'
    );
    raise exception 'valor zero foi aceito';
  exception when others then
    if sqlerrm = 'valor zero foi aceito' then raise; end if;
    if sqlerrm <> 'valor da parcela deve ser maior que zero' then raise; end if;
  end;
  begin
    perform public.replace_com_pedido_condicao_financeira_idempotente(
      '12600000-0000-4000-8000-000000000016', v_order,
      '[{"numero_parcela":1,"forma_pagamento":"cessao_credito","valor_centavos":10000,"data_vencimento":"2026-08-15"}]',
      'Vencimento anterior deve ser bloqueado'
    );
    raise exception 'vencimento anterior foi aceito';
  exception when others then
    if sqlerrm = 'vencimento anterior foi aceito' then raise; end if;
    if sqlerrm <> 'vencimento nao pode ser anterior a data de emissao do pedido' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', v_denied::text, true);
  begin
    perform public.replace_com_pedido_condicao_financeira_idempotente(
      '12600000-0000-4000-8000-000000000017', v_order,
      '[{"numero_parcela":1,"forma_pagamento":"pix","valor_centavos":10000,"data_vencimento":"2026-08-16"}]',
      'Usuario sem permissao deve ser bloqueado'
    );
    raise exception 'usuario sem permissao alterou condicao';
  exception when others then
    if sqlerrm = 'usuario sem permissao alterou condicao' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.payment_terms.manage' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', v_authorized::text, true);

  if (select count(*) from public.com_pedido_comissionados) <> v_commissions_before
     or (select count(*) from public.com_recebimentos) <> v_receipts_before
     or (select count(*) from public.cad_limites_credito_cliente) <> v_credit_before
     or (select count(*) from public.com_listas_preco) <> v_lists_before then
    raise exception 'condicao financeira alterou dominio fora da fase 1B';
  end if;
end
$$;

rollback;
