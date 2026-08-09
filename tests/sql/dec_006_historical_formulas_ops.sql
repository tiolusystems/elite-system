\set ON_ERROR_STOP on

begin;

do $dec006$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000754';
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_source_row_id bigint;
  v_second_source_row_id bigint;
  v_l_id bigint := public.resolve_cad_unidade_id('l');
  v_kg_id bigint := public.resolve_cad_unidade_id('kg');
  v_product_id bigint;
  v_mp_id bigint;
  v_system_formula_id bigint;
  v_historical_formula_id bigint;
  v_historical_item_id bigint;
  v_stage_id bigint;
  v_unknown_ref_id bigint;
  v_historical_op_id bigint;
  v_pa_before bigint;
  v_pi_before bigint;
begin
  if v_migration_actor is null or v_l_id is null or v_kg_id is null then
    raise exception 'DEC-006 smoke prerequisites are missing';
  end if;

  insert into auth.users(id) values (v_human_actor)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-006 Human Reviewer', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = false,
    system_actor_key = null;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_human_actor, 'system.admin', true, v_human_actor)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_human_actor::text, true);
  perform public.set_system_runtime_environment(
    'test', 'test_reset', 'Validacao transacional da DEC-006 em PostgreSQL local'
  );

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec006-fixture.xlsx', repeat('6', 64), 600,
    '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_workbook_id;
  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', 'DEC-006 fixture', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;
  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'Formula', 'DEC006Fixture', 'A1:H3', 1, 2, 3, 8, 2, '{}'::jsonb
  ) returning id into v_table_id;
  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('7', 64), '{"fixture":1}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;
  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 3, 1, repeat('8', 64), '{"fixture":2}'::jsonb, '{}'::jsonb
  ) returning id into v_second_source_row_id;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    '8006', 'Produto DEC-006', 'produto dec-006', 'active', '{}'::jsonb,
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_id;
  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status,
    payload_origem_json, created_by, updated_by, origem_dados
  ) values (
    'DEC006-MP', 'MP DEC-006', 'mp dec-006', 'kg', 'active', '{}'::jsonb,
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_mp_id;

  insert into public.pcp_formula_versoes(
    produto_id, tipo_receita, versao, justificativa, entry_hash,
    created_by, review_status, origem_dados
  ) values (
    v_product_id, 'producao', 1, 'Formula operacional fixture', repeat('a', 64),
    v_human_actor, 'approved', 'sistema'
  ) returning id into v_system_formula_id;
  insert into public.pcp_formula_rendimentos(
    formula_versao_id, quantidade_base, unidade_base_id,
    quantidade_saida, unidade_saida_id, natureza_saida,
    review_status, origem_dados, created_by
  ) values (
    v_system_formula_id, 1, v_l_id, 1, v_l_id, 'PI',
    'approved', 'sistema', v_human_actor
  );
  insert into public.pcp_formula_ativacoes(
    formula_versao_id, produto_id, tipo_receita, motivo, created_by
  ) values (
    v_system_formula_id, v_product_id, 'producao', 'Fixture operacional', v_human_actor
  );

  if not exists (
    select 1 from public.pcp_formula_versoes_completas
    where formula_versao_id = v_system_formula_id and natureza_saida = 'PI'
  ) then
    raise exception 'system formula yield did not reach complete view';
  end if;

  insert into public.pcp_formula_versoes(
    produto_id, tipo_receita, versao, justificativa, entry_hash,
    created_by, review_status, origem_dados, source_batch_id, source_row_id
  ) values (
    v_product_id, 'producao', 2, 'Formula historica pendente', repeat('b', 64),
    v_migration_actor, 'pending_review', 'excel_legado',
    v_batch_id, v_source_row_id
  ) returning id into v_historical_formula_id;
  insert into public.pcp_formula_itens(
    formula_versao_id, tipo_componente, materia_prima_id,
    quantidade, unidade, unidade_id, review_status, origem_dados,
    source_batch_id, source_row_id, created_by
  ) values (
    v_historical_formula_id, 'MP', v_mp_id, 1, 'kg', v_kg_id,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor
  ) returning id into v_historical_item_id;
  insert into public.pcp_formula_rendimentos(
    formula_versao_id, quantidade_base, unidade_base_id,
    quantidade_saida, unidade_saida_id, natureza_saida,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_formula_id, 1, v_l_id, 1, v_l_id, 'nao_determinada',
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor
  );
  insert into public.pcp_formula_etapas(
    formula_versao_id, sequencia, fase, instrucao,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_formula_id, 1, 'Fase A', 'Adicionar lentamente',
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor
  ) returning id into v_stage_id;
  insert into public.pcp_formula_item_etapas(
    formula_versao_id, formula_item_id, etapa_id, ordem_adicao,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_formula_id, v_historical_item_id, v_stage_id, 1,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor
  );

  begin
    insert into public.pcp_formula_ativacoes(
      formula_versao_id, produto_id, tipo_receita, motivo, created_by
    ) values (
      v_historical_formula_id, v_product_id, 'producao',
      'Tentativa historica', v_human_actor
    );
    raise exception 'historical formula was activated';
  exception when others then
    if sqlerrm <> 'historical or pending formula cannot be activated' then
      raise;
    end if;
  end;

  insert into public.pcp_formula_referencias_historicas(
    produto_id, codigo_legado, evidencia_detalhe,
    source_batch_id, source_row_id, created_by
  ) values (
    v_product_id, null,
    'Workbook nao identifica a versao de formula usada pela OP',
    v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_unknown_ref_id;

  insert into public.pcp_ordens_producao(
    codigo_op, produto_id, formula_versao_id, formula_referencia_historica_id,
    tipo_op, tipo_op_legado, status, quantidade_planejada,
    review_status, origem_dados, source_batch_id, source_row_id,
    created_by, updated_by
  ) values (
    'DEC006-OP-HIST', v_product_id, null, v_unknown_ref_id,
    'historico_nao_classificado', 'TIPO LEGADO', 'completed', 100,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor, v_migration_actor
  ) returning id into v_historical_op_id;

  if not exists (
    select 1 from public.pcp_op_historicas_pendentes
    where id = v_historical_op_id
      and formula_versao_id is null
      and formula_referencia_historica_id = v_unknown_ref_id
  ) then
    raise exception 'unknown historical formula reference was not preserved';
  end if;

  begin
    insert into public.pcp_ordens_producao(
      codigo_op, produto_id, formula_versao_id, tipo_op, status,
      review_status, origem_dados, source_batch_id, source_row_id,
      created_by, updated_by
    ) values (
      'DEC006-OP-BAD', v_product_id, v_system_formula_id, 'estoque', 'completed',
      'pending_review', 'excel_legado', v_batch_id, v_second_source_row_id,
      v_migration_actor, v_migration_actor
    );
    raise exception 'historical OP referenced current formula';
  exception when others then
    if sqlerrm <> 'historical OP cannot reference a current system formula' then
      raise;
    end if;
  end;

  select count(*) into v_pa_before from public.est_movimentos_pa;
  select count(*) into v_pi_before from public.est_movimentos_pi;

  insert into public.pcp_op_saidas_historicas(
    op_id, produto_id, natureza_saida, codigo_lote_legado,
    quantidade, unidade_id, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_op_id, v_product_id, 'nao_classificada', 'LOTE-LEGADO',
    100, v_l_id, v_batch_id, v_source_row_id, v_migration_actor
  );
  insert into public.pcp_op_cq_historico_parcial(
    op_id, ph, densidade_kg_l, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_op_id, 6.5, 1.1, v_batch_id, v_source_row_id, v_migration_actor
  );

  if (select count(*) from public.est_movimentos_pa) <> v_pa_before
     or (select count(*) from public.est_movimentos_pi) <> v_pi_before then
    raise exception 'historical OP generated stock automatically';
  end if;

  begin
    update public.pcp_ordens_producao set status = 'in_process'
    where id = v_historical_op_id;
    raise exception 'historical OP entered live workflow';
  exception when others then
    if sqlerrm <> 'historical OP state is immutable and cannot enter the live workflow' then
      raise;
    end if;
  end;
end;
$dec006$;

rollback;

select 'DEC_006_HISTORICAL_FORMULAS_OPS_SMOKE_OK' as result;
