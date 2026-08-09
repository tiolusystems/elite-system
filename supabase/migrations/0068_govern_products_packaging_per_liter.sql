-- UX-01C: governed product/package maintenance and normalized packaging BOM in UN/L.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.produtos.update.identity', 'cadastros', 'Alterar identidade do produto', true, 81, 'cadastros', 'write'),
  ('cadastros.produtos.update.technical', 'cadastros', 'Alterar dados tecnicos do produto', true, 82, 'cadastros', 'write'),
  ('cadastros.produtos.update.regulatory', 'cadastros', 'Alterar dados regulatorios do produto', true, 83, 'cadastros', 'write'),
  ('cadastros.produtos.deactivate', 'cadastros', 'Desativar produto', true, 84, 'cadastros', 'write'),
  ('cadastros.produtos.reactivate', 'cadastros', 'Reativar produto', true, 85, 'cadastros', 'write'),
  ('cadastros.embalagens.update.identity', 'cadastros', 'Alterar identidade da embalagem', true, 86, 'cadastros', 'write'),
  ('cadastros.embalagens.update.physical', 'cadastros', 'Alterar capacidade e estoque da embalagem', true, 87, 'cadastros', 'write'),
  ('cadastros.embalagens.deactivate', 'cadastros', 'Desativar embalagem', true, 88, 'cadastros', 'write'),
  ('cadastros.embalagens.reactivate', 'cadastros', 'Reativar embalagem', true, 89, 'cadastros', 'write'),
  ('cadastros.apresentacoes.deactivate', 'cadastros', 'Desativar apresentacao comercial', true, 90, 'cadastros', 'write'),
  ('cadastros.apresentacoes.reactivate', 'cadastros', 'Reativar apresentacao comercial', true, 91, 'cadastros', 'write'),
  ('cadastros.embalagens.composition.version.create', 'cadastros', 'Criar versao da composicao de embalagem', true, 92, 'cadastros', 'write'),
  ('cadastros.embalagens.composition.component.manage', 'cadastros', 'Gerenciar componente da composicao de embalagem', true, 93, 'cadastros', 'write'),
  ('cadastros.embalagens.composition.version.review', 'cadastros', 'Revisar versao da composicao de embalagem', true, 94, 'cadastros', 'write'),
  ('cadastros.embalagens.composition.version.activate', 'cadastros', 'Ativar versao da composicao de embalagem', true, 95, 'cadastros', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.normalize_cad_product_code(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(upper(regexp_replace(btrim(p_value), '[^[:alnum:]]+', '', 'g')), '')
$$;

revoke all on function public.normalize_cad_product_code(text) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from public.cad_produtos_base
     where public.normalize_cad_product_code(codigo_produto) is not null
     group by public.normalize_cad_product_code(codigo_produto)
    having count(*) > 1
  ) then
    raise exception 'normalized duplicate product code exists; reconcile before migration 0068';
  end if;
  if exists (
    select 1 from public.cad_produto_embalagens
     where public.normalize_cad_product_code(codigo_item) is not null
     group by public.normalize_cad_product_code(codigo_item)
    having count(*) > 1
  ) then
    raise exception 'normalized duplicate sale item code exists; reconcile before migration 0068';
  end if;
end;
$$;

create unique index if not exists idx_cad_produtos_codigo_norm
  on public.cad_produtos_base(public.normalize_cad_product_code(codigo_produto));

create unique index if not exists idx_cad_produto_embalagens_codigo_norm
  on public.cad_produto_embalagens(public.normalize_cad_product_code(codigo_item));

create or replace function public.validate_cad_product_package_operational_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'cad_produtos_base' then
    if coalesce(new.origem_dados, 'sistema') = 'sistema' and new.codigo_produto !~ '^[0-9]{4}$' then
      raise exception 'system product code must contain exactly four digits';
    end if;
    return new;
  end if;
  if tg_table_name = 'cad_embalagens' then
    if coalesce(new.origem_dados, 'sistema') = 'sistema'
       and (upper(new.unidade) <> 'UN' or new.volume_litros is null or new.volume_litros <= 0) then
      raise exception 'system package requires UN unit and positive liter capacity';
    end if;
    return new;
  end if;
  if not exists (
    select 1 from public.cad_produtos_base product where product.id = new.produto_id and product.status = 'active'
  ) or not exists (
    select 1 from public.cad_embalagens package where package.id = new.embalagem_id and package.status = 'active'
  ) then raise exception 'sale item requires active product and package'; end if;
  return new;
end;
$$;

revoke all on function public.validate_cad_product_package_operational_write() from public, anon, authenticated;

drop trigger if exists trg_cad_product_operational_code on public.cad_produtos_base;
create trigger trg_cad_product_operational_code
before insert or update of codigo_produto on public.cad_produtos_base
for each row execute function public.validate_cad_product_package_operational_write();

drop trigger if exists trg_cad_package_operational_basis on public.cad_embalagens;
create trigger trg_cad_package_operational_basis
before insert or update of unidade, unidade_id, volume_litros, origem_dados on public.cad_embalagens
for each row execute function public.validate_cad_product_package_operational_write();

drop trigger if exists trg_cad_sale_item_active_relations on public.cad_produto_embalagens;
create trigger trg_cad_sale_item_active_relations
before insert or update of produto_id, embalagem_id on public.cad_produto_embalagens
for each row execute function public.validate_cad_product_package_operational_write();

alter table public.cad_embalagem_versoes
  add column if not exists unidades_embalagem_por_litro numeric;

alter table public.cad_embalagem_versoes
  drop constraint if exists cad_embalagem_versoes_un_l_check,
  add constraint cad_embalagem_versoes_un_l_check check (
    unidades_embalagem_por_litro is null or unidades_embalagem_por_litro > 0
  );

alter table public.cad_embalagem_componentes
  add column if not exists quantidade_un_l numeric,
  add column if not exists status text not null default 'active';

alter table public.cad_embalagem_componentes
  drop constraint if exists cad_embalagem_componentes_quantidade_un_l_check,
  drop constraint if exists cad_embalagem_componentes_status_check,
  add constraint cad_embalagem_componentes_quantidade_un_l_check check (
    quantidade_un_l is null or quantidade_un_l > 0
  ),
  add constraint cad_embalagem_componentes_status_check check (
    status in ('active', 'removed')
  );

comment on column public.cad_embalagem_versoes.unidades_embalagem_por_litro is
  'Normalized package requirement in UN per liter of finished product, derived from package capacity.';
comment on column public.cad_embalagem_componentes.quantidade_un_l is
  'Authoritative normalized quantity of the packaging component in UN per liter of finished product.';
comment on column public.cad_embalagem_componentes.quantidade is
  'Compatibility snapshot. New operational writes mirror quantidade_un_l; quantidade_un_l is authoritative.';

create table public.cad_embalagem_versao_revisoes (
  id bigint generated always as identity primary key,
  embalagem_versao_id bigint not null references public.cad_embalagem_versoes(id) on delete restrict,
  decisao text not null check (decisao in ('approved', 'rejected')),
  motivo text not null check (nullif(btrim(motivo), '') is not null),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint cad_embalagem_versao_revisoes_once unique (embalagem_versao_id)
);

create table public.cad_embalagem_componente_eventos (
  id bigint generated always as identity primary key,
  embalagem_componente_id bigint not null references public.cad_embalagem_componentes(id) on delete restrict,
  tipo_evento text not null check (tipo_evento = 'remocao'),
  motivo text not null check (nullif(btrim(motivo), '') is not null),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint cad_embalagem_componente_eventos_once unique (embalagem_componente_id, tipo_evento)
);

create index idx_cad_embalagem_versao_revisoes_current
  on public.cad_embalagem_versao_revisoes(embalagem_versao_id, created_at desc, id desc);
create index idx_cad_embalagem_componente_eventos_current
  on public.cad_embalagem_componente_eventos(embalagem_componente_id, created_at desc, id desc);

comment on table public.cad_embalagem_versao_revisoes is
  'Append-only review decisions for immutable package composition versions.';
comment on table public.cad_embalagem_componente_eventos is
  'Append-only lifecycle events for immutable package composition components.';

create trigger trg_cad_embalagem_versao_revisoes_append_only
before update or delete on public.cad_embalagem_versao_revisoes
for each row execute function public.prevent_dec008_fact_changes();
create trigger trg_cad_embalagem_versao_revisoes_no_truncate
before truncate on public.cad_embalagem_versao_revisoes
for each statement execute function public.prevent_dec008_fact_changes();
create trigger trg_cad_embalagem_componente_eventos_append_only
before update or delete on public.cad_embalagem_componente_eventos
for each row execute function public.prevent_dec008_fact_changes();
create trigger trg_cad_embalagem_componente_eventos_no_truncate
before truncate on public.cad_embalagem_componente_eventos
for each statement execute function public.prevent_dec008_fact_changes();

alter table public.cad_embalagem_versao_revisoes enable row level security;
alter table public.cad_embalagem_componente_eventos enable row level security;
create policy "active user read cad_embalagem_versao_revisoes"
  on public.cad_embalagem_versao_revisoes for select to authenticated
  using (public.current_actor_id() is not null);
create policy "active user read cad_embalagem_componente_eventos"
  on public.cad_embalagem_componente_eventos for select to authenticated
  using (public.current_actor_id() is not null);

create or replace function public.current_cad_embalagem_versao_review_status(p_embalagem_versao_id bigint)
returns text
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select review.decisao
       from public.cad_embalagem_versao_revisoes review
      where review.embalagem_versao_id = p_embalagem_versao_id
      order by review.created_at desc, review.id desc
      limit 1),
    (select version.review_status
       from public.cad_embalagem_versoes version
      where version.id = p_embalagem_versao_id)
  )
$$;

create or replace function public.is_cad_embalagem_componente_active(p_componente_id bigint)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.cad_embalagem_componentes component
     where component.id = p_componente_id
       and not exists (
         select 1 from public.cad_embalagem_componente_eventos event
          where event.embalagem_componente_id = component.id
            and event.tipo_evento = 'remocao'
       )
  )
$$;

create or replace function public.update_cad_produto_identity(
  p_produto_id bigint,
  p_codigo_produto text,
  p_nome text,
  p_grupo_id bigint default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_group public.cad_grupos_produto%rowtype;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.produtos.update.identity', 'cadastros', 'cad_produtos_base',
    'field_risk', jsonb_build_object('correlation_id', 'produto:' || p_produto_id || ':identity')
  );
  if public.normalize_cad_product_code(p_codigo_produto) is null then raise exception 'codigo_produto is required'; end if;
  if p_codigo_produto !~ '^[0-9]{4}$' then raise exception 'product code must contain exactly four digits'; end if;
  if nullif(btrim(p_nome), '') is null then raise exception 'nome is required'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  if p_grupo_id is not null then
    select * into v_group from public.cad_grupos_produto where id = p_grupo_id and status = 'active';
    if not found then raise exception 'active product group not found'; end if;
  end if;
  select to_jsonb(product) into v_before
    from public.cad_produtos_base product where product.id = p_produto_id for update;
  if not found then raise exception 'product not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_produtos_base
     set codigo_produto = upper(btrim(p_codigo_produto)),
         nome = btrim(p_nome),
         nome_norm = public.normalize_catalog_term(p_nome),
         grupo_id = p_grupo_id,
         grupo = case when p_grupo_id is null then null else v_group.codigo end,
         updated_by = v_actor
   where id = p_produto_id;
  select to_jsonb(product) into v_after from public.cad_produtos_base product where product.id = p_produto_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produtos_base', p_produto_id::text,
    'cadastros.produto_identity_updated', 'cadastros.produtos.update.identity',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_produto_id;
