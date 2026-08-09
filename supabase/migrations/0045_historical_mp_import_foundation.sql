-- Historical MP import foundation: staging, canonical aliases, acquisition
-- values and read models. This migration does not import real workbook data.

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values
  ('migration.mp.view', 'migracao', 'Consultar staging, mapeamentos e reconciliacao historica de MP', true, 45, 'auditoria', 'read'),
  ('migration.mp.stage', 'migracao', 'Registrar staging idempotente de cadastro historico de MP', true, 46, 'auditoria', 'write'),
  ('migration.mp.map', 'migracao', 'Aprovar vinculo entre identidade legada e MP canonica', true, 47, 'auditoria', 'write'),
  ('migration.mp.import', 'migracao', 'Importar fato historico de MP previamente conciliado', true, 48, 'auditoria', 'write'),
  ('migration.mp.reconcile', 'migracao', 'Executar reconciliacao historica de MP', true, 49, 'auditoria', 'write'),
  ('estoque.mp.acquisition_value.register', 'estoque', 'Registrar componentes de valor de aquisicao vinculados a entrada MP', true, 438, 'estoque', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values
  ('/importacao-historica', 'auditoria', true),
  ('/importacao-historica/mp', 'auditoria', true)
on conflict (route_prefix) do update set
  module_key = excluded.module_key,
  match_children = excluded.match_children;

alter table public.est_lotes_mp
  add column if not exists origem_dados text,
  add column if not exists codigo_lote_legado text,
  add column if not exists codigo_lote_fornecedor text,
  add column if not exists source_batch_id bigint,
  add column if not exists source_row_id bigint;

alter table public.est_lotes_mp
  drop constraint if exists est_lotes_mp_origem_dados_check,
  drop constraint if exists est_lotes_mp_source_batch_fk,
  drop constraint if exists est_lotes_mp_source_row_fk,
  add constraint est_lotes_mp_origem_dados_check check (
    origem_dados is null or origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint est_lotes_mp_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id),
  add constraint est_lotes_mp_source_row_fk
    foreign key (source_row_id) references public.source_rows(id);

alter table public.est_movimentos_mp
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint,
  add column if not exists source_row_id bigint;

alter table public.est_movimentos_mp
  drop constraint if exists est_movimentos_mp_origem_dados_check,
  drop constraint if exists est_movimentos_mp_source_batch_fk,
  drop constraint if exists est_movimentos_mp_source_row_fk,
  add constraint est_movimentos_mp_origem_dados_check check (
    origem_dados is null or origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint est_movimentos_mp_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id),
  add constraint est_movimentos_mp_source_row_fk
    foreign key (source_row_id) references public.source_rows(id);

create index if not exists idx_est_lotes_mp_source_lineage
  on public.est_lotes_mp(source_batch_id, source_row_id)
  where source_batch_id is not null;

create index if not exists idx_est_movimentos_mp_source_lineage
  on public.est_movimentos_mp(source_batch_id, source_row_id)
  where source_batch_id is not null;

create table if not exists public.migration_mp_staging_items (
  id bigint generated always as identity primary key,
  batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  codigo_legado text,
  codigo_norm text generated always as (
    nullif(lower(regexp_replace(btrim(codigo_legado), '\s+', ' ', 'g')), '')
  ) stored,
  nome_legado text,
  nome_norm text generated always as (
    nullif(lower(regexp_replace(btrim(nome_legado), '\s+', ' ', 'g')), '')
  ) stored,
  unidade_origem text,
  densidade numeric,
  estoque_minimo numeric,
  custo_unitario_snapshot numeric,
  payload_hash text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint migration_mp_staging_identity_check check (
    nullif(trim(codigo_legado), '') is not null
    or nullif(trim(nome_legado), '') is not null
  ),
  constraint migration_mp_staging_density_check check (densidade is null or densidade > 0),
  constraint migration_mp_staging_stock_check check (estoque_minimo is null or estoque_minimo >= 0),
  constraint migration_mp_staging_cost_check check (custo_unitario_snapshot is null or custo_unitario_snapshot >= 0),
  constraint migration_mp_staging_hash_check check (nullif(trim(payload_hash), '') is not null),
  constraint migration_mp_staging_source_key unique (batch_id, source_row_id)
);

create table if not exists public.migration_mp_mapping_events (
  id bigint generated always as identity primary key,
  staging_item_id bigint not null references public.migration_mp_staging_items(id),
  status text not null,
  materia_prima_id bigint references public.cad_materias_primas(id),
  match_method text not null,
  confidence numeric,
  reason_code text not null,
  reason_detail text,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint migration_mp_mapping_status_check check (
    status in ('suggested', 'approved', 'rejected', 'conflict', 'pending')
  ),
  constraint migration_mp_mapping_method_check check (
    match_method in (
      'exact_sku',
      'exact_legacy_code',
      'exact_name',
      'normalized_name',
      'manual',
      'new_required',
      'none'
    )
  ),
  constraint migration_mp_mapping_confidence_check check (
    confidence is null or (confidence >= 0 and confidence <= 100)
  ),
  constraint migration_mp_mapping_target_check check (
    status not in ('suggested', 'approved') or materia_prima_id is not null
  ),
  constraint migration_mp_mapping_reason_check check (
    reason_code in (
      'exact_match',
      'manual_confirmation',
      'legacy_code_as_name',
      'duplicate_code',
      'duplicate_name',
      'no_match',
      'new_canonical_required',
      'other'
    )
  ),
  constraint migration_mp_mapping_detail_check check (
    reason_code <> 'other' or nullif(trim(reason_detail), '') is not null
  )
);

create index if not exists idx_migration_mp_mapping_latest
  on public.migration_mp_mapping_events(staging_item_id, id desc);

create table if not exists public.cad_materia_prima_aliases (
  id bigint generated always as identity primary key,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  alias_type text not null,
  alias_value text not null,
  alias_norm text generated always as (
    lower(regexp_replace(btrim(alias_value), '\s+', ' ', 'g'))
  ) stored,
  contexto_origem text not null default 'excel_legado',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  approved_by uuid not null references public.user_profiles(id),
  approved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint cad_mp_alias_type_check check (
    alias_type in ('excel_codigo', 'excel_nome', 'fornecedor_codigo', 'fornecedor_nome', 'outro')
  ),
  constraint cad_mp_alias_value_check check (nullif(trim(alias_value), '') is not null),
  constraint cad_mp_alias_context_check check (nullif(trim(contexto_origem), '') is not null),
  constraint cad_mp_alias_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_mp_alias_excel_source_check check (
    contexto_origem <> 'excel_legado'
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_mp_alias_source_key unique (alias_type, alias_norm, contexto_origem)
);

create index if not exists idx_cad_mp_aliases_materia
  on public.cad_materia_prima_aliases(materia_prima_id, alias_type);

create table if not exists public.est_movimentos_mp_valores (
  id bigint generated always as identity primary key,
  movimento_mp_id bigint not null unique references public.est_movimentos_mp(id),
  quantidade_origem numeric not null,
  unidade_origem text not null,
  quantidade_base numeric not null,
  moeda text not null default 'BRL',
  valor_materia_prima numeric not null default 0,
  frete numeric not null default 0,
  difal_icms numeric not null default 0,
  difal_status text not null,
  difal_motivo text,
  outras_despesas numeric not null default 0,
  custo_aquisicao_total numeric generated always as (
    valor_materia_prima + frete + difal_icms + outras_despesas
  ) stored,
  custo_unitario_base numeric generated always as (
    (valor_materia_prima + frete + difal_icms + outras_despesas) / nullif(quantidade_base, 0)
  ) stored,
  custo_total_legado numeric,
  custo_medio_ponderado_legado numeric,
  saldo_lote_legado numeric,
  documento_ref text,
  data_documento date,
  uf_emitente text,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_mp_valores_quantidade_origem_check check (quantidade_origem > 0),
  constraint est_mp_valores_quantidade_base_check check (quantidade_base > 0),
  constraint est_mp_valores_unidade_check check (nullif(trim(unidade_origem), '') is not null),
  constraint est_mp_valores_moeda_check check (moeda ~ '^[A-Z]{3}$'),
  constraint est_mp_valores_componentes_check check (
    valor_materia_prima >= 0 and frete >= 0 and difal_icms >= 0 and outras_despesas >= 0
  ),
  constraint est_mp_valores_snapshots_check check (
    (custo_total_legado is null or custo_total_legado >= 0)
    and (custo_medio_ponderado_legado is null or custo_medio_ponderado_legado >= 0)
    and (saldo_lote_legado is null or saldo_lote_legado >= 0)
  ),
  constraint est_mp_valores_difal_status_check check (
    difal_status in ('informed', 'not_applicable', 'pending_review')
  ),
  constraint est_mp_valores_difal_value_check check (
    (difal_icms > 0 and difal_status = 'informed')
    or (difal_icms = 0 and difal_status in ('informed', 'not_applicable', 'pending_review'))
  ),
  constraint est_mp_valores_difal_reason_check check (
    difal_status <> 'pending_review' or nullif(trim(difal_motivo), '') is not null
  ),
  constraint est_mp_valores_uf_check check (uf_emitente is null or uf_emitente ~ '^[A-Z]{2}$'),
  constraint est_mp_valores_sp_difal_check check (
    uf_emitente is distinct from 'SP' or difal_icms = 0
  ),
  constraint est_mp_valores_origem_check check (origem_dados in ('sistema', 'excel_legado'))
);

create index if not exists idx_est_mp_valores_source
  on public.est_movimentos_mp_valores(source_batch_id, source_row_id)
  where source_batch_id is not null;

create or replace function public.prevent_historical_mp_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; register a new event or correction', tg_table_name;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'migration_mp_staging_items',
    'migration_mp_mapping_events',
    'cad_materia_prima_aliases',
    'est_movimentos_mp_valores'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_append_only', v_table);
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_historical_mp_fact_changes()',
      'trg_' || v_table || '_append_only',
      v_table
    );
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_no_truncate', v_table);
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_historical_mp_fact_changes()',
      'trg_' || v_table || '_no_truncate',
      v_table
    );
  end loop;
