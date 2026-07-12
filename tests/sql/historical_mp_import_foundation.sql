\set ON_ERROR_STOP on

begin;

do $setup$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000045';
  v_workbook_id bigint;
  v_table_master_id bigint;
  v_table_entry_id bigint;
begin
  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Historical MP Smoke Actor', 'admin', 'active')
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
      'Smoke da fundacao de importacao historica de MP'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'historical MP smoke requires unconfigured or test environment';
  end if;

  insert into public.source_workbooks(
    source_path, file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    null,
    'fixture-historico-mp.xlsx',
    'fixture-historico-mp-0045',
    1,
    '{"fixture":true}'::jsonb,
    v_actor
  ) returning id into v_workbook_id;

  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'completed', 'Fixture descartavel 0045', v_actor, v_actor);

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row,
    data_first_row, data_last_row, column_count, row_count
  ) values (
    v_workbook_id, 'Cadastro MP', 'CADASTRO_MATERIA_PRIMA', 'A1:H2', 1, 2, 2, 8, 1
  ) returning id into v_table_master_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row,
    data_first_row, data_last_row, column_count, row_count
  ) values (
    v_workbook_id, 'Entradas MP', 'ENTRADAS_MP', 'A1:N2', 1, 2, 2, 14, 1
  ) returning id into v_table_entry_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json
  ) values
    (
      v_table_master_id,
      2,
      1,
      'fixture-master-row-0045',
      '{"id_sku_mp":"LEG-0045","MATERIA PRIMA":"MP Historico Smoke"}'::jsonb
    ),
    (
      v_table_entry_id,
      2,
      1,
      'fixture-entry-row-0045',
      '{"ORIGEM (NF)":"NF-0045","QUANTIDADE":100,"VALOR":1200,"FRETE":100,"Dif. ICMS":60}'::jsonb
    );
end;
$setup$;

set local role authenticated;

do $smoke$
declare
  v_batch_id bigint;
  v_master_row_id bigint;
  v_entry_row_id bigint;
  v_mp_id bigint;
  v_staging_id bigint;
  v_mapping_1 bigint;
  v_mapping_2 bigint;
  v_lote_id bigint;
  v_lote_sp_id bigint;
  v_movement_id bigint;
  v_movement_sp_id bigint;
  v_value_1 bigint;
  v_value_2 bigint;
  v_total numeric;
  v_unit numeric;
  v_result jsonb;
