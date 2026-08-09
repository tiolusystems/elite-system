-- DEC-007: normalized technical catalogs, governed aliases and versioned
-- product specifications. Historical rows remain pending until human review.

create or replace function public.normalize_catalog_term(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(lower(regexp_replace(btrim(p_value), '\s+', ' ', 'g')), '')
$$;

revoke all on function public.normalize_catalog_term(text) from public, anon, authenticated;

create or replace function public.historical_migration_actor_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select profile.id
    from public.user_profiles profile
   where profile.is_system_actor = true
     and profile.system_actor_key = 'migracao_historica'
   limit 1
$$;

revoke all on function public.historical_migration_actor_id() from public, anon, authenticated;

create or replace function public.enforce_historical_record_contract()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_record jsonb := to_jsonb(new);
  v_origin text := nullif(v_record->>'origem_dados', '');
  v_batch_id bigint := nullif(v_record->>'source_batch_id', '')::bigint;
  v_source_row_id bigint := nullif(v_record->>'source_row_id', '')::bigint;
  v_created_by uuid := nullif(v_record->>'created_by', '')::uuid;
  v_actor_id uuid;
  v_batch_workbook_id bigint;
  v_row_workbook_id bigint;
  v_review_column text := nullif(coalesce(tg_argv[0], ''), '');
  v_required_review text := nullif(coalesce(tg_argv[1], ''), '');
begin
  if v_origin is null then
    if v_batch_id is not null or v_source_row_id is not null then
      raise exception 'source lineage requires origem_dados excel_legado';
    end if;
    return new;
  end if;

  if v_origin not in ('sistema', 'excel_legado') then
    raise exception 'invalid origem_dados: %', v_origin;
  end if;

  if v_origin = 'sistema' then
    if v_batch_id is not null or v_source_row_id is not null then
      raise exception 'source lineage is reserved for origem_dados excel_legado';
    end if;
    return new;
  end if;

  if v_batch_id is null or v_source_row_id is null then
    raise exception 'excel_legado requires source_batch_id and source_row_id';
  end if;

  v_actor_id := public.historical_migration_actor_id();
  if v_actor_id is null then
    raise exception 'Migracao Historica system actor is not provisioned';
  end if;
  if v_created_by is distinct from v_actor_id then
    raise exception 'excel_legado must be created by Migracao Historica system actor';
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
    raise exception 'historical source lineage not found';
  end if;
  if v_batch_workbook_id <> v_row_workbook_id then
    raise exception 'source_row_id does not belong to source_batch_id workbook';
  end if;

  if v_review_column is not null
     and v_record->>v_review_column is distinct from v_required_review then
    raise exception 'excel_legado requires % = %', v_review_column, v_required_review;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_historical_record_contract() from public, anon, authenticated;

create table if not exists public.cad_unidades_medida (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  simbolo text not null,
  dimensao text not null,
  status text not null default 'pending_review',
  vigencia_inicio date,
  vigencia_fim date,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_unidades_codigo_check check (
    codigo_norm is not null and char_length(codigo) <= 60
  ),
  constraint cad_unidades_text_check check (
    nullif(btrim(nome), '') is not null
    and nullif(btrim(simbolo), '') is not null
    and char_length(nome) <= 120
    and char_length(simbolo) <= 30
  ),
  constraint cad_unidades_dimensao_check check (
    dimensao in (
      'massa', 'volume', 'quantidade', 'concentracao', 'percentual',
      'temperatura', 'adimensional', 'outra', 'nao_classificada'
    )
  ),
  constraint cad_unidades_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_unidades_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_unidades_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_unidades_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_unidades_codigo_key unique (codigo_norm)
);

create unique index if not exists idx_cad_unidades_source_once
  on public.cad_unidades_medida(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table if not exists public.cad_unidade_aliases (
  id bigint generated always as identity primary key,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  alias text not null,
  alias_norm text generated always as (public.normalize_catalog_term(alias)) stored,
  contexto text not null default 'global',
  status text not null default 'pending_review',
  vigencia_inicio date,
  vigencia_fim date,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_unidade_alias_text_check check (
    alias_norm is not null and nullif(btrim(contexto), '') is not null
  ),
  constraint cad_unidade_alias_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_unidade_alias_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_unidade_alias_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_unidade_alias_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_unidade_alias_key unique (alias_norm, contexto)
);

create unique index if not exists idx_cad_unidade_alias_source_once
  on public.cad_unidade_aliases(source_batch_id, source_row_id, alias_norm)
  where origem_dados = 'excel_legado';

create table if not exists public.cad_nutrientes (
  id bigint generated always as identity primary key,
  nome text not null,
  nome_norm text generated always as (public.normalize_catalog_term(nome)) stored,
  simbolo text,
  status text not null default 'pending_review',
  vigencia_inicio date,
  vigencia_fim date,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_nutrientes_nome_check check (
    nome_norm is not null and char_length(nome) <= 120
  ),
  constraint cad_nutrientes_simbolo_check check (
    simbolo is null or (nullif(btrim(simbolo), '') is not null and char_length(simbolo) <= 30)
  ),
  constraint cad_nutrientes_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_nutrientes_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_nutrientes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_nutrientes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_nutrientes_nome_key unique (nome_norm)
);

create unique index if not exists idx_cad_nutrientes_source_once
  on public.cad_nutrientes(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table if not exists public.cad_nutriente_aliases (
  id bigint generated always as identity primary key,
  nutriente_id bigint not null references public.cad_nutrientes(id),
  alias text not null,
  alias_norm text generated always as (public.normalize_catalog_term(alias)) stored,
  contexto text not null default 'global',
  status text not null default 'pending_review',
  vigencia_inicio date,
  vigencia_fim date,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_nutriente_alias_text_check check (
    alias_norm is not null and nullif(btrim(contexto), '') is not null
  ),
  constraint cad_nutriente_alias_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_nutriente_alias_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_nutriente_alias_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_nutriente_alias_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_nutriente_alias_key unique (alias_norm, contexto)
);

create unique index if not exists idx_cad_nutriente_alias_source_once
  on public.cad_nutriente_aliases(source_batch_id, source_row_id, alias_norm)
  where origem_dados = 'excel_legado';

create table if not exists public.cad_parametros_tecnicos (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  tipo_valor text not null,
  unidade_padrao_id bigint references public.cad_unidades_medida(id),
  status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_parametros_codigo_check check (
    codigo_norm is not null and char_length(codigo) <= 80
  ),
  constraint cad_parametros_nome_check check (
    nullif(btrim(nome), '') is not null and char_length(nome) <= 120
  ),
  constraint cad_parametros_tipo_check check (tipo_valor in ('numeric', 'text')),
  constraint cad_parametros_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_parametros_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_parametros_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_parametros_codigo_key unique (codigo_norm)
);

create unique index if not exists idx_cad_parametros_source_once
  on public.cad_parametros_tecnicos(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table if not exists public.cad_especificacao_produto_versoes (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  tipo_especificacao text not null,
  versao integer not null,
  status text not null default 'pending_review',
  vigencia_inicio date,
  vigencia_fim date,
  justificativa text not null,
  supersedes_id bigint references public.cad_especificacao_produto_versoes(id),
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_especificacao_tipo_check check (
    tipo_especificacao in ('tecnica', 'mapa_documental')
  ),
  constraint cad_especificacao_versao_check check (versao > 0),
  constraint cad_especificacao_status_check check (
    status in ('draft', 'pending_review', 'retired')
  ),
  constraint cad_especificacao_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_especificacao_justificativa_check check (
    nullif(btrim(justificativa), '') is not null
  ),
  constraint cad_especificacao_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_especificacao_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_especificacao_version_key unique (
    produto_id, tipo_especificacao, versao
  )
);

create unique index if not exists idx_cad_especificacao_source_once
  on public.cad_especificacao_produto_versoes(
    source_batch_id, source_row_id, tipo_especificacao
  )
  where origem_dados = 'excel_legado';

create table if not exists public.cad_especificacao_produto_parametros (
  id bigint generated always as identity primary key,
  especificacao_versao_id bigint not null
    references public.cad_especificacao_produto_versoes(id),
  parametro_id bigint not null references public.cad_parametros_tecnicos(id),
  operador text not null,
  valor_minimo numeric,
  valor_maximo numeric,
  valor_texto text,
  unidade_id bigint references public.cad_unidades_medida(id),
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_especificacao_parametro_operador_check check (
    operador in ('igual', 'minimo', 'maximo', 'faixa', 'informativo')
  ),
  constraint cad_especificacao_parametro_valor_check check (
    (
      operador = 'faixa'
      and valor_minimo is not null
      and valor_maximo is not null
      and valor_maximo >= valor_minimo
      and valor_texto is null
    )
    or (
      operador in ('igual', 'minimo', 'maximo')
      and valor_minimo is not null
      and valor_maximo is null
      and valor_texto is null
    )
    or (
      operador = 'informativo'
      and valor_minimo is null
      and valor_maximo is null
      and nullif(btrim(valor_texto), '') is not null
    )
  ),
  constraint cad_especificacao_parametro_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_especificacao_parametro_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_especificacao_parametro_key unique (
    especificacao_versao_id, parametro_id
  )
);

create unique index if not exists idx_cad_especificacao_param_source_once
  on public.cad_especificacao_produto_parametros(
    source_batch_id, source_row_id, parametro_id
  )
  where origem_dados = 'excel_legado';

create table if not exists public.cad_especificacao_produto_ativacoes (
  id bigint generated always as identity primary key,
  especificacao_versao_id bigint not null unique
    references public.cad_especificacao_produto_versoes(id),
  motivo text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_especificacao_ativacao_motivo_check check (
    nullif(btrim(motivo), '') is not null
  )
);

create or replace function public.prevent_system_actor_catalog_activation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
      from public.user_profiles profile
     where profile.id = new.created_by
       and profile.is_system_actor = false
       and profile.status = 'active'
  ) then
    raise exception 'only active human profiles can activate product specifications';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_system_actor_catalog_activation() from public, anon, authenticated;

drop trigger if exists trg_cad_especificacao_activation_human on public.cad_especificacao_produto_ativacoes;
create trigger trg_cad_especificacao_activation_human
before insert on public.cad_especificacao_produto_ativacoes
for each row execute function public.prevent_system_actor_catalog_activation();

create or replace function public.prevent_technical_catalog_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new version or activation event', tg_table_name;
end;
$$;

revoke all on function public.prevent_technical_catalog_fact_changes() from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_especificacao_produto_versoes',
    'cad_especificacao_produto_parametros',
    'cad_especificacao_produto_ativacoes'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_technical_catalog_fact_changes()',
      'trg_' || v_table || '_append_only',
      v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_technical_catalog_fact_changes()',
      'trg_' || v_table || '_no_truncate',
      v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
begin
  if v_actor is null then
    raise exception 'Migracao Historica system actor is required by DEC-007';
  end if;

  insert into public.cad_unidades_medida(
    codigo, nome, simbolo, dimensao, status, origem_dados, created_by
  )
  values
    ('kg', 'Quilograma', 'kg', 'massa', 'active', 'sistema', v_actor),
    ('g', 'Grama', 'g', 'massa', 'active', 'sistema', v_actor),
    ('t', 'Tonelada', 't', 'massa', 'active', 'sistema', v_actor),
    ('l', 'Litro', 'L', 'volume', 'active', 'sistema', v_actor),
    ('ml', 'Mililitro', 'mL', 'volume', 'active', 'sistema', v_actor),
    ('un', 'Unidade', 'un', 'quantidade', 'active', 'sistema', v_actor),
    ('sc', 'Saca', 'sc', 'quantidade', 'active', 'sistema', v_actor),
    ('percent', 'Percentual', '%', 'percentual', 'active', 'sistema', v_actor),
    ('kg/l', 'Quilograma por litro', 'kg/L', 'concentracao', 'active', 'sistema', v_actor),
    ('deg_c', 'Celsius', 'C', 'temperatura', 'active', 'sistema', v_actor),
    ('one', 'Adimensional', '1', 'adimensional', 'active', 'sistema', v_actor)
  on conflict (codigo_norm) do nothing;

  insert into public.cad_unidade_aliases(
    unidade_id, alias, contexto, status, origem_dados, created_by
  )
  select unit.id, source.alias, 'global', 'active', 'sistema', v_actor
    from (
      values
        ('kg', 'kg'), ('kg', 'quilograma'), ('kg', 'quilogramas'),
        ('g', 'g'), ('g', 'grama'), ('g', 'gramas'),
        ('t', 't'), ('t', 'ton'), ('t', 'tonelada'), ('t', 'toneladas'),
        ('l', 'l'), ('l', 'lt'), ('l', 'litro'), ('l', 'litros'),
        ('ml', 'ml'), ('ml', 'mililitro'), ('ml', 'mililitros'),
        ('un', 'un'), ('un', 'und'), ('un', 'unidade'), ('un', 'unidades'),
        ('sc', 'sc'), ('sc', 'saca'), ('sc', 'sacas'),
        ('percent', '%'), ('percent', 'percentual'),
        ('kg/l', 'kg/l'), ('kg/l', 'quilograma por litro'),
        ('deg_c', 'c'), ('deg_c', 'celsius'),
        ('one', '1'), ('one', 'adimensional')
    ) as source(codigo, alias)
    join public.cad_unidades_medida unit
      on unit.codigo_norm = public.normalize_catalog_term(source.codigo)
  on conflict (alias_norm, contexto) do nothing;

  insert into public.cad_parametros_tecnicos(
    codigo, nome, tipo_valor, status, origem_dados, created_by
  ) values (
    'ph', 'pH', 'numeric', 'active', 'sistema', v_actor
  )
  on conflict (codigo_norm) do nothing;

  insert into public.cad_nutrientes(
    nome, simbolo, status, origem_dados, created_by
  ) values (
    'Nitrogenio', 'N', 'active', 'sistema', v_actor
  )
  on conflict (nome_norm) do nothing;

  insert into public.cad_nutriente_aliases(
    nutriente_id, alias, contexto, status, origem_dados, created_by
  )
  select nutrient.id, source.alias, 'global', 'active', 'sistema', v_actor
    from (values ('N'), ('Nitrogenio')) as source(alias)
    join public.cad_nutrientes nutrient
      on nutrient.nome_norm = public.normalize_catalog_term('Nitrogenio')
  on conflict (alias_norm, contexto) do nothing;
end;
$$;

-- Backfill distinct free-text values without silently classifying unknown terms.
do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
begin
  with source_units(raw_value) as (
    select unidade_base_estoque from public.cad_materias_primas
    union
    select unidade from public.cad_garantias_produto_mapa
    union
    select unidade from public.cad_garantias_lote_mp
    union
    select unidade from public.pcp_formula_itens
    union
    select unidade from public.pcp_op_garantia_resultados
  ), normalized as (
    select distinct on (public.normalize_catalog_term(raw_value))
      btrim(raw_value) as raw_value,
      public.normalize_catalog_term(raw_value) as normalized_value
    from source_units
    where public.normalize_catalog_term(raw_value) is not null
    order by public.normalize_catalog_term(raw_value), btrim(raw_value)
  )
  insert into public.cad_unidades_medida(
    codigo, nome, simbolo, dimensao, status, origem_dados, created_by
  )
  select
    normalized.raw_value,
    normalized.raw_value,
    normalized.raw_value,
    'nao_classificada',
    'pending_review',
    'sistema',
    v_actor
  from normalized
  where not exists (
    select 1
      from public.cad_unidade_aliases alias
     where alias.alias_norm = normalized.normalized_value
       and alias.status = 'active'
  )
  on conflict (codigo_norm) do nothing;

  with source_units(raw_value) as (
    select unidade_base_estoque from public.cad_materias_primas
    union
    select unidade from public.cad_garantias_produto_mapa
    union
    select unidade from public.cad_garantias_lote_mp
    union
    select unidade from public.pcp_formula_itens
    union
    select unidade from public.pcp_op_garantia_resultados
  )
  insert into public.cad_unidade_aliases(
    unidade_id, alias, contexto, status, origem_dados, created_by
  )
  select distinct
    unit.id,
    btrim(source.raw_value),
    'global',
    unit.status,
    'sistema',
    v_actor
  from source_units source
  join public.cad_unidades_medida unit
    on unit.codigo_norm = public.normalize_catalog_term(source.raw_value)
  where public.normalize_catalog_term(source.raw_value) is not null
  on conflict (alias_norm, contexto) do nothing;

  with source_nutrients(raw_value) as (
    select nutriente from public.cad_garantias_produto_mapa
    union
    select nutriente from public.cad_garantias_lote_mp
    union
    select nutriente from public.pcp_op_garantia_resultados
  ), normalized as (
    select distinct on (public.normalize_catalog_term(raw_value))
      btrim(raw_value) as raw_value,
      public.normalize_catalog_term(raw_value) as normalized_value
    from source_nutrients
    where public.normalize_catalog_term(raw_value) is not null
    order by public.normalize_catalog_term(raw_value), btrim(raw_value)
  )
  insert into public.cad_nutrientes(
    nome, status, origem_dados, created_by
  )
  select normalized.raw_value, 'pending_review', 'sistema', v_actor
  from normalized
  on conflict (nome_norm) do nothing;

  with source_nutrients(raw_value) as (
    select nutriente from public.cad_garantias_produto_mapa
    union
    select nutriente from public.cad_garantias_lote_mp
    union
    select nutriente from public.pcp_op_garantia_resultados
  )
  insert into public.cad_nutriente_aliases(
    nutriente_id, alias, contexto, status, origem_dados, created_by
  )
  select distinct
    nutrient.id,
    btrim(source.raw_value),
    'global',
    nutrient.status,
    'sistema',
    v_actor
  from source_nutrients source
  join public.cad_nutrientes nutrient
    on nutrient.nome_norm = public.normalize_catalog_term(source.raw_value)
  where public.normalize_catalog_term(source.raw_value) is not null
  on conflict (alias_norm, contexto) do nothing;
end;
$$;

create or replace function public.resolve_cad_unidade_id(p_value text)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text := public.normalize_catalog_term(p_value);
  v_ids bigint[];
begin
  if v_norm is null then
    return null;
  end if;

  select array_agg(distinct candidate.id order by candidate.id)
    into v_ids
    from (
      select unit.id
        from public.cad_unidades_medida unit
       where unit.status = 'active'
         and (
           unit.codigo_norm = v_norm
           or public.normalize_catalog_term(unit.nome) = v_norm
           or public.normalize_catalog_term(unit.simbolo) = v_norm
         )
      union
      select alias.unidade_id
        from public.cad_unidade_aliases alias
        join public.cad_unidades_medida unit on unit.id = alias.unidade_id
       where alias.alias_norm = v_norm
         and alias.status = 'active'
         and unit.status = 'active'
         and (alias.vigencia_inicio is null or alias.vigencia_inicio <= current_date)
         and (alias.vigencia_fim is null or alias.vigencia_fim >= current_date)
    ) candidate;

  if coalesce(cardinality(v_ids), 0) = 0 then
    raise exception 'unknown or unapproved unit: %', p_value;
  end if;
  if cardinality(v_ids) > 1 then
    raise exception 'ambiguous unit alias: %', p_value;
  end if;
  return v_ids[1];
end;
$$;

create or replace function public.resolve_cad_nutriente_id(p_value text)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text := public.normalize_catalog_term(p_value);
  v_ids bigint[];
begin
  if v_norm is null then
    return null;
  end if;

  select array_agg(distinct candidate.id order by candidate.id)
    into v_ids
    from (
      select nutrient.id
        from public.cad_nutrientes nutrient
       where nutrient.status = 'active'
         and (
           nutrient.nome_norm = v_norm
           or public.normalize_catalog_term(nutrient.simbolo) = v_norm
         )
      union
      select alias.nutriente_id
        from public.cad_nutriente_aliases alias
        join public.cad_nutrientes nutrient on nutrient.id = alias.nutriente_id
       where alias.alias_norm = v_norm
         and alias.status = 'active'
         and nutrient.status = 'active'
         and (alias.vigencia_inicio is null or alias.vigencia_inicio <= current_date)
         and (alias.vigencia_fim is null or alias.vigencia_fim >= current_date)
    ) candidate;

  if coalesce(cardinality(v_ids), 0) = 0 then
    raise exception 'unknown or unapproved nutrient: %', p_value;
  end if;
  if cardinality(v_ids) > 1 then
    raise exception 'ambiguous nutrient alias: %', p_value;
  end if;
  return v_ids[1];
end;
$$;

revoke all on function public.resolve_cad_unidade_id(text) from public, anon, authenticated;
revoke all on function public.resolve_cad_nutriente_id(text) from public, anon, authenticated;

alter table public.cad_materias_primas
  add column if not exists unidade_base_estoque_id bigint;

alter table public.pcp_formula_itens
  add column if not exists unidade_id bigint;

alter table public.cad_garantias_produto_mapa
  add column if not exists nutriente_id bigint,
  add column if not exists unidade_id bigint,
  add column if not exists natureza text not null default 'mapa_documental',
  add column if not exists review_status text not null default 'approved',
  add column if not exists origem_dados text not null default 'sistema',
  add column if not exists source_batch_id bigint,
  add column if not exists source_row_id bigint;

alter table public.cad_garantias_lote_mp
  add column if not exists nutriente_id bigint,
  add column if not exists unidade_id bigint,
  add column if not exists review_status text not null default 'approved',
  add column if not exists origem_dados text not null default 'sistema',
  add column if not exists source_batch_id bigint,
  add column if not exists source_row_id bigint;

alter table public.pcp_op_garantia_resultados
  add column if not exists nutriente_id bigint,
  add column if not exists unidade_id bigint;

alter table public.cad_garantias_produto_mapa disable trigger trg_cad_garantias_produto_append_only;
alter table public.cad_garantias_lote_mp disable trigger trg_cad_garantias_lote_append_only;
alter table public.pcp_formula_itens disable trigger trg_pcp_formula_itens_no_update;
alter table public.pcp_op_garantia_resultados disable trigger trg_pcp_op_garantia_resultados_append_only;

update public.cad_materias_primas material
   set unidade_base_estoque_id = coalesce(
     (
       select alias.unidade_id
         from public.cad_unidade_aliases alias
        where alias.alias_norm = public.normalize_catalog_term(material.unidade_base_estoque)
        order by case alias.status when 'active' then 0 else 1 end, alias.id
        limit 1
     ),
     (
       select unit.id
         from public.cad_unidades_medida unit
        where unit.codigo_norm = public.normalize_catalog_term(material.unidade_base_estoque)
        order by unit.id
        limit 1
     )
   )
 where material.unidade_base_estoque_id is null;

update public.pcp_formula_itens item
   set unidade = null
 where public.normalize_catalog_term(item.unidade) is null;

update public.pcp_formula_itens item
   set unidade_id = coalesce(
     (
       select alias.unidade_id
         from public.cad_unidade_aliases alias
        where alias.alias_norm = public.normalize_catalog_term(item.unidade)
        order by case alias.status when 'active' then 0 else 1 end, alias.id
        limit 1
     ),
     (
       select unit.id
         from public.cad_unidades_medida unit
        where unit.codigo_norm = public.normalize_catalog_term(item.unidade)
        order by unit.id
        limit 1
     )
   )
 where item.unidade_id is null
   and item.unidade is not null;

update public.cad_garantias_produto_mapa guarantee
   set nutriente_id = nutrient.id
  from public.cad_nutrientes nutrient
 where nutrient.nome_norm = public.normalize_catalog_term(guarantee.nutriente)
   and guarantee.nutriente_id is null;

update public.cad_garantias_produto_mapa guarantee
   set unidade_id = coalesce(
     (
       select alias.unidade_id
         from public.cad_unidade_aliases alias
        where alias.alias_norm = public.normalize_catalog_term(guarantee.unidade)
        order by case alias.status when 'active' then 0 else 1 end, alias.id
        limit 1
     ),
     (
       select unit.id
         from public.cad_unidades_medida unit
        where unit.codigo_norm = public.normalize_catalog_term(guarantee.unidade)
        order by unit.id
        limit 1
     )
   )
 where guarantee.unidade_id is null;

update public.cad_garantias_produto_mapa
   set natureza = case
         when fonte = 'calculado' then 'calculada_formula_legada'
         else 'mapa_documental'
       end,
       review_status = case
         when fonte = 'calculado' then 'pending_review'
         else 'approved'
       end;

update public.cad_garantias_lote_mp guarantee
   set nutriente_id = nutrient.id
  from public.cad_nutrientes nutrient
 where nutrient.nome_norm = public.normalize_catalog_term(guarantee.nutriente)
   and guarantee.nutriente_id is null;

update public.cad_garantias_lote_mp guarantee
   set unidade_id = coalesce(
     (
       select alias.unidade_id
         from public.cad_unidade_aliases alias
        where alias.alias_norm = public.normalize_catalog_term(guarantee.unidade)
        order by case alias.status when 'active' then 0 else 1 end, alias.id
        limit 1
     ),
     (
       select unit.id
         from public.cad_unidades_medida unit
        where unit.codigo_norm = public.normalize_catalog_term(guarantee.unidade)
        order by unit.id
        limit 1
     )
   )
 where guarantee.unidade_id is null;

update public.pcp_op_garantia_resultados result
   set nutriente_id = nutrient.id
  from public.cad_nutrientes nutrient
 where nutrient.nome_norm = public.normalize_catalog_term(result.nutriente)
   and result.nutriente_id is null;

update public.pcp_op_garantia_resultados result
   set unidade_id = coalesce(
     (
       select alias.unidade_id
         from public.cad_unidade_aliases alias
        where alias.alias_norm = public.normalize_catalog_term(result.unidade)
        order by case alias.status when 'active' then 0 else 1 end, alias.id
        limit 1
     ),
     (
       select unit.id
         from public.cad_unidades_medida unit
        where unit.codigo_norm = public.normalize_catalog_term(result.unidade)
        order by unit.id
        limit 1
     )
   )
 where result.unidade_id is null;

alter table public.cad_garantias_produto_mapa enable trigger trg_cad_garantias_produto_append_only;
alter table public.cad_garantias_lote_mp enable trigger trg_cad_garantias_lote_append_only;
alter table public.pcp_formula_itens enable trigger trg_pcp_formula_itens_no_update;
alter table public.pcp_op_garantia_resultados enable trigger trg_pcp_op_garantia_resultados_append_only;

do $$
begin
  if exists (
    select 1 from public.cad_materias_primas where unidade_base_estoque_id is null
  ) then
    raise exception 'DEC-007 backfill failed for cad_materias_primas units';
  end if;
  if exists (
    select 1 from public.cad_garantias_produto_mapa
     where nutriente_id is null or unidade_id is null
  ) then
    raise exception 'DEC-007 backfill failed for product guarantees';
  end if;
  if exists (
    select 1 from public.cad_garantias_lote_mp
     where nutriente_id is null or unidade_id is null
  ) then
    raise exception 'DEC-007 backfill failed for MP lot guarantees';
  end if;
  if exists (
    select 1 from public.pcp_op_garantia_resultados
     where nutriente_id is null or unidade_id is null
  ) then
    raise exception 'DEC-007 backfill failed for calculated OP guarantees';
  end if;
end;
$$;

alter table public.cad_materias_primas
  alter column unidade_base_estoque_id set not null,
  drop constraint if exists cad_materias_unidade_base_fk,
  add constraint cad_materias_unidade_base_fk
    foreign key (unidade_base_estoque_id) references public.cad_unidades_medida(id)
    not valid;
alter table public.cad_materias_primas validate constraint cad_materias_unidade_base_fk;

alter table public.pcp_formula_itens
  drop constraint if exists pcp_formula_itens_unidade_fk,
  drop constraint if exists pcp_formula_itens_unidade_pair_check,
  add constraint pcp_formula_itens_unidade_fk
    foreign key (unidade_id) references public.cad_unidades_medida(id) not valid,
  add constraint pcp_formula_itens_unidade_pair_check check (
    (unidade is null and unidade_id is null)
    or (nullif(btrim(unidade), '') is not null and unidade_id is not null)
  ) not valid;
alter table public.pcp_formula_itens validate constraint pcp_formula_itens_unidade_fk;
alter table public.pcp_formula_itens validate constraint pcp_formula_itens_unidade_pair_check;

alter table public.cad_garantias_produto_mapa
  alter column nutriente_id set not null,
  alter column unidade_id set not null,
  drop constraint if exists cad_garantias_produto_nutriente_fk,
  drop constraint if exists cad_garantias_produto_unidade_fk,
  drop constraint if exists cad_garantias_produto_source_batch_fk,
  drop constraint if exists cad_garantias_produto_source_row_fk,
  drop constraint if exists cad_garantias_produto_natureza_check,
  drop constraint if exists cad_garantias_produto_review_check,
  drop constraint if exists cad_garantias_produto_origem_check,
  drop constraint if exists cad_garantias_produto_source_pair_check,
  add constraint cad_garantias_produto_nutriente_fk
    foreign key (nutriente_id) references public.cad_nutrientes(id) not valid,
  add constraint cad_garantias_produto_unidade_fk
    foreign key (unidade_id) references public.cad_unidades_medida(id) not valid,
  add constraint cad_garantias_produto_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id),
  add constraint cad_garantias_produto_source_row_fk
    foreign key (source_row_id) references public.source_rows(id),
  add constraint cad_garantias_produto_natureza_check check (
    (natureza = 'mapa_documental' and fonte <> 'calculado')
    or (
      natureza = 'calculada_formula_legada'
      and fonte = 'calculado'
      and review_status = 'pending_review'
    )
  ) not valid,
  add constraint cad_garantias_produto_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint cad_garantias_produto_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_garantias_produto_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );
alter table public.cad_garantias_produto_mapa validate constraint cad_garantias_produto_nutriente_fk;
alter table public.cad_garantias_produto_mapa validate constraint cad_garantias_produto_unidade_fk;
alter table public.cad_garantias_produto_mapa validate constraint cad_garantias_produto_natureza_check;

alter table public.cad_garantias_lote_mp
  alter column nutriente_id set not null,
  alter column unidade_id set not null,
  drop constraint if exists cad_garantias_lote_nutriente_fk,
  drop constraint if exists cad_garantias_lote_unidade_fk,
  drop constraint if exists cad_garantias_lote_source_batch_fk,
  drop constraint if exists cad_garantias_lote_source_row_fk,
  drop constraint if exists cad_garantias_lote_review_check,
  drop constraint if exists cad_garantias_lote_origem_check,
  drop constraint if exists cad_garantias_lote_source_pair_check,
  add constraint cad_garantias_lote_nutriente_fk
    foreign key (nutriente_id) references public.cad_nutrientes(id) not valid,
  add constraint cad_garantias_lote_unidade_fk
    foreign key (unidade_id) references public.cad_unidades_medida(id) not valid,
  add constraint cad_garantias_lote_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id),
  add constraint cad_garantias_lote_source_row_fk
    foreign key (source_row_id) references public.source_rows(id),
  add constraint cad_garantias_lote_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint cad_garantias_lote_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_garantias_lote_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );
alter table public.cad_garantias_lote_mp validate constraint cad_garantias_lote_nutriente_fk;
alter table public.cad_garantias_lote_mp validate constraint cad_garantias_lote_unidade_fk;

alter table public.pcp_op_garantia_resultados
  alter column nutriente_id set not null,
  alter column unidade_id set not null,
  drop constraint if exists pcp_op_garantia_nutriente_fk,
  drop constraint if exists pcp_op_garantia_unidade_fk,
  add constraint pcp_op_garantia_nutriente_fk
    foreign key (nutriente_id) references public.cad_nutrientes(id) not valid,
  add constraint pcp_op_garantia_unidade_fk
    foreign key (unidade_id) references public.cad_unidades_medida(id) not valid;
alter table public.pcp_op_garantia_resultados validate constraint pcp_op_garantia_nutriente_fk;
alter table public.pcp_op_garantia_resultados validate constraint pcp_op_garantia_unidade_fk;

create unique index if not exists idx_cad_garantia_produto_source_once
  on public.cad_garantias_produto_mapa(
    source_batch_id, source_row_id, nutriente_id, unidade_id, tipo_limite
  ) where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_garantia_lote_source_once
  on public.cad_garantias_lote_mp(
    source_batch_id, source_row_id, nutriente_id, unidade_id
  ) where origem_dados = 'excel_legado';