end;
$$;

create or replace function public.enforce_historical_mp_source_lineage()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_batch_workbook_id bigint;
  v_row_workbook_id bigint;
begin
  if new.source_batch_id is null and new.source_row_id is null then
    if new.origem_dados = 'excel_legado' then
      raise exception 'excel_legado requires source_batch_id and source_row_id';
    end if;
    return new;
  end if;

  if new.source_batch_id is null or new.source_row_id is null then
    raise exception 'source_batch_id and source_row_id must be provided together';
  end if;

  select batch.workbook_id
    into v_batch_workbook_id
    from public.migration_batches batch
   where batch.id = new.source_batch_id;

  select source_table.workbook_id
    into v_row_workbook_id
    from public.source_rows source_row
    join public.source_tables source_table on source_table.id = source_row.table_id
   where source_row.id = new.source_row_id;

  if v_batch_workbook_id is null or v_row_workbook_id is null then
    raise exception 'historical source lineage not found';
  end if;
  if v_batch_workbook_id <> v_row_workbook_id then
    raise exception 'source_row_id does not belong to source_batch_id workbook';
  end if;
  if new.origem_dados is distinct from 'excel_legado' then
    raise exception 'source lineage is reserved for origem_dados excel_legado';
  end if;

  return new;
end;
$$;

