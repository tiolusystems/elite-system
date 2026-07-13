-- DEC-011: typed and temporal client/seller/property/area links.
-- Historical links remain pending and never grant live visibility.

create table public.cad_cliente_vinculo_papeis (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  concede_visibilidade boolean not null default false,
  status text not null default 'active',
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_cliente_vinculo_papeis_codigo_check check (
    codigo_norm is not null and char_length(codigo) <= 60
  ),
  constraint cad_cliente_vinculo_papeis_nome_check check (
    nullif(btrim(nome), '') is not null and char_length(nome) <= 120
  ),
  constraint cad_cliente_vinculo_papeis_status_check check (
    status in ('active', 'inactive')
  ),
  constraint cad_cliente_vinculo_papeis_key unique (codigo_norm)
);

do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
begin
  if v_actor is null then
    raise exception 'Migracao Historica system actor is required by DEC-011';
  end if;

  insert into public.cad_cliente_vinculo_papeis(
    codigo, nome, concede_visibilidade, status, created_by
  ) values
    ('cadastrou', 'Cadastrou o cliente', false, 'active', v_actor),
    ('atende', 'Atende o cliente', true, 'active', v_actor),
    ('gerencia', 'Gerencia a conta', true, 'active', v_actor),
    ('apoio', 'Apoio comercial', true, 'active', v_actor);
end;
$$;

alter table public.cad_cliente_vendedores
  add column if not exists papel_vinculo_id bigint,
  add column if not exists propriedade_id bigint,
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

update public.cad_cliente_vendedores relation
   set papel_vinculo_id = role_catalog.id,
       origem_dados = coalesce(relation.origem_dados, 'sistema')
  from public.cad_cliente_vinculo_papeis role_catalog
 where role_catalog.codigo_norm = 'atende'
   and relation.papel_vinculo_id is null;

alter table public.cad_cliente_vendedores
  alter column papel_vinculo_id set not null,
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  drop constraint if exists cad_cliente_vendedores_key,
  add constraint cad_cliente_vendedores_papel_fk foreign key (papel_vinculo_id)
    references public.cad_cliente_vinculo_papeis(id),
  add constraint cad_cliente_vendedores_propriedade_fk
    foreign key (propriedade_id, cliente_id)
    references public.cad_cliente_propriedades(id, cliente_id) not valid,
  add constraint cad_cliente_vendedores_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  add constraint cad_cliente_vendedores_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_cliente_vendedores_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

alter table public.cad_cliente_vendedores
  validate constraint cad_cliente_vendedores_propriedade_fk;

create unique index idx_cad_cliente_vendedores_natural_key
  on public.cad_cliente_vendedores(
    cliente_id,
    pessoa_id,
    papel_vinculo_id,
    coalesce(propriedade_id, 0),
    coalesce(vigencia_inicio, '-infinity'::date)
  );

create unique index idx_cad_cliente_vendedores_source_once
  on public.cad_cliente_vendedores(
    source_batch_id, source_row_id, papel_vinculo_id, pessoa_id
  ) where origem_dados = 'excel_legado';

create unique index idx_cad_cliente_vendedores_identity
  on public.cad_cliente_vendedores(id, cliente_id, pessoa_id);

alter table public.cad_areas_comerciais
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

alter table public.cad_pessoa_areas_comerciais
  add column if not exists origem_dados text,
  add column if not exists source_batch_id bigint references public.migration_batches(id),
  add column if not exists source_row_id bigint references public.source_rows(id);

update public.cad_areas_comerciais
   set origem_dados = coalesce(origem_dados, 'sistema');
update public.cad_pessoa_areas_comerciais
   set origem_dados = coalesce(origem_dados, 'sistema');

alter table public.cad_areas_comerciais
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint cad_areas_comerciais_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_areas_comerciais_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

alter table public.cad_pessoa_areas_comerciais
  alter column origem_dados set default 'sistema',
  alter column origem_dados set not null,
  add constraint cad_pessoa_areas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  add constraint cad_pessoa_areas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  );

