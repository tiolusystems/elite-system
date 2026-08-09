-- DEC-008: versioned packaging BOM, canonical conversions, logistics events
-- and relational PA/PI transformations. Historical rows never become current
-- operational facts without an explicit human-governed event.

alter table public.cad_embalagens
  add column if not exists unidade_id bigint,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.cad_produto_embalagens
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.cad_veiculos
  add column if not exists capacidade_unidade_id bigint references public.cad_unidades_medida(id),
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.cad_conversoes_unidade_mp
  add column if not exists unidade_origem_id bigint,
  add column if not exists unidade_destino_id bigint,
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_term text;
begin
  if v_actor is null then
    raise exception 'Migracao Historica system actor is required by DEC-008';
  end if;

  for v_term in
    select distinct source_term
      from (
        select nullif(btrim(embalagem.unidade), '') as source_term
          from public.cad_embalagens embalagem
        union
        select nullif(btrim(conversao.unidade_origem), '')
          from public.cad_conversoes_unidade_mp conversao
        union
        select nullif(btrim(conversao.unidade_destino), '')
          from public.cad_conversoes_unidade_mp conversao
      ) source_units
     where source_term is not null
  loop
    if public.resolve_cad_unidade_id(v_term) is null then
      if char_length(v_term) > 60 then
        raise exception 'legacy unit exceeds canonical code limit: %', v_term;
      end if;
      insert into public.cad_unidades_medida(
        codigo, nome, simbolo, dimensao, status, origem_dados, created_by
      ) values (
        v_term, v_term, v_term, 'nao_classificada', 'pending_review', 'sistema', v_actor
      )
      on conflict (codigo_norm) do nothing;
    end if;
  end loop;
end;
$$;

update public.cad_embalagens embalagem
   set unidade_id = public.resolve_cad_unidade_id(embalagem.unidade),
       origem_dados = coalesce(embalagem.origem_dados, 'sistema');

update public.cad_produto_embalagens produto_embalagem
   set origem_dados = coalesce(produto_embalagem.origem_dados, 'sistema');

update public.cad_veiculos veiculo
   set origem_dados = coalesce(veiculo.origem_dados, 'sistema'),
       status = case
         when veiculo.capacidade is not null
          and veiculo.capacidade_unidade_id is null
          and veiculo.status = 'active'
         then 'pending_review'
         else veiculo.status
       end;

update public.cad_conversoes_unidade_mp conversao
   set unidade_origem_id = public.resolve_cad_unidade_id(conversao.unidade_origem),
       unidade_destino_id = public.resolve_cad_unidade_id(conversao.unidade_destino),
       review_status = coalesce(conversao.review_status, 'approved'),
       origem_dados = coalesce(conversao.origem_dados, 'sistema');

do $$
begin
  if exists (select 1 from public.cad_embalagens where unidade_id is null) then
    raise exception 'DEC-008 could not resolve every packaging unit';
  end if;
  if exists (
    select 1
      from public.cad_conversoes_unidade_mp
     where unidade_origem_id is null or unidade_destino_id is null
  ) then
    raise exception 'DEC-008 could not resolve every MP conversion unit';
  end if;
end;
$$;

alter table public.cad_embalagens
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  alter column unidade_id set not null,
  drop constraint if exists cad_embalagens_origem_dados_check,
  add constraint cad_embalagens_origem_dados_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_embalagens_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  add constraint cad_embalagens_unidade_fk foreign key (unidade_id)
    references public.cad_unidades_medida(id) not valid;

alter table public.cad_embalagens validate constraint cad_embalagens_unidade_fk;

alter table public.cad_produto_embalagens
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  drop constraint if exists cad_produto_embalagens_origem_dados_check,
  add constraint cad_produto_embalagens_origem_dados_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_produto_embalagens_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

alter table public.cad_veiculos
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint cad_veiculos_origem_dados_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_veiculos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  add constraint cad_veiculos_capacidade_unidade_check check (
    capacidade is null or capacidade_unidade_id is not null or status = 'pending_review'
  );