create or replace function public.enforce_historical_mp_batch_row_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_record jsonb;
  v_batch_id bigint;
  v_source_row_id bigint;
  v_batch_workbook_id bigint;
  v_row_workbook_id bigint;
begin
  v_record := to_jsonb(new);
  v_batch_id := nullif(coalesce(v_record->>'source_batch_id', v_record->>'batch_id'), '')::bigint;
  v_source_row_id := nullif(v_record->>'source_row_id', '')::bigint;

  if v_batch_id is null and v_source_row_id is null then
    return new;
  end if;
  if v_batch_id is null or v_source_row_id is null then
    raise exception 'historical batch and source row must be provided together';
  end if;

  select batch.workbook_id
    into v_batch_workbook_id
    from public.migration_batches batch
   where batch.id = v_batch_id;
  select source_table.workbook_id
    into v_row_workbook_id
    from public.source_rows source_row
    join public.source_tables source_table on source_table.id = source_row.table_id
   where source_row.id = v_source_row_id;

  if v_batch_workbook_id is null or v_row_workbook_id is null then
    raise exception 'historical batch or source row not found';
  end if;
  if v_batch_workbook_id <> v_row_workbook_id then
    raise exception 'source_row_id does not belong to historical batch workbook';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_migration_mp_staging_source_pair on public.migration_mp_staging_items;
create trigger trg_migration_mp_staging_source_pair
before insert on public.migration_mp_staging_items
for each row execute function public.enforce_historical_mp_batch_row_consistency();

drop trigger if exists trg_cad_mp_aliases_source_pair on public.cad_materia_prima_aliases;
create trigger trg_cad_mp_aliases_source_pair
before insert on public.cad_materia_prima_aliases
for each row execute function public.enforce_historical_mp_batch_row_consistency();

drop trigger if exists trg_est_lotes_mp_historical_lineage on public.est_lotes_mp;
create trigger trg_est_lotes_mp_historical_lineage
before insert or update of origem_dados, source_batch_id, source_row_id on public.est_lotes_mp
for each row execute function public.enforce_historical_mp_source_lineage();

drop trigger if exists trg_est_movimentos_mp_historical_lineage on public.est_movimentos_mp;
create trigger trg_est_movimentos_mp_historical_lineage
before insert or update of origem_dados, source_batch_id, source_row_id on public.est_movimentos_mp
for each row execute function public.enforce_historical_mp_source_lineage();

drop trigger if exists trg_est_mp_valores_historical_lineage on public.est_movimentos_mp_valores;
create trigger trg_est_mp_valores_historical_lineage
before insert on public.est_movimentos_mp_valores
for each row execute function public.enforce_historical_mp_source_lineage();

create or replace view public.migration_mp_mapping_current
with (security_invoker = true) as
select distinct on (event.staging_item_id)
  event.id as mapping_event_id,
  event.staging_item_id,
  event.status,
  event.materia_prima_id,
  event.match_method,
  event.confidence,
  event.reason_code,
  event.reason_detail,
  event.created_by,
  event.created_at
from public.migration_mp_mapping_events event
order by event.staging_item_id, event.id desc;

create or replace view public.migration_mp_mapping_dashboard
with (security_invoker = true) as
select
  staging.id as staging_item_id,
  staging.batch_id,
  staging.source_row_id,
  staging.codigo_legado,
  staging.nome_legado,
  staging.unidade_origem,
  staging.densidade,
  staging.estoque_minimo,
  staging.custo_unitario_snapshot,
  coalesce(
    current_mapping.status,
    case
      when suggestion.match_count = 1 then 'suggested'
      when suggestion.match_count > 1 then 'conflict'
      else 'pending'
    end
  ) as mapping_status,
  coalesce(
    current_mapping.materia_prima_id,
    case when suggestion.match_count = 1 then suggestion.materia_prima_id end
  ) as materia_prima_id,
  canonical.sku_corrigido as materia_prima_sku,
  canonical.nome as materia_prima_nome,
  coalesce(
    current_mapping.match_method,
    case when suggestion.match_count = 1 then suggestion.match_method end,
    'none'
  ) as match_method,
  coalesce(
    current_mapping.confidence,
    case when suggestion.match_count = 1 then suggestion.confidence end
  ) as confidence,
  suggestion.match_count,
  current_mapping.reason_code,
  current_mapping.reason_detail,
  staging.created_at
from public.migration_mp_staging_items staging
left join public.migration_mp_mapping_current current_mapping
  on current_mapping.staging_item_id = staging.id