create unique index idx_cad_areas_comerciais_source_once
  on public.cad_areas_comerciais(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create unique index idx_cad_pessoa_areas_source_once
  on public.cad_pessoa_areas_comerciais(
    source_batch_id, source_row_id, pessoa_id, area_id, papel_area
  ) where origem_dados = 'excel_legado';

create unique index idx_cad_pessoa_areas_natural_key
  on public.cad_pessoa_areas_comerciais(
    pessoa_id, area_id, papel_area, coalesce(vigencia_inicio, '-infinity'::date)
  );

create table public.cad_cliente_areas_comerciais (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  propriedade_id bigint,
  area_id bigint not null references public.cad_areas_comerciais(id),
  status text not null default 'active',
  vigencia_inicio date,
  vigencia_fim date,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_areas_propriedade_fk
    foreign key (propriedade_id, cliente_id)
    references public.cad_cliente_propriedades(id, cliente_id),
  constraint cad_cliente_areas_status_check check (
    status in ('active', 'inactive', 'pending_review')
  ),
  constraint cad_cliente_areas_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_cliente_areas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_cliente_areas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_cad_cliente_areas_natural_key
  on public.cad_cliente_areas_comerciais(
    cliente_id, area_id, coalesce(propriedade_id, 0),
    coalesce(vigencia_inicio, '-infinity'::date)
  );

create unique index idx_cad_cliente_areas_source_once
  on public.cad_cliente_areas_comerciais(source_batch_id, source_row_id, area_id)
  where origem_dados = 'excel_legado';

create index idx_cad_cliente_areas_current
  on public.cad_cliente_areas_comerciais(cliente_id, status, area_id);

drop trigger if exists trg_cad_cliente_areas_updated_at on public.cad_cliente_areas_comerciais;
create trigger trg_cad_cliente_areas_updated_at
before update on public.cad_cliente_areas_comerciais
for each row execute function public.touch_updated_at();

alter table public.com_pedidos
  add column if not exists cliente_vendedor_vinculo_id bigint;

alter table public.com_pedidos
  add constraint com_pedidos_cliente_vendedor_vinculo_fk
    foreign key (cliente_vendedor_vinculo_id, cliente_id, vendedor_gerador_id)
    references public.cad_cliente_vendedores(id, cliente_id, pessoa_id) not valid;

alter table public.com_pedidos
  validate constraint com_pedidos_cliente_vendedor_vinculo_fk;

create index idx_com_pedidos_cliente_vendedor_vinculo
  on public.com_pedidos(cliente_vendedor_vinculo_id)
  where cliente_vendedor_vinculo_id is not null;

create or replace function public.validate_order_client_seller_link()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_link public.cad_cliente_vendedores%rowtype;
begin
  if new.cliente_vendedor_vinculo_id is null then
    return new;
  end if;

  select relation.* into v_link
    from public.cad_cliente_vendedores relation
   where relation.id = new.cliente_vendedor_vinculo_id;

  if not found then
    raise exception 'client seller link not found';
  end if;
  if v_link.cliente_id <> new.cliente_id
     or v_link.pessoa_id is distinct from new.vendedor_gerador_id then
    raise exception 'order client/seller does not match the selected link';
  end if;
  if v_link.propriedade_id is not null
     and v_link.propriedade_id is distinct from new.propriedade_id then
    raise exception 'order property is outside the selected client/seller link';
  end if;

  if coalesce(new.origem_dados, 'sistema') <> 'excel_legado' then
    if v_link.status <> 'active'
       or (v_link.vigencia_inicio is not null and v_link.vigencia_inicio > new.data_pedido)
       or (v_link.vigencia_fim is not null and v_link.vigencia_fim < new.data_pedido) then
      raise exception 'order requires an active client/seller link on order date';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_order_client_seller_link() from public, anon, authenticated;

create trigger trg_com_pedidos_client_seller_link
before insert or update of cliente_vendedor_vinculo_id, cliente_id,
  vendedor_gerador_id, propriedade_id, data_pedido, origem_dados
on public.com_pedidos
for each row execute function public.validate_order_client_seller_link();

create or replace function public.prevent_active_client_link_overlap()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status <> 'active' then
    return new;
  end if;

  if tg_table_name = 'cad_cliente_vendedores' then
    if exists (
      select 1
        from public.cad_cliente_vendedores existing
       where existing.id <> coalesce(new.id, 0)
         and existing.status = 'active'
         and existing.cliente_id = new.cliente_id
         and existing.pessoa_id = new.pessoa_id
         and existing.papel_vinculo_id = new.papel_vinculo_id
         and coalesce(existing.propriedade_id, 0) = coalesce(new.propriedade_id, 0)
         and daterange(
           coalesce(existing.vigencia_inicio, '-infinity'::date),
           coalesce(existing.vigencia_fim, 'infinity'::date), '[]'
         ) && daterange(
           coalesce(new.vigencia_inicio, '-infinity'::date),
           coalesce(new.vigencia_fim, 'infinity'::date), '[]'
         )
    ) then
      raise exception 'active client/seller link overlaps an existing period';
    end if;
  elsif exists (
    select 1
      from public.cad_cliente_areas_comerciais existing
     where existing.id <> coalesce(new.id, 0)
       and existing.status = 'active'
       and existing.cliente_id = new.cliente_id
       and existing.area_id = new.area_id
       and coalesce(existing.propriedade_id, 0) = coalesce(new.propriedade_id, 0)
       and daterange(
         coalesce(existing.vigencia_inicio, '-infinity'::date),
         coalesce(existing.vigencia_fim, 'infinity'::date), '[]'
       ) && daterange(
         coalesce(new.vigencia_inicio, '-infinity'::date),
         coalesce(new.vigencia_fim, 'infinity'::date), '[]'
       )
  ) then
    raise exception 'active client/area link overlaps an existing period';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_active_client_link_overlap() from public, anon, authenticated;

create trigger trg_cad_cliente_vendedores_no_overlap
before insert or update of cliente_id, pessoa_id, papel_vinculo_id,
  propriedade_id, status, vigencia_inicio, vigencia_fim
on public.cad_cliente_vendedores
for each row execute function public.prevent_active_client_link_overlap();

create trigger trg_cad_cliente_areas_no_overlap
before insert or update of cliente_id, area_id, propriedade_id,
  status, vigencia_inicio, vigencia_fim
on public.cad_cliente_areas_comerciais
for each row execute function public.prevent_active_client_link_overlap();

create or replace function public.validate_live_client_seller_role()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_role_code text;
begin
  if new.status <> 'active' or new.origem_dados = 'excel_legado' then
    return new;
  end if;

  select role_catalog.codigo_norm into v_role_code
    from public.cad_cliente_vinculo_papeis role_catalog
   where role_catalog.id = new.papel_vinculo_id
     and role_catalog.status = 'active';

  if v_role_code is null then
    raise exception 'client link role is inactive or unknown';
  end if;
  if not exists (
    select 1
      from public.cad_pessoa_papeis person_role
     where person_role.pessoa_id = new.pessoa_id
       and person_role.papel in ('vendedor', 'agente', 'gerente')
       and person_role.status = 'active'
       and (new.vigencia_inicio is null or person_role.vigencia_inicio::date <= new.vigencia_inicio)
       and (
         person_role.vigencia_fim is null
         or new.vigencia_inicio is null
         or person_role.vigencia_fim::date >= new.vigencia_inicio
       )
  ) then
    raise exception 'active client link requires an active commercial person role';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_live_client_seller_role() from public, anon, authenticated;

create trigger trg_cad_cliente_vendedores_live_role
before insert or update of pessoa_id, papel_vinculo_id, status,
  vigencia_inicio, vigencia_fim, origem_dados
on public.cad_cliente_vendedores
for each row execute function public.validate_live_client_seller_role();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_cliente_vendedores',
    'cad_areas_comerciais',
    'cad_pessoa_areas_comerciais',
    'cad_cliente_areas_comerciais'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', 'trg_' || v_table || '_historical_contract', v_table);
    execute format(
      'create trigger %I before insert or update of origem_dados, source_batch_id, source_row_id, created_by, status on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
      'trg_' || v_table || '_historical_contract', v_table, 'status', 'pending_review'
    );
  end loop;
end;
$$;

create or replace function public.prevent_temporal_commercial_link_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is historical; close the period or create a replacement link', tg_table_name;
end;
$$;

revoke all on function public.prevent_temporal_commercial_link_delete() from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_cliente_vendedores',
    'cad_pessoa_areas_comerciais',
    'cad_cliente_areas_comerciais'
  ]
  loop
    execute format(
      'create trigger %I before delete on public.%I for each row execute function public.prevent_temporal_commercial_link_delete()',
      'trg_' || v_table || '_no_delete', v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_temporal_commercial_link_delete()',
      'trg_' || v_table || '_no_truncate', v_table
    );
  end loop;
end;
$$;

create or replace view public.cad_cliente_vinculos_atuais
with (security_invoker = true)
as
select
  relation.id,
  relation.cliente_id,
  relation.propriedade_id,
  relation.pessoa_id,
  role_catalog.codigo_norm as papel_codigo,
  role_catalog.nome as papel_nome,
  role_catalog.concede_visibilidade,
  relation.vigencia_inicio,
  relation.vigencia_fim
from public.cad_cliente_vendedores relation
join public.cad_cliente_vinculo_papeis role_catalog
  on role_catalog.id = relation.papel_vinculo_id
where relation.status = 'active'
  and relation.origem_dados = 'sistema'
  and role_catalog.status = 'active'
  and (relation.vigencia_inicio is null or relation.vigencia_inicio <= current_date)
  and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date);

