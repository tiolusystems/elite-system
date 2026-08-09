\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_action_keys constant text[] := array[
    'faturamento.external_references.correct',
    'faturamento.external_references.register',
    'faturamento.nf.cancel',
    'faturamento.nf.complement',
    'faturamento.nf.correct',
    'faturamento.nf.issue',
    'faturamento.nf.substitute',
    'faturamento.nf.view',
    'financeiro.commissions.adjust',
    'financeiro.commissions.pay',
    'financeiro.commissions.release',
    'financeiro.commissions.view',
    'financeiro.credit_limits.adjust',
    'financeiro.receipts.register',
    'financeiro.receipts.reverse',
    'financeiro.receipts.view',
    'pedidos.receipts.create',
    'qualidade.rastreabilidade.export',
    'qualidade.rastreabilidade.recall_simulate',
    'qualidade.rastreabilidade.view',
    'reports.view'
  ];
  v_actor_admin constant uuid := '10800000-0000-4000-8000-000000000001';
  v_actor_commercial constant uuid := '10800000-0000-4000-8000-000000000002';
  v_actor_audit constant uuid := '10800000-0000-4000-8000-000000000003';
  v_actor uuid;
  v_action_key text;
begin
  if (
    select count(*)
      from public.permission_actions action
     where action.action_key = any(v_action_keys)
       and action.default_allowed = false
       and action.runtime_module_key in ('faturamento', 'financeiro', 'relatorios')
       and action.runtime_access_kind is not null
  ) <> cardinality(v_action_keys) then
    raise exception 'staging rollout actions are not complete and default-deny';
  end if;

  insert into auth.users(id)
  values (v_actor_admin), (v_actor_commercial), (v_actor_audit)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor_admin, '0108 Admin Without Override', 'admin', 'active'),
    (v_actor_commercial, '0108 Commercial Without Override', 'comercial', 'active'),
    (v_actor_audit, '0108 Audit With Explicit Override', 'auditoria', 'active')
  on conflict (id) do update
    set display_name = excluded.display_name,
        role = excluded.role,
        status = excluded.status;

  delete from public.user_permission_overrides
   where user_id in (v_actor_admin, v_actor_commercial, v_actor_audit)
     and action_key = any(v_action_keys);

  foreach v_actor in array array[v_actor_admin, v_actor_commercial, v_actor_audit]
  loop
    perform set_config('request.jwt.claim.sub', v_actor::text, true);
    foreach v_action_key in array v_action_keys
    loop
      if public.can_current_user(v_action_key) then
        raise exception 'role inferred permission for actor % and action %', v_actor, v_action_key;
      end if;
    end loop;
  end loop;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (
    v_actor_audit,
    'qualidade.rastreabilidade.view',
    true,
    v_actor_admin
  );

  perform set_config('request.jwt.claim.sub', v_actor_audit::text, true);
  if not public.can_current_user('qualidade.rastreabilidade.view') then
    raise exception 'explicit positive override did not grant the selected action';
  end if;
  if public.can_current_user('qualidade.rastreabilidade.export') then
    raise exception 'one override granted an unrelated traceability action';
  end if;
  if public.can_current_user('financeiro.receipts.register') then
    raise exception 'one override granted an unrelated financial action';
  end if;

  update public.user_permission_overrides
     set allowed = false,
         updated_by = v_actor_admin
   where user_id = v_actor_audit
     and action_key = 'qualidade.rastreabilidade.view';

  if public.can_current_user('qualidade.rastreabilidade.view') then
    raise exception 'explicit revocation did not deny the next permission check';
  end if;
end;
$contract$;

rollback;

\echo STAGING_ROLLOUT_DEFAULT_DENY_OK