left join lateral (
  select
    count(*)::integer as match_count,
    min(candidate.materia_prima_id) as materia_prima_id,
    max(candidate.match_method) as match_method,
    max(candidate.confidence) as confidence
  from (
    select distinct on (match_row.materia_prima_id)
      match_row.materia_prima_id,
      match_row.match_method,
      match_row.confidence,
      match_row.priority
    from (
      select mp.id as materia_prima_id, 'exact_sku'::text as match_method, 100::numeric as confidence, 1 as priority
        from public.cad_materias_primas mp
       where staging.codigo_norm is not null and lower(btrim(mp.sku_corrigido)) = staging.codigo_norm
      union all
      select mp.id, 'exact_legacy_code', 98::numeric, 2
        from public.cad_materias_primas mp
       where staging.codigo_norm is not null and lower(btrim(mp.codigo_legado)) = staging.codigo_norm
      union all
      select alias.materia_prima_id, 'exact_legacy_code', 98::numeric, 3
        from public.cad_materia_prima_aliases alias
       where staging.codigo_norm is not null
         and alias.alias_type in ('excel_codigo', 'fornecedor_codigo')
         and alias.alias_norm = staging.codigo_norm
      union all
      select mp.id, 'exact_name', 95::numeric, 4
        from public.cad_materias_primas mp
       where staging.nome_norm is not null and mp.nome_norm = staging.nome_norm
      union all
      select alias.materia_prima_id, 'normalized_name', 92::numeric, 5
        from public.cad_materia_prima_aliases alias
       where staging.nome_norm is not null
         and alias.alias_type in ('excel_nome', 'fornecedor_nome')
         and alias.alias_norm = staging.nome_norm
    ) match_row
    order by match_row.materia_prima_id, match_row.priority
  ) candidate
) suggestion on true
left join public.cad_materias_primas canonical
  on canonical.id = coalesce(
    current_mapping.materia_prima_id,
    case when suggestion.match_count = 1 then suggestion.materia_prima_id end
  );

create or replace view public.migration_mp_batch_summary
with (security_invoker = true) as
select
  mapping.batch_id,
  mapping.total_items,
  mapping.pending_items,
  mapping.suggested_items,
  mapping.approved_items,
  mapping.conflict_items,
  mapping.rejected_items,
  coalesce(acquisition.acquisition_records, 0)::bigint as acquisition_records,
  coalesce(acquisition.valor_materia_prima, 0)::numeric as valor_materia_prima,
  coalesce(acquisition.frete, 0)::numeric as frete,
  coalesce(acquisition.difal_icms, 0)::numeric as difal_icms,
  coalesce(acquisition.outras_despesas, 0)::numeric as outras_despesas,
  coalesce(acquisition.custo_aquisicao_total, 0)::numeric as custo_aquisicao_total
from (
  select
    dashboard.batch_id,
    count(*)::bigint as total_items,
    count(*) filter (where dashboard.mapping_status = 'pending')::bigint as pending_items,
    count(*) filter (where dashboard.mapping_status = 'suggested')::bigint as suggested_items,
    count(*) filter (where dashboard.mapping_status = 'approved')::bigint as approved_items,
    count(*) filter (where dashboard.mapping_status = 'conflict')::bigint as conflict_items,
    count(*) filter (where dashboard.mapping_status = 'rejected')::bigint as rejected_items
  from public.migration_mp_mapping_dashboard dashboard
  group by dashboard.batch_id
) mapping
left join (
  select
    value.source_batch_id as batch_id,
    count(*)::bigint as acquisition_records,
    sum(value.valor_materia_prima) as valor_materia_prima,
    sum(value.frete) as frete,
    sum(value.difal_icms) as difal_icms,
    sum(value.outras_despesas) as outras_despesas,
    sum(value.custo_aquisicao_total) as custo_aquisicao_total
  from public.est_movimentos_mp_valores value
  where value.source_batch_id is not null
  group by value.source_batch_id
) acquisition on acquisition.batch_id = mapping.batch_id;

create or replace view public.est_mp_historico_precos
with (security_invoker = true) as
select
  value.id as acquisition_value_id,
  value.movimento_mp_id,
  movement.materia_prima_id,
  mp.sku_corrigido,
  mp.nome as materia_prima_nome,
  movement.lote_mp_id,
  lot.codigo_lote,
  lot.codigo_lote_legado,
  lot.codigo_lote_fornecedor,
  value.data_documento,
  value.documento_ref,
  value.uf_emitente,
  value.quantidade_origem,
  value.unidade_origem,
  value.quantidade_base,
  value.valor_materia_prima,
  value.frete,
  value.difal_icms,
  value.difal_status,
  value.outras_despesas,
  value.custo_aquisicao_total,
  value.custo_unitario_base,
  value.custo_total_legado,
  value.custo_medio_ponderado_legado,
  value.saldo_lote_legado,
  value.origem_dados,
  value.source_batch_id,
  value.source_row_id,
  value.created_at
from public.est_movimentos_mp_valores value
join public.est_movimentos_mp movement on movement.id = value.movimento_mp_id
join public.est_lotes_mp lot on lot.id = movement.lote_mp_id
join public.cad_materias_primas mp on mp.id = movement.materia_prima_id;

