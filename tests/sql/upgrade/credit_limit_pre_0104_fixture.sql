\set ON_ERROR_STOP on

insert into auth.users(id, email)
values ('10400000-0000-4000-8000-000000000090', 'legacy-credit-0104@test.invalid');

insert into public.user_profiles(id, display_name, role, status)
values (
  '10400000-0000-4000-8000-000000000090',
  'Override legado 0104',
  'comercial',
  'active'
);

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values (
  '10400000-0000-4000-8000-000000000090',
  'pedidos.credit.limit.adjust',
  true,
  '10400000-0000-4000-8000-000000000090'
);

select 'PG_FIXTURE_0103_CREDIT_LIMIT_LEGACY_OVERRIDE_OK';