begin
  select batch.id
    into v_batch_id
    from public.migration_batches batch
    join public.source_workbooks workbook on workbook.id = batch.workbook_id
   where workbook.sha256 = 'fixture-historico-mp-0045';

  select source_row.id
    into v_master_row_id
    from public.source_rows source_row
    join public.source_tables source_table on source_table.id = source_row.table_id
   where source_table.table_name = 'CADASTRO_MATERIA_PRIMA'
     and source_row.row_hash = 'fixture-master-row-0045';

  select source_row.id
    into v_entry_row_id
    from public.source_rows source_row
    join public.source_tables source_table on source_table.id = source_row.table_id
   where source_table.table_name = 'ENTRADAS_MP'
     and source_row.row_hash = 'fixture-entry-row-0045';

  v_result := public.stage_migration_mp_items(
    v_batch_id,
    jsonb_build_array(
      jsonb_build_object(
        'source_row_id', v_master_row_id,
        'codigo_legado', 'LEG-0045',
        'nome_legado', 'MP Historico Smoke',
        'unidade_origem', 'KG',
        'densidade', 1.1,
        'estoque_minimo', 20,
        'custo_unitario_snapshot', 12
      )
    )
  );
  if (v_result->>'inserted')::integer <> 1 or (v_result->>'existing')::integer <> 0 then
    raise exception 'first MP staging call did not insert exactly one row: %', v_result;
  end if;

  v_result := public.stage_migration_mp_items(
    v_batch_id,
    jsonb_build_array(
      jsonb_build_object(
        'source_row_id', v_master_row_id,
        'codigo_legado', 'LEG-0045',
        'nome_legado', 'MP Historico Smoke',
        'unidade_origem', 'KG',
        'densidade', 1.1,
        'estoque_minimo', 20,
        'custo_unitario_snapshot', 12
      )
    )
  );
  if (v_result->>'inserted')::integer <> 0 or (v_result->>'existing')::integer <> 1 then
    raise exception 'second MP staging call was not idempotent: %', v_result;
  end if;

  select staging.id
    into v_staging_id
    from public.migration_mp_staging_items staging
   where staging.batch_id = v_batch_id
     and staging.source_row_id = v_master_row_id;

  v_mp_id := public.create_cad_materia_prima(
    'MP Historico Smoke 0045',
    'mp historico smoke 0045',
    'MP-0045',
    'KG',
    'active',
    'LEG-0045'
  );

  v_mapping_1 := public.approve_migration_mp_mapping(
    v_staging_id,
    v_mp_id,
    'exact_legacy_code',
    98,
    'exact_match',
    null
  );
  v_mapping_2 := public.approve_migration_mp_mapping(
    v_staging_id,
    v_mp_id,
    'exact_legacy_code',
    98,
    'exact_match',
    null
  );
  if v_mapping_1 is distinct from v_mapping_2 then
    raise exception 'mapping approval retry returned another event';
  end if;
  if (select count(*) from public.cad_materia_prima_aliases where materia_prima_id = v_mp_id) <> 2 then
    raise exception 'canonical MP aliases were not created exactly once';
  end if;

  v_lote_id := public.create_est_lote_mp(
    v_mp_id,
    100,
    null,
    'entrada_compra',
    'disponivel',
    current_date,
    current_date + 365,
    'NF-0045',
    'Entrada historica do smoke'
  );
  select movement.id
    into v_movement_id
    from public.est_movimentos_mp movement
   where movement.lote_mp_id = v_lote_id
     and movement.tipo_movimento = 'entrada_compra';

  v_value_1 := public.register_migration_mp_acquisition_value(
    p_movimento_mp_id => v_movement_id,
    p_quantidade_origem => 0.1,
    p_unidade_origem => 'TON',
    p_quantidade_base => 100,
    p_valor_materia_prima => 1200,
    p_frete => 100,
    p_difal_icms => 60,
    p_difal_status => 'informed',
    p_outras_despesas => 40,
    p_custo_total_legado => 1400,
    p_custo_medio_ponderado_legado => 14,
    p_saldo_lote_legado => 100,
    p_documento_ref => 'NF-0045',
    p_data_documento => current_date,
    p_uf_emitente => 'MG',
    p_source_batch_id => v_batch_id,
    p_source_row_id => v_entry_row_id
  );
  v_value_2 := public.register_migration_mp_acquisition_value(
    p_movimento_mp_id => v_movement_id,
    p_quantidade_origem => 0.1,
    p_unidade_origem => 'TON',
    p_quantidade_base => 100,
    p_valor_materia_prima => 1200,
    p_frete => 100,
    p_difal_icms => 60,
    p_difal_status => 'informed',
    p_outras_despesas => 40,
    p_custo_total_legado => 1400,
    p_custo_medio_ponderado_legado => 14,
    p_saldo_lote_legado => 100,
    p_documento_ref => 'NF-0045',
    p_data_documento => current_date,
    p_uf_emitente => 'MG',
    p_source_batch_id => v_batch_id,
    p_source_row_id => v_entry_row_id
  );
  if v_value_1 is distinct from v_value_2 then
    raise exception 'acquisition value retry returned another row';
  end if;

  select value.custo_aquisicao_total, value.custo_unitario_base
    into v_total, v_unit
    from public.est_movimentos_mp_valores value
   where value.id = v_value_1;
  if v_total <> 1400 or v_unit <> 14 then
    raise exception 'acquisition calculation is wrong: total %, unit %', v_total, v_unit;
  end if;

  begin
    perform public.register_migration_mp_acquisition_value(
      p_movimento_mp_id => v_movement_id,
      p_quantidade_origem => 0.1,
      p_unidade_origem => 'TON',
      p_quantidade_base => 100,
      p_valor_materia_prima => 1200,
      p_frete => 100,
      p_difal_icms => 60,
      p_difal_status => 'informed',
      p_outras_despesas => 40,
      p_documento_ref => 'NF-ALTERADA',
      p_data_documento => current_date,
      p_uf_emitente => 'MG',
      p_source_batch_id => v_batch_id,
      p_source_row_id => v_entry_row_id
    );
    raise exception 'immutable acquisition metadata drift was accepted';
  exception
    when others then
      if sqlerrm <> 'acquisition value already exists with different immutable data' then
        raise;
      end if;
  end;

  begin
    perform public.register_migration_mp_acquisition_value(
      p_movimento_mp_id => v_movement_id,
      p_quantidade_origem => 0.1,
      p_unidade_origem => 'TON',
      p_quantidade_base => 99,
      p_valor_materia_prima => 1200,
      p_frete => 100,
      p_difal_icms => 60,
      p_difal_status => 'informed',
      p_source_batch_id => v_batch_id,
      p_source_row_id => v_entry_row_id
    );
    raise exception 'acquisition quantity different from movement was accepted';
  exception
    when others then
      if sqlerrm <> 'quantidade_base must match the physical MP entry movement quantity' then
        raise;
      end if;
  end;

  v_lote_sp_id := public.create_est_lote_mp(v_mp_id, 10, null, 'entrada_compra');
  select movement.id into v_movement_sp_id
    from public.est_movimentos_mp movement
   where movement.lote_mp_id = v_lote_sp_id
     and movement.tipo_movimento = 'entrada_compra';
  begin
    perform public.register_migration_mp_acquisition_value(
      p_movimento_mp_id => v_movement_sp_id,
      p_quantidade_origem => 10,
      p_unidade_origem => 'KG',
      p_quantidade_base => 10,
      p_valor_materia_prima => 100,
      p_frete => 0,
      p_difal_icms => 0,
      p_difal_status => 'not_applicable',
      p_uf_emitente => 'SP',
      p_source_batch_id => v_batch_id,
      p_source_row_id => v_master_row_id
    );
    raise exception 'master-data row was accepted as acquisition source';
  exception
    when others then
      if sqlerrm <> 'historical acquisition source must be an ENTRADAS_MP row from the batch workbook' then
        raise;
      end if;
  end;

  begin
    perform public.register_migration_mp_acquisition_value(
      p_movimento_mp_id => v_movement_sp_id,
      p_quantidade_origem => 10,
      p_unidade_origem => 'KG',
      p_quantidade_base => 10,
      p_valor_materia_prima => 100,
      p_frete => 0,
      p_difal_icms => 5,
      p_difal_status => 'informed',
      p_uf_emitente => 'SP',
      p_source_batch_id => v_batch_id,
      p_source_row_id => v_entry_row_id
    );
    raise exception 'positive DIFAL for SP was accepted';
  exception
    when others then
      if sqlerrm <> 'DIFAL cannot be positive for SP emitter under the approved business rule' then
        raise;
      end if;
  end;

  if not exists (
    select 1 from public.migration_mp_mapping_dashboard dashboard
    where dashboard.staging_item_id = v_staging_id
      and dashboard.mapping_status = 'approved'
      and dashboard.materia_prima_id = v_mp_id
  ) then
    raise exception 'mapping dashboard did not expose the approved canonical MP';
  end if;
  if not exists (
    select 1 from public.est_mp_historico_precos history
    where history.acquisition_value_id = v_value_1
      and history.difal_icms = 60
      and history.custo_aquisicao_total = 1400
  ) then
    raise exception 'historical MP price view did not preserve acquisition components';
  end if;

  begin
    insert into public.migration_mp_staging_items(
      batch_id, source_row_id, nome_legado, payload_hash, created_by
    ) values (v_batch_id, v_entry_row_id, 'Escrita direta proibida', 'forbidden', public.current_actor_id());
    raise exception 'authenticated direct write to MP staging was accepted';
  exception
    when insufficient_privilege then null;
  end;

end;
$smoke$;

reset role;

do $append_only$
begin
  if not exists (
    select 1 from public.action_logs log
    where log.action_key = 'migration.mp.map'
      and log.action = 'auditoria.mp_mapping_approved'
  ) or not exists (
    select 1 from public.action_logs log
    where log.action_key = 'estoque.mp.acquisition_value.register'
      and log.action = 'estoque.mp_acquisition_value_registered'
  ) or not exists (
    select 1 from public.action_logs log
    where log.action_key = 'migration.mp.import'
      and log.action = 'auditoria.mp_acquisition_imported'
  ) then
    raise exception 'audited MP import logs are incomplete';
  end if;

  begin
    update public.est_movimentos_mp_valores
       set documento_ref = 'ALTERACAO-PROIBIDA'
     where documento_ref = 'NF-0045';
    raise exception 'append-only acquisition value accepted update';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  begin
    delete from public.migration_mp_mapping_events
     where reason_code = 'exact_match';
    raise exception 'append-only MP mapping accepted delete';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;
end;
$append_only$;

rollback;

\echo PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK
