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
  perform public.require_current_user_permission('security.manage_users');

  return query
  select
    profile.id,
    profile.display_name,
    profile.role,
    profile.status,
    coalesce(profile.is_system_actor, false) as is_system_actor,
    profile.system_actor_key,
    count(override_row.action_key) as overrides_count,
    profile.created_at,
    profile.updated_at
  from public.user_profiles profile
  left join public.user_permission_overrides override_row on override_row.user_id = profile.id
  group by
    profile.id,
    profile.display_name,
    profile.role,
    profile.status,
    profile.is_system_actor,
    profile.system_actor_key,
    profile.created_at,
    profile.updated_at
  order by
    coalesce(profile.is_system_actor, false),
    profile.status,
    profile.display_name;
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
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;

  perform public.require_current_user_permission('security.manage_permissions');

  if not exists (select 1 from public.user_profiles where id = p_user_id) then
    raise exception 'target user profile not found';
  end if;

  return query
  select
    action.action_key,
    action.module,
    action.description,
    action.default_allowed,
    override_row.allowed as override_allowed,
    coalesce(override_row.allowed, action.default_allowed) as effective_allowed,
    action.sort_order
  from public.permission_actions action
  left join public.user_permission_overrides override_row
    on override_row.action_key = action.action_key
   and override_row.user_id = p_user_id
  order by action.module, action.sort_order, action.action_key;
end;
$$;

revoke all on function public.list_security_user_profiles() from public;
revoke all on function public.list_security_effective_permissions(uuid) from public;

grant execute on function public.list_security_user_profiles() to authenticated;
grant execute on function public.list_security_effective_permissions(uuid) to authenticated;
