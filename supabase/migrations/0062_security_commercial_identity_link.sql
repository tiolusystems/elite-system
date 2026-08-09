-- Security owns the audited relationship between a human login and a
-- commercial person. Business roles never grant authentication privileges.

create or replace function public.list_security_commercial_identity_links()
returns table (
  pessoa_id bigint,
  pessoa_nome text,
  pessoa_status text,
  user_profile_id uuid,
  user_display_name text,
  user_role text,
  user_status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_users');

  return query
  select
    pessoa.id,
    pessoa.nome,
    pessoa.status,
    pessoa.user_profile_id,
    profile.display_name,
    profile.role,
    profile.status
  from public.cad_pessoas_comerciais pessoa
  left join public.user_profiles profile on profile.id = pessoa.user_profile_id
  order by pessoa.nome, pessoa.id;
end;
$$;

create or replace function public.link_security_commercial_identity(
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
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_existing_user_id uuid;
begin
  perform public.require_current_user_security_admin('security.manage_users');
  perform public.require_current_user_security_admin('security.manage_permissions');

  if p_user_id is null or p_pessoa_id is null then
    raise exception 'user_id and pessoa_id are required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;
  if not exists (
    select 1 from public.user_profiles profile
    where profile.id = p_user_id
      and not coalesce(profile.is_system_actor, false)
  ) then
    raise exception 'operational user profile not found';
  end if;

  select pessoa.user_profile_id
    into v_existing_user_id
    from public.cad_pessoas_comerciais pessoa
   where pessoa.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'commercial person not found';
  end if;
  if v_existing_user_id is not null and v_existing_user_id <> p_user_id then
    raise exception 'commercial person already linked to another user';
  end if;
  if exists (
    select 1
      from public.cad_pessoas_comerciais pessoa
     where pessoa.user_profile_id = p_user_id
       and pessoa.id <> p_pessoa_id
  ) then
    raise exception 'user already linked to another commercial person';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'cad_pessoas_comerciais',
    'change_type',
    jsonb_build_object(
      'event', 'commercial_identity_link',
      'secondary_permission', 'security.manage_permissions'
    )
  );
  v_actor := public.current_actor_id();

  select jsonb_build_object(
    'pessoa_id', pessoa.id,
    'pessoa_nome', pessoa.nome,
    'user_profile_id', pessoa.user_profile_id
  ) into v_before
  from public.cad_pessoas_comerciais pessoa
  where pessoa.id = p_pessoa_id;

  update public.cad_pessoas_comerciais
     set user_profile_id = p_user_id,
         updated_by = v_actor,
         updated_at = now()
   where id = p_pessoa_id;

  select jsonb_build_object(
    'pessoa_id', pessoa.id,
    'pessoa_nome', pessoa.nome,
    'user_profile_id', pessoa.user_profile_id
  ) into v_after
  from public.cad_pessoas_comerciais pessoa
  where pessoa.id = p_pessoa_id;

  perform public.log_audited_rpc_change(
    'seguranca',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'seguranca.identidade_comercial_vinculada',
    'security.manage_users',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'link_security_commercial_identity',
      'target_user_id', p_user_id,
      'motivo', trim(p_motivo),
      'secondary_permission', 'security.manage_permissions'
    )
  );

  return p_pessoa_id;
end;
$$;

create or replace function public.unlink_security_commercial_identity(
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
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  perform public.require_current_user_security_admin('security.manage_users');
  perform public.require_current_user_security_admin('security.manage_permissions');

  if p_user_id is null or p_pessoa_id is null then
    raise exception 'user_id and pessoa_id are required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  perform 1
    from public.cad_pessoas_comerciais pessoa
   where pessoa.id = p_pessoa_id
     and pessoa.user_profile_id = p_user_id
   for update;

  if not found then
    raise exception 'commercial identity link not found';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'cad_pessoas_comerciais',
    'change_type',
    jsonb_build_object(
      'event', 'commercial_identity_unlink',
      'secondary_permission', 'security.manage_permissions'
    )
  );
  v_actor := public.current_actor_id();

  select jsonb_build_object(
    'pessoa_id', pessoa.id,
    'pessoa_nome', pessoa.nome,
    'user_profile_id', pessoa.user_profile_id
  ) into v_before
  from public.cad_pessoas_comerciais pessoa
  where pessoa.id = p_pessoa_id;

  update public.cad_pessoas_comerciais
     set user_profile_id = null,
         updated_by = v_actor,
         updated_at = now()
   where id = p_pessoa_id
     and user_profile_id = p_user_id;

  select jsonb_build_object(
    'pessoa_id', pessoa.id,
    'pessoa_nome', pessoa.nome,
    'user_profile_id', pessoa.user_profile_id
  ) into v_after
  from public.cad_pessoas_comerciais pessoa
  where pessoa.id = p_pessoa_id;

  perform public.log_audited_rpc_change(
    'seguranca',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'seguranca.identidade_comercial_desvinculada',
    'security.manage_users',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'unlink_security_commercial_identity',
      'target_user_id', p_user_id,
      'motivo', trim(p_motivo),
      'secondary_permission', 'security.manage_permissions'
    )
  );

  return p_pessoa_id;
end;
$$;

revoke all on function public.list_security_commercial_identity_links() from public;

revoke all on function public.list_security_commercial_identity_links() from anon;

revoke all on function public.link_security_commercial_identity(uuid, bigint, text) from public;

revoke all on function public.link_security_commercial_identity(uuid, bigint, text) from anon;

revoke all on function public.unlink_security_commercial_identity(uuid, bigint, text) from public;

revoke all on function public.unlink_security_commercial_identity(uuid, bigint, text) from anon;

grant execute on function public.list_security_commercial_identity_links() to authenticated;

grant execute on function public.link_security_commercial_identity(uuid, bigint, text) to authenticated;

grant execute on function public.unlink_security_commercial_identity(uuid, bigint, text) to authenticated;

comment on function public.link_security_commercial_identity(uuid, bigint, text) is
  'Security-owned audited link between an Auth profile and a commercial person. Requires user and permission administration grants.';

comment on function public.unlink_security_commercial_identity(uuid, bigint, text) is
  'Security-owned audited unlink between an Auth profile and a commercial person. Business roles remain unchanged.';