create or replace function public.stage_migration_mp_items(
  p_batch_id bigint,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_item jsonb;
  v_received integer;
  v_inserted integer := 0;
  v_existing integer := 0;
  v_source_row_id bigint;
  v_source_hash text;
  v_codigo_legado text;
  v_nome_legado text;
  v_unidade_origem text;
  v_densidade numeric;
  v_estoque_minimo numeric;
  v_custo_snapshot numeric;
  v_existing_row public.migration_mp_staging_items%rowtype;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'migration.mp.stage',
    'auditoria',
    'migration_mp_staging_items',
    'change_type',
    jsonb_build_object(
      'batch_id', p_batch_id,
      'correlation_id', concat('migration_batch:', p_batch_id, ':mp_stage')
    )
  );
  v_actor := public.current_actor_id();

  if p_batch_id is null or not exists (
    select 1 from public.migration_batches batch where batch.id = p_batch_id
  ) then
    raise exception 'migration batch not found';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a json array';
  end if;

  v_received := jsonb_array_length(p_items);
  if v_received = 0 or v_received > 5000 then
    raise exception 'p_items must contain between 1 and 5000 rows';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'every staging item must be a json object';
    end if;

    begin
      v_source_row_id := nullif(v_item->>'source_row_id', '')::bigint;
      v_densidade := nullif(v_item->>'densidade', '')::numeric;
      v_estoque_minimo := nullif(v_item->>'estoque_minimo', '')::numeric;
      v_custo_snapshot := nullif(v_item->>'custo_unitario_snapshot', '')::numeric;
    exception
      when invalid_text_representation then
        raise exception 'invalid numeric value in MP staging item';
    end;

    v_codigo_legado := nullif(trim(v_item->>'codigo_legado'), '');
    v_nome_legado := nullif(trim(v_item->>'nome_legado'), '');
    v_unidade_origem := nullif(trim(v_item->>'unidade_origem'), '');

    if v_source_row_id is null then
      raise exception 'source_row_id is required';
    end if;
    if v_codigo_legado is null and v_nome_legado is null then
      raise exception 'codigo_legado or nome_legado is required';
    end if;

    select source_row.row_hash
      into v_source_hash
      from public.source_rows source_row
      join public.source_tables source_table on source_table.id = source_row.table_id
      join public.migration_batches batch
        on batch.id = p_batch_id
       and batch.workbook_id = source_table.workbook_id
     where source_row.id = v_source_row_id;

    if v_source_hash is null then
      raise exception 'source row % does not belong to migration batch %', v_source_row_id, p_batch_id;
    end if;

    select *
      into v_existing_row
      from public.migration_mp_staging_items staging
     where staging.batch_id = p_batch_id
       and staging.source_row_id = v_source_row_id;

    if found then
      if v_existing_row.payload_hash <> v_source_hash
         or v_existing_row.codigo_legado is distinct from v_codigo_legado
         or v_existing_row.nome_legado is distinct from v_nome_legado
         or v_existing_row.unidade_origem is distinct from v_unidade_origem
         or v_existing_row.densidade is distinct from v_densidade
         or v_existing_row.estoque_minimo is distinct from v_estoque_minimo
         or v_existing_row.custo_unitario_snapshot is distinct from v_custo_snapshot then
        raise exception 'staged MP item differs from existing immutable row %', v_source_row_id;
      end if;
      v_existing := v_existing + 1;
      continue;
    end if;

    insert into public.migration_mp_staging_items(
      batch_id,
      source_row_id,
      codigo_legado,
      nome_legado,
      unidade_origem,
      densidade,
      estoque_minimo,
      custo_unitario_snapshot,
      payload_hash,
      created_by
    )
    values (
      p_batch_id,
      v_source_row_id,
      v_codigo_legado,
      v_nome_legado,
      v_unidade_origem,
      v_densidade,
      v_estoque_minimo,
      v_custo_snapshot,
      v_source_hash,
      v_actor
    );
    v_inserted := v_inserted + 1;
  end loop;

  v_after := jsonb_build_object(
    'batch_id', p_batch_id,
    'received', v_received,
    'inserted', v_inserted,
    'existing', v_existing
  );

  perform public.log_audited_rpc_change(
    'auditoria',
    'migration_mp_staging_items',
    p_batch_id::text,
    'auditoria.mp_staging_registered',
    'migration.mp.stage',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object('source', 'stage_migration_mp_items'),
    'database_rpc'
  );

  return v_after;
end;
$$;