alter table public.cad_conversoes_unidade_mp
  alter column unidade_origem_id set not null,
  alter column unidade_destino_id set not null,
  alter column review_status set default 'approved',
  alter column review_status set not null,
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint cad_conversoes_unidade_origem_fk foreign key (unidade_origem_id)
    references public.cad_unidades_medida(id) not valid,
  add constraint cad_conversoes_unidade_destino_fk foreign key (unidade_destino_id)
    references public.cad_unidades_medida(id) not valid,
  add constraint cad_conversoes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  add constraint cad_conversoes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_conversoes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  add constraint cad_conversoes_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  add constraint cad_conversoes_distinct_units_check check (
    unidade_origem_id <> unidade_destino_id
  );

alter table public.cad_conversoes_unidade_mp
  validate constraint cad_conversoes_unidade_origem_fk;
alter table public.cad_conversoes_unidade_mp
  validate constraint cad_conversoes_unidade_destino_fk;

create unique index if not exists idx_cad_embalagens_source_once
  on public.cad_embalagens(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_produto_embalagens_source_once
  on public.cad_produto_embalagens(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_veiculos_source_once
  on public.cad_veiculos(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_conversoes_source_once
  on public.cad_conversoes_unidade_mp(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index if not exists idx_cad_conversoes_canonical_key
  on public.cad_conversoes_unidade_mp(
    materia_prima_id,
    unidade_origem_id,
    unidade_destino_id,
    coalesce(vigencia_inicio, '-infinity'::date)
  );

create table public.cad_embalagem_versoes (
  id bigint generated always as identity primary key,
  embalagem_id bigint not null references public.cad_embalagens(id),
  versao integer not null,
  vigencia_inicio date,
  vigencia_fim date,
  peso_tara_kg numeric,
  cubagem_m3 numeric,
  justificativa text,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_embalagem_versoes_versao_check check (versao > 0),
  constraint cad_embalagem_versoes_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_embalagem_versoes_tara_check check (
    peso_tara_kg is null or peso_tara_kg > 0
  ),
  constraint cad_embalagem_versoes_cubagem_check check (
    cubagem_m3 is null or cubagem_m3 > 0
  ),
  constraint cad_embalagem_versoes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint cad_embalagem_versoes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_embalagem_versoes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_embalagem_versoes_key unique (embalagem_id, versao)
);

create unique index idx_cad_embalagem_versoes_source_once
  on public.cad_embalagem_versoes(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.cad_embalagem_componentes (
  id bigint generated always as identity primary key,
  embalagem_versao_id bigint not null references public.cad_embalagem_versoes(id),
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  quantidade numeric not null,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_embalagem_componentes_quantidade_check check (quantidade > 0),
  constraint cad_embalagem_componentes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint cad_embalagem_componentes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_embalagem_componentes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_embalagem_componentes_key unique (
    embalagem_versao_id, materia_prima_id
  )
);

create unique index idx_cad_embalagem_componentes_source_once
  on public.cad_embalagem_componentes(source_batch_id, source_row_id, materia_prima_id)
  where origem_dados = 'excel_legado';

create or replace function public.validate_package_component_lineage()
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
    from public.cad_embalagem_versoes version
   where version.id = new.embalagem_versao_id;

  if new.origem_dados <> v_origin then
    raise exception 'packaging component origin must match its version';
  end if;
  if new.origem_dados = 'excel_legado' and new.source_batch_id <> v_batch_id then
    raise exception 'packaging component batch must match its version';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_package_component_lineage() from public, anon, authenticated;

create trigger trg_cad_embalagem_componentes_version_lineage
before insert on public.cad_embalagem_componentes
for each row execute function public.validate_package_component_lineage();

create table public.cad_embalagem_versao_ativacoes (
  id bigint generated always as identity primary key,
  embalagem_versao_id bigint not null references public.cad_embalagem_versoes(id),
  tipo_evento text not null,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_embalagem_ativacoes_tipo_check check (
    tipo_evento in ('ativacao', 'desativacao')
  ),
  constraint cad_embalagem_ativacoes_motivo_check check (
    nullif(btrim(motivo), '') is not null
  )
);

create index idx_cad_embalagem_ativacoes_version
  on public.cad_embalagem_versao_ativacoes(embalagem_versao_id, created_at desc, id desc);

create or replace function public.sync_dec008_canonical_units()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_unit_id bigint;
  v_unit_code text;
begin
  if tg_table_name = 'cad_embalagens' then
    if tg_op = 'INSERT'
       or new.unidade_id is null
       or new.unidade is distinct from old.unidade then
      v_unit_id := public.resolve_cad_unidade_id(new.unidade);
    else
      v_unit_id := new.unidade_id;
    end if;
    if v_unit_id is null then
      raise exception 'unknown packaging unit: %', new.unidade;
    end if;
    select unit.codigo into v_unit_code
      from public.cad_unidades_medida unit where unit.id = v_unit_id;
    new.unidade_id := v_unit_id;
    new.unidade := v_unit_code;
    return new;
  end if;

  new.unidade_origem_id := public.resolve_cad_unidade_id(new.unidade_origem);
  new.unidade_destino_id := public.resolve_cad_unidade_id(new.unidade_destino);
  if new.unidade_origem_id is null or new.unidade_destino_id is null then
    raise exception 'unknown MP conversion unit';
  end if;
  select unit.codigo into new.unidade_origem
    from public.cad_unidades_medida unit where unit.id = new.unidade_origem_id;
  select unit.codigo into new.unidade_destino
    from public.cad_unidades_medida unit where unit.id = new.unidade_destino_id;
  return new;
end;
$$;

revoke all on function public.sync_dec008_canonical_units() from public, anon, authenticated;

drop trigger if exists trg_10_cad_embalagem_canonical_unit on public.cad_embalagens;
create trigger trg_10_cad_embalagem_canonical_unit
before insert or update of unidade, unidade_id on public.cad_embalagens
for each row execute function public.sync_dec008_canonical_units();

drop trigger if exists trg_10_cad_conversao_canonical_units on public.cad_conversoes_unidade_mp;
create trigger trg_10_cad_conversao_canonical_units
before insert or update of unidade_origem, unidade_destino, unidade_origem_id, unidade_destino_id
on public.cad_conversoes_unidade_mp
for each row execute function public.sync_dec008_canonical_units();

create or replace function public.validate_package_activation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_review_status text;
  v_package_status text;
begin
  if not exists (
    select 1
      from public.user_profiles profile
     where profile.id = new.created_by
       and profile.is_system_actor = false
       and profile.status = 'active'
  ) then
    raise exception 'only active human profiles can activate packaging versions';
  end if;

  select version.review_status, package.status
    into v_review_status, v_package_status
    from public.cad_embalagem_versoes version
    join public.cad_embalagens package on package.id = version.embalagem_id
   where version.id = new.embalagem_versao_id;

  if new.tipo_evento = 'ativacao'
     and (v_review_status <> 'approved' or v_package_status <> 'active') then
    raise exception 'only approved versions of active packages can be activated';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_package_activation() from public, anon, authenticated;

create trigger trg_cad_embalagem_activation_human
before insert on public.cad_embalagem_versao_ativacoes
for each row execute function public.validate_package_activation();

create or replace view public.cad_embalagem_configuracoes_atuais
with (security_invoker = true)
as
with latest_event as (
  select distinct on (version.embalagem_id)
    version.embalagem_id,
    activation.embalagem_versao_id,
    activation.tipo_evento,
    activation.created_at as activated_at
  from public.cad_embalagem_versao_ativacoes activation
  join public.cad_embalagem_versoes version on version.id = activation.embalagem_versao_id
  order by version.embalagem_id, activation.created_at desc, activation.id desc
)
select
  package.id as embalagem_id,
  package.descricao,
  package.unidade_id,
  package.volume_litros,
  version.id as embalagem_versao_id,
  version.versao,
  version.peso_tara_kg,
  version.cubagem_m3,
  version.vigencia_inicio,
  version.vigencia_fim,
  latest_event.activated_at
from latest_event
join public.cad_embalagem_versoes version on version.id = latest_event.embalagem_versao_id
join public.cad_embalagens package on package.id = version.embalagem_id
where latest_event.tipo_evento = 'ativacao'
  and version.review_status = 'approved'
  and package.status = 'active';

create or replace view public.cad_embalagem_componentes_atuais
with (security_invoker = true)
as
select
  current_package.embalagem_id,
  current_package.embalagem_versao_id,
  component.id as componente_id,
  component.materia_prima_id,
  component.quantidade,
  component.unidade_id
from public.cad_embalagem_configuracoes_atuais current_package
join public.cad_embalagem_componentes component
  on component.embalagem_versao_id = current_package.embalagem_versao_id
where component.review_status = 'approved';

alter table public.exp_romaneios
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.exp_romaneio_itens
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.exp_romaneio_movimentos_pa
  add column if not exists review_status text,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

update public.exp_romaneios
   set review_status = coalesce(review_status, 'approved'),
       origem_dados = coalesce(origem_dados, 'sistema');
update public.exp_romaneio_itens
   set review_status = coalesce(review_status, 'approved'),
       origem_dados = coalesce(origem_dados, 'sistema');
update public.exp_romaneio_movimentos_pa
   set review_status = coalesce(review_status, 'approved'),
       origem_dados = coalesce(origem_dados, 'sistema');

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'exp_romaneios', 'exp_romaneio_itens', 'exp_romaneio_movimentos_pa'
  ]
  loop
    execute format('alter table public.%I alter column review_status set default ''approved''', v_table);
    execute format('alter table public.%I alter column review_status set not null', v_table);
    execute format('alter table public.%I alter column origem_dados set default ''sistema''', v_table);
    execute format('alter table public.%I alter column origem_dados set not null', v_table);
    execute format(
      'alter table public.%I add constraint %I check (review_status in (''approved'', ''pending_review'', ''rejected''))',
      v_table, v_table || '_review_status_check'
    );
    execute format(
      'alter table public.%I add constraint %I check (origem_dados in (''sistema'', ''excel_legado''))',
      v_table, v_table || '_origem_dados_check'
    );
    execute format(
      'alter table public.%I add constraint %I check ((source_batch_id is null and source_row_id is null) or (source_batch_id is not null and source_row_id is not null))',
      v_table, v_table || '_source_pair_check'
    );
  end loop;
end;
$$;

create unique index idx_exp_romaneios_source_once
  on public.exp_romaneios(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';
create unique index idx_exp_romaneio_itens_source_once
  on public.exp_romaneio_itens(source_batch_id, source_row_id, pedido_item_id)
  where origem_dados = 'excel_legado';
create unique index idx_exp_romaneio_movimentos_source_once
  on public.exp_romaneio_movimentos_pa(
    source_batch_id, source_row_id, coalesce(lote_pa_id, 0)
  )
  where origem_dados = 'excel_legado';

create table public.exp_romaneio_logistica_eventos (
  id bigint generated always as identity primary key,
  romaneio_id bigint not null references public.exp_romaneios(id),
  tipo_evento text not null,
  entregador_id bigint references public.cad_pessoas_comerciais(id),
  veiculo_id bigint references public.cad_veiculos(id),
  ocorrido_em timestamptz,
  motivo text,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint exp_romaneio_logistica_tipo_check check (
    tipo_evento in ('atribuicao', 'remocao')
  ),
  constraint exp_romaneio_logistica_target_check check (
    (tipo_evento = 'atribuicao' and (entregador_id is not null or veiculo_id is not null))
    or (tipo_evento = 'remocao' and entregador_id is null and veiculo_id is null)
  ),
  constraint exp_romaneio_logistica_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint exp_romaneio_logistica_time_check check (
    review_status = 'pending_review' or ocorrido_em is not null
  ),
  constraint exp_romaneio_logistica_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint exp_romaneio_logistica_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_exp_romaneio_logistica_source_once
  on public.exp_romaneio_logistica_eventos(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';
create index idx_exp_romaneio_logistica_current
  on public.exp_romaneio_logistica_eventos(romaneio_id, ocorrido_em desc, id desc);

create or replace function public.validate_romaneio_logistics_actor()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.tipo_evento = 'atribuicao'
     and new.entregador_id is not null
     and new.review_status = 'approved'
     and not exists (
       select 1
         from public.cad_pessoa_papeis role_link
        where role_link.pessoa_id = new.entregador_id
          and role_link.papel = 'entregador'
          and role_link.status = 'active'
          and role_link.vigencia_inicio <= new.ocorrido_em
          and (role_link.vigencia_fim is null or role_link.vigencia_fim >= new.ocorrido_em)
     ) then
    raise exception 'approved logistics assignment requires active entregador role';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_romaneio_logistics_actor() from public, anon, authenticated;

create trigger trg_exp_romaneio_logistics_actor
before insert on public.exp_romaneio_logistica_eventos
for each row execute function public.validate_romaneio_logistics_actor();

create or replace view public.exp_romaneio_logistica_atual
with (security_invoker = true)
as
with latest_event as (
  select distinct on (event.romaneio_id) event.*
    from public.exp_romaneio_logistica_eventos event
   where event.review_status = 'approved'
   order by event.romaneio_id, event.ocorrido_em desc, event.id desc
)
select
  latest_event.romaneio_id,
  latest_event.entregador_id,
  latest_event.veiculo_id,
  latest_event.ocorrido_em,
  latest_event.id as evento_id
from latest_event
where latest_event.tipo_evento = 'atribuicao';

create table public.est_transformacoes (
  id bigint generated always as identity primary key,
  tipo_transformacao text not null,
  ocorrido_em timestamptz,
  evidencia_tipo text not null,
  evidencia_detalhe text not null,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_transformacoes_tipo_check check (
    tipo_transformacao in (
      'fracionamento_embalagem', 'reembalagem', 'pa_para_pi', 'pi_para_pa'
    )
  ),
  constraint est_transformacoes_evidencia_check check (
    evidencia_tipo in ('comprovada', 'inferida')
    and nullif(btrim(evidencia_detalhe), '') is not null
  ),
  constraint est_transformacoes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
    and (evidencia_tipo <> 'inferida' or review_status = 'pending_review')
  ),
  constraint est_transformacoes_time_check check (
    review_status = 'pending_review' or ocorrido_em is not null
  ),
  constraint est_transformacoes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint est_transformacoes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_est_transformacoes_source_once
  on public.est_transformacoes(source_batch_id, source_row_id, tipo_transformacao)
  where origem_dados = 'excel_legado';

create table public.est_transformacao_origens (
  id bigint generated always as identity primary key,
  transformacao_id bigint not null references public.est_transformacoes(id),
  familia text not null,
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  quantidade numeric not null,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_transformacao_origens_familia_check check (familia in ('PA', 'PI')),
  constraint est_transformacao_origens_lote_check check (
    (familia = 'PA' and lote_pa_id is not null and lote_pi_id is null)
    or (familia = 'PI' and lote_pa_id is null and lote_pi_id is not null)
  ),
  constraint est_transformacao_origens_quantidade_check check (quantidade > 0),
  constraint est_transformacao_origens_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint est_transformacao_origens_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create table public.est_transformacao_destinos (
  id bigint generated always as identity primary key,
  transformacao_id bigint not null references public.est_transformacoes(id),
  familia text not null,
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  quantidade numeric not null,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_transformacao_destinos_familia_check check (familia in ('PA', 'PI')),
  constraint est_transformacao_destinos_lote_check check (
    (familia = 'PA' and lote_pa_id is not null and lote_pi_id is null)
    or (familia = 'PI' and lote_pa_id is null and lote_pi_id is not null)
  ),
  constraint est_transformacao_destinos_quantidade_check check (quantidade > 0),
  constraint est_transformacao_destinos_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint est_transformacao_destinos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create table public.est_transformacao_perdas (
  id bigint generated always as identity primary key,
  transformacao_id bigint not null references public.est_transformacoes(id),
  familia text not null,
  quantidade numeric not null,
  unidade_id bigint not null references public.cad_unidades_medida(id),
  motivo text,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_transformacao_perdas_familia_check check (familia in ('PA', 'PI')),
  constraint est_transformacao_perdas_quantidade_check check (quantidade > 0),
  constraint est_transformacao_perdas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint est_transformacao_perdas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_est_transformacao_origens_source_once
  on public.est_transformacao_origens(
    source_batch_id, source_row_id, familia,
    coalesce(lote_pa_id, 0), coalesce(lote_pi_id, 0)
  ) where origem_dados = 'excel_legado';
create unique index idx_est_transformacao_destinos_source_once
  on public.est_transformacao_destinos(
    source_batch_id, source_row_id, familia,
    coalesce(lote_pa_id, 0), coalesce(lote_pi_id, 0)
  ) where origem_dados = 'excel_legado';
create unique index idx_est_transformacao_perdas_source_once
  on public.est_transformacao_perdas(source_batch_id, source_row_id, familia)
  where origem_dados = 'excel_legado';

create index idx_est_transformacao_origens_header
  on public.est_transformacao_origens(transformacao_id);
create index idx_est_transformacao_destinos_header
  on public.est_transformacao_destinos(transformacao_id);
create index idx_est_transformacao_perdas_header
  on public.est_transformacao_perdas(transformacao_id);

create or replace function public.validate_transformation_lineage()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_origin text;
  v_batch_id bigint;
begin
  select transformation.origem_dados, transformation.source_batch_id
    into v_origin, v_batch_id
    from public.est_transformacoes transformation
   where transformation.id = new.transformacao_id;

  if new.origem_dados <> v_origin then
    raise exception 'transformation child origin must match its header';
  end if;
  if new.origem_dados = 'excel_legado' and new.source_batch_id <> v_batch_id then
    raise exception 'transformation child batch must match its header';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_transformation_lineage() from public, anon, authenticated;

create trigger trg_est_transformacao_origens_header_lineage
before insert on public.est_transformacao_origens
for each row execute function public.validate_transformation_lineage();
create trigger trg_est_transformacao_destinos_header_lineage
before insert on public.est_transformacao_destinos
for each row execute function public.validate_transformation_lineage();
create trigger trg_est_transformacao_perdas_header_lineage
before insert on public.est_transformacao_perdas
for each row execute function public.validate_transformation_lineage();

create or replace view public.est_transformacoes_aprovadas
with (security_invoker = true)
as
select transformation.*
  from public.est_transformacoes transformation
 where transformation.review_status = 'approved'
   and transformation.evidencia_tipo = 'comprovada'
   and exists (
     select 1 from public.est_transformacao_origens source
      where source.transformacao_id = transformation.id
   )
   and exists (
     select 1 from public.est_transformacao_destinos target
      where target.transformacao_id = transformation.id
   );

create or replace function public.prevent_dec008_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new version or event', tg_table_name;
end;
$$;

revoke all on function public.prevent_dec008_fact_changes() from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_conversoes_unidade_mp',
    'cad_embalagem_versoes',
    'cad_embalagem_componentes',
    'cad_embalagem_versao_ativacoes',
    'exp_romaneio_logistica_eventos',
    'est_transformacoes',
    'est_transformacao_origens',
    'est_transformacao_destinos',
    'est_transformacao_perdas'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_dec008_fact_changes()',
      'trg_' || v_table || '_append_only', v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_dec008_fact_changes()',
      'trg_' || v_table || '_no_truncate', v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
  v_review_column text;
  v_update_columns text;
begin
  foreach v_table in array array[
    'cad_embalagens',
    'cad_produto_embalagens',
    'cad_veiculos',
    'cad_conversoes_unidade_mp',
    'cad_embalagem_versoes',
    'cad_embalagem_componentes',
    'exp_romaneios',
    'exp_romaneio_itens',
    'exp_romaneio_movimentos_pa',
    'exp_romaneio_logistica_eventos',
    'est_transformacoes',
    'est_transformacao_origens',
    'est_transformacao_destinos',
    'est_transformacao_perdas'
  ]
  loop
    v_review_column := case
      when v_table in ('cad_embalagens', 'cad_produto_embalagens', 'cad_veiculos') then 'status'
      when v_table in (
        'cad_conversoes_unidade_mp', 'cad_embalagem_versoes',
        'cad_embalagem_componentes', 'exp_romaneios', 'exp_romaneio_itens',
        'exp_romaneio_movimentos_pa', 'exp_romaneio_logistica_eventos',
        'est_transformacoes'
      ) then 'review_status'
      else null
    end;

    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_historical_contract', v_table);
    if v_table in (
      'cad_embalagens', 'cad_produto_embalagens', 'cad_veiculos',
      'exp_romaneios', 'exp_romaneio_itens'
    ) then
      v_update_columns := format(
        'origem_dados, source_batch_id, source_row_id, created_by, %I',
        v_review_column
      );
      execute format(
        'create trigger %I before insert or update of %s on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_update_columns, v_table,
        v_review_column, 'pending_review'
      );
    elsif v_review_column is null then
      execute format(
        'create trigger %I before insert on public.%I for each row execute function public.enforce_historical_record_contract()',
        'trg_' || v_table || '_historical_contract', v_table
      );
    else
      execute format(
        'create trigger %I before insert on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_table,
        v_review_column, 'pending_review'
      );
    end if;
  end loop;
end;
$$;

create or replace function public.prevent_historical_romaneio_state_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.origem_dados = 'excel_legado' and new.status is distinct from old.status then
    raise exception 'historical romaneio state is immutable and cannot enter the live workflow';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_historical_romaneio_state_change() from public, anon, authenticated;

create trigger trg_exp_romaneios_historical_state
before update of status on public.exp_romaneios
for each row execute function public.prevent_historical_romaneio_state_change();

create trigger trg_exp_romaneio_itens_historical_state
before update of status on public.exp_romaneio_itens
for each row execute function public.prevent_historical_romaneio_state_change();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_embalagem_versoes',
    'cad_embalagem_componentes',
    'cad_embalagem_versao_ativacoes',
    'exp_romaneio_logistica_eventos',
    'est_transformacoes',
    'est_transformacao_origens',
    'est_transformacao_destinos',
    'est_transformacao_perdas'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      'active user read ' || v_table, v_table
    );
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
  end loop;
end;
$$;

grant select on public.cad_embalagem_configuracoes_atuais to authenticated;
grant select on public.cad_embalagem_componentes_atuais to authenticated;
grant select on public.exp_romaneio_logistica_atual to authenticated;
grant select on public.est_transformacoes_aprovadas to authenticated;

comment on table public.cad_embalagem_versoes is
  'Versoes append-only da configuracao de embalagem. Tara e cubagem nao sobrescrevem a identidade da embalagem.';
comment on table public.cad_embalagem_componentes is
  'BOM relacional da embalagem por versao; cada componente referencia uma MP, quantidade e unidade canonica.';
comment on table public.exp_romaneio_logistica_eventos is
  'Ledger append-only de atribuicao ou remocao de entregador e veiculo do romaneio.';
comment on table public.est_transformacoes is
  'Cabecalho auditavel de transformacao PA/PI. Nao gera movimento de estoque automaticamente.';
comment on view public.est_transformacoes_aprovadas is
  'Somente transformacoes comprovadas, aprovadas e com origem/destino relacionais.';
comment on column public.est_transformacoes.evidencia_tipo is
  'comprovada exige evidencia descrita; inferida permanece pending_review e nunca entra automaticamente na operacao.';
