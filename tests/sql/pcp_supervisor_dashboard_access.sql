\set ON_ERROR_STOP on
begin;

do $catalog$
begin
  if not exists (
    select 1
      from public.permission_actions action
     where action.action_key = 'pcp.dashboard.view'
       and action.module = 'pcp'
       and action.description = 'Consultar painel supervisor da produção'
       and action.default_allowed = false
       and action.runtime_module_key = 'pcp'
       and action.runtime_access_kind = 'read'
  ) then
    raise exception 'pcp supervisor dashboard permission is invalid';
  end if;

  if not (
    select class.relrowsecurity
      from pg_class class
     where class.oid = 'public.permission_actions'::regclass
  ) then
    raise exception 'permission action catalog is not protected by RLS';
  end if;

  if has_function_privilege(
       'public',
       'public.get_pcp_supervisor_dashboard()',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.get_pcp_supervisor_dashboard()',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.get_pcp_supervisor_dashboard()',
       'EXECUTE'
     ) then
    raise exception 'pcp supervisor dashboard grants are invalid';
  end if;

  if not (
    select procedure.prosecdef
      from pg_proc procedure
     where procedure.oid = 'public.get_pcp_supervisor_dashboard()'::regprocedure
  ) then
    raise exception 'pcp supervisor dashboard must use a guarded definer contract';
  end if;

  if pg_get_functiondef(
       'public.get_pcp_supervisor_dashboard()'::regprocedure
     ) not like '%require_current_user_permission(''pcp.dashboard.view'')%'
  then
    raise exception 'pcp supervisor dashboard does not require its atomic permission';
  end if;
end
$catalog$;

insert into auth.users(id, email) values
  ('10700000-0000-4000-8000-000000000001', 'pcp-supervisor-0107@test.invalid'),
  ('10700000-0000-4000-8000-000000000002', 'pcp-operator-0107@test.invalid'),
  ('10700000-0000-4000-8000-000000000003', 'runtime-admin-0107@test.invalid');

insert into public.user_profiles(id, display_name, role, status) values
  ('10700000-0000-4000-8000-000000000001', 'Supervisor com alçada individual', 'producao', 'active'),
  ('10700000-0000-4000-8000-000000000002', 'Operador sem painel supervisor', 'producao', 'active'),
  ('10700000-0000-4000-8000-000000000003', 'Administrador do ambiente descartável', 'admin', 'active');

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  (
    '10700000-0000-4000-8000-000000000001',
    'pcp.dashboard.view',
    true,
    '10700000-0000-4000-8000-000000000001'
  ),
  (
    '10700000-0000-4000-8000-000000000002',
    'pcp.dashboard.view',
    false,
    '10700000-0000-4000-8000-000000000001'
  ),
  (
    '10700000-0000-4000-8000-000000000003',
    'system.admin',
    true,
    '10700000-0000-4000-8000-000000000003'
  );

select set_config('request.jwt.claim.sub', '10700000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'initial_configuration', 'Smoke descartável 0107')
 where public.current_system_environment() = 'unconfigured';

set local role authenticated;

select set_config('request.jwt.claim.sub', '10700000-0000-4000-8000-000000000002', true);
do $operator_denied$
begin
  if public.can_current_user('pcp.dashboard.view') then
    raise exception 'operator inherited supervisor dashboard permission';
  end if;

  begin
    perform public.get_pcp_supervisor_dashboard();
    raise exception 'operator read the supervisor dashboard without permission';
  exception when others then
    if sqlerrm = 'operator read the supervisor dashboard without permission' then
      raise;
    end if;
    if sqlerrm not like 'not allowed: pcp.dashboard.view%' then
      raise;
    end if;
  end;
end
$operator_denied$;

select set_config('request.jwt.claim.sub', '10700000-0000-4000-8000-000000000001', true);
do $supervisor_allowed$
declare
  v_dashboard jsonb;
begin
  if not public.can_current_user('pcp.dashboard.view') then
    raise exception 'explicit supervisor permission was not effective';
  end if;

  v_dashboard := public.get_pcp_supervisor_dashboard();
  if not (
    v_dashboard ? 'ops_aguardando'
    and v_dashboard ? 'ops_em_producao'
    and v_dashboard ? 'componentes_sem_reserva'
    and v_dashboard ? 'lotes_bloqueados'
  ) then
    raise exception 'supervisor dashboard result is incomplete';
  end if;
end
$supervisor_allowed$;

reset role;
rollback;