create or replace function public.approve_migration_mp_mapping(
  p_staging_item_id bigint,
  p_materia_prima_id bigint,
  p_match_method text,
  p_confidence numeric,
  p_reason_code text,
  p_reason_detail text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_cad_permission_context jsonb;
  v_staging public.migration_mp_staging_items%rowtype;
  v_mp public.cad_materias_primas%rowtype;
  v_latest public.migration_mp_mapping_events%rowtype;
  v_event_id bigint;
  v_alias_id bigint;
  v_alias_ids jsonb := '[]'::jsonb;
  v_existing_alias public.cad_materia_prima_aliases%rowtype;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'migration.mp.map',
    'auditoria',
    'migration_mp_mapping_events',
    'status_transition',
    jsonb_build_object(
      'staging_item_id', p_staging_item_id,
      'correlation_id', concat('migration_mp_staging:', p_staging_item_id, ':approve')
    )
  );
  v_cad_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.update.identity',
    'cadastros',
    'cad_materia_prima_aliases',
    'change_type',
    jsonb_build_object(
      'staging_item_id', p_staging_item_id,
      'correlation_id', concat('migration_mp_staging:', p_staging_item_id, ':approve')
    )
  );
  v_actor := public.current_actor_id();

  select *
    into v_staging
    from public.migration_mp_staging_items staging
   where staging.id = p_staging_item_id
   for update;
  if not found then
    raise exception 'MP staging item not found';
  end if;

  select *
    into v_mp
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;
  if not found or v_mp.status <> 'active' then
    raise exception 'active canonical MP not found';
  end if;

  select *
    into v_latest
    from public.migration_mp_mapping_events event
   where event.staging_item_id = p_staging_item_id
   order by event.id desc
   limit 1;

  if found and v_latest.status = 'approved' then
    if v_latest.materia_prima_id = p_materia_prima_id then
      return v_latest.id;
    end if;
    raise exception 'MP staging item already approved for another canonical MP';
  end if;

  if p_match_method not in ('exact_sku', 'exact_legacy_code', 'exact_name', 'normalized_name', 'manual') then
    raise exception 'invalid approved match_method';
  end if;
  if p_confidence is null or p_confidence < 0 or p_confidence > 100 then
    raise exception 'confidence must be between 0 and 100';
  end if;
  if p_reason_code not in ('exact_match', 'manual_confirmation', 'legacy_code_as_name', 'other') then
    raise exception 'invalid approval reason_code';
  end if;
  if p_reason_code = 'other' and nullif(trim(p_reason_detail), '') is null then
    raise exception 'reason_detail is required for other';
  end if;

  if v_staging.codigo_legado is not null then
    select *
      into v_existing_alias
      from public.cad_materia_prima_aliases alias
     where alias.alias_type = 'excel_codigo'
       and alias.alias_norm = v_staging.codigo_norm
       and alias.contexto_origem = 'excel_legado';
    if found and v_existing_alias.materia_prima_id <> p_materia_prima_id then
      raise exception 'legacy code alias already belongs to another canonical MP';
    end if;
    if not found then
      insert into public.cad_materia_prima_aliases(
        materia_prima_id,
        alias_type,
        alias_value,
        contexto_origem,
        source_batch_id,
        source_row_id,
        approved_by
      )
      values (
        p_materia_prima_id,
        'excel_codigo',
        v_staging.codigo_legado,
        'excel_legado',
        v_staging.batch_id,
        v_staging.source_row_id,
        v_actor
      )
      returning id into v_alias_id;
      v_alias_ids := v_alias_ids || jsonb_build_array(v_alias_id);
    end if;
  end if;

  if v_staging.nome_legado is not null then
    select *
      into v_existing_alias
      from public.cad_materia_prima_aliases alias
     where alias.alias_type = 'excel_nome'
       and alias.alias_norm = v_staging.nome_norm
       and alias.contexto_origem = 'excel_legado';
    if found and v_existing_alias.materia_prima_id <> p_materia_prima_id then
      raise exception 'legacy name alias already belongs to another canonical MP';
    end if;
    if not found then
      insert into public.cad_materia_prima_aliases(
        materia_prima_id,
        alias_type,
        alias_value,
        contexto_origem,
        source_batch_id,
        source_row_id,
        approved_by
      )
      values (
        p_materia_prima_id,
        'excel_nome',
        v_staging.nome_legado,
        'excel_legado',
        v_staging.batch_id,
        v_staging.source_row_id,
        v_actor
      )
      returning id into v_alias_id;
      v_alias_ids := v_alias_ids || jsonb_build_array(v_alias_id);
    end if;
  end if;

  insert into public.migration_mp_mapping_events(
    staging_item_id,
    status,
    materia_prima_id,
    match_method,
    confidence,
    reason_code,
    reason_detail,
    created_by
  )
  values (
    p_staging_item_id,
    'approved',
    p_materia_prima_id,
    p_match_method,
    p_confidence,
    p_reason_code,
    nullif(trim(p_reason_detail), ''),
    v_actor
  )
  returning id into v_event_id;

  v_after := jsonb_build_object(
    'mapping_event_id', v_event_id,
    'staging_item_id', p_staging_item_id,
    'materia_prima_id', p_materia_prima_id,
    'match_method', p_match_method,
    'confidence', p_confidence,
    'alias_ids', v_alias_ids
  );

  perform public.log_audited_rpc_change(
    'auditoria',
    'migration_mp_mapping_events',
    v_event_id::text,
    'auditoria.mp_mapping_approved',
    'migration.mp.map',
    v_permission_context,
    case when v_latest.id is null then null else to_jsonb(v_latest) end,
    v_after,
    jsonb_build_object('batch_id', v_staging.batch_id, 'source_row_id', v_staging.source_row_id),
    'database_rpc'
  );

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_materia_prima_aliases',
    p_materia_prima_id::text,
    'cadastros.materia_prima_aliases_registered',
    'cadastros.materias_primas.update.identity',
    v_cad_permission_context,
    null,
    jsonb_build_object('materia_prima_id', p_materia_prima_id, 'alias_ids', v_alias_ids),
    jsonb_build_object('batch_id', v_staging.batch_id, 'source_row_id', v_staging.source_row_id),
    'database_rpc'
  );

  return v_event_id;
end;
$$;

