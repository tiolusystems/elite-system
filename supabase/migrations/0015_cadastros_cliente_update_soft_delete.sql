insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('cadastros.clientes.update.own', 'cadastros', 'Editar clientes criados pelo proprio usuario', true, 71),
  ('cadastros.clientes.update.any', 'cadastros', 'Editar qualquer cliente', true, 72),
  ('cadastros.clientes.deactivate.own', 'cadastros', 'Desativar clientes criados pelo proprio usuario', true, 73),
  ('cadastros.clientes.deactivate.any', 'cadastros', 'Desativar qualquer cliente', true, 74)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.require_cad_cliente_scope_permission(
  p_cliente_created_by uuid,
  p_own_action_key text,
  p_any_action_key text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_owned_by_actor boolean;
begin
  v_actor := public.current_actor_id();
  v_owned_by_actor := v_actor is not null and p_cliente_created_by = v_actor;

  if v_owned_by_actor and public.can_current_user(p_own_action_key) then
    return p_own_action_key;
  end if;

  if public.can_current_user(p_any_action_key) then
    return p_any_action_key;
  end if;

  if v_owned_by_actor then
    raise exception 'not allowed: %', p_own_action_key;
  end if;

  raise exception 'not allowed: %', p_any_action_key;
end;
$$;

revoke all on function public.require_cad_cliente_scope_permission(uuid, text, text) from public;

create or replace function public.update_cad_cliente(
  p_cliente_id bigint,
  p_nome text,
  p_nome_norm text,
  p_cidade text,
  p_uf text,
  p_codigo_legado text default null,
  p_apelidos_json jsonb default '[]'::jsonb,
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
  v_created_by uuid;
  v_action_key text;
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_nome_norm), '') is null then
    raise exception 'nome_norm is required';
  end if;
  if nullif(trim(p_cidade), '') is null then
    raise exception 'cidade is required';
  end if;
  if p_uf is null or char_length(trim(p_uf)) <> 2 then
    raise exception 'uf must have exactly two letters';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(c), c.created_by
    into v_before, v_created_by
    from public.cad_clientes c
   where c.id = p_cliente_id
   for update;

  if not found then
    raise exception 'cliente not found';
  end if;

  v_action_key := public.require_cad_cliente_scope_permission(
    v_created_by,
    'cadastros.clientes.update.own',
    'cadastros.clientes.update.any'
  );
  v_actor := public.current_actor_id();

  update public.cad_clientes
     set codigo_legado = nullif(trim(p_codigo_legado), ''),
         nome = trim(p_nome),
         nome_norm = trim(p_nome_norm),
         cidade = trim(p_cidade),
         uf = upper(trim(p_uf)),
         apelidos_json = coalesce(p_apelidos_json, '[]'::jsonb),
         updated_by = v_actor
   where id = p_cliente_id;

  select to_jsonb(c)
    into v_after
    from public.cad_clientes c
   where c.id = p_cliente_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_clientes',
    p_cliente_id::text,
    'cadastros.cliente_updated',
    v_action_key,
    'success',
    v_before,
    v_after,
    jsonb_build_object(
      'alcada_usada', v_action_key,
      'scope', case when v_action_key = 'cadastros.clientes.update.own' then 'own' else 'any' end,
      'owned_by_actor', v_created_by = v_actor
    ),
    'database_rpc',
    jsonb_build_object('source', 'update_cad_cliente', 'motivo', trim(p_motivo))
  );

  return p_cliente_id;
end;
$$;

revoke all on function public.update_cad_cliente(bigint, text, text, text, text, text, jsonb, text) from public;
grant execute on function public.update_cad_cliente(bigint, text, text, text, text, text, jsonb, text) to authenticated;

create or replace function public.deactivate_cad_cliente(
  p_cliente_id bigint,
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
  v_created_by uuid;
  v_status text;
  v_action_key text;
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(c), c.created_by, c.status
    into v_before, v_created_by, v_status
    from public.cad_clientes c
   where c.id = p_cliente_id
   for update;

  if not found then
    raise exception 'cliente not found';
  end if;
  if v_status = 'inactive' then
    raise exception 'cliente already inactive';
  end if;

  v_action_key := public.require_cad_cliente_scope_permission(
    v_created_by,
    'cadastros.clientes.deactivate.own',
    'cadastros.clientes.deactivate.any'
  );
  v_actor := public.current_actor_id();

  update public.cad_clientes
     set status = 'inactive',
         updated_by = v_actor
   where id = p_cliente_id;

  select to_jsonb(c)
    into v_after
    from public.cad_clientes c
   where c.id = p_cliente_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_clientes',
    p_cliente_id::text,
    'cadastros.cliente_deactivated',
    v_action_key,
    'success',
    v_before,
    v_after,
    jsonb_build_object(
      'alcada_usada', v_action_key,
      'scope', case when v_action_key = 'cadastros.clientes.deactivate.own' then 'own' else 'any' end,
      'owned_by_actor', v_created_by = v_actor
    ),
    'database_rpc',
    jsonb_build_object('source', 'deactivate_cad_cliente', 'motivo', trim(p_motivo))
  );

  return p_cliente_id;
end;
$$;

revoke all on function public.deactivate_cad_cliente(bigint, text) from public;
grant execute on function public.deactivate_cad_cliente(bigint, text) to authenticated;
