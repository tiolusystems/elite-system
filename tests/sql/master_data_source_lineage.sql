\set ON_ERROR_STOP on

begin;

do $lineage$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_workbook_a bigint;
  v_workbook_b bigint;
  v_batch_a bigint;
  v_batch_b bigint;
  v_table_a bigint;
  v_row_a bigint;
begin
  insert into public.source_workbooks(file_name, sha256, size_bytes, created_by)
  values ('lineage-a.xlsx', repeat('a', 64), 1, v_actor)
  returning id into v_workbook_a;

  insert into public.source_workbooks(file_name, sha256, size_bytes, created_by)
  values ('lineage-b.xlsx', repeat('b', 64), 1, v_actor)
  returning id into v_workbook_b;

  insert into public.migration_batches(workbook_id, status, created_by, updated_by)
  values (v_workbook_a, 'running', v_actor, v_actor)
  returning id into v_batch_a;

  insert into public.migration_batches(workbook_id, status, created_by, updated_by)
  values (v_workbook_b, 'running', v_actor, v_actor)
  returning id into v_batch_b;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, column_count, row_count
  ) values (
    v_workbook_a, 'Clientes', 'Clientes', 'A1:B2', 2, 1
  ) returning id into v_table_a;

  insert into public.source_rows(table_id, row_index, row_hash)
  values (v_table_a, 0, repeat('c', 64))
  returning id into v_row_a;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, source_row_id, source_batch_id,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente com linhagem valida', 'cliente com linhagem valida', 'Campinas',
    'SP', 'pending_review', v_row_a, v_batch_a, v_actor, v_actor, 'excel_legado'
  );

  begin
    insert into public.cad_clientes(
      nome, nome_norm, cidade, uf, status, source_row_id, source_batch_id,
      created_by, updated_by, origem_dados
    ) values (
      'Cliente com lote incorreto', 'cliente com lote incorreto', 'Campinas',
      'SP', 'pending_review', v_row_a, v_batch_b, v_actor, v_actor, 'excel_legado'
    );
    raise exception 'mismatched workbook lineage was accepted';
  exception
    when others then
      if sqlerrm not like 'source_row_id does not belong to source_batch_id workbook%' then
        raise;
      end if;
  end;

  begin
    insert into public.cad_clientes(
      nome, nome_norm, cidade, uf, status, source_row_id,
      created_by, updated_by, origem_dados
    ) values (
      'Cliente sem lote', 'cliente sem lote', 'Campinas', 'SP',
      'pending_review', v_row_a, v_actor, v_actor, 'excel_legado'
    );
    raise exception 'incomplete lineage pair was accepted';
  exception
    when others then
      if sqlerrm not like 'source_batch_id and source_row_id must be provided together%' then
        raise;
      end if;
  end;
end;
$lineage$;

rollback;

select 'PG_MASTER_DATA_SOURCE_LINEAGE_OK' as validation_marker;
