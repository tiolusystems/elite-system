\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_admin uuid := '00000000-0000-4000-8000-00000000a001';
  v_target uuid := '00000000-0000-4000-8000-00000000a002';
  v_target2 uuid := '00000000-0000-4000-8000-00000000a003';
  v_profile_id bigint;
  v_profile_v2_id bigint;
  v_action_key text;
  v_log_count bigint;
  v_person_id bigint;
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
  if exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key = 'comercial_vendedor'
      and permission.action_key in ('cadastros.manage', 'cadastros.credit.manage', 'pedidos.credit.limit.adjust',
        'pedidos.price_lists.publish', 'pedidos.price_lists.withdraw', 'pedidos.commissions.assign')
  ) then raise exception 'commercial seller profile contains a privileged allow'; end if;
  if exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key in ('consulta_auditoria', 'diretoria') and permission.action_key = 'audit.reconciliation.run'
  ) then raise exception 'read-only or board profile contains reconciliation execution'; end if;
  if exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key = 'administrador_sistema'
      and permission.action_key in ('financeiro.commissions.adjust', 'pcp.op.create', 'estoque.mp.adjust')
  ) then raise exception 'system administrator profile contains operational domain grants'; end if;
  if exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key = 'pcp_producao' and permission.action_key in ('estoque.mp.adjust', 'estoque.pi.adjust')
  ) then raise exception 'PCP profile contains general stock adjustment'; end if;

  insert into auth.users(id) values (v_admin), (v_target), (v_target2) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status, is_system_actor)
  values (v_admin, 'IAM Test Admin', 'admin', 'active', false),
         (v_target, 'IAM Test Human', 'comercial', 'active', false),
         (v_target2, 'IAM Provisioned Human', 'auditoria', 'active', false)
  on conflict (id) do nothing;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_admin, 'security.manage_permissions', true, v_admin),
         (v_admin, 'security.manage_users', true, v_admin)
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

  insert into public.security_access_profiles(profile_key, name, description, version, status)
  values ('comercial_vendedor', 'Comercial / Vendedor v2', 'Versao explicita para migracao controlada.', 2, 'active')
  returning id into v_profile_v2_id;
  insert into public.security_access_profile_permissions(profile_id, action_key)
  values (v_profile_v2_id, v_action_key);
  if not public.security_user_has_profile_permission(v_target, v_action_key) then
    raise exception 'creating profile v2 revoked active v1 access';
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if not public.assign_security_access_profile(v_target, v_profile_v2_id, 'Migracao explicita para versao dois', 'iam:smoke:v2') then
    raise exception 'explicit profile version migration failed';
  end if;
  if (select count(*) from public.security_user_access_profiles assignment
      join public.security_access_profiles profile on profile.id = assignment.profile_id
     where assignment.user_id = v_target and profile.profile_key = 'comercial_vendedor') <> 1 then
    raise exception 'user has more than one version of the same profile key';
  end if;
  if not public.security_user_has_profile_permission(v_target, v_action_key) then
    raise exception 'migrated profile v2 did not preserve permission';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_person_id := public.provision_security_human_identity(
    v_target2, v_profile_id, null, 'IAM Provisioned Human',
    'Provisionamento completo de identidade IAM', 'iam:smoke:provision'
  );
  if not exists (
    select 1 from public.cad_pessoas_comerciais person
     where person.id = v_person_id and person.user_profile_id = v_target2
       and person.tipo_comercial is null and person.papeis_json @> '["funcionario_elite"]'::jsonb
  ) then raise exception 'new human identity was not created and linked atomically'; end if;
  if (select count(*) from public.cad_pessoas_comerciais where user_profile_id = v_target2) <> 1 then
    raise exception 'new human identity was duplicated';
  end if;
end;
$contract$;

rollback;

\echo PG_IAM01_ACCESS_GOVERNANCE_OK
