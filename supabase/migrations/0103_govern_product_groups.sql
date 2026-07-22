-- Govern product groups as the single relational source for new product operations.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.grupos_produto.read', 'cadastros', 'Consultar grupos de produto', true, 181, 'cadastros', 'read'),
  ('cadastros.grupos_produto.create', 'cadastros', 'Criar grupo de produto', true, 182, 'cadastros', 'write'),
  ('cadastros.grupos_produto.update', 'cadastros', 'Alterar grupo de produto', true, 183, 'cadastros', 'write'),
  ('cadastros.grupos_produto.deactivate', 'cadastros', 'Desativar grupo de produto', true, 184, 'cadastros', 'write'),
  ('cadastros.grupos_produto.reactivate', 'cadastros', 'Reativar grupo de produto', true, 185, 'cadastros', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

alter table public.cad_grupos_produto
  add column if not exists descricao text,
  add column if not exists ordem_exibicao integer not null default 0,
  add column if not exists nome_norm text generated always as (public.normalize_catalog_term(nome)) stored,
  add column if not exists updated_by uuid references public.user_profiles(id),
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if exists (
    select 1 from public.cad_grupos_produto
     where nome_norm is not null
     group by nome_norm having count(*) > 1
  ) then
    raise exception 'duplicate normalized product group names exist; review is required before migration 0103';
  end if;
end;
$$;

create unique index if not exists idx_cad_grupos_produto_nome_norm
  on public.cad_grupos_produto(nome_norm);
create index if not exists idx_cad_grupos_produto_status_order
  on public.cad_grupos_produto(status, ordem_exibicao, nome);
create index if not exists idx_cad_produtos_base_grupo_id
  on public.cad_produtos_base(grupo_id);

create or replace function public.create_cad_grupo_produto(
  p_codigo text,
  p_nome text,
  p_descricao text default null,
  p_ordem_exibicao integer default 0
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.grupos_produto.create', 'cadastros', 'cad_grupos_produto',
    'change_type', jsonb_build_object('correlation_id', gen_random_uuid()::text)
  );
  if public.normalize_catalog_term(p_codigo) is null then raise exception 'codigo is required'; end if;
  if public.normalize_catalog_term(p_nome) is null then raise exception 'nome is required'; end if;
  if coalesce(p_ordem_exibicao, 0) < 0 then raise exception 'display order must be non-negative'; end if;
  perform pg_advisory_xact_lock(hashtextextended('cad_grupos_produto:' || public.normalize_catalog_term(p_codigo), 0));
  v_actor := public.current_actor_id();
  insert into public.cad_grupos_produto(
    codigo, nome, descricao, ordem_exibicao, status, origem_dados, created_by, updated_by
  ) values (
    upper(btrim(p_codigo)), btrim(p_nome), nullif(btrim(p_descricao), ''), coalesce(p_ordem_exibicao, 0),
    'active', 'sistema', v_actor, v_actor
  ) returning id into v_id;
  select to_jsonb(product_group) into v_after from public.cad_grupos_produto product_group where id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_grupos_produto', v_id::text, 'cadastros.grupo_produto_created',
    'cadastros.grupos_produto.create', v_permission_context, null, v_after,
    jsonb_build_object('source', 'create_cad_grupo_produto'), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.update_cad_grupo_produto(
  p_grupo_id bigint,
  p_codigo text,
  p_nome text,
  p_descricao text,
  p_ordem_exibicao integer,
  p_motivo text
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
    'cadastros.grupos_produto.update', 'cadastros', 'cad_grupos_produto',
    'field_risk', jsonb_build_object('correlation_id', 'grupo_produto:' || p_grupo_id || ':update')
  );
  if public.normalize_catalog_term(p_codigo) is null then raise exception 'codigo is required'; end if;
  if public.normalize_catalog_term(p_nome) is null then raise exception 'nome is required'; end if;
  if coalesce(p_ordem_exibicao, 0) < 0 then raise exception 'display order must be non-negative'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  select to_jsonb(product_group) into v_before
    from public.cad_grupos_produto product_group where id = p_grupo_id for update;
  if not found then raise exception 'product group not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_grupos_produto
     set codigo = upper(btrim(p_codigo)), nome = btrim(p_nome), descricao = nullif(btrim(p_descricao), ''),
         ordem_exibicao = coalesce(p_ordem_exibicao, 0), updated_by = v_actor, updated_at = now()
   where id = p_grupo_id;
  select to_jsonb(product_group) into v_after from public.cad_grupos_produto product_group where id = p_grupo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_grupos_produto', p_grupo_id::text, 'cadastros.grupo_produto_updated',
    'cadastros.grupos_produto.update', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_grupo_id;
end;
$$;

create or replace function public.set_cad_grupo_produto_active_state(
  p_grupo_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text := case when p_active then 'cadastros.grupos_produto.reactivate' else 'cadastros.grupos_produto.deactivate' end;
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    v_action_key, 'cadastros', 'cad_grupos_produto', 'status_transition',
    jsonb_build_object('correlation_id', 'grupo_produto:' || p_grupo_id || ':active_state')
  );
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  select to_jsonb(product_group) into v_before
    from public.cad_grupos_produto product_group where id = p_grupo_id for update;
  if not found then raise exception 'product group not found'; end if;
  if p_active and v_before->>'status' <> 'inactive' then raise exception 'product group is not inactive'; end if;
  if not p_active and v_before->>'status' <> 'active' then raise exception 'product group is not active'; end if;
  v_actor := public.current_actor_id();
  update public.cad_grupos_produto
     set status = case when p_active then 'active' else 'inactive' end,
         updated_by = v_actor, updated_at = now()
   where id = p_grupo_id;
  select to_jsonb(product_group) into v_after from public.cad_grupos_produto product_group where id = p_grupo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_grupos_produto', p_grupo_id::text,
    case when p_active then 'cadastros.grupo_produto_reactivated' else 'cadastros.grupo_produto_deactivated' end,
    v_action_key, v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'linked_products_preserved', true), 'database_rpc'
  );
  return p_grupo_id;