create index if not exists idx_cad_garantias_produto_catalog
  on public.cad_garantias_produto_mapa(produto_id, nutriente_id, unidade_id, id desc);

create index if not exists idx_cad_garantias_lote_catalog
  on public.cad_garantias_lote_mp(lote_mp_id, nutriente_id, unidade_id, id desc);

create or replace function public.sync_cad_materia_prima_unidade()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_resolved_id bigint;
begin
  if tg_op = 'UPDATE'
     and public.normalize_catalog_term(new.unidade_base_estoque)
         is distinct from public.normalize_catalog_term(old.unidade_base_estoque)
     and new.unidade_base_estoque_id is not distinct from old.unidade_base_estoque_id then
    new.unidade_base_estoque_id := public.resolve_cad_unidade_id(new.unidade_base_estoque);
  elsif new.unidade_base_estoque_id is null then
    new.unidade_base_estoque_id := public.resolve_cad_unidade_id(new.unidade_base_estoque);
  elsif tg_op = 'UPDATE'
        and public.normalize_catalog_term(new.unidade_base_estoque)
            is distinct from public.normalize_catalog_term(old.unidade_base_estoque)
        and new.unidade_base_estoque_id is distinct from old.unidade_base_estoque_id then
    v_resolved_id := public.resolve_cad_unidade_id(new.unidade_base_estoque);
    if v_resolved_id <> new.unidade_base_estoque_id then
      raise exception 'unit text and unidade_base_estoque_id refer to different units';
    end if;
  end if;
  select unit.simbolo into new.unidade_base_estoque
    from public.cad_unidades_medida unit
   where unit.id = new.unidade_base_estoque_id;
  if new.unidade_base_estoque is null then
    raise exception 'unidade_base_estoque_id not found';
  end if;
  return new;
