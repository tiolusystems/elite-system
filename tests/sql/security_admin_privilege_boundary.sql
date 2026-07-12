\set ON_ERROR_STOP on

begin;

do $security_admin_privilege_boundary_smoke$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000491';
  v_operator uuid := '00000000-0000-4000-8000-000000000492';
  v_limited_admin uuid := '00000000-0000-4000-8000-000000000493';
  v_target uuid := '00000000-0000-4000-8000-000000000494';
  v_default_count integer;
begin
  select count(*)
    into v_default_count
    from public.permission_actions action
   where action.action_key in (
     'system.admin',
     'security.manage_users',
     'security.manage_permissions',
     'security.email_change.review'
   )
     and action.default_allowed = false;

  if v_default_count <> 4 then
    raise exception 'critical security actions are not default deny';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.security_user_profile_snapshot(uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute internal security snapshot';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_security_auth_user_temp_password_sent(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute legacy temporary password logger';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.upsert_security_user_profile_impl_0049(uuid,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can bypass user profile wrapper';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.set_security_permission_override_impl_0049(uuid,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can bypass permission wrapper';
  end if;

  insert into auth.users(id, email, email_confirmed_at)
  values
    (v_admin, 'admin-boundary@validation.elite.com.br', now()),
    (v_operator, 'operator-boundary@validation.elite.com.br', now()),
    (v_limited_admin, 'limited-admin-boundary@validation.elite.com.br', now()),
    (v_target, 'target-boundary@validation.elite.com.br', now())
  on conflict (id) do update set
    email = excluded.email,
    email_confirmed_at = excluded.email_confirmed_at;

  insert into public.user_profiles(id, display_name, role, status, is_system_actor)
  values
    (v_admin, 'Boundary Admin', 'admin', 'active', false),
    (v_operator, 'Boundary Operator', 'comercial', 'active', false),
    (v_limited_admin, 'Boundary Limited Admin', 'admin', 'active', false)
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = false,
    system_actor_key = null;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_admin, critical_action.action_key, true, v_admin
    from (
      values
        ('system.admin'::text),
        ('security.manage_users'::text),
        ('security.manage_permissions'::text),
        ('security.email_change.review'::text)
    ) critical_action(action_key)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  -- Make the synthetic administrator the only capable one for the lockout
  -- assertions. The enclosing transaction always rolls this setup back.
  update public.user_permission_overrides
     set allowed = false,
         updated_by = v_admin
   where user_id <> v_admin
     and action_key in (
       'system.admin',
       'security.manage_users',
       'security.manage_permissions',
       'security.email_change.review'
     );

  -- Even an accidental explicit grant must not turn a non-admin into an admin.
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_operator, 'system.admin', true, v_admin),
    (v_operator, 'security.manage_users', true, v_admin),
    (v_operator, 'security.manage_permissions', true, v_admin),
    (v_operator, 'security.email_change.review', true, v_admin),
    (v_limited_admin, 'security.manage_users', true, v_admin)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_operator::text, true);

  if not public.can_current_user('security.manage_users') then
    raise exception 'smoke setup failed to create accidental operator grant';
  end if;
  if not public.can_current_user('security.email_change.request') then
    raise exception 'self-service email request should remain available';
  end if;

  begin
    perform public.list_security_user_profiles();
    raise exception 'non-admin listed security users';
  exception
    when others then
      if sqlerrm = 'non-admin listed security users'
         or sqlerrm not like '%system administrator role required%' then
        raise;
      end if;
  end;

  begin
    perform public.upsert_security_user_profile(v_target, 'Escalated Target', 'admin', 'active');
    raise exception 'non-admin promoted a user';
  exception
    when others then
      if sqlerrm = 'non-admin promoted a user'
         or sqlerrm not like '%system administrator role required%' then
        raise;
      end if;
  end;

  begin
    perform public.set_security_permission_override(v_operator, 'system.admin', true);
    raise exception 'non-admin changed a permission';
  exception
    when others then
      if sqlerrm = 'non-admin changed a permission'
         or sqlerrm not like '%system administrator role required%' then
        raise;
      end if;
  end;

  begin
    perform public.set_system_runtime_environment('local', 'test_reset', 'boundary smoke');
    raise exception 'non-admin changed runtime environment';
  exception
    when others then
      if sqlerrm = 'non-admin changed runtime environment'
         or sqlerrm not like '%system administrator role required%' then
        raise;
      end if;
  end;

  -- An admin with user-management rights cannot create another admin without
  -- the separate permission-management grant.
  perform set_config('request.jwt.claim.sub', v_limited_admin::text, true);
  perform public.authorize_security_auth_user_provision(
    'commercial-invite@validation.elite.com.br',
    'Commercial Invite',
    'comercial',
    'active'
  );

  begin
    perform public.authorize_security_auth_user_provision(
      'admin-invite@validation.elite.com.br',
      'Admin Invite',
      'admin',
      'active'
    );
    raise exception 'limited admin authorized another admin';
  exception
    when others then
      if sqlerrm = 'limited admin authorized another admin'
         or sqlerrm not like '%not allowed: security.manage_permissions%' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  if public.require_current_user_security_admin('security.manage_users') <> v_admin then
    raise exception 'capable admin guard did not return current actor';
  end if;
  if not public.security_admin_has_core_grants(v_admin) then
    raise exception 'capable admin was not recognized';
  end if;
  if public.security_admin_has_core_grants(v_limited_admin) then
    raise exception 'limited admin was incorrectly recognized as capable';
  end if;

  perform public.upsert_security_user_profile(v_target, 'Governed Target', 'comercial', 'active');

  begin
    perform public.set_security_permission_override(v_admin, 'security.manage_users', false);
    raise exception 'last capable admin lost a core grant';
  exception
    when others then
      if sqlerrm = 'last capable admin lost a core grant'
         or sqlerrm not like '%last capable system administrator must retain core grants%' then
        raise;
      end if;
  end;

  begin
    perform public.clear_security_permission_override(v_admin, 'security.manage_permissions');
    raise exception 'last capable admin core grant was cleared';
  exception
    when others then
      if sqlerrm = 'last capable admin core grant was cleared'
         or sqlerrm not like '%last capable system administrator must retain core grants%' then
        raise;
      end if;
  end;

  begin
    perform public.upsert_security_user_profile(v_admin, 'Boundary Admin', 'admin', 'inactive');
    raise exception 'last capable admin was deactivated';
  exception
    when others then
      if sqlerrm = 'last capable admin was deactivated'
         or sqlerrm not like '%last capable system administrator cannot be demoted or deactivated%' then
        raise;
      end if;
  end;

  raise notice 'PG_VALIDATE_0049_SECURITY_ADMIN_PRIVILEGE_BOUNDARY_OK';
end;
$security_admin_privilege_boundary_smoke$;

rollback;
