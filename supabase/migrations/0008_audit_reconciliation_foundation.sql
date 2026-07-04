create table if not exists public.source_workbooks (
  id bigint generated always as identity primary key,
  source_path text,
  file_name text not null,
  sha256 text not null unique,
  size_bytes bigint not null,
  imported_at timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  constraint source_workbooks_sha256_check check (length(btrim(sha256)) > 0),
  constraint source_workbooks_size_check check (size_bytes >= 0)
);

create table if not exists public.migration_batches (
  id bigint generated always as identity primary key,
  workbook_id bigint not null references public.source_workbooks(id),
  status text not null default 'running',
  notes text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint migration_batches_status_check check (status in ('running', 'completed', 'failed', 'cancelled'))
);

create table if not exists public.source_tables (
  id bigint generated always as identity primary key,
  workbook_id bigint not null references public.source_workbooks(id) on delete cascade,
  sheet_name text not null,
  table_name text not null,
  ref text not null,
  header_row integer,
  data_first_row integer,
  data_last_row integer,
  column_count integer not null default 0,
  row_count integer not null default 0,
  metadata_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint source_tables_counts_check check (column_count >= 0 and row_count >= 0),
  constraint source_tables_key unique (workbook_id, sheet_name, table_name, ref)
);

create table if not exists public.source_rows (
  id bigint generated always as identity primary key,
  table_id bigint not null references public.source_tables(id) on delete cascade,
  excel_row_number integer,
  row_index integer not null,
  row_hash text not null,
  payload_json jsonb not null default '{}'::jsonb,
  formulas_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint source_rows_row_index_check check (row_index >= 0),
  constraint source_rows_hash_check check (length(btrim(row_hash)) > 0),
  constraint source_rows_key unique (table_id, row_index, row_hash)
);

create table if not exists public.migration_issues (
  id bigint generated always as identity primary key,
  batch_id bigint references public.migration_batches(id),
  severity text not null,
  scope text not null,
  source_table text,
  source_row_id bigint references public.source_rows(id),
  code text not null,
  message text not null,
  payload_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint migration_issues_severity_check check (severity in ('info', 'warning', 'error')),
  constraint migration_issues_scope_check check (length(btrim(scope)) > 0),
  constraint migration_issues_code_check check (length(btrim(code)) > 0)
);

create table if not exists public.imported_records (
  id bigint generated always as identity primary key,
  batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  entity_name text not null,
  entity_key text,
  payload_hash text not null,
  created_at timestamptz not null default now(),
  constraint imported_records_entity_check check (length(btrim(entity_name)) > 0),
  constraint imported_records_payload_hash_check check (length(btrim(payload_hash)) > 0),
  constraint imported_records_key unique (batch_id, source_row_id, entity_name)
);

create table if not exists public.audit_snapshots (
  id bigint generated always as identity primary key,
  batch_id bigint not null references public.migration_batches(id),
  audit_name text not null,
  source_table text,
  expected_count integer,
  actual_count integer,
  status text not null,
  payload_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint audit_snapshots_status_check check (status in ('ok', 'attention', 'issue', 'missing')),
  constraint audit_snapshots_counts_check check (
    (expected_count is null or expected_count >= 0)
    and (actual_count is null or actual_count >= 0)
  ),
  constraint audit_snapshots_key unique (batch_id, audit_name, source_table)
);

create table if not exists public.source_expected_metrics (
  batch_id bigint not null references public.migration_batches(id) on delete cascade,
  metric_name text not null,
  source_label text not null,
  source_value numeric,
  tolerance numeric not null default 0.01,
  details_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (batch_id, metric_name),
  constraint source_expected_metrics_name_check check (length(btrim(metric_name)) > 0),
  constraint source_expected_metrics_tolerance_check check (tolerance >= 0)
);

create table if not exists public.audit_reconciliation_runs (
  id bigint generated always as identity primary key,
  batch_id bigint references public.migration_batches(id),
  scope text not null default 'operational',
  status text not null default 'running',
  metric_count integer not null default 0,
  attention_count integer not null default 0,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint audit_reconciliation_runs_status_check check (status in ('running', 'ok', 'attention', 'failed')),
  constraint audit_reconciliation_runs_counts_check check (metric_count >= 0 and attention_count >= 0)
);

