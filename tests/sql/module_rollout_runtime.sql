\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000041';
  v_status jsonb;
  v_log_count_before bigint;
  v_log_count_after bigint;
  v_rollout_event_id bigint;
  v_environment_event_id bigint;
  v_route_status jsonb;
  v_count integer;
begin
  if exists (
    select 1
      from public.permission_actions action
     where action.runtime_module_key is null
        or action.runtime_access_kind is null
  ) then
    raise exception 'permission action without runtime ownership survived';
  end if;

  if exists (
    with recursive dependency_path as (
      select
        dependency.module_key as root_module,
        dependency.depends_on_module_key as current_module,
        array[dependency.module_key, dependency.depends_on_module_key]::text[] as path,
        dependency.depends_on_module_key = dependency.module_key as cycle
      from public.sys_module_dependencies dependency
      where dependency.required

      union all

      select
        path.root_module,
        dependency.depends_on_module_key,
        path.path || dependency.depends_on_module_key,
        dependency.depends_on_module_key = any(path.path)
      from dependency_path path
      join public.sys_module_dependencies dependency
        on dependency.module_key = path.current_module
       and dependency.required
      where not path.cycle
    )
    select 1 from dependency_path where cycle
  ) then
    raise exception 'required module dependency cycle survived';
  end if;

  if exists (
    select route_prefix
      from public.sys_module_routes
     group by route_prefix
    having count(*) > 1
  ) then
    raise exception 'duplicate module route registration';
  end if;

  if not exists (
    select 1
      from public.sys_module_routes
     where route_prefix = '/producao'
       and module_key = 'pcp'
       and match_children
  ) then
    raise exception 'production route is not owned by PCP';
  end if;

  if public.current_system_environment() <> 'unconfigured' then
    raise exception 'new database must start unconfigured';
  end if;

  v_status := public.system_module_status('unconfigured', 'core', 'read_write');
  if not coalesce((v_status->>'available')::boolean, false) then
    raise exception 'core bootstrap is unavailable: %', v_status;
  end if;

  v_status := public.system_module_status('unconfigured', 'cadastros', 'read_only');
  if coalesce((v_status->>'available')::boolean, false) or v_status->>'reason' <> 'environment_unconfigured' then
    raise exception 'operational module did not fail closed in unconfigured environment: %', v_status;
  end if;

  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Module Runtime Smoke Actor', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'system.admin', true, v_actor),
    (v_actor, 'estoque.mp.view', true, v_actor),
    (v_actor, 'estoque.mp.adjust', true, v_actor)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  select count(*) into v_log_count_before from public.action_logs where actor_user_id = v_actor;

  select count(*)
    into v_count
    from public.list_system_module_runtime('production') runtime
   where runtime.environment = 'production'
     and runtime.active_environment = 'unconfigured';
  if v_count <> 14 then
    raise exception 'future environment inspection did not return complete catalog: %', v_count;
  end if;

  v_environment_event_id := public.set_system_runtime_environment(
    'test',
    'test_reset',
    'Smoke da migration 0041'
  );
  if v_environment_event_id is null or public.current_system_environment() <> 'test' then
    raise exception 'test environment was not activated';
  end if;

  v_status := public.system_module_status('test', 'pcp', 'read_write');
  if not coalesce((v_status->>'available')::boolean, false) then
    raise exception 'test baseline PCP should be available: %', v_status;
  end if;

  select to_jsonb(route_status)
    into v_route_status
    from public.get_current_route_module_access('/pcp') route_status;
  if not coalesce((v_route_status->>'available')::boolean, false) or v_route_status->>'module_key' <> 'pcp' then
    raise exception 'PCP route did not resolve to available module: %', v_route_status;
  end if;

  select to_jsonb(route_status)
    into v_route_status
    from public.get_current_route_module_access('/producao') route_status;
  if not coalesce((v_route_status->>'available')::boolean, false) or v_route_status->>'module_key' <> 'pcp' then
    raise exception 'production route did not resolve to available module: %', v_route_status;
  end if;

  select to_jsonb(route_status)
    into v_route_status
    from public.get_current_route_module_access('/rota-sem-dono') route_status;
  if coalesce((v_route_status->>'available')::boolean, false) or v_route_status->>'reason' <> 'route_not_registered' then
    raise exception 'unregistered route did not fail closed: %', v_route_status;
  end if;

  v_rollout_event_id := public.set_system_module_rollout(
    'test',
    'estoque',
    'technical_validation',
    'read_only',
    'technical_validation',
    'Validacao de modo somente leitura'
  );
  if v_rollout_event_id is null then
    raise exception 'read-only rollout event was not created';
  end if;

  perform public.require_current_user_permission('estoque.mp.view');
  begin
    perform public.require_current_user_permission('estoque.mp.adjust');
    raise exception 'write action passed while stock module was read_only';
  exception
    when others then
      if sqlerrm not like 'module unavailable: estoque%' then
        raise;
      end if;
  end;

  perform public.set_system_module_rollout(
    'test',
    'estoque',
    'suspended',
    'disabled',
    'incident',
    'Simulacao de dependencia suspensa'
  );

  v_status := public.system_module_status('test', 'pcp', 'read_only');
  if coalesce((v_status->>'available')::boolean, false) or v_status->>'reason' <> 'dependency_unavailable' then
    raise exception 'PCP did not close after stock suspension: %', v_status;
  end if;

  select to_jsonb(route_status)
    into v_route_status
    from public.get_current_route_module_access('/pcp') route_status;
  if coalesce((v_route_status->>'available')::boolean, false) or v_route_status->>'reason' <> 'dependency_unavailable' then
    raise exception 'PCP route remained open after stock suspension: %', v_route_status;
  end if;

  begin
    perform public.set_system_module_rollout(
      'test',
      'pcp',
      'technical_validation',
      'read_write',
      'dependency_change',
      'Tentativa deve falhar'
    );
    raise exception 'PCP activation passed with unavailable dependency';
  exception
    when others then
      if sqlerrm not like 'module dependencies unavailable:%' then
        raise;
      end if;
  end;

  perform public.set_system_module_rollout(
    'test',
    'estoque',
    'technical_validation',
    'read_write',
    'technical_validation',
    'Restauracao apos smoke'
  );

  begin
    perform public.set_system_module_rollout(
      'production',
      'cadastros',
      'technical_validation',
      'read_write',
      'production_release',
      'Tentativa deve falhar'
    );
    raise exception 'technical_validation was accepted for production write';
  exception
    when others then
      if sqlerrm <> 'module lifecycle does not allow requested access in environment' then
        raise;
      end if;
  end;

  begin
    update public.sys_module_rollout_events
       set reason_detail = 'mutacao indevida'
     where id = v_rollout_event_id;
    raise exception 'rollout event update was accepted';
  exception
    when others then
      if sqlerrm not like 'sys_module_rollout_events is append-only%' then
        raise;
      end if;
  end;

  begin
    execute 'truncate table public.sys_runtime_environment_events';
    raise exception 'runtime environment truncate was accepted';
  exception
    when others then
      if sqlerrm not like 'sys_runtime_environment_events is append-only%' then
        raise;
      end if;
  end;

  begin
    insert into public.sys_module_dependencies(
      module_key,
      depends_on_module_key,
      minimum_access,
      required,
      reason
    ) values (
      'core',
      'pcp',
      'read_only',
      true,
      'Ciclo artificial do smoke'
    );
    raise exception 'dependency cycle was accepted';
  exception
    when others then
      if sqlerrm not like 'module dependency cycle:%' then
        raise;
      end if;
  end;

  select count(*) into v_log_count_after from public.action_logs where actor_user_id = v_actor;
  if v_log_count_after <= v_log_count_before then
    raise exception 'module runtime changes did not create action logs';
  end if;
end;
$contract$;

rollback;

\echo PG_MODULE_ROLLOUT_RUNTIME_OK