end;
$$;

create or replace function public.sync_pcp_formula_item_unidade()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.unidade is null and new.unidade_id is null then
    return new;
  end if;
  if new.unidade_id is null then
    new.unidade_id := public.resolve_cad_unidade_id(new.unidade);
  end if;
  select unit.simbolo into new.unidade
    from public.cad_unidades_medida unit
   where unit.id = new.unidade_id;
  if new.unidade is null then
    raise exception 'unidade_id not found';
  end if;
  return new;
end;
$$;

create or replace function public.sync_cad_garantia_catalog_refs()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.nutriente_id is null then
    new.nutriente_id := public.resolve_cad_nutriente_id(new.nutriente);
  end if;
  if new.unidade_id is null then
    new.unidade_id := public.resolve_cad_unidade_id(new.unidade);
  end if;
  select nutrient.nome into new.nutriente
    from public.cad_nutrientes nutrient
   where nutrient.id = new.nutriente_id;
  select unit.simbolo into new.unidade
    from public.cad_unidades_medida unit
   where unit.id = new.unidade_id;
  if new.nutriente is null or new.unidade is null then
    raise exception 'nutrient or unit catalog reference not found';
  end if;
  return new;
end;
$$;

create or replace function public.classify_cad_product_guarantee()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.fonte = 'calculado' then
    new.natureza := 'calculada_formula_legada';
    new.review_status := 'pending_review';
  else
    new.natureza := 'mapa_documental';
  end if;
  return new;