create table if not exists public.value_reconciliations (
  id bigint generated always as identity primary key,
  run_id bigint not null references public.audit_reconciliation_runs(id) on delete cascade,
  batch_id bigint references public.migration_batches(id),
  metric_name text not null,
  source_label text not null,
  source_value numeric,
  system_value numeric,
  difference numeric,
  tolerance numeric not null,
  status text not null,
  details_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint value_reconciliations_status_check check (status in ('ok', 'attention', 'issue', 'missing')),
  constraint value_reconciliations_tolerance_check check (tolerance >= 0),
  constraint value_reconciliations_key unique (run_id, metric_name)
);

create table if not exists public.reconciliation_details (
  id bigint generated always as identity primary key,
  run_id bigint not null references public.audit_reconciliation_runs(id) on delete cascade,
  batch_id bigint references public.migration_batches(id),
  metric_name text not null,
  key_type text not null,
  key_norm text not null,
  key_label text not null,
  source_value numeric not null default 0,
  system_value numeric not null default 0,
  difference numeric,
  tolerance numeric not null,
  status text not null,
  details_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint reconciliation_details_status_check check (status in ('ok', 'attention', 'issue', 'missing')),
  constraint reconciliation_details_tolerance_check check (tolerance >= 0),
  constraint reconciliation_details_key unique (run_id, metric_name, key_type, key_norm)
);

create index if not exists idx_migration_batches_workbook
  on public.migration_batches(workbook_id, started_at desc);

create index if not exists idx_source_tables_workbook
  on public.source_tables(workbook_id, table_name);

create index if not exists idx_source_rows_table
  on public.source_rows(table_id, row_index);

create index if not exists idx_migration_issues_batch
  on public.migration_issues(batch_id, severity, source_table);

create index if not exists idx_imported_records_batch_entity
  on public.imported_records(batch_id, entity_name);

create index if not exists idx_audit_snapshots_batch
  on public.audit_snapshots(batch_id, status);

create index if not exists idx_audit_reconciliation_runs_batch
  on public.audit_reconciliation_runs(batch_id, created_at desc);

create index if not exists idx_value_reconciliations_run_status
  on public.value_reconciliations(run_id, status, metric_name);

create index if not exists idx_reconciliation_details_run_status
  on public.reconciliation_details(run_id, status, metric_name);

drop trigger if exists trg_migration_batches_updated_at on public.migration_batches;
create trigger trg_migration_batches_updated_at before update on public.migration_batches
for each row execute function public.touch_updated_at();

drop trigger if exists trg_source_expected_metrics_updated_at on public.source_expected_metrics;
create trigger trg_source_expected_metrics_updated_at before update on public.source_expected_metrics
for each row execute function public.touch_updated_at();

create or replace function public.prevent_migration_source_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'migration source records are append-only';
end;
$$;

drop trigger if exists trg_source_workbooks_no_update on public.source_workbooks;
create trigger trg_source_workbooks_no_update
before update or delete on public.source_workbooks
for each row execute function public.prevent_migration_source_changes();

drop trigger if exists trg_source_tables_no_update on public.source_tables;
create trigger trg_source_tables_no_update
before update or delete on public.source_tables
for each row execute function public.prevent_migration_source_changes();

drop trigger if exists trg_source_rows_no_update on public.source_rows;
create trigger trg_source_rows_no_update
before update or delete on public.source_rows
for each row execute function public.prevent_migration_source_changes();

drop trigger if exists trg_imported_records_no_update on public.imported_records;
create trigger trg_imported_records_no_update
before update or delete on public.imported_records
for each row execute function public.prevent_migration_source_changes();

alter table public.source_workbooks enable row level security;
alter table public.migration_batches enable row level security;
alter table public.source_tables enable row level security;
alter table public.source_rows enable row level security;
alter table public.migration_issues enable row level security;
alter table public.imported_records enable row level security;
alter table public.audit_snapshots enable row level security;
alter table public.source_expected_metrics enable row level security;
alter table public.audit_reconciliation_runs enable row level security;
alter table public.value_reconciliations enable row level security;
alter table public.reconciliation_details enable row level security;