create or replace view public.cad_cliente_visibilidade_comercial_atual
with (security_invoker = true)
as
select distinct
  direct_link.cliente_id,
  direct_link.propriedade_id,
  direct_link.pessoa_id,
  'vinculo_direto'::text as origem_visibilidade,
  direct_link.id as origem_id
from public.cad_cliente_vinculos_atuais direct_link
where direct_link.concede_visibilidade = true
union
select distinct
  client_area.cliente_id,
  client_area.propriedade_id,
  person_area.pessoa_id,
  'area_comercial'::text as origem_visibilidade,
  client_area.id as origem_id
from public.cad_cliente_areas_comerciais client_area
join public.cad_areas_comerciais area
  on area.id = client_area.area_id and area.status = 'active'
join public.cad_pessoa_areas_comerciais person_area
  on person_area.area_id = client_area.area_id
 and person_area.status = 'active'
where client_area.status = 'active'
  and client_area.origem_dados = 'sistema'
  and person_area.origem_dados = 'sistema'
  and (client_area.vigencia_inicio is null or client_area.vigencia_inicio <= current_date)
  and (client_area.vigencia_fim is null or client_area.vigencia_fim >= current_date)
  and (person_area.vigencia_inicio is null or person_area.vigencia_inicio <= current_date)
  and (person_area.vigencia_fim is null or person_area.vigencia_fim >= current_date);