end;
$$;

revoke all on function public.sync_cad_materia_prima_unidade() from public, anon, authenticated;
revoke all on function public.sync_pcp_formula_item_unidade() from public, anon, authenticated;
revoke all on function public.sync_cad_garantia_catalog_refs() from public, anon, authenticated;
revoke all on function public.classify_cad_product_guarantee() from public, anon, authenticated;

drop trigger if exists trg_10_cad_materia_prima_unidade on public.cad_materias_primas;
create trigger trg_10_cad_materia_prima_unidade
before insert or update of unidade_base_estoque, unidade_base_estoque_id
on public.cad_materias_primas
for each row execute function public.sync_cad_materia_prima_unidade();

drop trigger if exists trg_10_pcp_formula_item_unidade on public.pcp_formula_itens;
create trigger trg_10_pcp_formula_item_unidade
before insert on public.pcp_formula_itens
for each row execute function public.sync_pcp_formula_item_unidade();

drop trigger if exists trg_10_cad_garantia_produto_catalog on public.cad_garantias_produto_mapa;
create trigger trg_10_cad_garantia_produto_catalog
before insert on public.cad_garantias_produto_mapa
for each row execute function public.sync_cad_garantia_catalog_refs();

drop trigger if exists trg_20_cad_garantia_produto_classify on public.cad_garantias_produto_mapa;
create trigger trg_20_cad_garantia_produto_classify
before insert on public.cad_garantias_produto_mapa
for each row execute function public.classify_cad_product_guarantee();

