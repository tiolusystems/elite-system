-- Govern the two relational links required by seller-scoped order creation.
-- Identity remains owned by Security; the customer portfolio remains owned by Cadastros.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  (
    'security.identity.person.link',
    'seguranca',
    'Vincular conta a pessoa comercial',
    false,
    44,
    'seguranca',
    'write'
  ),
  (
    'cadastros.clientes.commercial_links.manage',
    'cadastros',
    'Gerenciar responsaveis comerciais do cliente',
    false,
    188,
    'cadastros',
    'write'
  )
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = false,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.link_security_user_commercial_person(
  p_user_id uuid,
  p_pessoa_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_profile_status text;
  v_is_system_actor boolean;
  v_existing_person_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'security.identity.person.link',
    'seguranca',
    'cad_pessoas_comerciais',
    'change_type',
    jsonb_build_object(
      'correlation_id',
      'security_identity:' || coalesce(p_user_id::text, 'null') || ':' || coalesce(p_pessoa_id::text, 'null')
    )
  );

  if p_user_id is null or p_pessoa_id is null then
    raise exception 'user_id and pessoa_id are required';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('security_identity:user:' || p_user_id::text, 0)
  );
  perform pg_advisory_xact_lock(
    hashtextextended('security_identity:person:' || p_pessoa_id::text, 0)
  );

  select profile.status, profile.is_system_actor
    into v_profile_status, v_is_system_actor
    from public.user_profiles profile
   where profile.id = p_user_id
   for update;

  if not found then
    raise exception 'target user profile not found';
  end if;
  if coalesce(v_is_system_actor, false) then
    raise exception 'system actor cannot be linked to a commercial person';
  end if;
  if v_profile_status <> 'active' then
    raise exception 'target user profile is not active';
  end if;

  select to_jsonb(person)
    into v_before
    from public.cad_pessoas_comerciais person
   where person.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'commercial person not found';
  end if;
  if v_before->>'status' <> 'active' then
    raise exception 'commercial person is not active';
  end if;

  select person.id
    into v_existing_person_id
    from public.cad_pessoas_comerciais person
   where person.user_profile_id = p_user_id
   for update;

  if v_existing_person_id is not null and v_existing_person_id <> p_pessoa_id then
    raise exception 'target user profile is already linked to another commercial person';
  end if;
  if v_before->>'user_profile_id' = p_user_id::text then
    return p_pessoa_id;
  end if;
  if v_before->>'user_profile_id' is not null then
    raise exception 'commercial person is already linked to another user profile';
  end if;

  v_actor := public.current_actor_id();
  update public.cad_pessoas_comerciais
     set user_profile_id = p_user_id,
         updated_by = v_actor,
         updated_at = now()
   where id = p_pessoa_id;

  select to_jsonb(person)
    into v_after
    from public.cad_pessoas_comerciais person
   where person.id = p_pessoa_id;

  perform public.log_audited_rpc_change(
    'seguranca',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'seguranca.conta_pessoa_vinculada',
    'security.identity.person.link',
    v_context,
    v_before,
    v_after,
    jsonb_build_object(
      'motivo', btrim(p_motivo),
      'user_profile_id', p_user_id,
      'source', 'link_security_user_commercial_person'
    ),
    'database_rpc'
  );

  return p_pessoa_id;
end;
$$;

