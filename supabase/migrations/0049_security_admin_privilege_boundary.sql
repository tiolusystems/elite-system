-- Security administration is an explicit privilege boundary.
-- Operational autonomy never grants user, permission, or runtime administration.

update public.permission_actions
   set default_allowed = false
 where action_key in (
   'system.admin',
   'security.manage_users',
   'security.manage_permissions',
   'security.email_change.review'
 );

-- Preserve access for administrators that existed before this default-deny
-- migration. New administrators must receive explicit grants through the
-- governed permission UI.
insert into public.user_permission_overrides(
  user_id,
  action_key,
  allowed,
  updated_by
)
select
  profile.id,
  critical_action.action_key,
  true,
  profile.id
from public.user_profiles profile
cross join (
  values
    ('system.admin'::text),
    ('security.manage_users'::text),
    ('security.manage_permissions'::text),
    ('security.email_change.review'::text)
) critical_action(action_key)
where profile.role = 'admin'
  and profile.status = 'active'
  and not coalesce(profile.is_system_actor, false)
on conflict (user_id, action_key) do nothing;

create or replace function public.security_admin_has_core_grants(
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.user_profiles profile
     where profile.id = p_user_id
       and profile.role = 'admin'
       and profile.status = 'active'
       and not coalesce(profile.is_system_actor, false)
       and not exists (
         select 1
           from (
             values
               ('system.admin'::text),
               ('security.manage_users'::text),
               ('security.manage_permissions'::text),
               ('security.email_change.review'::text)
           ) critical_action(action_key)
           left join public.permission_actions action
             on action.action_key = critical_action.action_key
           left join public.user_permission_overrides override_row
             on override_row.user_id = profile.id
            and override_row.action_key = critical_action.action_key
          where not coalesce(override_row.allowed, action.default_allowed, false)
       )
  );
$$;