end;
$$;

create or replace function public.list_cad_grupo_produto_history(p_grupo_id bigint)
returns table(action text, status text, before_json jsonb, after_json jsonb, metadata_json jsonb, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('cadastros.grupos_produto.read');
  return query
    select log.action, log.status, log.before_json, log.after_json, log.metadata_json, log.created_at
      from public.action_logs log
     where log.entity_type = 'cad_grupos_produto' and log.entity_id = p_grupo_id::text
     order by log.created_at desc, log.id desc;
end;
$$;

create or replace function public.create_cad_produto_base_governado(
  p_codigo_produto text,
  p_nome text,
  p_grupo_id bigint default null,
  p_status text default 'active',
  p_densidade_kg_l numeric default null,
  p_reg_mapa text default null,
  p_ncm text default null,
  p_ibama text default null,
  p_ads text default null,
  p_payload_origem_json jsonb default '{}'::jsonb,
  p_prazo_validade_meses integer default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_code text;
begin
  perform public.require_current_user_permission('cadastros.produtos.create');
  if p_grupo_id is not null then
    select codigo into v_group_code from public.cad_grupos_produto where id = p_grupo_id and status = 'active';
    if not found then raise exception 'active product group not found'; end if;
  end if;
  return public.create_cad_produto_base(
    p_codigo_produto, p_nome, public.normalize_catalog_term(p_nome), p_status, v_group_code,
    p_densidade_kg_l, p_reg_mapa, p_ncm, p_ibama, p_ads, p_payload_origem_json, p_prazo_validade_meses
  );
end;
$$;

revoke all on function public.create_cad_grupo_produto(text, text, text, integer) from public, anon;
revoke all on function public.update_cad_grupo_produto(bigint, text, text, text, integer, text) from public, anon;
revoke all on function public.set_cad_grupo_produto_active_state(bigint, boolean, text) from public, anon;
revoke all on function public.list_cad_grupo_produto_history(bigint) from public, anon;
revoke all on function public.create_cad_produto_base_governado(text, text, bigint, text, numeric, text, text, text, text, jsonb, integer) from public, anon;
grant execute on function public.create_cad_grupo_produto(text, text, text, integer) to authenticated;
grant execute on function public.update_cad_grupo_produto(bigint, text, text, text, integer, text) to authenticated;
grant execute on function public.set_cad_grupo_produto_active_state(bigint, boolean, text) to authenticated;
grant execute on function public.list_cad_grupo_produto_history(bigint) to authenticated;
grant execute on function public.create_cad_produto_base_governado(text, text, bigint, text, numeric, text, text, text, text, jsonb, integer) to authenticated;

revoke execute on function public.create_cad_produto_base(text, text, text, text, text, numeric, text, text, text, text, jsonb, integer)
  from authenticated;
revoke insert, update, delete, truncate on public.cad_grupos_produto from public, anon, authenticated;

comment on column public.cad_produtos_base.grupo is
  'Legacy compatibility cache. New operations use grupo_id and do not accept free-text group input.';
comment on function public.create_cad_produto_base_governado(text, text, bigint, text, numeric, text, text, text, text, jsonb, integer) is
  'Creates a product using an active relational product group ID; the legacy text is resolved internally.';
