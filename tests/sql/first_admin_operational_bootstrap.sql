\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000042';
  v_second uuid := '00000000-0000-4000-8000-000000000142';
  v_result jsonb;
  v_log_count bigint;
begin
  if to_regclass('public.idx_sys_runtime_environment_actor') is null
     or to_regclass('public.idx_sys_module_rollout_actor') is null
     or to_regclass('public.idx_sys_module_rollout_module') is null then
    raise exception 'module runtime foreign key index coverage is incomplete';
  end if;

  if has_function_privilege('anon', 'public.bootstrap_first_system_admin(uuid, text)', 'execute') then
    raise exception 'anon can execute first admin bootstrap';
  end if;
  if has_function_privilege('authenticated', 'public.bootstrap_first_system_admin(uuid, text)', 'execute') then
    raise exception 'authenticated can execute first admin bootstrap';
  end if;
  if not has_function_privilege('service_role', 'public.bootstrap_first_system_admin(uuid, text)', 'execute') then
    raise exception 'service_role cannot execute first admin bootstrap';
  end if;

  insert into auth.users(id)
  values (v_admin), (v_second)
  on conflict (id) do nothing;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.bootstrap_first_system_admin(v_admin, 'Bootstrap Admin');
    raise exception 'authenticated caller passed first admin bootstrap';
  exception
    when others then
      if sqlerrm <> 'service role required for first administrator bootstrap' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  v_result := public.bootstrap_first_system_admin(v_admin, 'Bootstrap Admin');

  if v_result->>'role' <> 'admin'
     or v_result->>'status' <> 'active'
     or coalesce((v_result->>'is_system_actor')::boolean, true) then
    raise exception 'invalid first admin result: %', v_result;
  end if;

  if not exists (
    select 1
      from public.user_profiles profile
     where profile.id = v_admin
       and profile.role = 'admin'
       and profile.status = 'active'
       and not profile.is_system_actor
  ) then
    raise exception 'first admin profile was not persisted';
  end if;

  select count(*)
    into v_log_count
    from public.action_logs log_row
   where log_row.action = 'seguranca.first_system_admin_bootstrapped'
     and log_row.entity_id = v_admin::text
     and log_row.status = 'success'
     and log_row.metadata_json->>'source' = 'service_role_bootstrap'
     and log_row.metadata_json->>'contains_credentials' = 'false';
  if v_log_count <> 1 then
    raise exception 'first admin bootstrap audit log missing: %', v_log_count;
  end if;

  begin
    perform public.bootstrap_first_system_admin(v_second, 'Second Bootstrap Admin');
    raise exception 'second first-admin bootstrap was accepted';
  exception
    when others then
      if sqlerrm <> 'first administrator bootstrap already closed' then
        raise;
      end if;
  end;

  if exists (select 1 from public.user_profiles where id = v_second) then
    raise exception 'second bootstrap wrote a profile';
  end if;
end;
$contract$;

rollback;

\echo PG_FIRST_ADMIN_OPERATIONAL_BOOTSTRAP_OK