create or replace function public.require_current_user_security_admin(
  p_action_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := public.current_actor_id();
  if v_actor is null then
    raise exception 'active user profile required';
  end if;

  if not exists (
    select 1
      from public.user_profiles profile
     where profile.id = v_actor
       and profile.role = 'admin'
       and profile.status = 'active'
       and not coalesce(profile.is_system_actor, false)
  ) then
    raise exception 'system administrator role required';
  end if;

  perform public.require_current_user_permission(p_action_key);
  return v_actor;
end;
$$;

comment on function public.require_current_user_security_admin(text) is
  'Requires both an active human admin role and the explicit requested action permission.';

-- Keep the 0048 helper name as a compatibility boundary while centralizing
-- the role and permission rule in one function.
create or replace function public.require_current_user_admin_role()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.require_current_user_security_admin('security.email_change.review');
end;
$$;

-- Preserve the mature audited implementations and place an administrator
-- boundary in front of every public entry point.
alter function public.upsert_security_user_profile(uuid, text, text, text)
  rename to upsert_security_user_profile_impl_0049;
alter function public.set_security_permission_override(uuid, text, boolean)
  rename to set_security_permission_override_impl_0049;
alter function public.clear_security_permission_override(uuid, text)
  rename to clear_security_permission_override_impl_0049;
alter function public.authorize_security_auth_user_provision(text, text, text, text)
  rename to authorize_security_auth_user_provision_impl_0049;
alter function public.record_security_auth_user_invitation_sent(uuid, text)
  rename to record_security_auth_user_invitation_sent_impl_0049;
alter function public.list_security_user_profiles()
  rename to list_security_user_profiles_impl_0049;
alter function public.list_security_effective_permissions(uuid)
  rename to list_security_effective_permissions_impl_0049;
alter function public.set_system_runtime_environment(text, text, text)
  rename to set_system_runtime_environment_impl_0049;
alter function public.set_system_module_rollout(text, text, text, text, text, text)
  rename to set_system_module_rollout_impl_0049;

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
  v_role text;
  v_status text;
  v_existing_role text;
begin
  perform public.require_current_user_security_admin('security.manage_users');

  v_role := lower(coalesce(nullif(trim(p_role), ''), 'comercial'));
  v_status := lower(coalesce(nullif(trim(p_status), ''), 'active'));

  select profile.role
    into v_existing_role
    from public.user_profiles profile
   where profile.id = p_user_id;

  if v_role = 'admin' or v_existing_role = 'admin' then
    perform public.require_current_user_security_admin('security.manage_permissions');
  end if;

  if public.security_admin_has_core_grants(p_user_id)
     and (v_role <> 'admin' or v_status <> 'active')
     and not exists (
       select 1
         from public.user_profiles profile
        where profile.id <> p_user_id
          and public.security_admin_has_core_grants(profile.id)
     ) then
    raise exception 'last capable system administrator cannot be demoted or deactivated';
  end if;

  return public.upsert_security_user_profile_impl_0049(
    p_user_id,
    p_display_name,
    p_role,
    p_status
  );
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
  v_action_key text;
begin
  perform public.require_current_user_security_admin('security.manage_permissions');
  v_action_key := nullif(trim(p_action_key), '');

  if v_action_key in (
       'system.admin',
       'security.manage_users',
       'security.manage_permissions',
       'security.email_change.review'
     )
     and p_allowed is false
     and public.security_admin_has_core_grants(p_user_id)
     and not exists (
       select 1
         from public.user_profiles profile
        where profile.id <> p_user_id
          and public.security_admin_has_core_grants(profile.id)
     ) then
    raise exception 'last capable system administrator must retain core grants';
  end if;

  return public.set_security_permission_override_impl_0049(
    p_user_id,
    p_action_key,
    p_allowed
  );
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
  v_action_key text;
begin
  perform public.require_current_user_security_admin('security.manage_permissions');
  v_action_key := nullif(trim(p_action_key), '');

  if v_action_key in (
       'system.admin',
       'security.manage_users',
       'security.manage_permissions',
       'security.email_change.review'
     )
     and public.security_admin_has_core_grants(p_user_id)
     and not exists (
       select 1
         from public.user_profiles profile
        where profile.id <> p_user_id
          and public.security_admin_has_core_grants(profile.id)
     ) then
    raise exception 'last capable system administrator must retain core grants';
  end if;

  return public.clear_security_permission_override_impl_0049(
    p_user_id,
    p_action_key
  );
end;
$$;

create or replace function public.authorize_security_auth_user_provision(
  p_email text,
  p_display_name text,
  p_role text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_users');
  if lower(nullif(trim(p_role), '')) = 'admin' then
    perform public.require_current_user_security_admin('security.manage_permissions');
  end if;

  return public.authorize_security_auth_user_provision_impl_0049(
    p_email,
    p_display_name,
    p_role,
    p_status
  );
end;
$$;

create or replace function public.record_security_auth_user_invitation_sent(
  p_user_id uuid,
  p_email text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_users');
  return public.record_security_auth_user_invitation_sent_impl_0049(p_user_id, p_email);
end;
$$;

create or replace function public.list_security_user_profiles()
returns table (
  id uuid,
  display_name text,
  role text,
  status text,
  is_system_actor boolean,
  system_actor_key text,
  overrides_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_users');
  return query select * from public.list_security_user_profiles_impl_0049();
end;
$$;

create or replace function public.list_security_effective_permissions(
  p_user_id uuid
)
returns table (
  action_key text,
  module text,
  description text,
  default_allowed boolean,
  override_allowed boolean,
  effective_allowed boolean,
  sort_order integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_permissions');
  return query select * from public.list_security_effective_permissions_impl_0049(p_user_id);
end;
$$;

create or replace function public.set_system_runtime_environment(
  p_environment text,
  p_reason_code text,
  p_reason_detail text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('system.admin');
  return public.set_system_runtime_environment_impl_0049(
    p_environment,
    p_reason_code,
    p_reason_detail
  );
end;
$$;

create or replace function public.set_system_module_rollout(
  p_environment text,
  p_module_key text,
  p_lifecycle text,
  p_access_mode text,
  p_reason_code text,
  p_reason_detail text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('system.admin');
  return public.set_system_module_rollout_impl_0049(
    p_environment,
    p_module_key,
    p_lifecycle,
    p_access_mode,
    p_reason_code,
    p_reason_detail
  );
end;
$$;

-- A fresh database has no administrator during migrations. The one-time
-- service-role bootstrap must therefore grant the four explicit capabilities
-- together with the first human admin profile.
create or replace function public.bootstrap_first_system_admin(
  p_user_id uuid,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text;
  v_result jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required for first administrator bootstrap';
  end if;

  if p_user_id is null then
    raise exception 'user id is required';
  end if;

  v_display_name := nullif(trim(p_display_name), '');
  if v_display_name is null or char_length(v_display_name) > 160 then
    raise exception 'display name must contain between 1 and 160 characters';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('elite:first-system-admin-bootstrap', 0));

  if exists (
    select 1
      from public.user_profiles profile
     where not profile.is_system_actor
  ) then
    raise exception 'first administrator bootstrap already closed';
  end if;

  if not exists (
    select 1
      from auth.users auth_user
     where auth_user.id = p_user_id
  ) then
    raise exception 'auth user not found';
  end if;

  insert into public.user_profiles(
    id,
    display_name,
    role,
    status,
    is_system_actor,
    system_actor_key
  ) values (
    p_user_id,
    v_display_name,
    'admin',
    'active',
    false,
    null
  );

  insert into public.user_permission_overrides(
    user_id,
    action_key,
    allowed,
    updated_by
  )
  select
    p_user_id,
    critical_action.action_key,
    true,
    p_user_id
  from (
    values
      ('system.admin'::text),
      ('security.manage_users'::text),
      ('security.manage_permissions'::text),
      ('security.email_change.review'::text)
  ) critical_action(action_key);

  select jsonb_build_object(
    'user_id', profile.id,
    'display_name', profile.display_name,
    'role', profile.role,
    'status', profile.status,
    'is_system_actor', profile.is_system_actor,
    'core_admin_grants', true
  )
    into v_result
    from public.user_profiles profile
   where profile.id = p_user_id;

  perform public.log_action(
    'seguranca.first_system_admin_bootstrapped',
    'user_profiles',
    p_user_id::text,
    'success',
    null,
    v_result,
    jsonb_build_object(
      'source', 'service_role_bootstrap',
      'bootstrap_once', true,
      'contains_credentials', false,
      'core_admin_grants', true
    )
  );

  return v_result;
end;
$$;

comment on function public.bootstrap_first_system_admin(uuid, text) is
  'Creates the first human admin exactly once with explicit core grants. Requires service_role.';

revoke all on function public.security_admin_has_core_grants(uuid) from public;
revoke all on function public.require_current_user_security_admin(text) from public;
revoke all on function public.require_current_user_admin_role() from public;
revoke all on function public.security_user_profile_snapshot(uuid) from authenticated;
revoke all on function public.security_user_profile_snapshot(uuid) from anon;
revoke all on function public.record_security_auth_user_temp_password_sent(uuid, text) from authenticated;
revoke all on function public.record_security_auth_user_temp_password_sent(uuid, text) from anon;

revoke all on function public.upsert_security_user_profile_impl_0049(uuid, text, text, text) from public;
revoke all on function public.set_security_permission_override_impl_0049(uuid, text, boolean) from public;
revoke all on function public.clear_security_permission_override_impl_0049(uuid, text) from public;
revoke all on function public.authorize_security_auth_user_provision_impl_0049(text, text, text, text) from public;
revoke all on function public.record_security_auth_user_invitation_sent_impl_0049(uuid, text) from public;
revoke all on function public.list_security_user_profiles_impl_0049() from public;
revoke all on function public.list_security_effective_permissions_impl_0049(uuid) from public;
revoke all on function public.set_system_runtime_environment_impl_0049(text, text, text) from public;
revoke all on function public.set_system_module_rollout_impl_0049(text, text, text, text, text, text) from public;

revoke all on function public.upsert_security_user_profile_impl_0049(uuid, text, text, text) from authenticated;
revoke all on function public.set_security_permission_override_impl_0049(uuid, text, boolean) from authenticated;
revoke all on function public.clear_security_permission_override_impl_0049(uuid, text) from authenticated;
revoke all on function public.authorize_security_auth_user_provision_impl_0049(text, text, text, text) from authenticated;
revoke all on function public.record_security_auth_user_invitation_sent_impl_0049(uuid, text) from authenticated;
revoke all on function public.list_security_user_profiles_impl_0049() from authenticated;
revoke all on function public.list_security_effective_permissions_impl_0049(uuid) from authenticated;
revoke all on function public.set_system_runtime_environment_impl_0049(text, text, text) from authenticated;
revoke all on function public.set_system_module_rollout_impl_0049(text, text, text, text, text, text) from authenticated;

revoke all on function public.upsert_security_user_profile(uuid, text, text, text) from public;
revoke all on function public.set_security_permission_override(uuid, text, boolean) from public;
revoke all on function public.clear_security_permission_override(uuid, text) from public;
revoke all on function public.authorize_security_auth_user_provision(text, text, text, text) from public;
revoke all on function public.record_security_auth_user_invitation_sent(uuid, text) from public;
revoke all on function public.list_security_user_profiles() from public;
revoke all on function public.list_security_effective_permissions(uuid) from public;
revoke all on function public.set_system_runtime_environment(text, text, text) from public;
revoke all on function public.set_system_module_rollout(text, text, text, text, text, text) from public;
revoke all on function public.bootstrap_first_system_admin(uuid, text) from public;

grant execute on function public.upsert_security_user_profile(uuid, text, text, text) to authenticated;
grant execute on function public.set_security_permission_override(uuid, text, boolean) to authenticated;
grant execute on function public.clear_security_permission_override(uuid, text) to authenticated;
grant execute on function public.authorize_security_auth_user_provision(text, text, text, text) to authenticated;
grant execute on function public.record_security_auth_user_invitation_sent(uuid, text) to authenticated;
grant execute on function public.list_security_user_profiles() to authenticated;
grant execute on function public.list_security_effective_permissions(uuid) to authenticated;
grant execute on function public.set_system_runtime_environment(text, text, text) to authenticated;
grant execute on function public.set_system_module_rollout(text, text, text, text, text, text) to authenticated;
grant execute on function public.bootstrap_first_system_admin(uuid, text) to service_role;

comment on function public.upsert_security_user_profile(uuid, text, text, text) is
  'Admin-only wrapper. Promotion or management of an admin additionally requires manage_permissions.';
comment on function public.set_security_permission_override(uuid, text, boolean) is
  'Admin-only wrapper that preserves at least one capable administrator.';
comment on function public.clear_security_permission_override(uuid, text) is
  'Admin-only wrapper that preserves at least one capable administrator.';