create or replace function public.link_cad_cliente_commercial_person(
  p_cliente_id bigint,
  p_pessoa_id bigint,
  p_papel_vinculo_id bigint,
  p_propriedade_id bigint,
  p_vigencia_inicio date,
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
  v_after jsonb;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.clientes.commercial_links.manage',
    'cadastros',
    'cad_cliente_vendedores',
    'change_type',
    jsonb_build_object(
      'correlation_id',
      'cliente:' || coalesce(p_cliente_id::text, 'null') ||
      ':pessoa:' || coalesce(p_pessoa_id::text, 'null') ||
      ':papel:' || coalesce(p_papel_vinculo_id::text, 'null')
    )
  );

  if p_cliente_id is null or p_pessoa_id is null or p_papel_vinculo_id is null then
    raise exception 'cliente_id, pessoa_id and papel_vinculo_id are required';
  end if;
  if p_vigencia_inicio is null then
    raise exception 'start date is required';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'cliente_commercial_link:' || p_cliente_id::text || ':' ||
      p_pessoa_id::text || ':' || p_papel_vinculo_id::text || ':' ||
      coalesce(p_propriedade_id::text, '0'),
      0
    )
  );

  perform 1
    from public.cad_clientes client
   where client.id = p_cliente_id
     and client.status = 'active'
   for update;
  if not found then
    raise exception 'active client not found';
  end if;

  perform 1
    from public.cad_pessoas_comerciais person
   where person.id = p_pessoa_id
     and person.status = 'active'
   for update;
  if not found then
    raise exception 'active commercial person not found';
  end if;

  perform 1
    from public.cad_cliente_vinculo_papeis role_catalog
   where role_catalog.id = p_papel_vinculo_id
     and role_catalog.status = 'active'
   for update;
  if not found then
    raise exception 'active client link role not found';
  end if;

  if p_propriedade_id is not null and not exists (
    select 1
      from public.cad_cliente_propriedades property
     where property.id = p_propriedade_id
       and property.cliente_id = p_cliente_id
       and property.status = 'active'
  ) then
    raise exception 'active client property not found';
  end if;

  v_actor := public.current_actor_id();
  insert into public.cad_cliente_vendedores(
    cliente_id,
    pessoa_id,
    papel_vinculo_id,
    propriedade_id,
    status,
    vigencia_inicio,
    vigencia_fim,
    origem_dados,
    created_by,
    updated_by
  )
  values (
    p_cliente_id,
    p_pessoa_id,
    p_papel_vinculo_id,
    p_propriedade_id,
    'active',
    p_vigencia_inicio,
    null,
    'sistema',
    v_actor,
    v_actor
  )
  returning id into v_id;

  select to_jsonb(link)
    into v_after
    from public.cad_cliente_vendedores link
   where link.id = v_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_cliente_vendedores',
    v_id::text,
    'cadastros.cliente_responsavel_vinculado',
    'cadastros.clientes.commercial_links.manage',
    v_context,
    null,
    v_after,
    jsonb_build_object(
      'motivo', btrim(p_motivo),
      'source', 'link_cad_cliente_commercial_person'
    ),
    'database_rpc'
  );

  return v_id;
end;
$$;

create or replace function public.close_cad_cliente_commercial_person(
  p_vinculo_id bigint,
  p_vigencia_fim date,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_start date;
  v_status text;
  v_before jsonb;
  v_after jsonb;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.clientes.commercial_links.manage',
    'cadastros',
    'cad_cliente_vendedores',
    'status_transition',
    jsonb_build_object(
      'correlation_id',
      'cliente_commercial_link:' || coalesce(p_vinculo_id::text, 'null') || ':close'
    )
  );

  if p_vinculo_id is null or p_vigencia_fim is null then
    raise exception 'vinculo_id and end date are required';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;

  select to_jsonb(link), link.vigencia_inicio, link.status
    into v_before, v_start, v_status
    from public.cad_cliente_vendedores link
   where link.id = p_vinculo_id
   for update;

  if not found then
    raise exception 'client commercial link not found';
  end if;
  if v_status <> 'active' then
    raise exception 'client commercial link is not active';
  end if;
  if v_start is not null and p_vigencia_fim < v_start then
    raise exception 'end date cannot precede start date';
  end if;

  v_actor := public.current_actor_id();
  update public.cad_cliente_vendedores
     set status = 'inactive',
         vigencia_fim = p_vigencia_fim,
         updated_by = v_actor,
         updated_at = now()
   where id = p_vinculo_id;

  select to_jsonb(link)
    into v_after
    from public.cad_cliente_vendedores link
   where link.id = p_vinculo_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_cliente_vendedores',
    p_vinculo_id::text,
    'cadastros.cliente_responsavel_encerrado',
    'cadastros.clientes.commercial_links.manage',
    v_context,
    v_before,
    v_after,
    jsonb_build_object(
      'motivo', btrim(p_motivo),
      'history_preserved', true,
      'source', 'close_cad_cliente_commercial_person'
    ),
    'database_rpc'
  );

  return p_vinculo_id;
end;
$$;

revoke all on function public.link_security_user_commercial_person(uuid, bigint, text)
  from public, anon;
revoke all on function public.link_cad_cliente_commercial_person(bigint, bigint, bigint, bigint, date, text)
  from public, anon;
revoke all on function public.close_cad_cliente_commercial_person(bigint, date, text)
  from public, anon;

grant execute on function public.link_security_user_commercial_person(uuid, bigint, text)
  to authenticated;
grant execute on function public.link_cad_cliente_commercial_person(bigint, bigint, bigint, bigint, date, text)
  to authenticated;
grant execute on function public.close_cad_cliente_commercial_person(bigint, date, text)
  to authenticated;

revoke insert, update, delete, truncate on public.cad_pessoas_comerciais
  from public, anon, authenticated;
revoke insert, update, delete, truncate on public.cad_cliente_vendedores
  from public, anon, authenticated;

comment on function public.link_security_user_commercial_person(uuid, bigint, text) is
  'Links one active human account to one active commercial person through an individually authorized audited RPC.';
comment on function public.link_cad_cliente_commercial_person(bigint, bigint, bigint, bigint, date, text) is
  'Creates an audited temporal customer-commercial-person link using governed relationship IDs.';
comment on function public.close_cad_cliente_commercial_person(bigint, date, text) is
  'Closes a customer-commercial-person link without deleting its historical record.';