end;
$$;

create or replace function public.update_cad_produto_technical(
  p_produto_id bigint,
  p_densidade_kg_l numeric default null,
  p_prazo_validade_meses integer default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.produtos.update.technical', 'cadastros', 'cad_produtos_base',
    'field_risk', jsonb_build_object('correlation_id', 'produto:' || p_produto_id || ':technical')
  );
  if p_densidade_kg_l is not null and p_densidade_kg_l <= 0 then raise exception 'density must be greater than zero'; end if;
  if p_prazo_validade_meses is not null and (p_prazo_validade_meses < 1 or p_prazo_validade_meses > 240) then
    raise exception 'shelf life must be between 1 and 240 months';
  end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(product) into v_before
    from public.cad_produtos_base product where product.id = p_produto_id for update;
  if not found then raise exception 'product not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_produtos_base
     set densidade_kg_l = p_densidade_kg_l,
         prazo_validade_meses = p_prazo_validade_meses,
         updated_by = v_actor
   where id = p_produto_id;
  select to_jsonb(product) into v_after from public.cad_produtos_base product where product.id = p_produto_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produtos_base', p_produto_id::text,
    'cadastros.produto_technical_updated', 'cadastros.produtos.update.technical',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'formula_base', 'per_liter'), 'database_rpc'
  );
  return p_produto_id;
end;
$$;

create or replace function public.update_cad_produto_regulatory(
  p_produto_id bigint,
  p_reg_mapa text default null,
  p_ncm text default null,
  p_ibama text default null,
  p_ads text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_ncm text;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.produtos.update.regulatory', 'cadastros', 'cad_produtos_base',
    'field_risk', jsonb_build_object('correlation_id', 'produto:' || p_produto_id || ':regulatory')
  );
  v_ncm := nullif(regexp_replace(coalesce(p_ncm, ''), '[^0-9]', '', 'g'), '');
  if v_ncm is not null and length(v_ncm) <> 8 then raise exception 'ncm must contain eight digits'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(product) into v_before
    from public.cad_produtos_base product where product.id = p_produto_id for update;
  if not found then raise exception 'product not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_produtos_base
     set reg_mapa = nullif(btrim(p_reg_mapa), ''),
         ncm = v_ncm,
         ibama = nullif(btrim(p_ibama), ''),
         ads = nullif(btrim(p_ads), ''),
         updated_by = v_actor
   where id = p_produto_id;
  select to_jsonb(product) into v_after from public.cad_produtos_base product where product.id = p_produto_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produtos_base', p_produto_id::text,
    'cadastros.produto_regulatory_updated', 'cadastros.produtos.update.regulatory',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_produto_id;
