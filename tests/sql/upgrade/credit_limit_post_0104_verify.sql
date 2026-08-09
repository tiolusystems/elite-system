\set ON_ERROR_STOP on

do $upgrade$
begin
  if not exists (
    select 1
      from public.user_permission_overrides override_row
     where override_row.user_id = '10400000-0000-4000-8000-000000000090'
       and override_row.action_key = 'pedidos.credit.limit.adjust'
       and override_row.allowed = true
  ) then
    raise exception 'legacy positive override history was not preserved';
  end if;

  if exists (
    select 1
      from public.user_permission_overrides override_row
     where override_row.user_id = '10400000-0000-4000-8000-000000000090'
       and override_row.action_key = 'financeiro.credit_limits.adjust'
  ) then
    raise exception 'legacy positive override was copied automatically';
  end if;

  if exists (
    select 1
      from public.permission_actions action
     where action.action_key in (
       'pedidos.credit.limit.adjust',
       'financeiro.credit_limits.adjust'
     )
       and action.default_allowed = true
  ) then
    raise exception 'credit limit permission remained default allow after upgrade';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '10400000-0000-4000-8000-000000000090',
    true
  );
  if not public.can_current_user('pedidos.credit.limit.adjust') then
    raise exception 'legacy override record is no longer readable as history';
  end if;
  if public.can_current_user('financeiro.credit_limits.adjust') then
    raise exception 'legacy override authorized the canonical financial action';
  end if;
end
$upgrade$;

select 'PG_VALIDATE_UPGRADE_0103_TO_0104_OK';
