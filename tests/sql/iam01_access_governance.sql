\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_admin uuid := '00000000-0000-4000-8000-00000000a001';
  v_target uuid := '00000000-0000-4000-8000-00000000a002';
  v_profile_id bigint;
  v_action_key text;
  v_log_count bigint;
begin
  if (select count(*) from public.security_access_profiles) <> 10 then
    raise exception 'IAM-01A initial access profile catalog is incomplete';
  end if;
  if exists (select 1 from public.security_access_profiles where status <> 'active') then
    raise exception 'IAM-01A initial profiles must be active';
  end if;
  if not exists (select 1 from public.security_access_profile_permissions) then
    raise exception 'IAM-01A profile permission catalog is empty';
  end if;
  if not exists (
    select 1 from pg_class relation
    where relation.oid in ('public.security_access_profiles'::regclass, 'public.security_access_profile_permissions'::regclass, 'public.security_user_access_profiles'::regclass)
      and relation.relrowsecurity
  ) then
    raise exception 'IAM-01A access tables must keep RLS enabled';
  end if;
  if has_table_privilege('authenticated', 'public.security_access_profiles', 'select') then
    raise exception 'IAM-01A access profile tables must not be directly readable';
  end if;
  if has_function_privilege('anon', 'public.assign_security_access_profile(uuid,bigint,text,text)', 'execute') then
    raise exception 'anon can assign access profiles';
  end if;

  insert into auth.users(id) values (v_admin), (v_target) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status, is_system_actor)
  values (v_admin, 'IAM Test Admin', 'admin', 'active', false),
         (v_target, 'IAM Test Human', 'comercial', 'active', false)
  on conflict (id) do nothing;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_admin, 'security.manage_permissions', true, v_admin)
  on conflict (user_id, action_key) do update set allowed = true;

  select profile.id into v_profile_id from public.security_access_profiles profile where profile.profile_key = 'comercial_vendedor' and profile.version = 1;
  select permission.action_key into v_action_key
    from public.security_access_profile_permissions permission
   where permission.profile_id = v_profile_id and permission.granted
   order by permission.action_key limit 1;
  if v_action_key is null then raise exception 'commercial profile has no explicit permission'; end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if not public.assign_security_access_profile(v_target, v_profile_id, 'Perfil comercial para homologacao IAM', 'iam:smoke:assign') then
    raise exception 'profile assignment did not succeed';
  end if;
  if not public.security_user_has_profile_permission(v_target, v_action_key) then
    raise exception 'profile permission union was not effective';
  end if;
  select count(*) into v_log_count from public.action_logs where action = 'seguranca.access_profile_assigned' and entity_id = v_target::text and metadata_json->>'profile_id' = v_profile_id::text;
  if v_log_count <> 1 then raise exception 'access profile assignment audit missing'; end if;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_target, v_action_key, false, v_admin)
  on conflict (user_id, action_key) do update set allowed = false;
  perform set_config('request.jwt.claim.sub', v_target::text, true);
  if public.can_current_user(v_action_key) then raise exception 'individual deny did not override profile grant'; end if;
end;
$contract$;

rollback;

\echo PG_IAM01_ACCESS_GOVERNANCE_OK
