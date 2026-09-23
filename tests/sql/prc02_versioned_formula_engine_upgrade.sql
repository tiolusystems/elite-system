\set ON_ERROR_STOP on
begin;

do $$
begin
  if to_regclass('public.prc_politicas') is null
     or to_regprocedure('public.salvar_prc_politica_versao_v2_idempotente(uuid,bigint,text,text,numeric,numeric,numeric,text)') is null then
    raise exception 'PRC-01/0150 contract missing before PRC-02 upgrade';
  end if;
  if to_regclass('public.prc_formula_versoes') is null
     or to_regprocedure('public.salvar_prc_formula_versao_idempotente(uuid,bigint,text,jsonb,jsonb,text[],bigint,integer,text)') is null then
    raise exception 'PRC-02 0151 contract missing after upgrade';
  end if;
  if (select max(version) from supabase_migrations.schema_migrations) <> '0151' then
    raise exception 'upgrade ledger did not reach 0151';
  end if;
end $$;

rollback;
\echo PG_PRC02_0150_0151_UPGRADE_OK
