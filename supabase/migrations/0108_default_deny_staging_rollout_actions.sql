-- Enabling a runtime module must not grant sensitive fiscal, financial, or
-- traceability actions. Access remains individual and explicitly overridden.

do $migration$
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
  v_missing text[];
  v_invalid text[];
begin
  select array_agg(expected.action_key order by expected.action_key)
    into v_missing
    from unnest(v_action_keys) as expected(action_key)
   where not exists (
     select 1
       from public.permission_actions action
      where action.action_key = expected.action_key
   );

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception '0108 missing permission actions: %', array_to_string(v_missing, ', ');
  end if;

  select array_agg(action.action_key order by action.action_key)
    into v_invalid
    from public.permission_actions action
   where action.action_key = any(v_action_keys)
     and (
       action.runtime_module_key not in ('faturamento', 'financeiro', 'relatorios')
       or action.runtime_access_kind is null
     );

  if coalesce(array_length(v_invalid, 1), 0) > 0 then
    raise exception '0108 invalid runtime permission metadata: %', array_to_string(v_invalid, ', ');
  end if;

  update public.permission_actions
     set default_allowed = false
   where action_key = any(v_action_keys);
end;
$migration$;