create policy "authenticated full source workbook access" on public.source_workbooks
for all to authenticated using (true) with check (true);
create policy "authenticated full migration batch access" on public.migration_batches
for all to authenticated using (true) with check (true);
create policy "authenticated full source table access" on public.source_tables
for all to authenticated using (true) with check (true);
create policy "authenticated full source row access" on public.source_rows
for all to authenticated using (true) with check (true);
create policy "authenticated full migration issue access" on public.migration_issues
for all to authenticated using (true) with check (true);
create policy "authenticated full imported record access" on public.imported_records
for all to authenticated using (true) with check (true);
create policy "authenticated full audit snapshot access" on public.audit_snapshots
for all to authenticated using (true) with check (true);
create policy "authenticated full expected metric access" on public.source_expected_metrics
for all to authenticated using (true) with check (true);
create policy "authenticated full reconciliation run access" on public.audit_reconciliation_runs
for all to authenticated using (true) with check (true);
create policy "authenticated full value reconciliation access" on public.value_reconciliations
for all to authenticated using (true) with check (true);
create policy "authenticated full reconciliation detail access" on public.reconciliation_details
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('migration.import', 'migracao', 'Registrar fonte Excel, batch, linhas brutas e normalizacao', true, 40),
  ('audit.reconciliation.run', 'auditoria', 'Rodar reconciliacoes de valores e saldos contra fonte esperada', true, 510)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.aud_reconciliation_status(
  p_source_value numeric,
  p_system_value numeric,
  p_tolerance numeric
)
returns text
language sql
immutable
as $$
  select case
    when p_source_value is null or p_system_value is null then 'missing'
    when abs(p_system_value - p_source_value) <= coalesce(p_tolerance, 0) then 'ok'
    else 'attention'
  end;
$$;

create or replace view public.aud_operational_metric_values as
select
  'total_pedidos_distintos'::text as metric_name,
  'Sistema com_pedidos.id distintos'::text as system_label,
  count(distinct pedido.id)::numeric as system_value,
  0::numeric as default_tolerance,
  jsonb_build_object('system_table', 'com_pedidos', 'system_column', 'id') as details_json
from public.com_pedidos pedido
union all
select
  'faturamento_total',
  'Sistema com_pedidos.valor_total',
  coalesce(sum(pedido.valor_total), 0)::numeric,
  0.01::numeric,
  jsonb_build_object('system_table', 'com_pedidos', 'system_column', 'valor_total')
from public.com_pedidos pedido
union all
select
  'faturamento_vendas',
  'Sistema com_pedidos.valor_total where tipo_pedido = venda',
  coalesce(sum(pedido.valor_total), 0)::numeric,
  0.01::numeric,
  jsonb_build_object('system_table', 'com_pedidos', 'system_column', 'valor_total', 'system_filter', 'tipo_pedido = venda')
from public.com_pedidos pedido
where pedido.tipo_pedido = 'venda'
union all
select
  'recebimentos_total',
  'Sistema com_recebimentos.valor_recebido',
  coalesce(sum(recebimento.valor_recebido), 0)::numeric,
  0.01::numeric,
  jsonb_build_object('system_table', 'com_recebimentos', 'system_column', 'valor_recebido')
from public.com_recebimentos recebimento
union all
select
  'comissao_prevista',
  'Sistema com_pedido_comissionados.valor_previsto',
  coalesce(sum(comissionado.valor_previsto), 0)::numeric,
  0.01::numeric,
  jsonb_build_object('system_table', 'com_pedido_comissionados', 'system_column', 'valor_previsto')
from public.com_pedido_comissionados comissionado
union all
select
  'comissao_liberada',
  'Sistema com_comissao_liberacoes.valor_liberado liberada',
  coalesce(sum(liberacao.valor_liberado), 0)::numeric,
  0.01::numeric,
  jsonb_build_object('system_table', 'com_comissao_liberacoes', 'system_column', 'valor_liberado', 'system_filter', 'status = liberada')
