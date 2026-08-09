-- DEC-006: formula yield/stages and historical OPs with explicit unknown
-- formula reference. Historical outputs never create stock automatically.

alter table public.pcp_formula_versoes
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.pcp_formula_itens
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id),
  add column if not exists created_by uuid references public.user_profiles(id);

alter table public.pcp_formula_versoes disable trigger user;
alter table public.pcp_formula_itens disable trigger user;

update public.pcp_formula_versoes
   set review_status = coalesce(review_status, 'approved'),
       origem_dados = coalesce(origem_dados, 'sistema');
update public.pcp_formula_itens item
   set review_status = coalesce(item.review_status, 'approved'),
       origem_dados = coalesce(item.origem_dados, 'sistema'),
       created_by = coalesce(item.created_by, version.created_by)
  from public.pcp_formula_versoes version
 where version.id = item.formula_versao_id;

alter table public.pcp_formula_versoes enable trigger user;
alter table public.pcp_formula_itens enable trigger user;

alter table public.pcp_formula_versoes
  alter column review_status set default 'approved',
  alter column review_status set not null,
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint pcp_formula_versoes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint pcp_formula_versoes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint pcp_formula_versoes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

alter table public.pcp_formula_itens
  alter column review_status set default 'approved',
  alter column review_status set not null,
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint pcp_formula_itens_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint pcp_formula_itens_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint pcp_formula_itens_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

create unique index idx_pcp_formula_versoes_source_once
  on public.pcp_formula_versoes(source_batch_id, source_row_id, tipo_receita)
  where origem_dados = 'excel_legado';
create unique index idx_pcp_formula_itens_source_once
  on public.pcp_formula_itens(source_batch_id, source_row_id, tipo_componente)
  where origem_dados = 'excel_legado';
create unique index idx_pcp_formula_versoes_identity_product
  on public.pcp_formula_versoes(id, produto_id);
create unique index idx_pcp_formula_itens_identity_version
  on public.pcp_formula_itens(id, formula_versao_id);