alter table public.cad_cliente_vinculo_papeis enable row level security;
alter table public.cad_cliente_areas_comerciais enable row level security;

create policy "active user read client link roles"
  on public.cad_cliente_vinculo_papeis
  for select to authenticated
  using (public.current_actor_id() is not null);

create policy "active user read client commercial areas"
  on public.cad_cliente_areas_comerciais
  for select to authenticated
  using (public.current_actor_id() is not null);

revoke insert, update, delete, truncate on public.cad_cliente_vinculo_papeis
  from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_cliente_areas_comerciais
  from public, anon, authenticated;
grant select on public.cad_cliente_vinculo_papeis to authenticated;
grant select on public.cad_cliente_areas_comerciais to authenticated;
grant select on public.cad_cliente_vinculos_atuais to authenticated;
grant select on public.cad_cliente_visibilidade_comercial_atual to authenticated;

comment on table public.cad_cliente_vinculo_papeis is
  'Catalogo relacional dos papeis do vinculo cliente-pessoa. Papel Auth nao pertence a esta tabela.';
comment on table public.cad_cliente_vendedores is
  'Vinculo temporal tipado entre cliente/propriedade e pessoa comercial. Historico Excel permanece pending_review.';
comment on table public.cad_cliente_areas_comerciais is
  'Vinculo temporal entre cliente/propriedade e area comercial.';
comment on view public.cad_cliente_visibilidade_comercial_atual is
  'Read model relacional para politicas futuras. Nao substitui autorizacao no backend e no banco.';