from public.com_comissao_liberacoes liberacao
where liberacao.status = 'liberada'
union all
select
  'romaneios_confirmados',
  'Sistema exp_romaneios status confirmado',
  count(*)::numeric,
  0::numeric,
  jsonb_build_object('system_table', 'exp_romaneios', 'system_filter', 'status = confirmado')
from public.exp_romaneios romaneio
where romaneio.status = 'confirmado'
union all
select
  'romaneios_baixa_pa_quantidade',
  'Sistema exp_romaneio_movimentos_pa quantidade baixa',
  coalesce(sum(movimento.quantidade), 0)::numeric,
  0.001::numeric,
  jsonb_build_object('system_table', 'exp_romaneio_movimentos_pa', 'system_column', 'quantidade', 'system_filter', 'tipo_movimento = baixa')
from public.exp_romaneio_movimentos_pa movimento
where movimento.tipo_movimento = 'baixa'
union all
select
  'entradas_pa_quantidade',
  'Sistema est_movimentos_pa entradas positivas',
  coalesce(sum(case when movimento.quantidade > 0 then movimento.quantidade else 0 end), 0)::numeric,
  0.001::numeric,
  jsonb_build_object('system_table', 'est_movimentos_pa', 'system_column', 'quantidade', 'system_filter', 'quantidade > 0')
from public.est_movimentos_pa movimento
union all
select
  'saidas_pa_quantidade',
  'Sistema est_movimentos_pa saida_romaneio',
  coalesce(sum(case when movimento.tipo_movimento = 'saida_romaneio' then -1 * movimento.quantidade else 0 end), 0)::numeric,
  0.001::numeric,
  jsonb_build_object('system_table', 'est_movimentos_pa', 'system_column', 'quantidade', 'system_filter', 'tipo_movimento = saida_romaneio')
from public.est_movimentos_pa movimento
union all
select
  'estornos_pa_quantidade',
  'Sistema est_movimentos_pa estorno_saida',
  coalesce(sum(case when movimento.tipo_movimento = 'estorno_saida' then movimento.quantidade else 0 end), 0)::numeric,
  0.001::numeric,
  jsonb_build_object('system_table', 'est_movimentos_pa', 'system_column', 'quantidade', 'system_filter', 'tipo_movimento = estorno_saida')
from public.est_movimentos_pa movimento
union all
select
  'estoque_pa_saldo',
  'Sistema est_lotes_pa_saldos.saldo_fisico',
  coalesce(sum(saldo.saldo_fisico), 0)::numeric,
  0.1::numeric,
  jsonb_build_object('system_view', 'est_lotes_pa_saldos', 'system_column', 'saldo_fisico')
from public.est_lotes_pa_saldos saldo
union all
select
  'estoque_pa_reservado',
  'Sistema est_lotes_pa_saldos.quantidade_reservada',
  coalesce(sum(saldo.quantidade_reservada), 0)::numeric,
  0.001::numeric,
  jsonb_build_object('system_view', 'est_lotes_pa_saldos', 'system_column', 'quantidade_reservada')
from public.est_lotes_pa_saldos saldo;

grant select on public.aud_operational_metric_values to authenticated;

