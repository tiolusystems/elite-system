begin;

do $$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000750';
  v_workbook_id bigint;
  v_other_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_other_table_id bigint;
  v_source_row_id bigint;
  v_other_source_row_id bigint;
  v_unit_id bigint;
  v_historical_unit_id bigint;
  v_nutrient_id bigint;
  v_parameter_id bigint;
  v_product_id bigint;
  v_spec_id bigint;
  v_guarantee_id bigint;
begin
  if v_migration_actor is null then
    raise exception 'DEC-007 smoke requires Migracao Historica actor';
  end if;

  insert into auth.users(id)
  values (v_human_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-007 Human Reviewer', 'admin', 'active')
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
    'test',
    'test_reset',
    'Validacao transacional da DEC-007 em PostgreSQL local descartavel'
  );
  if public.current_system_environment() <> 'test' then
    raise exception 'DEC-007 smoke requires test runtime environment';
  end if;

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec007-fixture.xlsx', repeat('a', 64), 100, '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_workbook_id;

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec007-other-fixture.xlsx', repeat('b', 64), 200, '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_other_workbook_id;

  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', 'DEC-007 fixture', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'Fixture', 'FixtureTable', 'A1:C2', 1, 2, 2, 3, 1, '{}'::jsonb
  ) returning id into v_table_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_other_workbook_id, 'OtherFixture', 'OtherFixtureTable', 'A1:C2', 1, 2, 2, 3, 1, '{}'::jsonb
  ) returning id into v_other_table_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('c', 64), '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_other_table_id, 2, 0, repeat('d', 64), '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_other_source_row_id;

  select id into v_unit_id
    from public.cad_unidades_medida
   where codigo_norm = 'kg';
  if v_unit_id is null then
    raise exception 'canonical kg unit was not seeded';
  end if;
  if public.resolve_cad_unidade_id('quilogramas') <> v_unit_id then
    raise exception 'unit alias did not resolve to canonical kg';
  end if;

  insert into public.cad_unidades_medida(
    codigo, nome, simbolo, dimensao, status, origem_dados,
    source_batch_id, source_row_id, created_by
  ) values (
    'fixture_unit', 'Fixture unit', 'fu', 'outra', 'pending_review', 'excel_legado',
    v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_historical_unit_id;

  begin
    insert into public.cad_unidades_medida(
      codigo, nome, simbolo, dimensao, status, origem_dados,
      source_batch_id, source_row_id, created_by
    ) values (
      'fixture_active', 'Fixture active', 'fa', 'outra', 'active', 'excel_legado',
      v_batch_id, v_source_row_id, v_migration_actor
    );
    raise exception 'historical active unit should have failed';
  exception when others then
    if sqlerrm not like 'excel_legado requires status = pending_review%' then
      raise;
    end if;
  end;

  begin
    insert into public.cad_nutrientes(
      nome, status, origem_dados, source_batch_id, source_row_id, created_by
    ) values (
      'Fixture mismatch', 'pending_review', 'excel_legado',
      v_batch_id, v_other_source_row_id, v_migration_actor
    );
    raise exception 'mismatched source lineage should have failed';
  exception when others then
    if sqlerrm not like 'source_row_id does not belong to source_batch_id workbook%' then
      raise;
    end if;
  end;

  insert into public.cad_nutrientes(nome, simbolo, status, origem_dados, created_by)
  values ('Fixture nutrient', 'FN', 'active', 'sistema', v_migration_actor)
  returning id into v_nutrient_id;

  insert into public.cad_nutriente_aliases(
    nutriente_id, alias, contexto, status, origem_dados, created_by
  ) values (
    v_nutrient_id, 'Fixture nutrient alias', 'global', 'active', 'sistema', v_migration_actor
  );

  if public.resolve_cad_nutriente_id('Fixture nutrient alias') <> v_nutrient_id then
    raise exception 'nutrient alias did not resolve to canonical nutrient';
  end if;

  select id into v_parameter_id
    from public.cad_parametros_tecnicos
   where codigo_norm = 'ph';
  if v_parameter_id is null then
    raise exception 'pH parameter was not seeded';
  end if;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    '7007', 'DEC-007 fixture product', 'dec-007 fixture product',
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_id;

  insert into public.cad_garantias_produto_mapa(
    produto_id, nutriente, nutriente_id, tipo_limite, valor,
    unidade, unidade_id, fonte, justificativa, created_by
  ) values (
    v_product_id, 'Fixture nutrient alias', v_nutrient_id, 'declarado', 1,
    'percentual', (select id from public.cad_unidades_medida where codigo_norm = 'percent'),
    'mapa', 'DEC-007 smoke', v_human_actor
  ) returning id into v_guarantee_id;

  if not exists (
    select 1 from public.cad_garantias_produto_mapa_atuais where id = v_guarantee_id
  ) then
    raise exception 'approved MAPA guarantee did not reach current view';
  end if;

  insert into public.cad_garantias_produto_mapa(
    produto_id, nutriente, nutriente_id, tipo_limite, valor,
    unidade, unidade_id, fonte, justificativa, created_by
  ) values (
    v_product_id, 'Fixture nutrient', v_nutrient_id, 'declarado', 2,
    'percentual', (select id from public.cad_unidades_medida where codigo_norm = 'percent'),
    'calculado', 'DEC-007 calculated legacy smoke', v_human_actor
  ) returning id into v_guarantee_id;

  if not exists (
    select 1
      from public.cad_garantias_produto_calculadas_pendentes
     where id = v_guarantee_id
  ) then
    raise exception 'calculated guarantee was not isolated as pending';
  end if;
  if exists (
    select 1 from public.cad_garantias_produto_mapa_atuais where id = v_guarantee_id
  ) then
    raise exception 'calculated guarantee leaked into MAPA current view';
  end if;

  insert into public.cad_especificacao_produto_versoes(
    produto_id, tipo_especificacao, versao, status, justificativa,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_product_id, 'tecnica', 1, 'pending_review', 'Imported fixture specification',
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_spec_id;

  insert into public.cad_especificacao_produto_parametros(
    especificacao_versao_id, parametro_id, operador, valor_minimo,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_spec_id, v_parameter_id, 'igual', 7,
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  if exists (
    select 1 from public.cad_especificacoes_produto_atuais where id = v_spec_id
  ) then
    raise exception 'historical specification was promoted without activation';
  end if;

  begin
    insert into public.cad_especificacao_produto_ativacoes(
      especificacao_versao_id, motivo, created_by
    ) values (v_spec_id, 'System actor must not activate', v_migration_actor);
    raise exception 'system actor activation should have failed';
  exception when others then
    if sqlerrm not like 'only active human profiles can activate product specifications%' then
      raise;
    end if;
  end;

  insert into public.cad_especificacao_produto_ativacoes(
    especificacao_versao_id, motivo, created_by
  ) values (v_spec_id, 'Human-reviewed fixture', v_human_actor);

  if not exists (
    select 1 from public.cad_especificacoes_produto_atuais where id = v_spec_id
  ) then
    raise exception 'human activation did not publish current specification';
  end if;

  begin
    update public.cad_especificacao_produto_versoes
       set justificativa = 'forbidden edit'
     where id = v_spec_id;
    raise exception 'append-only specification update should have failed';
  exception when others then
    if sqlerrm not like 'cad_especificacao_produto_versoes is append-only%' then
      raise;
    end if;
  end;

  if has_table_privilege('authenticated', 'public.cad_unidades_medida', 'INSERT') then
    raise exception 'authenticated retained direct insert on technical catalog';
  end if;
  if has_table_privilege('authenticated', 'public.cad_especificacao_produto_versoes', 'UPDATE') then
    raise exception 'authenticated retained direct update on specification versions';
  end if;
end;
$$;

rollback;

select 'DEC_007_TECHNICAL_CATALOGS_SMOKE_OK' as result;
