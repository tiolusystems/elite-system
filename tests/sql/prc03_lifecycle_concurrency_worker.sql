\set ON_ERROR_STOP on

begin;
set local application_name = 'prc03_lifecycle_concurrency';
select set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000001',true);

select public.alterar_prc_valoracao_lifecycle_idempotente(
  :'request_key'::uuid,:'version_id'::bigint,'ACTIVE','Ativacao concorrente de politica deve serializar'
)
where :'target_kind'='policy';
select public.alterar_prc_valoracao_referencia_lifecycle_idempotente(
  :'request_key'::uuid,:'version_id'::bigint,'ACTIVE','Ativacao concorrente de referencia deve serializar'
)
where :'target_kind'='reference';

-- The transaction-level lock remains held while the companion session reaches
-- the same governed transition, proving a real two-session serialization.
select pg_sleep(2);
commit;
