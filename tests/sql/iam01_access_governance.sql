\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_admin uuid := '00000000-0000-4000-8000-00000000a001';
  v_target uuid := '00000000-0000-4000-8000-00000000a002';
  v_target2 uuid := '00000000-0000-4000-8000-00000000a003';
  v_expired_target uuid := '00000000-0000-4000-8000-00000000a004';
  v_legacy_target uuid := '00000000-0000-4000-8000-00000000a005';
  v_homonym_target uuid := '00000000-0000-4000-8000-00000000a006';
  v_linked_target uuid := '00000000-0000-4000-8000-00000000a007';
  v_profile_id bigint;
  v_profile_v2_id bigint;
  v_action_key text;
  v_log_count bigint;
  v_person_id bigint;
  v_candidate_person_id bigint;
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
  if (
    select count(*) from pg_class relation
    where relation.oid in (
      'public.security_access_profiles'::regclass,
      'public.security_access_profile_permissions'::regclass,
      'public.security_user_access_profiles'::regclass,
      'public.security_access_profile_adoptions'::regclass
    )
      and relation.relrowsecurity
  ) <> 4 then
    raise exception 'IAM-01A access tables must keep RLS enabled';
  end if;
  if has_table_privilege('authenticated', 'public.security_access_profiles', 'select')
     or has_table_privilege('authenticated', 'public.security_access_profile_adoptions', 'select') then
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
  if not exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key = 'administrador_sistema'
      and profile.version = 1
      and permission.action_key = 'security.identity.person.link'
      and permission.granted
  ) then raise exception 'system administrator profile cannot link a governed human identity'; end if;
  if exists (
    select 1 from public.security_access_profile_permissions permission
    join public.security_access_profiles profile on profile.id = permission.profile_id
    where profile.profile_key = 'pcp_producao' and permission.action_key in ('estoque.mp.adjust', 'estoque.pi.adjust')
  ) then raise exception 'PCP profile contains general stock adjustment'; end if;

  insert into auth.users(id) values
    (v_admin), (v_target), (v_target2), (v_expired_target),
    (v_legacy_target), (v_homonym_target), (v_linked_target)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status, is_system_actor)
  values (v_admin, 'IAM Test Admin', 'admin', 'active', false),
         (v_target, 'IAM Test Human', 'comercial', 'active', false),
         (v_target2, 'IAM Provisioned Human', 'auditoria', 'active', false),
         (v_expired_target, 'IAM Expired Profile Human', 'comercial', 'active', false),
         (v_legacy_target, 'IAM Legacy Human', 'comercial', 'active', false),
         (v_homonym_target, 'IAM Homonym Human', 'auditoria', 'active', false),
         (v_linked_target, 'IAM Linked Human', 'auditoria', 'active', false)
  on conflict (id) do nothing;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_admin, 'security.manage_permissions', true, v_admin),
         (v_admin, 'security.manage_users', true, v_admin),
         (v_admin, 'security.identity.person.link', true, v_admin)
  on conflict (user_id, action_key) do update set allowed = true;
  insert into public.security_user_access_profiles(
    user_id, profile_id, profile_key, assigned_by, reason, correlation_id
  )
  select
    v_admin, profile.id, profile.profile_key, v_admin,
    'Perfil restritivo para validar menor privilegio IAM',
    'iam:smoke:admin-restricted'
  from public.security_access_profiles profile
  where profile.profile_key = 'consulta_auditoria'
    and profile.version = 1
  on conflict (user_id, profile_key) do nothing;

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

  if not public.remove_security_access_profile(
    v_target, v_profile_v2_id, 'Remocao do ultimo perfil para validar fail closed'
  ) then
    raise exception 'last profile removal did not succeed';
  end if;
  if not exists (
    select 1 from public.security_access_profile_adoptions adoption
    where adoption.user_id = v_target
  ) then raise exception 'profile adoption marker was removed with the last profile'; end if;
  perform set_config('request.jwt.claim.sub', v_target::text, true);
  if public.can_current_user('cadastros.manage') then
    raise exception 'removed last profile reopened legacy fallback';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if not public.assign_security_access_profile(
    v_expired_target, v_profile_id, 'Perfil temporario para validar expiracao', 'iam:smoke:expiry'
  ) then raise exception 'expiring profile assignment did not succeed'; end if;
  update public.security_user_access_profiles
     set expires_at = clock_timestamp() - interval '1 minute'
   where user_id = v_expired_target and profile_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_expired_target::text, true);
  if public.can_current_user('cadastros.manage') then
    raise exception 'expired last profile reopened legacy fallback';
  end if;

  perform set_config('request.jwt.claim.sub', v_legacy_target::text, true);
  if not public.can_current_user('cadastros.manage') then
    raise exception 'never-adopted user lost legacy transition fallback';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if public.can_current_user('cadastros.pessoas.create') then
    raise exception 'security smoke admin received generic Cadastros create permission';
  end if;
  if has_schema_privilege('authenticated', 'cadastros_internal', 'usage')
     or has_schema_privilege('anon', 'cadastros_internal', 'usage') then
    raise exception 'private Cadastros schema usage leaked';
  end if;
  if has_function_privilege('authenticated', 'cadastros_internal.create_security_human_person(text,text)', 'execute')
     or has_function_privilege('anon', 'cadastros_internal.create_security_human_person(text,text)', 'execute') then
    raise exception 'private identity helper is exposed to an application role';
  end if;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, tipo_comercial, papeis_json, status,
    apelidos_json, grafias_incorretas_json, payload_origem_json,
    created_by, updated_by
  ) values (
    'Pessoa Homonima IAM', 'PESSOA HOMONIMA IAM', null, '["funcionario"]'::jsonb, 'active',
    '[]'::jsonb, '[]'::jsonb, '{"source":"iam-smoke-candidate"}'::jsonb,
    v_admin, v_admin
  ) returning id into v_candidate_person_id;
  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  values (v_candidate_person_id, 'Alias Candidato IAM', 'alias candidato iam', 'apelido');

  begin
    perform public.provision_security_human_identity(
      v_homonym_target, v_profile_id, null, 'Pessoa Homonima IAM',
      'Tentativa automatica com pessoa homonima', 'iam:smoke:homonym'
    );
    raise exception 'automatic provisioning reused a homonym';
  exception when others then
    if sqlerrm <> 'possible commercial person exists; choose p_pessoa_id explicitly' then raise; end if;
  end;
  if exists (
    select 1 from public.cad_pessoas_comerciais person
    where person.user_profile_id = v_homonym_target
  ) then raise exception 'rejected homonym was linked silently'; end if;

  begin
    perform public.provision_security_human_identity(
      v_homonym_target, v_profile_id, null, 'Alias Candidato IAM',
      'Tentativa automatica usando alias existente', 'iam:smoke:alias'
    );
    raise exception 'automatic provisioning ignored an existing alias';
  exception when others then
    if sqlerrm <> 'possible commercial person exists; choose p_pessoa_id explicitly' then raise; end if;
  end;

  v_person_id := public.provision_security_human_identity(
    v_homonym_target, v_profile_id, v_candidate_person_id, null,
    'Selecao explicita da pessoa candidata correta', 'iam:smoke:explicit-person'
  );
  if v_person_id <> v_candidate_person_id or not exists (
    select 1 from public.cad_pessoas_comerciais person
    where person.id = v_candidate_person_id and person.user_profile_id = v_homonym_target
  ) then raise exception 'explicit person selection did not link the chosen person'; end if;

  begin
    perform public.provision_security_human_identity(
      v_linked_target, v_profile_id, v_candidate_person_id, null,
      'Tentativa de vincular pessoa ocupada a outra conta', 'iam:smoke:already-linked'
    );
    raise exception 'person linked to another user was accepted';
  exception when others then
    if sqlerrm <> 'commercial person is already linked to another user profile' then raise; end if;
  end;

  v_person_id := public.provision_security_human_identity(
    v_target2, v_profile_id, null, 'IAM Provisioned Human',
    'Provisionamento completo de identidade IAM', 'iam:smoke:provision'
  );
  if not exists (
    select 1 from public.cad_pessoas_comerciais person
     where person.id = v_person_id and person.user_profile_id = v_target2
       and person.tipo_comercial is null and person.papeis_json @> '["funcionario"]'::jsonb
  ) then raise exception 'new human identity was not created and linked atomically'; end if;
  if (select count(*) from public.cad_pessoas_comerciais where user_profile_id = v_target2) <> 1 then
    raise exception 'new human identity was duplicated';
  end if;
end;
$contract$;

rollback;

\echo PG_IAM01_ACCESS_GOVERNANCE_OK
