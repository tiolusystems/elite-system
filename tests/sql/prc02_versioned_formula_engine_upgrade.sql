\set ON_ERROR_STOP on
begin;

do $$
declare v_probe public.prc02_upgrade_probe%rowtype; v_v2 bigint; v_legacy bigint; v_grid bigint;
begin
  select * into v_probe from public.prc02_upgrade_probe;
  if not found or (select count(*) from public.prc02_upgrade_probe)<>1 then raise exception 'pre-0151 PRC-01 facts missing'; end if;
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
  if (select documento_sha256 from public.prc_politica_versoes where id=v_probe.policy_id) is distinct from v_probe.policy_sha
     or (select documento_sha256 from public.prc_politica_versoes where id=v_probe.legacy_id) is distinct from v_probe.legacy_sha
     or (select result_sha256 from public.prc_calculos where id=v_probe.calculation_id) is distinct from v_probe.calculation_sha
     or (select intermediarios_json from public.prc_calculos where id=v_probe.calculation_id) is distinct from v_probe.calculation_json
     or (select count(*) from public.prc_calculo_componentes where calculo_id=v_probe.calculation_id)<>11
     or (select count(*) from public.prc_calculo_precos_prazo where calculo_id=v_probe.calculation_id)<>18 then
    raise exception 'PRC-01 facts or hashes changed during 0151';
  end if;
  perform set_config('request.jwt.claim.sub','15110000-0000-4000-8000-000000000001',true);
  v_v2:=public.salvar_prc_politica_versao_v2_idempotente('15110000-0000-4000-8000-000000000021',null,'Upgrade depois','margem_liquida',0.20,null,0.01,'V2 continua funcional apos migration 0151');
  v_legacy:=public.salvar_prc_politica_versao_idempotente('15110000-0000-4000-8000-000000000022','POL-FORGED','Legado depois','markup',null,0.20,0.01,'Wrapper continua funcional apos migration 0151');
  if v_v2 is null or v_legacy is null or v_v2=v_legacy
     or exists(select 1 from public.prc_politicas where codigo='POL-FORGED') then
    raise exception 'RPC V2 ou wrapper legado regressou no upgrade';
  end if;
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  values ('15110000-0000-4000-8000-000000000001','precificacao.formula.manage',true,'15110000-0000-4000-8000-000000000003');
  v_grid:=public.salvar_prc_grade_prazo_versao_idempotente('15110000-0000-4000-8000-000000000023',null,'Grade apos upgrade',
    jsonb_build_array(jsonb_build_object('ordem',1,'prazo_dias',28,'fator_periodo','1')),
    'PRC-02 disponivel depois da migration 0151');
  if v_grid is null or not exists(select 1 from public.prc_grade_prazo_versoes where id=v_grid) then
    raise exception 'PRC-02 indisponivel apos upgrade';
  end if;
end $$;

rollback;
\echo PG_PRC02_0150_0151_UPGRADE_OK
