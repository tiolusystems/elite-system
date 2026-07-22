-- Restore the audited historical MP import entrypoints after the global RPC
-- exposure gate in 0066. Each function performs its own permission check and
-- audit logging; trigger helpers and direct table writes remain inaccessible.

revoke all on function public.stage_migration_mp_items(bigint, jsonb) from public;
revoke execute on function public.stage_migration_mp_items(bigint, jsonb) from anon;
grant execute on function public.stage_migration_mp_items(bigint, jsonb) to authenticated;

revoke all on function public.approve_migration_mp_mapping(
  bigint, bigint, text, numeric, text, text
) from public;
revoke execute on function public.approve_migration_mp_mapping(
  bigint, bigint, text, numeric, text, text
) from anon;
grant execute on function public.approve_migration_mp_mapping(
  bigint, bigint, text, numeric, text, text
) to authenticated;

revoke all on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) from public;
revoke execute on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) from anon;
grant execute on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) to authenticated;

comment on function public.stage_migration_mp_items(bigint, jsonb) is
  'Audited historical MP staging entrypoint. Authenticated execution still requires migration.mp.stage.';
comment on function public.approve_migration_mp_mapping(bigint, bigint, text, numeric, text, text) is
  'Audited historical MP mapping entrypoint. Authenticated execution requires the union of mapping and master-data permissions.';
comment on function public.register_migration_mp_acquisition_value(
  bigint, numeric, text, numeric, numeric, numeric, numeric, text, numeric,
  numeric, numeric, numeric, text, date, text, bigint, bigint, text
) is
  'Audited historical MP acquisition-value entrypoint. Authenticated execution requires the union of import and stock permissions.';

-- The historical import composes with the governed stock entrypoint. Keep its
-- independent stock permission and audit record instead of duplicating a lot
-- insert inside the import RPC.
revoke all on function public.create_est_lote_mp(
  bigint, numeric, text, text, text, date, date, text, text
) from public;
revoke execute on function public.create_est_lote_mp(
  bigint, numeric, text, text, text, date, date, text, text
) from anon;
grant execute on function public.create_est_lote_mp(
  bigint, numeric, text, text, text, date, date, text, text
) to authenticated;

comment on function public.create_est_lote_mp(
  bigint, numeric, text, text, text, date, date, text, text
) is
  'Audited MP lot entrypoint. Authenticated execution requires estoque.mp.lots.create.';
