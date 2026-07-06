revoke insert, update, delete on public.user_profiles from authenticated;
revoke insert, update, delete on public.permission_actions from authenticated;
revoke insert, update, delete on public.user_permission_overrides from authenticated;

grant select on public.user_profiles to authenticated;
grant select on public.permission_actions to authenticated;
grant select on public.user_permission_overrides to authenticated;

create or replace function public.security_user_profile_snapshot(
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile jsonb;
  v_overrides jsonb;
begin
  select to_jsonb(profile)
    into v_profile
    from public.user_profiles profile
   where profile.id = p_user_id;

  if v_profile is null then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'action_key', override_row.action_key,
      'allowed', override_row.allowed,
      'updated_by', override_row.updated_by,
      'updated_at', override_row.updated_at
    )
    order by override_row.action_key
  ), '[]'::jsonb)
    into v_overrides
    from public.user_permission_overrides override_row
   where override_row.user_id = p_user_id;

  return jsonb_build_object(
    'profile', v_profile,
    'permission_overrides', v_overrides
  );
end;
$$;

create or replace function public.upsert_security_user_profile(
  p_user_id uuid,
  p_display_name text,
  p_role text default 'comercial',
  p_status text default 'active'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_role text;
  v_status text;
  v_before jsonb;
  v_after jsonb;
  v_existing_system_actor boolean := false;
begin
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;
  if nullif(trim(p_display_name), '') is null then
    raise exception 'display_name is required';
  end if;

  v_role := lower(coalesce(nullif(trim(p_role), ''), 'comercial'));
  v_status := lower(coalesce(nullif(trim(p_status), ''), 'active'));

  if v_role not in ('admin', 'comercial', 'producao', 'estoque', 'expedicao', 'auditoria') then
    raise exception 'invalid user role';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'invalid user status';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'auth user must exist before creating profile';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'user_profiles',
    'change_type',
    jsonb_build_object('event', 'user_profile_upsert')
  );

  select public.security_user_profile_snapshot(p_user_id)
    into v_before;

  select coalesce(profile.is_system_actor, false)
    into v_existing_system_actor
    from public.user_profiles profile
   where profile.id = p_user_id
   for update;

  if coalesce(v_existing_system_actor, false) then
    raise exception 'system actor profile cannot be managed by user profile RPC';
  end if;

  v_actor := public.current_actor_id();

  insert into public.user_profiles(
    id,
    display_name,
    role,
    status,
    is_system_actor,
    system_actor_key
  )
  values (
    p_user_id,
    trim(p_display_name),
    v_role,
    v_status,
    false,
    null
  )
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = false,
    system_actor_key = null;

  select public.security_user_profile_snapshot(p_user_id)
    into v_after;

  perform public.log_audited_rpc_change(
    'seguranca',
    'user_profiles',
    p_user_id::text,
    'seguranca.user_profile_upserted',
    'security.manage_users',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'upsert_security_user_profile',
      'target_user_id', p_user_id,
      'display_name', trim(p_display_name),
      'role', v_role,
      'status', v_status,
      'changed_by', v_actor
    )
  );

  return p_user_id;
end;
$$;