drop trigger if exists trg_30_cad_garantia_produto_history on public.cad_garantias_produto_mapa;
create trigger trg_30_cad_garantia_produto_history
before insert on public.cad_garantias_produto_mapa
for each row execute function public.enforce_historical_record_contract('review_status', 'pending_review');

drop trigger if exists trg_10_cad_garantia_lote_catalog on public.cad_garantias_lote_mp;
create trigger trg_10_cad_garantia_lote_catalog
before insert on public.cad_garantias_lote_mp
for each row execute function public.sync_cad_garantia_catalog_refs();

drop trigger if exists trg_30_cad_garantia_lote_history on public.cad_garantias_lote_mp;
create trigger trg_30_cad_garantia_lote_history
before insert on public.cad_garantias_lote_mp
for each row execute function public.enforce_historical_record_contract('review_status', 'pending_review');

drop trigger if exists trg_10_pcp_op_garantia_catalog on public.pcp_op_garantia_resultados;
create trigger trg_10_pcp_op_garantia_catalog
before insert on public.pcp_op_garantia_resultados
for each row execute function public.sync_cad_garantia_catalog_refs();

do $$
declare
  v_table text;
  v_review_column text;
begin
  foreach v_table in array array[
    'cad_unidades_medida',
    'cad_unidade_aliases',
    'cad_nutrientes',
    'cad_nutriente_aliases',
    'cad_parametros_tecnicos',
    'cad_especificacao_produto_versoes',
    'cad_especificacao_produto_parametros'
  ]
  loop
    v_review_column := case
      when v_table = 'cad_especificacao_produto_parametros' then ''
      else 'status'
    end;
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_history', v_table);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
      'trg_' || v_table || '_history',
      v_table,
      v_review_column,
      case when v_review_column = '' then '' else 'pending_review' end
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['cad_materias_primas', 'cad_produtos_base']
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_history', v_table);
    execute format(
      'create trigger %I before insert or update of origem_dados, source_batch_id, source_row_id, created_by, status on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
      'trg_' || v_table || '_history',
      v_table,
      'status',
      'pending_review'
    );
  end loop;
