\set ON_ERROR_STOP on

begin;

do $dec009$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000755';
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_source_row_id bigint;
  v_client_id bigint;
  v_person_id bigint;
  v_order_id bigint;
  v_commissioned_id bigint;
  v_historical_plan_id bigint;
  v_system_plan_id bigint;
  v_receipts_before bigint;
  v_allocations_before bigint;
  v_commission_movements_before bigint;
  v_fiscal_documents_before bigint;
begin
  if v_migration_actor is null then
    raise exception 'DEC-009 smoke requires Migracao Historica actor';
  end if;

  insert into auth.users(id) values (v_human_actor)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-009 Human Reviewer', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = false,
    system_actor_key = null;

  select count(*) into v_receipts_before from public.com_recebimentos;
  select count(*) into v_allocations_before from public.fin_recebimento_alocacoes;
  select count(*) into v_commission_movements_before from public.fin_comissao_movimentos;
  select count(*) into v_fiscal_documents_before from public.fat_notas_fiscais;

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec009-fixture.xlsx', repeat('9', 64), 900,
    '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_workbook_id;

  insert into public.migration_batches(
    workbook_id, status, notes, created_by, updated_by
  ) values (
    v_workbook_id, 'running', 'DEC-009 fixture',
    v_migration_actor, v_migration_actor
  ) returning id into v_batch_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'PEDIDOS_RESUMO', 'GESTAO_PEDIDOS', 'A1:AZ2',
    1, 2, 2, 52, 1, '{}'::jsonb
  ) returning id into v_table_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('8', 64),
    '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente DEC-009', 'cliente dec-009', 'Campinas', 'SP', 'active',
    '[]'::jsonb, '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Vendedor DEC-009', 'vendedor dec-009', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_person_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    condicao_pagamento, origem_canal, valor_total,
    created_by, updated_by, origem_dados
  ) values (
    'DEC009-PED', v_client_id, 'venda', 'open', current_date,
    '30/60', 'interno', 1200,
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.com_pedido_comissionados(
    pedido_id, pessoa_id, papel_comissao, percentual_comissao,
    valor_base, valor_previsto, status, created_by, updated_by
  ) values (
    v_order_id, v_person_id, 'vendedor', 5, 1200, 60,
    'prevista', v_human_actor, v_human_actor
  ) returning id into v_commissioned_id;

  insert into public.fin_pedido_planos_pagamento(
    pedido_id, versao, review_status, origem_dados,
    source_batch_id, source_row_id, created_by
  ) values (
    v_order_id, 1, 'pending_review', 'excel_legado',
    v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_historical_plan_id;

  insert into public.fin_pedido_parcelas(
    plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values
    (
      v_historical_plan_id, 1, current_date + 30, null,
      'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
      v_migration_actor
    ),
    (
      v_historical_plan_id, 2, current_date + 60, null,
      'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
      v_migration_actor
    );

  insert into public.fin_recebimento_posicoes_historicas(
    pedido_id, status_recebimento_legado, classificacao_normalizada,
    data_posicao, source_batch_id, source_row_id, created_by
  ) values (
    v_order_id, 'RECEBIDO', null, null,
    v_batch_id, v_source_row_id, v_migration_actor
  );

  insert into public.fin_comissao_posicoes_historicas(
    comissionado_id, valor_pago_informado, data_posicao,
    source_batch_id, source_row_id, created_by
  ) values (
    v_commissioned_id, 50, null,
    v_batch_id, v_source_row_id, v_migration_actor
  );

  insert into public.fat_referencias_fiscais_historicas(
    pedido_id, referencia_legada, data_emissao_informada,
    source_batch_id, source_row_id, created_by
  ) values (
    v_order_id, 'NF 12345', null,
    v_batch_id, v_source_row_id, v_migration_actor
  );

  if (select count(*) from public.com_recebimentos) <> v_receipts_before
     or (select count(*) from public.fin_recebimento_alocacoes) <> v_allocations_before
     or (select count(*) from public.fin_comissao_movimentos) <> v_commission_movements_before
     or (select count(*) from public.fat_notas_fiscais) <> v_fiscal_documents_before then
    raise exception 'legacy positions created operational financial/fiscal events';
  end if;

  if exists (
    select 1 from public.fin_pedido_parcelas_atuais current_installment
    where current_installment.pedido_id = v_order_id
  ) then
    raise exception 'historical pending schedule leaked into operational read model';
  end if;

  if not exists (
    select 1
      from public.fin_recebimento_posicoes_historicas receipt_position
      join public.fin_comissao_posicoes_historicas commission_position
        on commission_position.source_row_id = receipt_position.source_row_id
      join public.fat_referencias_fiscais_historicas fiscal_reference
        on fiscal_reference.source_row_id = receipt_position.source_row_id
     where receipt_position.pedido_id = v_order_id
       and receipt_position.classificacao_normalizada is null
       and receipt_position.data_posicao is null
       and commission_position.data_posicao is null
       and fiscal_reference.data_emissao_informada is null
  ) then
    raise exception 'DEC-009 did not preserve explicit unknown dates/classification';
  end if;

  insert into public.fin_pedido_planos_pagamento(
    pedido_id, versao, vigencia_inicio, review_status,
    origem_dados, created_by
  ) values (
    v_order_id, 2, current_date, 'approved', 'sistema', v_human_actor
  ) returning id into v_system_plan_id;

  insert into public.fin_pedido_parcelas(
    plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto,
    review_status, origem_dados, created_by
  ) values (
    v_system_plan_id, 1, current_date + 30, 1200,
    'approved', 'sistema', v_human_actor
  );

  if not exists (
    select 1 from public.fin_pedido_parcelas_atuais current_installment
    where current_installment.pedido_id = v_order_id
      and current_installment.versao = 2
      and current_installment.numero_parcela = 1
  ) then
    raise exception 'approved system schedule is absent from operational read model';
  end if;

  begin
    insert into public.fin_recebimento_posicoes_historicas(
      pedido_id, status_recebimento_legado, review_status,
      source_batch_id, source_row_id, created_by
    ) values (
      v_order_id, 'RECEBIDO', 'approved',
      v_batch_id, v_source_row_id, v_migration_actor
    );
    raise exception 'historical receipt position was approved automatically';
  exception when others then
    if sqlerrm not like 'excel_legado requires review_status = pending_review%'
       and sqlerrm not like '%fin_recebimento_posicoes_review_check%' then
      raise;
    end if;
  end;

  begin
    insert into public.fin_pedido_planos_pagamento(
      pedido_id, versao, review_status, origem_dados,
      source_batch_id, source_row_id, created_by
    ) values (
      v_order_id, 3, 'pending_review', 'excel_legado',
      v_batch_id, v_source_row_id, v_migration_actor
    );
    raise exception 'duplicate historical payment plan was accepted';
  exception when unique_violation then
    null;
  end;

  begin
    update public.fat_referencias_fiscais_historicas
       set referencia_legada = 'NF ALTERADA'
     where pedido_id = v_order_id;
    raise exception 'historical fiscal reference was edited';
  exception when others then
    if sqlerrm not like '%is append-only; create a new version or historical position%' then
      raise;
    end if;
  end;
end;
$dec009$;

rollback;

select 'DEC_009_LEGACY_FINANCIAL_FISCAL_SMOKE_OK' as result;
