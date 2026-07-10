-- One-time bootstrap for the first human administrator.
-- This is the only operational write allowed before an authenticated profile exists.

-- Complete index coverage for the foreign keys introduced by the module runtime.
create index if not exists idx_sys_runtime_environment_actor
  on public.sys_runtime_environment_events(actor_id)
  where actor_id is not null;
create index if not exists idx_sys_module_rollout_actor
  on public.sys_module_rollout_events(actor_id)
  where actor_id is not null;
create index if not exists idx_sys_module_rollout_module
  on public.sys_module_rollout_events(module_key, environment, id desc);

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
  -- Check the trusted caller before reading any security state.
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

  select jsonb_build_object(
    'user_id', profile.id,
    'display_name', profile.display_name,
    'role', profile.role,
    'status', profile.status,
    'is_system_actor', profile.is_system_actor
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
      'contains_credentials', false
    )
  );

  return v_result;
end;
$$;

comment on function public.bootstrap_first_system_admin(uuid, text) is
  'Creates the first human admin exactly once. Requires service_role and logs no email or credential.';

revoke all on function public.bootstrap_first_system_admin(uuid, text) from public;
revoke all on function public.bootstrap_first_system_admin(uuid, text) from anon;
revoke all on function public.bootstrap_first_system_admin(uuid, text) from authenticated;
grant execute on function public.bootstrap_first_system_admin(uuid, text) to service_role;