end;
$$;

drop view if exists public.cad_garantias_produto_mapa_atuais;
create view public.cad_garantias_produto_mapa_atuais
with (security_invoker = true)
as
select current_guarantee.*
from (
  select
    guarantee.*,
    row_number() over (
      partition by guarantee.produto_id, guarantee.nutriente_id, guarantee.unidade_id
      order by guarantee.id desc
    ) as guarantee_rank
  from public.cad_garantias_produto_mapa guarantee
  where guarantee.natureza = 'mapa_documental'
    and guarantee.review_status = 'approved'
    and (guarantee.vigencia_inicio is null or guarantee.vigencia_inicio <= current_date)
    and (guarantee.vigencia_fim is null or guarantee.vigencia_fim >= current_date)
) current_guarantee
where current_guarantee.guarantee_rank = 1;

create or replace view public.cad_garantias_produto_calculadas_pendentes
with (security_invoker = true)
as
select guarantee.*
  from public.cad_garantias_produto_mapa guarantee
 where guarantee.natureza = 'calculada_formula_legada'
   and guarantee.review_status = 'pending_review';

drop view if exists public.cad_garantias_lote_mp_atuais;
create view public.cad_garantias_lote_mp_atuais
with (security_invoker = true)
as
select current_guarantee.*
from (
  select
    guarantee.*,
    row_number() over (
      partition by guarantee.lote_mp_id, guarantee.nutriente_id, guarantee.unidade_id
      order by guarantee.data_referencia desc nulls last, guarantee.id desc
    ) as guarantee_rank
  from public.cad_garantias_lote_mp guarantee
  where guarantee.lote_mp_id is not null
    and guarantee.review_status = 'approved'
) current_guarantee
where current_guarantee.guarantee_rank = 1;