create or replace function public.record_aud_source_expected_metric(
  p_batch_id bigint,
  p_metric_name text,
  p_source_label text,
  p_source_value numeric,
  p_tolerance numeric default 0.01,
  p_details_json jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  if p_batch_id is null or p_batch_id <= 0 then
    raise exception 'batch_id is required';
  end if;
  if nullif(trim(p_metric_name), '') is null then
    raise exception 'metric_name is required';
  end if;
  if nullif(trim(p_source_label), '') is null then
    raise exception 'source_label is required';
  end if;
  if p_tolerance is null or p_tolerance < 0 then
    raise exception 'tolerance must be greater than or equal to zero';
  end if;
  if not exists (select 1 from public.migration_batches where id = p_batch_id) then
    raise exception 'migration batch not found';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.source_expected_metrics(
    batch_id,
    metric_name,
    source_label,
    source_value,
    tolerance,
    details_json,
    created_by,
    updated_by
  )
  values (
    p_batch_id,
    trim(p_metric_name),
    trim(p_source_label),
    p_source_value,
    p_tolerance,
    coalesce(p_details_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  on conflict (batch_id, metric_name) do update set
    source_label = excluded.source_label,
    source_value = excluded.source_value,
    tolerance = excluded.tolerance,
    details_json = excluded.details_json,
    updated_by = excluded.updated_by;

  perform public.log_action(
    'auditoria.expected_metric_recorded',
    'source_expected_metrics',
    concat(p_batch_id::text, ':', trim(p_metric_name)),
    'success',
    null,
    jsonb_build_object(
      'batch_id', p_batch_id,
      'metric_name', trim(p_metric_name),
      'source_label', trim(p_source_label),
      'source_value', p_source_value,
      'tolerance', p_tolerance
    ),
    jsonb_build_object('source', 'record_aud_source_expected_metric')
  );

  return trim(p_metric_name);
end;
$$;

create or replace function public.run_aud_reconciliacao_operacional(
  p_batch_id bigint default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_run_id bigint;
  v_metric_count integer;
  v_attention_count integer;
begin
  if p_batch_id is not null and not exists (
    select 1 from public.migration_batches where id = p_batch_id
  ) then
    raise exception 'migration batch not found';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.audit_reconciliation_runs(
    batch_id,
    scope,
    status,
    observacao,
    created_by
  )
  values (
    p_batch_id,
    'operational',
    'running',
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_run_id;

  insert into public.value_reconciliations(
    run_id,
    batch_id,
    metric_name,
    source_label,
    source_value,
    system_value,
    difference,
    tolerance,
    status,
    details_json,
    created_by
  )
  select
    v_run_id,
    p_batch_id,
    metric.metric_name,
    coalesce(expected.source_label, 'Fonte Excel nao carregada para esta metrica'),
    expected.source_value,
    metric.system_value,
    case
      when expected.source_value is null or metric.system_value is null then null
      else metric.system_value - expected.source_value
    end,
    coalesce(expected.tolerance, metric.default_tolerance),
    public.aud_reconciliation_status(expected.source_value, metric.system_value, coalesce(expected.tolerance, metric.default_tolerance)),
    jsonb_build_object(
      'system_label', metric.system_label,
      'system_details', metric.details_json,
      'source_details', coalesce(expected.details_json, '{}'::jsonb),
      'batch_id', p_batch_id
    ),
    v_actor
  from public.aud_operational_metric_values metric
  left join public.source_expected_metrics expected
    on expected.batch_id = p_batch_id
   and expected.metric_name = metric.metric_name;

  select count(*), count(*) filter (where status <> 'ok')
    into v_metric_count, v_attention_count
    from public.value_reconciliations
    where run_id = v_run_id;

  update public.audit_reconciliation_runs
     set status = case when v_attention_count = 0 then 'ok' else 'attention' end,
         metric_count = v_metric_count,
         attention_count = v_attention_count,
         finished_at = now()
   where id = v_run_id;

  perform public.log_action(
    'auditoria.reconciliacao_operacional_executada',
    'audit_reconciliation_runs',
    v_run_id::text,
    'success',
    null,
    jsonb_build_object(
      'batch_id', p_batch_id,
      'metric_count', v_metric_count,
      'attention_count', v_attention_count,
      'observacao', nullif(trim(p_observacao), '')
    ),
    jsonb_build_object('source', 'run_aud_reconciliacao_operacional')
  );

  return v_run_id;
end;
$$;

revoke all on function public.prevent_migration_source_changes() from public;
revoke all on function public.aud_reconciliation_status(numeric, numeric, numeric) from public;

revoke all on function public.record_aud_source_expected_metric(bigint, text, text, numeric, numeric, jsonb) from public;
grant execute on function public.record_aud_source_expected_metric(bigint, text, text, numeric, numeric, jsonb) to authenticated;

revoke all on function public.run_aud_reconciliacao_operacional(bigint, text) from public;
grant execute on function public.run_aud_reconciliacao_operacional(bigint, text) to authenticated;