create or replace function public.register_migration_mp_acquisition_value(
  p_movimento_mp_id bigint,
  p_quantidade_origem numeric,
  p_unidade_origem text,
  p_quantidade_base numeric,
  p_valor_materia_prima numeric,
  p_frete numeric,
  p_difal_icms numeric,
  p_difal_status text,
  p_outras_despesas numeric default 0,
  p_custo_total_legado numeric default null,
  p_custo_medio_ponderado_legado numeric default null,
  p_saldo_lote_legado numeric default null,
  p_documento_ref text default null,
  p_data_documento date default null,
  p_uf_emitente text default null,
  p_source_batch_id bigint default null,
  p_source_row_id bigint default null,
  p_difal_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_stock_permission_context jsonb;
  v_movement public.est_movimentos_mp%rowtype;
  v_existing public.est_movimentos_mp_valores%rowtype;
  v_value_id bigint;
  v_uf text;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'migration.mp.import',
    'auditoria',
    'est_movimentos_mp_valores',
    'movement_event',
    jsonb_build_object(
      'movimento_mp_id', p_movimento_mp_id,
      'correlation_id', concat('migration_mp_movement:', p_movimento_mp_id, ':acquisition_value')
    )
  );
  v_stock_permission_context := public.begin_audited_rpc(
    'estoque.mp.acquisition_value.register',
    'estoque',
    'est_movimentos_mp_valores',
    'movement_event',
    jsonb_build_object(
      'movimento_mp_id', p_movimento_mp_id,
      'correlation_id', concat('migration_mp_movement:', p_movimento_mp_id, ':acquisition_value')
    )
  );
  v_actor := public.current_actor_id();
  v_uf := upper(nullif(trim(p_uf_emitente), ''));

  select *
    into v_movement
    from public.est_movimentos_mp movement
   where movement.id = p_movimento_mp_id
   for update;
  if not found then
    raise exception 'MP movement not found';
  end if;
  if v_movement.tipo_movimento not in ('importacao_inicial', 'entrada_compra', 'ajuste_entrada')
     or v_movement.quantidade <= 0 then
    raise exception 'acquisition value requires a positive MP entry movement';
  end if;

  if p_quantidade_origem is null or p_quantidade_origem <= 0
     or p_quantidade_base is null or p_quantidade_base <= 0 then
    raise exception 'origin and base quantities must be greater than zero';
  end if;
  if v_movement.quantidade is distinct from p_quantidade_base then
    raise exception 'quantidade_base must match the physical MP entry movement quantity';
  end if;
  if nullif(trim(p_unidade_origem), '') is null then
    raise exception 'unidade_origem is required';
  end if;
  if coalesce(p_valor_materia_prima, -1) < 0
     or coalesce(p_frete, -1) < 0
     or coalesce(p_difal_icms, -1) < 0
     or coalesce(p_outras_despesas, -1) < 0 then
    raise exception 'acquisition value components must be greater than or equal to zero';
  end if;
  if p_difal_status not in ('informed', 'not_applicable', 'pending_review') then
    raise exception 'invalid difal_status';
  end if;
  if p_difal_icms > 0 and p_difal_status <> 'informed' then
    raise exception 'positive DIFAL requires informed status';
  end if;
  if p_difal_status = 'pending_review' and nullif(trim(p_difal_motivo), '') is null then
    raise exception 'difal_motivo is required for pending_review';
  end if;
  if v_uf = 'SP' and p_difal_icms > 0 then
    raise exception 'DIFAL cannot be positive for SP emitter under the approved business rule';
  end if;
  if v_uf is not null and v_uf !~ '^[A-Z]{2}$' then
    raise exception 'invalid uf_emitente';
  end if;
  if p_source_batch_id is null or p_source_row_id is null then
    raise exception 'historical acquisition requires source_batch_id and source_row_id';
  end if;
  if not exists (
    select 1
      from public.source_rows source_row
      join public.source_tables source_table on source_table.id = source_row.table_id
      join public.migration_batches batch
        on batch.id = p_source_batch_id
       and batch.workbook_id = source_table.workbook_id
     where source_row.id = p_source_row_id
       and source_table.table_name = 'ENTRADAS_MP'
  ) then
    raise exception 'historical acquisition source must be an ENTRADAS_MP row from the batch workbook';
  end if;

  select *
    into v_existing
    from public.est_movimentos_mp_valores value
   where value.movimento_mp_id = p_movimento_mp_id;
  if found then
    if v_existing.quantidade_origem is not distinct from p_quantidade_origem
       and v_existing.unidade_origem is not distinct from trim(p_unidade_origem)
       and v_existing.quantidade_base is not distinct from p_quantidade_base
       and v_existing.valor_materia_prima is not distinct from p_valor_materia_prima
       and v_existing.frete is not distinct from p_frete
       and v_existing.difal_icms is not distinct from p_difal_icms
       and v_existing.difal_status is not distinct from p_difal_status
       and v_existing.difal_motivo is not distinct from nullif(trim(p_difal_motivo), '')
       and v_existing.outras_despesas is not distinct from p_outras_despesas
       and v_existing.custo_total_legado is not distinct from p_custo_total_legado
       and v_existing.custo_medio_ponderado_legado is not distinct from p_custo_medio_ponderado_legado
       and v_existing.saldo_lote_legado is not distinct from p_saldo_lote_legado
       and v_existing.documento_ref is not distinct from nullif(trim(p_documento_ref), '')
       and v_existing.data_documento is not distinct from p_data_documento
       and v_existing.uf_emitente is not distinct from v_uf
       and v_existing.source_batch_id is not distinct from p_source_batch_id
       and v_existing.source_row_id is not distinct from p_source_row_id then
      return v_existing.id;
    end if;
    raise exception 'acquisition value already exists with different immutable data';
  end if;

  insert into public.est_movimentos_mp_valores(
    movimento_mp_id,
    quantidade_origem,
    unidade_origem,
    quantidade_base,
    valor_materia_prima,
    frete,
    difal_icms,
    difal_status,
    difal_motivo,
    outras_despesas,
    custo_total_legado,
    custo_medio_ponderado_legado,
    saldo_lote_legado,
    documento_ref,
    data_documento,
    uf_emitente,
    origem_dados,
    source_batch_id,
    source_row_id,
    created_by
  )
  values (
    p_movimento_mp_id,
    p_quantidade_origem,
    trim(p_unidade_origem),
    p_quantidade_base,
    p_valor_materia_prima,
    p_frete,
    p_difal_icms,
    p_difal_status,
    nullif(trim(p_difal_motivo), ''),
    p_outras_despesas,
    p_custo_total_legado,
    p_custo_medio_ponderado_legado,
    p_saldo_lote_legado,
    nullif(trim(p_documento_ref), ''),
    p_data_documento,
    v_uf,
    'excel_legado',
    p_source_batch_id,
    p_source_row_id,
    v_actor
  )
  returning id into v_value_id;

  select to_jsonb(value)
    into v_after
    from public.est_movimentos_mp_valores value
   where value.id = v_value_id;

  perform public.log_audited_rpc_change(
    'estoque',
    'est_movimentos_mp_valores',
    v_value_id::text,
    'estoque.mp_acquisition_value_registered',
    'estoque.mp.acquisition_value.register',
    v_stock_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source_batch_id', p_source_batch_id,
      'source_row_id', p_source_row_id,
      'difal_component', p_difal_icms
    ),
    'database_rpc'
  );

  perform public.log_audited_rpc_change(
    'auditoria',
    'est_movimentos_mp_valores',
    v_value_id::text,
    'auditoria.mp_acquisition_imported',
    'migration.mp.import',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source_batch_id', p_source_batch_id,
      'source_row_id', p_source_row_id,
      'movimento_mp_id', p_movimento_mp_id
    ),
    'database_rpc'
  );

  return v_value_id;