create or replace view public.cad_especificacoes_produto_atuais
with (security_invoker = true)
as
select current_spec.*
from (
  select
    spec.*,
    activation.id as activation_id,
    activation.motivo as activation_reason,
    activation.created_by as activated_by,
    activation.created_at as activated_at,
    row_number() over (
      partition by spec.produto_id, spec.tipo_especificacao
      order by activation.created_at desc, activation.id desc
    ) as specification_rank
  from public.cad_especificacao_produto_versoes spec
  join public.cad_especificacao_produto_ativacoes activation
    on activation.especificacao_versao_id = spec.id
  where spec.status <> 'retired'
    and (spec.vigencia_inicio is null or spec.vigencia_inicio <= current_date)
    and (spec.vigencia_fim is null or spec.vigencia_fim >= current_date)
) current_spec
where current_spec.specification_rank = 1;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_unidades_medida',
    'cad_unidade_aliases',
    'cad_nutrientes',
    'cad_nutriente_aliases',
    'cad_parametros_tecnicos',
    'cad_especificacao_produto_versoes',
    'cad_especificacao_produto_parametros',
    'cad_especificacao_produto_ativacoes'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('drop policy if exists %I on public.%I', 'authenticated read ' || v_table, v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      'authenticated read ' || v_table,
      v_table
    );
    execute format('grant select on public.%I to authenticated', v_table);
    execute format('revoke insert, update, delete, truncate on public.%I from public, anon, authenticated', v_table);
  end loop;
end;
$$;

grant select on
  public.cad_garantias_produto_calculadas_pendentes,
  public.cad_especificacoes_produto_atuais
to authenticated;

comment on table public.cad_unidades_medida is
  'Catalogo tecnico canonico de unidades. Aliases e conversoes referenciam esta identidade.';
comment on table public.cad_nutrientes is
  'Catalogo normalizado de nutrientes usado por garantias documentais e calculadas.';
comment on table public.cad_especificacao_produto_versoes is
  'Versoes append-only de especificacoes tecnicas ou documentais; importacao historica nasce pendente.';
comment on table public.cad_especificacao_produto_parametros is
  'Valores relacionais por parametro; JSON nao substitui faixas consultaveis.';
comment on view public.cad_especificacoes_produto_atuais is
  'Somente especificacoes ativadas por ator humano; Migracao Historica nao pode ativar.';
comment on view public.cad_garantias_produto_calculadas_pendentes is
  'Valores calculados legados isolados da garantia documental MAPA e nunca promovidos automaticamente.';