create or replace function public.set_security_permission_override(
  p_user_id uuid,
  p_action_key text,
  p_allowed boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_action_key text;
  v_before jsonb;
  v_after jsonb;
  v_is_system_actor boolean;
begin
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;
  if p_allowed is null then
    raise exception 'allowed is required';
  end if;

  v_action_key := nullif(trim(p_action_key), '');
  if v_action_key is null then
    raise exception 'action_key is required';
  end if;
  if not exists (select 1 from public.permission_actions where action_key = v_action_key) then
    raise exception 'permission action not found';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.manage_permissions',
    'seguranca',
    'user_permission_overrides',
    'change_type',
    jsonb_build_object('event', 'permission_override_set', 'target_action_key', v_action_key)
  );

  select profile.is_system_actor
    into v_is_system_actor
    from public.user_profiles profile
   where profile.id = p_user_id
   for update;

  if not found then
    raise exception 'target user profile not found';
  end if;
  if coalesce(v_is_system_actor, false) then
    raise exception 'system actor permissions cannot be changed by override RPC';
  end if;

  select to_jsonb(override_row)
    into v_before
    from public.user_permission_overrides override_row
   where override_row.user_id = p_user_id
     and override_row.action_key = v_action_key
   for update;

  v_actor := public.current_actor_id();

  insert into public.user_permission_overrides(
    user_id,
    action_key,
    allowed,
    updated_by
  )
  values (
    p_user_id,
    v_action_key,
    p_allowed,
    v_actor
  )
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  select to_jsonb(override_row)
    into v_after
    from public.user_permission_overrides override_row
   where override_row.user_id = p_user_id
     and override_row.action_key = v_action_key;

  perform public.log_audited_rpc_change(
    'seguranca',
    'user_permission_overrides',
    concat(p_user_id::text, ':', v_action_key),
    'seguranca.permission_override_set',
    'security.manage_permissions',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'set_security_permission_override',
      'target_user_id', p_user_id,
      'target_action_key', v_action_key,
      'allowed', p_allowed,
      'changed_by', v_actor
    )
  );

  return p_user_id;
end;
$$;

create or replace function public.clear_security_permission_override(
  p_user_id uuid,
  p_action_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_action_key text;
  v_before jsonb;
  v_removed boolean := false;
  v_removed_count integer := 0;
  v_is_system_actor boolean;
begin
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;

  v_action_key := nullif(trim(p_action_key), '');
  if v_action_key is null then
    raise exception 'action_key is required';
  end if;
  if not exists (select 1 from public.permission_actions where action_key = v_action_key) then
    raise exception 'permission action not found';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.manage_permissions',
    'seguranca',
    'user_permission_overrides',
    'change_type',
    jsonb_build_object('event', 'permission_override_clear', 'target_action_key', v_action_key)
  );

  select profile.is_system_actor
    into v_is_system_actor
    from public.user_profiles profile
   where profile.id = p_user_id
   for update;

  if not found then
    raise exception 'target user profile not found';
  end if;
  if coalesce(v_is_system_actor, false) then
    raise exception 'system actor permissions cannot be changed by override RPC';
  end if;

  select to_jsonb(override_row)
    into v_before
    from public.user_permission_overrides override_row
   where override_row.user_id = p_user_id
     and override_row.action_key = v_action_key
   for update;

  v_actor := public.current_actor_id();

  delete from public.user_permission_overrides
   where user_id = p_user_id
     and action_key = v_action_key;

  get diagnostics v_removed_count = row_count;
  v_removed := v_removed_count > 0;

  perform public.log_audited_rpc_change(
    'seguranca',
    'user_permission_overrides',
    concat(p_user_id::text, ':', v_action_key),
    'seguranca.permission_override_cleared',
    'security.manage_permissions',
    v_permission_context,
    v_before,
    null,
    jsonb_build_object(
      'source', 'clear_security_permission_override',
      'target_user_id', p_user_id,
      'target_action_key', v_action_key,
      'removed', v_removed,
      'changed_by', v_actor
    )
  );

  return p_user_id;
end;
$$;

revoke all on function public.security_user_profile_snapshot(uuid) from public;
revoke all on function public.upsert_security_user_profile(uuid, text, text, text) from public;
revoke all on function public.set_security_permission_override(uuid, text, boolean) from public;
revoke all on function public.clear_security_permission_override(uuid, text) from public;

grant execute on function public.security_user_profile_snapshot(uuid) to authenticated;
grant execute on function public.upsert_security_user_profile(uuid, text, text, text) to authenticated;
grant execute on function public.set_security_permission_override(uuid, text, boolean) to authenticated;
grant execute on function public.clear_security_permission_override(uuid, text) to authenticated;