end;
$$;

create or replace function public.set_cad_produto_active_state(
  p_produto_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_action_key := case when p_active then 'cadastros.produtos.reactivate' else 'cadastros.produtos.deactivate' end;
  v_permission_context := public.begin_audited_rpc(
    v_action_key, 'cadastros', 'cad_produtos_base', 'status_transition',
    jsonb_build_object('correlation_id', 'produto:' || p_produto_id || ':status')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(product) into v_before
    from public.cad_produtos_base product where product.id = p_produto_id for update;
  if not found then raise exception 'product not found'; end if;
  if p_active and v_before->>'status' = 'active' then raise exception 'product already active'; end if;
  if not p_active and v_before->>'status' = 'inactive' then raise exception 'product already inactive'; end if;
  v_actor := public.current_actor_id();
  update public.cad_produtos_base
     set status = case when p_active then 'active' else 'inactive' end,
         updated_by = v_actor
   where id = p_produto_id;
  select to_jsonb(product) into v_after from public.cad_produtos_base product where product.id = p_produto_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produtos_base', p_produto_id::text,
    case when p_active then 'cadastros.produto_reactivated' else 'cadastros.produto_deactivated' end,
    v_action_key, v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_produto_id;
end;
$$;

create or replace function public.update_cad_embalagem_identity(
  p_embalagem_id bigint,
  p_descricao text,
  p_codigo_legado text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.update.identity', 'cadastros', 'cad_embalagens',
    'field_risk', jsonb_build_object('correlation_id', 'embalagem:' || p_embalagem_id || ':identity')
  );
  if nullif(btrim(p_descricao), '') is null then raise exception 'descricao is required'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(package) into v_before
    from public.cad_embalagens package where package.id = p_embalagem_id for update;
  if not found then raise exception 'package not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_embalagens
     set descricao = btrim(p_descricao),
         descricao_norm = public.normalize_catalog_term(p_descricao),
         codigo_legado = nullif(btrim(p_codigo_legado), ''),
         updated_by = v_actor
   where id = p_embalagem_id;
  select to_jsonb(package) into v_after from public.cad_embalagens package where package.id = p_embalagem_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagens', p_embalagem_id::text,
    'cadastros.embalagem_identity_updated', 'cadastros.embalagens.update.identity',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_embalagem_id;
end;
$$;

create or replace function public.update_cad_embalagem_physical(
  p_embalagem_id bigint,
  p_unidade_id bigint,
  p_volume_litros numeric,
  p_controla_estoque boolean,
  p_materia_prima_id bigint default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_unit public.cad_unidades_medida%rowtype;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.update.physical', 'cadastros', 'cad_embalagens',
    'field_risk', jsonb_build_object('correlation_id', 'embalagem:' || p_embalagem_id || ':physical')
  );
  if p_volume_litros is null or p_volume_litros <= 0 then raise exception 'package capacity in liters must be greater than zero'; end if;
  if coalesce(p_controla_estoque, false) and p_materia_prima_id is null then raise exception 'stock controlled package requires raw material'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select * into v_unit from public.cad_unidades_medida where id = p_unidade_id and status = 'active';
  if not found or upper(v_unit.codigo) <> 'UN' then raise exception 'package operational unit must be UN'; end if;
  if p_materia_prima_id is not null and not exists (
    select 1 from public.cad_materias_primas material where material.id = p_materia_prima_id and material.status = 'active'
  ) then raise exception 'active package raw material not found'; end if;
  select to_jsonb(package) into v_before
    from public.cad_embalagens package where package.id = p_embalagem_id for update;
  if not found then raise exception 'package not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_embalagens
     set unidade_id = v_unit.id,
         unidade = v_unit.codigo,
         volume_litros = p_volume_litros,
         controla_estoque = coalesce(p_controla_estoque, false),
         materia_prima_id = p_materia_prima_id,
         updated_by = v_actor
   where id = p_embalagem_id;
  select to_jsonb(package) into v_after from public.cad_embalagens package where package.id = p_embalagem_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagens', p_embalagem_id::text,
    'cadastros.embalagem_physical_updated', 'cadastros.embalagens.update.physical',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'normalized_basis', 'UN/L'), 'database_rpc'
  );
  return p_embalagem_id;
end;
$$;