create table public.pcp_formula_rendimentos (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null unique references public.pcp_formula_versoes(id),
  quantidade_base numeric not null,
  unidade_base_id bigint not null references public.cad_unidades_medida(id),
  quantidade_saida numeric not null,
  unidade_saida_id bigint not null references public.cad_unidades_medida(id),
  natureza_saida text not null,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_rendimentos_quantidade_check check (
    quantidade_base > 0 and quantidade_saida > 0
  ),
  constraint pcp_formula_rendimentos_natureza_check check (
    natureza_saida in ('PA', 'PI', 'nao_determinada')
    and (natureza_saida <> 'nao_determinada' or review_status = 'pending_review')
  ),
  constraint pcp_formula_rendimentos_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint pcp_formula_rendimentos_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint pcp_formula_rendimentos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_pcp_formula_rendimentos_source_once
  on public.pcp_formula_rendimentos(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.pcp_formula_etapas (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.pcp_formula_versoes(id),
  sequencia integer not null,
  fase text,
  instrucao text,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_etapas_sequencia_check check (sequencia > 0),
  constraint pcp_formula_etapas_text_check check (
    nullif(btrim(coalesce(fase, '')), '') is not null
    or nullif(btrim(coalesce(instrucao, '')), '') is not null
  ),
  constraint pcp_formula_etapas_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint pcp_formula_etapas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint pcp_formula_etapas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint pcp_formula_etapas_key unique (formula_versao_id, sequencia)
);

create unique index idx_pcp_formula_etapas_identity_version
  on public.pcp_formula_etapas(id, formula_versao_id);
create unique index idx_pcp_formula_etapas_source_once
  on public.pcp_formula_etapas(source_batch_id, source_row_id, sequencia)
  where origem_dados = 'excel_legado';

create table public.pcp_formula_item_etapas (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.pcp_formula_versoes(id),
  formula_item_id bigint not null,
  etapa_id bigint not null,
  ordem_adicao integer,
  observacao text,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_item_etapas_item_fk
    foreign key (formula_item_id, formula_versao_id)
    references public.pcp_formula_itens(id, formula_versao_id),
  constraint pcp_formula_item_etapas_etapa_fk
    foreign key (etapa_id, formula_versao_id)
    references public.pcp_formula_etapas(id, formula_versao_id),
  constraint pcp_formula_item_etapas_ordem_check check (
    ordem_adicao is null or ordem_adicao > 0
  ),
  constraint pcp_formula_item_etapas_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint pcp_formula_item_etapas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint pcp_formula_item_etapas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint pcp_formula_item_etapas_key unique (formula_item_id)
);

create unique index idx_pcp_formula_item_etapas_source_once
  on public.pcp_formula_item_etapas(source_batch_id, source_row_id, formula_item_id)
  where origem_dados = 'excel_legado';

create table public.pcp_formula_referencias_historicas (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  referencia_tipo text not null default 'versao_desconhecida',
  codigo_legado text,
  evidencia_detalhe text not null,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_refs_tipo_check check (
    referencia_tipo = 'versao_desconhecida'
  ),
  constraint pcp_formula_refs_evidencia_check check (
    nullif(btrim(evidencia_detalhe), '') is not null
  ),
  constraint pcp_formula_refs_review_check check (review_status = 'pending_review'),
  constraint pcp_formula_refs_origem_check check (origem_dados = 'excel_legado'),
  constraint pcp_formula_refs_source_key unique (source_batch_id, source_row_id, produto_id)
);

create unique index idx_pcp_formula_refs_identity_product
  on public.pcp_formula_referencias_historicas(id, produto_id);

alter table public.pcp_ordens_producao
  add column if not exists produto_id bigint,
  add column if not exists formula_referencia_historica_id bigint,
  add column if not exists tipo_op_legado text,
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

update public.pcp_ordens_producao op
   set produto_id = version.produto_id,
       review_status = coalesce(op.review_status, 'approved'),
       origem_dados = coalesce(op.origem_dados, 'sistema')
  from public.pcp_formula_versoes version
 where version.id = op.formula_versao_id;

alter table public.pcp_ordens_producao
  alter column produto_id set not null,
  alter column formula_versao_id drop not null,
  alter column review_status set default 'approved',
  alter column review_status set not null,
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  drop constraint if exists pcp_ordens_tipo_check,
  add constraint pcp_ordens_tipo_check check (
    tipo_op in (
      'estoque', 'experimental', 'desenvolvimento', 'reprocessamento',
      'mapa_documental', 'historico_nao_classificado'
    )
  ),
  add constraint pcp_ordens_produto_fk foreign key (produto_id)
    references public.cad_produtos_base(id),
  add constraint pcp_ordens_formula_product_fk
    foreign key (formula_versao_id, produto_id)
    references public.pcp_formula_versoes(id, produto_id) not valid,
  add constraint pcp_ordens_formula_ref_product_fk
    foreign key (formula_referencia_historica_id, produto_id)
    references public.pcp_formula_referencias_historicas(id, produto_id) not valid,
  add constraint pcp_ordens_formula_reference_check check (
    (formula_versao_id is not null and formula_referencia_historica_id is null)
    or (formula_versao_id is null and formula_referencia_historica_id is not null)
  ),
  add constraint pcp_ordens_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint pcp_ordens_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint pcp_ordens_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

alter table public.pcp_ordens_producao validate constraint pcp_ordens_formula_product_fk;
alter table public.pcp_ordens_producao validate constraint pcp_ordens_formula_ref_product_fk;

create unique index idx_pcp_ordens_source_once
  on public.pcp_ordens_producao(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_produto_embalagens_identity_product
  on public.cad_produto_embalagens(id, produto_id);

create table public.pcp_op_saidas_historicas (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id),
  produto_id bigint not null references public.cad_produtos_base(id),
  natureza_saida text not null,
  produto_embalagem_id bigint,
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  codigo_lote_legado text,
  quantidade numeric not null,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_saidas_produto_embalagem_fk
    foreign key (produto_embalagem_id, produto_id)
    references public.cad_produto_embalagens(id, produto_id),
  constraint pcp_op_saidas_natureza_check check (
    (natureza_saida = 'nao_classificada' and produto_embalagem_id is null and lote_pa_id is null and lote_pi_id is null)
    or (natureza_saida = 'PA' and produto_embalagem_id is not null and lote_pi_id is null)
    or (natureza_saida = 'PI' and produto_embalagem_id is null and lote_pa_id is null)
  ),
  constraint pcp_op_saidas_quantidade_check check (quantidade > 0),
  constraint pcp_op_saidas_review_check check (review_status = 'pending_review'),
  constraint pcp_op_saidas_origem_check check (origem_dados = 'excel_legado'),
  constraint pcp_op_saidas_source_key unique (source_batch_id, source_row_id, natureza_saida)
);

create table public.pcp_op_cq_historico_parcial (
  id bigint generated always as identity primary key,
  op_id bigint not null unique references public.pcp_ordens_producao(id),
  ph numeric,
  densidade_kg_l numeric,
  volume_l numeric,
  massa_kg numeric,
  temperatura_c numeric,
  observacao text,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_cq_historico_values_check check (
    (ph is null or ph >= 0)
    and (densidade_kg_l is null or densidade_kg_l > 0)
    and (volume_l is null or volume_l > 0)
    and (massa_kg is null or massa_kg > 0)
  ),
  constraint pcp_op_cq_historico_presence_check check (
    ph is not null or densidade_kg_l is not null or volume_l is not null
    or massa_kg is not null or temperatura_c is not null
    or nullif(btrim(coalesce(observacao, '')), '') is not null
  ),
  constraint pcp_op_cq_historico_review_check check (review_status = 'pending_review'),
  constraint pcp_op_cq_historico_origem_check check (origem_dados = 'excel_legado'),
  constraint pcp_op_cq_historico_source_key unique (source_batch_id, source_row_id)
);

create or replace function public.validate_historical_op_formula_reference()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_formula_origin text;
  v_formula_review text;
begin
  if new.produto_id is null and new.formula_versao_id is not null then
    select version.produto_id into new.produto_id
      from public.pcp_formula_versoes version
     where version.id = new.formula_versao_id;
  end if;

  if new.origem_dados = 'excel_legado' then
    if new.formula_versao_id is not null then
      select version.origem_dados, version.review_status
        into v_formula_origin, v_formula_review
        from public.pcp_formula_versoes version
       where version.id = new.formula_versao_id;
      if v_formula_origin <> 'excel_legado' or v_formula_review <> 'pending_review' then
        raise exception 'historical OP cannot reference a current system formula';
      end if;
    end if;
  elsif new.formula_referencia_historica_id is not null then
    raise exception 'live OP cannot use an unknown historical formula reference';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_historical_op_formula_reference() from public, anon, authenticated;

create trigger trg_pcp_ordens_formula_reference
before insert or update of formula_versao_id, formula_referencia_historica_id,
  produto_id, origem_dados, review_status
on public.pcp_ordens_producao
for each row execute function public.validate_historical_op_formula_reference();

create or replace function public.prevent_historical_op_state_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.origem_dados = 'excel_legado' and new.status is distinct from old.status then
    raise exception 'historical OP state is immutable and cannot enter the live workflow';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_historical_op_state_change() from public, anon, authenticated;

create trigger trg_pcp_ordens_historical_state
before update of status on public.pcp_ordens_producao
for each row execute function public.prevent_historical_op_state_change();

create or replace function public.validate_formula_activation_source()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
      from public.user_profiles profile
     where profile.id = new.created_by
       and profile.status = 'active'
       and profile.is_system_actor = false
  ) then
    raise exception 'only active human profiles can activate formulas';
  end if;
  if not exists (
    select 1 from public.pcp_formula_versoes version
     where version.id = new.formula_versao_id
       and version.produto_id = new.produto_id
       and version.tipo_receita = new.tipo_receita
       and version.origem_dados = 'sistema'
       and version.review_status = 'approved'
  ) then
    raise exception 'historical or pending formula cannot be activated';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_formula_activation_source() from public, anon, authenticated;

create trigger trg_pcp_formula_activation_source
before insert on public.pcp_formula_ativacoes
for each row execute function public.validate_formula_activation_source();

create or replace function public.validate_formula_child_lineage()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_origin text;
  v_batch_id bigint;
begin
  select version.origem_dados, version.source_batch_id
    into v_origin, v_batch_id
    from public.pcp_formula_versoes version
   where version.id = new.formula_versao_id;

  if new.origem_dados <> v_origin then
    raise exception 'formula child origin must match its version';
  end if;
  if new.origem_dados = 'excel_legado' and new.source_batch_id <> v_batch_id then
    raise exception 'formula child batch must match its version';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_formula_child_lineage() from public, anon, authenticated;

create trigger trg_pcp_formula_itens_version_lineage
before insert on public.pcp_formula_itens
for each row execute function public.validate_formula_child_lineage();
create trigger trg_pcp_formula_rendimentos_version_lineage
before insert on public.pcp_formula_rendimentos
for each row execute function public.validate_formula_child_lineage();
create trigger trg_pcp_formula_etapas_version_lineage
before insert on public.pcp_formula_etapas
for each row execute function public.validate_formula_child_lineage();
create trigger trg_pcp_formula_item_etapas_version_lineage
before insert on public.pcp_formula_item_etapas
for each row execute function public.validate_formula_child_lineage();

create or replace function public.validate_historical_op_child_lineage()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_origin text;
  v_batch_id bigint;
  v_product_id bigint;
begin
  select op.origem_dados, op.source_batch_id, op.produto_id
    into v_origin, v_batch_id, v_product_id
    from public.pcp_ordens_producao op
   where op.id = new.op_id;

  if v_origin <> 'excel_legado'
     or new.origem_dados <> v_origin
     or new.source_batch_id <> v_batch_id then
    raise exception 'historical OP child must match the OP origin and batch';
  end if;
  if tg_table_name = 'pcp_op_saidas_historicas' then
    if nullif(to_jsonb(new)->>'produto_id', '')::bigint <> v_product_id then
      raise exception 'historical OP output product must match the OP product';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_historical_op_child_lineage() from public, anon, authenticated;

create trigger trg_pcp_op_saidas_historicas_op_lineage
before insert on public.pcp_op_saidas_historicas
for each row execute function public.validate_historical_op_child_lineage();
create trigger trg_pcp_op_cq_historico_op_lineage
before insert on public.pcp_op_cq_historico_parcial
for each row execute function public.validate_historical_op_child_lineage();

create or replace function public.prevent_dec006_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new historical fact', tg_table_name;
end;
$$;

revoke all on function public.prevent_dec006_fact_changes() from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pcp_formula_rendimentos', 'pcp_formula_etapas',
    'pcp_formula_item_etapas', 'pcp_formula_referencias_historicas',
    'pcp_op_saidas_historicas', 'pcp_op_cq_historico_parcial'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_dec006_fact_changes()',
      'trg_' || v_table || '_append_only', v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_dec006_fact_changes()',
      'trg_' || v_table || '_no_truncate', v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pcp_formula_versoes', 'pcp_formula_itens', 'pcp_formula_rendimentos',
    'pcp_formula_etapas', 'pcp_formula_item_etapas',
    'pcp_formula_referencias_historicas', 'pcp_ordens_producao',
    'pcp_op_saidas_historicas', 'pcp_op_cq_historico_parcial'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_historical_contract', v_table);
    if v_table = 'pcp_ordens_producao' then
      execute format(
        'create trigger %I before insert or update of origem_dados, source_batch_id, source_row_id, created_by, review_status on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_table,
        'review_status', 'pending_review'
      );
    else
      execute format(
        'create trigger %I before insert on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_table,
        'review_status', 'pending_review'
      );
    end if;
  end loop;
end;
$$;

create or replace view public.pcp_formula_versoes_completas
with (security_invoker = true)
as
select
  version.id as formula_versao_id,
  version.produto_id,
  version.tipo_receita,
  version.versao,
  yield.quantidade_base,
  yield.unidade_base_id,
  yield.quantidade_saida,
  yield.unidade_saida_id,
  yield.natureza_saida
from public.pcp_formula_versoes version
join public.pcp_formula_rendimentos yield on yield.formula_versao_id = version.id
where version.review_status = 'approved'
  and version.origem_dados = 'sistema'
  and yield.review_status = 'approved'
  and yield.origem_dados = 'sistema';

create or replace view public.pcp_op_historicas_pendentes
with (security_invoker = true)
as
select
  op.id,
  op.codigo_op,
  op.produto_id,
  op.tipo_op,
  op.tipo_op_legado,
  op.status,
  op.formula_versao_id,
  op.formula_referencia_historica_id,
  op.source_batch_id,
  op.source_row_id
from public.pcp_ordens_producao op
where op.origem_dados = 'excel_legado'
  and op.review_status = 'pending_review';

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pcp_formula_rendimentos', 'pcp_formula_etapas',
    'pcp_formula_item_etapas', 'pcp_formula_referencias_historicas',
    'pcp_op_saidas_historicas', 'pcp_op_cq_historico_parcial'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      'active user read ' || v_table, v_table
    );
    execute format('revoke insert, update, delete, truncate on public.%I from public, anon, authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
  end loop;
end;
$$;

grant select on public.pcp_formula_versoes_completas to authenticated;
grant select on public.pcp_op_historicas_pendentes to authenticated;

comment on table public.pcp_formula_referencias_historicas is
  'Referencia explicita a versao desconhecida. Nunca aponta silenciosamente para a formula atual.';
comment on table public.pcp_op_saidas_historicas is
  'Saida historica pendente. Natureza nao_classificada nao possui lote e nao gera estoque.';
comment on table public.pcp_op_cq_historico_parcial is
  'CQ historico parcial preserva somente medidas existentes; campos ausentes permanecem nulos.';