end;
$$;

alter table public.migration_mp_staging_items enable row level security;
alter table public.migration_mp_mapping_events enable row level security;
alter table public.cad_materia_prima_aliases enable row level security;
alter table public.est_movimentos_mp_valores enable row level security;

drop policy if exists "active user read migration MP staging" on public.migration_mp_staging_items;
drop policy if exists "permitted user read migration MP staging" on public.migration_mp_staging_items;
create policy "permitted user read migration MP staging"
on public.migration_mp_staging_items for select to authenticated
using (public.can_current_user('migration.mp.view'));

drop policy if exists "active user read migration MP mappings" on public.migration_mp_mapping_events;
drop policy if exists "permitted user read migration MP mappings" on public.migration_mp_mapping_events;
create policy "permitted user read migration MP mappings"
on public.migration_mp_mapping_events for select to authenticated
using (public.can_current_user('migration.mp.view'));

drop policy if exists "active user read MP aliases" on public.cad_materia_prima_aliases;
drop policy if exists "permitted user read MP aliases" on public.cad_materia_prima_aliases;
create policy "permitted user read MP aliases"
on public.cad_materia_prima_aliases for select to authenticated
using (public.can_current_user('migration.mp.view'));

drop policy if exists "active user read MP acquisition values" on public.est_movimentos_mp_valores;
drop policy if exists "permitted user read MP acquisition values" on public.est_movimentos_mp_valores;
create policy "permitted user read MP acquisition values"
on public.est_movimentos_mp_valores for select to authenticated
using (public.can_current_user('migration.mp.view'));

revoke all on public.migration_mp_staging_items from anon, authenticated;
revoke all on public.migration_mp_mapping_events from anon, authenticated;
revoke all on public.cad_materia_prima_aliases from anon, authenticated;
revoke all on public.est_movimentos_mp_valores from anon, authenticated;
grant select on public.migration_mp_staging_items to authenticated;
grant select on public.migration_mp_mapping_events to authenticated;
grant select on public.cad_materia_prima_aliases to authenticated;
grant select on public.est_movimentos_mp_valores to authenticated;

revoke all on public.migration_mp_mapping_current from anon, authenticated;
revoke all on public.migration_mp_mapping_dashboard from anon, authenticated;
revoke all on public.migration_mp_batch_summary from anon, authenticated;
revoke all on public.est_mp_historico_precos from anon, authenticated;
grant select on public.migration_mp_mapping_current to authenticated;
grant select on public.migration_mp_mapping_dashboard to authenticated;
grant select on public.migration_mp_batch_summary to authenticated;
grant select on public.est_mp_historico_precos to authenticated;

revoke all on function public.prevent_historical_mp_fact_changes() from public;
revoke all on function public.enforce_historical_mp_source_lineage() from public;
revoke all on function public.enforce_historical_mp_batch_row_consistency() from public;
revoke all on function public.stage_migration_mp_items(bigint, jsonb) from public;
revoke all on function public.approve_migration_mp_mapping(bigint, bigint, text, numeric, text, text) from public;
revoke all on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) from public;

grant execute on function public.stage_migration_mp_items(bigint, jsonb) to authenticated;
grant execute on function public.approve_migration_mp_mapping(bigint, bigint, text, numeric, text, text) to authenticated;
grant execute on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) to authenticated;

comment on table public.migration_mp_staging_items is
  'Staging append-only e idempotente das identidades de MP extraidas do Excel. Nao e cadastro operacional.';
comment on table public.migration_mp_mapping_events is
  'Eventos append-only de sugestao, conflito e aprovacao entre identidade legada e MP canonica.';
comment on table public.cad_materia_prima_aliases is
  'Aliases historicos aprovados. Codigo/nome legado nunca substitui o SKU canonico.';
comment on table public.est_movimentos_mp_valores is
  'Componentes imutaveis do valor de aquisicao de uma entrada MP. Mercadoria, frete e DIFAL permanecem separados.';
comment on column public.est_movimentos_mp_valores.difal_icms is
  'Diferencial de aliquota de ICMS aplicavel informado pelo documento ou por confirmacao auditada; compoe o custo de aquisicao.';
comment on view public.migration_mp_mapping_dashboard is
  'Fila visual de conciliacao. Sugestao automatica nunca equivale a aprovacao.';
comment on view public.est_mp_historico_precos is
  'Linha do tempo de aquisicoes por MP/lote com componentes de valor e origem historica.';