create or replace function public.set_cad_embalagem_active_state(
  p_embalagem_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_action_key := case when p_active then 'cadastros.embalagens.reactivate' else 'cadastros.embalagens.deactivate' end;
  v_permission_context := public.begin_audited_rpc(
    v_action_key, 'cadastros', 'cad_embalagens', 'status_transition',
    jsonb_build_object('correlation_id', 'embalagem:' || p_embalagem_id || ':status')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(package) into v_before
    from public.cad_embalagens package where package.id = p_embalagem_id for update;
  if not found then raise exception 'package not found'; end if;
  if p_active and v_before->>'status' = 'active' then raise exception 'package already active'; end if;
  if not p_active and v_before->>'status' = 'inactive' then raise exception 'package already inactive'; end if;
  if not p_active and exists (
    select 1 from public.cad_produto_embalagens item
     where item.embalagem_id = p_embalagem_id and item.status = 'active'
  ) then raise exception 'deactivate active sale items before package'; end if;
  v_actor := public.current_actor_id();
  update public.cad_embalagens
     set status = case when p_active then 'active' else 'inactive' end,
         updated_by = v_actor
   where id = p_embalagem_id;
  select to_jsonb(package) into v_after from public.cad_embalagens package where package.id = p_embalagem_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagens', p_embalagem_id::text,
    case when p_active then 'cadastros.embalagem_reactivated' else 'cadastros.embalagem_deactivated' end,
    v_action_key, v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_embalagem_id;
end;
$$;

create or replace function public.set_cad_apresentacao_active_state(
  p_apresentacao_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_action_key := case when p_active then 'cadastros.apresentacoes.reactivate' else 'cadastros.apresentacoes.deactivate' end;
  v_permission_context := public.begin_audited_rpc(
    v_action_key, 'cadastros', 'cad_produto_embalagens', 'status_transition',
    jsonb_build_object('correlation_id', 'apresentacao:' || p_apresentacao_id || ':status')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(item) into v_before
    from public.cad_produto_embalagens item where item.id = p_apresentacao_id for update;
  if not found then raise exception 'sale item not found'; end if;
  if p_active and not exists (
    select 1 from public.cad_produtos_base product
    join public.cad_embalagens package on package.id = (v_before->>'embalagem_id')::bigint
    where product.id = (v_before->>'produto_id')::bigint
      and product.status = 'active' and package.status = 'active'
  ) then raise exception 'active product and package are required'; end if;
  v_actor := public.current_actor_id();
  update public.cad_produto_embalagens
     set status = case when p_active then 'active' else 'inactive' end,
         updated_by = v_actor
   where id = p_apresentacao_id;
  select to_jsonb(item) into v_after from public.cad_produto_embalagens item where item.id = p_apresentacao_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produto_embalagens', p_apresentacao_id::text,
    case when p_active then 'cadastros.apresentacao_reactivated' else 'cadastros.apresentacao_deactivated' end,
    v_action_key, v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_apresentacao_id;
end;
$$;

create or replace function public.create_cad_embalagem_versao_un_l(
  p_embalagem_id bigint,
  p_vigencia_inicio date default null,
  p_vigencia_fim date default null,
  p_peso_tara_kg numeric default null,
  p_cubagem_m3 numeric default null,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_version integer;
  v_capacity numeric;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.composition.version.create', 'cadastros', 'cad_embalagem_versoes',
    'change_type', jsonb_build_object('correlation_id', 'embalagem:' || p_embalagem_id || ':composition')
  );
  if p_vigencia_inicio is not null and p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then raise exception 'invalid validity range'; end if;
  if p_peso_tara_kg is not null and p_peso_tara_kg <= 0 then raise exception 'tare must be greater than zero'; end if;
  if p_cubagem_m3 is not null and p_cubagem_m3 <= 0 then raise exception 'volume must be greater than zero'; end if;
  if nullif(btrim(p_justificativa), '') is null then raise exception 'justificativa is required'; end if;
  select package.volume_litros into v_capacity
    from public.cad_embalagens package
   where package.id = p_embalagem_id and package.status = 'active'
   for update;
  if not found then raise exception 'active package not found'; end if;
  if v_capacity is null or v_capacity <= 0 then raise exception 'package capacity is required for UN/L'; end if;
  select coalesce(max(version.versao), 0) + 1 into v_version
    from public.cad_embalagem_versoes version where version.embalagem_id = p_embalagem_id;
  v_actor := public.current_actor_id();
  insert into public.cad_embalagem_versoes(
    embalagem_id, versao, vigencia_inicio, vigencia_fim, peso_tara_kg, cubagem_m3,
    justificativa, review_status, origem_dados, created_by, unidades_embalagem_por_litro
  ) values (
    p_embalagem_id, v_version, p_vigencia_inicio, p_vigencia_fim, p_peso_tara_kg, p_cubagem_m3,
    btrim(p_justificativa), 'pending_review', 'sistema', v_actor, 1 / v_capacity
  ) returning id into v_id;
  select to_jsonb(version) into v_after from public.cad_embalagem_versoes version where version.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagem_versoes', v_id::text,
    'cadastros.embalagem_composition_version_created',
    'cadastros.embalagens.composition.version.create', v_permission_context, null, v_after,
    jsonb_build_object('normalized_basis', 'UN/L', 'package_capacity_liters', v_capacity), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.add_cad_embalagem_componente_un_l(
  p_embalagem_versao_id bigint,
  p_materia_prima_id bigint,
  p_quantidade_un_l numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_unit_id bigint;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.composition.component.manage', 'cadastros', 'cad_embalagem_componentes',
    'change_type', jsonb_build_object('correlation_id', 'embalagem_versao:' || p_embalagem_versao_id || ':components')
  );
  if p_quantidade_un_l is null or p_quantidade_un_l <= 0 then raise exception 'component quantity in UN/L must be greater than zero'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  perform 1 from public.cad_embalagem_versoes version
   where version.id = p_embalagem_versao_id
     and public.current_cad_embalagem_versao_review_status(version.id) = 'pending_review'
   for update;
  if not found then raise exception 'only a pending version accepts components'; end if;
  if not exists (
    select 1 from public.cad_materias_primas material where material.id = p_materia_prima_id and material.status = 'active'
  ) then raise exception 'active packaging component not found'; end if;
  select unit.id into v_unit_id from public.cad_unidades_medida unit
   where upper(unit.codigo) = 'UN' and unit.status = 'active';
  if not found then raise exception 'active UN unit not found'; end if;
  v_actor := public.current_actor_id();
  insert into public.cad_embalagem_componentes(
    embalagem_versao_id, materia_prima_id, quantidade, quantidade_un_l, unidade_id,
    review_status, origem_dados, created_by, status
  ) values (
    p_embalagem_versao_id, p_materia_prima_id, p_quantidade_un_l, p_quantidade_un_l,
    v_unit_id, 'pending_review', 'sistema', v_actor, 'active'
  ) returning id into v_id;
  select to_jsonb(component) into v_after from public.cad_embalagem_componentes component where component.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagem_componentes', v_id::text,
    'cadastros.embalagem_composition_component_added',
    'cadastros.embalagens.composition.component.manage', v_permission_context, null, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'normalized_basis', 'UN/L'), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.remove_cad_embalagem_componente(
  p_componente_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_event_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.composition.component.manage', 'cadastros', 'cad_embalagem_componentes',
    'change_type', jsonb_build_object('correlation_id', 'embalagem_componente:' || p_componente_id || ':remove')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(component) into v_before
    from public.cad_embalagem_componentes component
    join public.cad_embalagem_versoes version on version.id = component.embalagem_versao_id
   where component.id = p_componente_id
     and public.is_cad_embalagem_componente_active(component.id)
     and public.current_cad_embalagem_versao_review_status(version.id) = 'pending_review'
   for update of component;
  if not found then raise exception 'active component in pending version not found'; end if;
  v_actor := public.current_actor_id();
  insert into public.cad_embalagem_componente_eventos(
    embalagem_componente_id, tipo_evento, motivo, created_by
  ) values (p_componente_id, 'remocao', btrim(p_motivo), v_actor)
  returning id into v_event_id;
  select jsonb_build_object(
    'componente', to_jsonb(component),
    'evento', (select to_jsonb(event) from public.cad_embalagem_componente_eventos event where event.id = v_event_id)
  ) into v_after
    from public.cad_embalagem_componentes component where component.id = p_componente_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagem_componentes', p_componente_id::text,
    'cadastros.embalagem_composition_component_removed',
    'cadastros.embalagens.composition.component.manage', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_componente_id;
end;
$$;

create or replace function public.review_cad_embalagem_versao(
  p_embalagem_versao_id bigint,
  p_decisao text,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_review_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.composition.version.review', 'cadastros', 'cad_embalagem_versoes',
    'status_transition', jsonb_build_object('correlation_id', 'embalagem_versao:' || p_embalagem_versao_id || ':review')
  );
  if p_decisao not in ('approved', 'rejected') then raise exception 'invalid review decision'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(version) into v_before
    from public.cad_embalagem_versoes version
   where version.id = p_embalagem_versao_id
     and public.current_cad_embalagem_versao_review_status(version.id) = 'pending_review'
   for update;
  if not found then raise exception 'pending package version not found'; end if;
  if p_decisao = 'approved' and (
    (v_before->>'unidades_embalagem_por_litro') is null
    or not exists (
      select 1 from public.cad_embalagem_componentes component
       where component.embalagem_versao_id = p_embalagem_versao_id
         and public.is_cad_embalagem_componente_active(component.id)
         and component.quantidade_un_l > 0
    )
  ) then raise exception 'normalized UN/L composition is incomplete'; end if;
  v_actor := public.current_actor_id();
  insert into public.cad_embalagem_versao_revisoes(
    embalagem_versao_id, decisao, motivo, created_by
  ) values (p_embalagem_versao_id, p_decisao, btrim(p_motivo), v_actor)
  returning id into v_review_id;
  select jsonb_build_object(
    'versao', to_jsonb(version),
    'revisao', (select to_jsonb(review) from public.cad_embalagem_versao_revisoes review where review.id = v_review_id)
  ) into v_after
    from public.cad_embalagem_versoes version where version.id = p_embalagem_versao_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagem_versoes', p_embalagem_versao_id::text,
    'cadastros.embalagem_composition_version_reviewed',
    'cadastros.embalagens.composition.version.review', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'decisao', p_decisao), 'database_rpc'
  );
  return p_embalagem_versao_id;
end;
$$;

create or replace function public.activate_cad_embalagem_versao(
  p_embalagem_versao_id bigint,
  p_ativar boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_event_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.embalagens.composition.version.activate', 'cadastros', 'cad_embalagem_versao_ativacoes',
    'status_transition', jsonb_build_object('correlation_id', 'embalagem_versao:' || p_embalagem_versao_id || ':activation')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select jsonb_build_object(
    'versao', to_jsonb(version),
    'evento_atual', (
      select to_jsonb(event) from public.cad_embalagem_versao_ativacoes event
       join public.cad_embalagem_versoes event_version on event_version.id = event.embalagem_versao_id
       where event_version.embalagem_id = version.embalagem_id
       order by event.created_at desc, event.id desc limit 1
    )
  ) into v_before
    from public.cad_embalagem_versoes version
   where version.id = p_embalagem_versao_id
   for update;
  if not found then raise exception 'package version not found'; end if;
  if p_ativar and public.current_cad_embalagem_versao_review_status(p_embalagem_versao_id) <> 'approved'
    then raise exception 'only approved version can be activated'; end if;
  v_actor := public.current_actor_id();
  insert into public.cad_embalagem_versao_ativacoes(
    embalagem_versao_id, tipo_evento, motivo, created_by
  ) values (
    p_embalagem_versao_id, case when p_ativar then 'ativacao' else 'desativacao' end,
    btrim(p_motivo), v_actor
  ) returning id into v_event_id;
  select to_jsonb(event) into v_after from public.cad_embalagem_versao_ativacoes event where event.id = v_event_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_embalagem_versao_ativacoes', v_event_id::text,
    case when p_ativar then 'cadastros.embalagem_composition_version_activated' else 'cadastros.embalagem_composition_version_deactivated' end,
    'cadastros.embalagens.composition.version.activate', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'normalized_basis', 'UN/L'), 'database_rpc'
  );
  return v_event_id;
end;
$$;

create or replace function public.validate_package_activation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_review_status text;
  v_package_status text;
  v_un_l numeric;
begin
  if not exists (
    select 1 from public.user_profiles profile
     where profile.id = new.created_by and profile.is_system_actor = false and profile.status = 'active'
  ) then raise exception 'only active human profiles can activate packaging versions'; end if;
  select public.current_cad_embalagem_versao_review_status(version.id), package.status,
         version.unidades_embalagem_por_litro
    into v_review_status, v_package_status, v_un_l
    from public.cad_embalagem_versoes version
    join public.cad_embalagens package on package.id = version.embalagem_id
   where version.id = new.embalagem_versao_id;
  if new.tipo_evento = 'ativacao' and (
    v_review_status <> 'approved' or v_package_status <> 'active' or v_un_l is null
    or not exists (
      select 1 from public.cad_embalagem_componentes component
       where component.embalagem_versao_id = new.embalagem_versao_id
         and public.is_cad_embalagem_componente_active(component.id)
         and component.quantidade_un_l > 0
    )
  ) then raise exception 'only complete approved UN/L versions of active packages can be activated'; end if;
  return new;
end;
$$;

create or replace view public.cad_embalagem_configuracoes_atuais
with (security_invoker = true)
as
with latest_event as (
  select distinct on (version.embalagem_id)
    version.embalagem_id, activation.embalagem_versao_id,
    activation.tipo_evento, activation.created_at as activated_at
  from public.cad_embalagem_versao_ativacoes activation
  join public.cad_embalagem_versoes version on version.id = activation.embalagem_versao_id
  order by version.embalagem_id, activation.created_at desc, activation.id desc
)
select
  package.id as embalagem_id, package.descricao, package.unidade_id,
  package.volume_litros, version.id as embalagem_versao_id, version.versao,
  version.peso_tara_kg, version.cubagem_m3, version.vigencia_inicio,
  version.vigencia_fim, latest_event.activated_at,
  version.unidades_embalagem_por_litro
from latest_event
join public.cad_embalagem_versoes version on version.id = latest_event.embalagem_versao_id
join public.cad_embalagens package on package.id = version.embalagem_id
where latest_event.tipo_evento = 'ativacao'
  and public.current_cad_embalagem_versao_review_status(version.id) = 'approved'
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
  component.unidade_id,
  current_package.unidades_embalagem_por_litro,
  component.quantidade_un_l
from public.cad_embalagem_configuracoes_atuais current_package
join public.cad_embalagem_componentes component
  on component.embalagem_versao_id = current_package.embalagem_versao_id
where public.current_cad_embalagem_versao_review_status(component.embalagem_versao_id) = 'approved'
  and public.is_cad_embalagem_componente_active(component.id)
  and component.quantidade_un_l is not null;

revoke all on function public.update_cad_produto_identity(bigint, text, text, bigint, text) from public, anon;
revoke all on function public.update_cad_produto_technical(bigint, numeric, integer, text) from public, anon;
revoke all on function public.update_cad_produto_regulatory(bigint, text, text, text, text, text) from public, anon;
revoke all on function public.set_cad_produto_active_state(bigint, boolean, text) from public, anon;
revoke all on function public.update_cad_embalagem_identity(bigint, text, text, text) from public, anon;
revoke all on function public.update_cad_embalagem_physical(bigint, bigint, numeric, boolean, bigint, text) from public, anon;
revoke all on function public.set_cad_embalagem_active_state(bigint, boolean, text) from public, anon;
revoke all on function public.set_cad_apresentacao_active_state(bigint, boolean, text) from public, anon;
revoke all on function public.create_cad_embalagem_versao_un_l(bigint, date, date, numeric, numeric, text) from public, anon;
revoke all on function public.add_cad_embalagem_componente_un_l(bigint, bigint, numeric, text) from public, anon;
revoke all on function public.remove_cad_embalagem_componente(bigint, text) from public, anon;
revoke all on function public.review_cad_embalagem_versao(bigint, text, text) from public, anon;
revoke all on function public.activate_cad_embalagem_versao(bigint, boolean, text) from public, anon;
revoke all on function public.current_cad_embalagem_versao_review_status(bigint) from public, anon;
revoke all on function public.is_cad_embalagem_componente_active(bigint) from public, anon;

grant execute on function public.update_cad_produto_identity(bigint, text, text, bigint, text) to authenticated;
grant execute on function public.update_cad_produto_technical(bigint, numeric, integer, text) to authenticated;
grant execute on function public.update_cad_produto_regulatory(bigint, text, text, text, text, text) to authenticated;
grant execute on function public.set_cad_produto_active_state(bigint, boolean, text) to authenticated;
grant execute on function public.update_cad_embalagem_identity(bigint, text, text, text) to authenticated;
grant execute on function public.update_cad_embalagem_physical(bigint, bigint, numeric, boolean, bigint, text) to authenticated;
grant execute on function public.set_cad_embalagem_active_state(bigint, boolean, text) to authenticated;
grant execute on function public.set_cad_apresentacao_active_state(bigint, boolean, text) to authenticated;
grant execute on function public.create_cad_embalagem_versao_un_l(bigint, date, date, numeric, numeric, text) to authenticated;
grant execute on function public.add_cad_embalagem_componente_un_l(bigint, bigint, numeric, text) to authenticated;
grant execute on function public.remove_cad_embalagem_componente(bigint, text) to authenticated;
grant execute on function public.review_cad_embalagem_versao(bigint, text, text) to authenticated;
grant execute on function public.activate_cad_embalagem_versao(bigint, boolean, text) to authenticated;
grant execute on function public.current_cad_embalagem_versao_review_status(bigint) to authenticated;
grant execute on function public.is_cad_embalagem_componente_active(bigint) to authenticated;

revoke insert, update, delete, truncate on public.cad_produtos_base from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagens from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_produto_embalagens from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagem_versoes from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagem_componentes from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagem_versao_ativacoes from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagem_versao_revisoes from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_embalagem_componente_eventos from public, anon, authenticated;

grant select on public.cad_embalagem_versao_revisoes to authenticated;
grant select on public.cad_embalagem_componente_eventos to authenticated;
revoke all on public.cad_embalagem_versao_revisoes from public, anon;
revoke all on public.cad_embalagem_componente_eventos from public, anon;

grant select on public.cad_embalagem_configuracoes_atuais to authenticated;
grant select on public.cad_embalagem_componentes_atuais to authenticated;
revoke all on public.cad_embalagem_configuracoes_atuais from public, anon;
revoke all on public.cad_embalagem_componentes_atuais from public, anon;
