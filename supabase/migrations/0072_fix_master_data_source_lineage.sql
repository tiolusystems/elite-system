create or replace function public.enforce_cad_source_lineage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source_row_id is null and new.source_batch_id is null then
    return new;
  end if;

  if new.source_row_id is null or new.source_batch_id is null then
    raise exception 'source_batch_id and source_row_id must be provided together';
  end if;

  if not exists (
    select 1
      from public.source_rows source_row
      join public.source_tables source_table
        on source_table.id = source_row.table_id
      join public.migration_batches batch
        on batch.id = new.source_batch_id
       and batch.workbook_id = source_table.workbook_id
     where source_row.id = new.source_row_id
  ) then
    raise exception 'source_row_id does not belong to source_batch_id workbook';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_cad_source_lineage() from public, anon, authenticated;

comment on function public.enforce_cad_source_lineage() is
  'Validates master-data lineage by the workbook shared by source row and migration batch.';
