\set ON_ERROR_STOP on

begin;

insert into auth.users(id,email) values
  ('15230000-0000-4000-8000-000000000001','prc03-lifecycle-manager@test.invalid'),
  ('15230000-0000-4000-8000-000000000002','prc03-lifecycle-reviewer@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
  ('15230000-0000-4000-8000-000000000001','PRC03 Lifecycle Manager','admin','active'),
  ('15230000-0000-4000-8000-000000000002','PRC03 Lifecycle Reviewer','admin','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by) values
  ('15230000-0000-4000-8000-000000000001','system.admin',true,'15230000-0000-4000-8000-000000000001'),
  ('15230000-0000-4000-8000-000000000001','precificacao.valuation.manage',true,'15230000-0000-4000-8000-000000000001'),
  ('15230000-0000-4000-8000-000000000001','precificacao.valuation.lifecycle',true,'15230000-0000-4000-8000-000000000001'),
  ('15230000-0000-4000-8000-000000000002','precificacao.valuation.review',true,'15230000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000001',true);
select public.set_system_runtime_environment('test','test_reset','PRC-03 lifecycle concurrency test')
  where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-03 lifecycle concurrency test');

create table public.prc03_lifecycle_concurrency_probe (
  target_kind text primary key check (target_kind in ('policy','reference')),
  identity_id bigint not null,
  version_one_id bigint not null,
  version_two_id bigint not null
);

do $setup$
declare
  v_policy_one bigint;
  v_policy_two bigint;
  v_policy_id bigint;
  v_ref_one bigint;
  v_ref_two bigint;
  v_ref_id bigint;
  v_mp bigint;
begin
  v_policy_one:=public.salvar_prc_valoracao_versao_idempotente(
    '15230000-0000-4000-8000-000000000011',null,'Politica concorrente',
    'STOCK_ACQUISITION_LAYER','WEIGHTED_AVAILABLE_BALANCE','ALLOW_UNKNOWN',null,
    'Criar primeira versao para concorrencia de lifecycle'
  );
  select politica_id into v_policy_id from public.prc_valoracao_versoes where id=v_policy_one;
  v_policy_two:=public.salvar_prc_valoracao_versao_idempotente(
    '15230000-0000-4000-8000-000000000012',v_policy_id,null,
    'STOCK_ACQUISITION_LAYER','WEIGHTED_AVAILABLE_BALANCE','ALLOW_UNKNOWN',null,
    'Criar segunda versao para concorrencia de lifecycle'
  );
  perform set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15230000-0000-4000-8000-000000000013',v_policy_one,'APPROVED','Aprovar primeira versao concorrente da politica');
  perform public.revisar_prc_valoracao_versao_idempotente('15230000-0000-4000-8000-000000000014',v_policy_two,'APPROVED','Aprovar segunda versao concorrente da politica');
  perform set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000001',true);

  insert into public.cad_materias_primas(sku_corrigido,nome,nome_norm,unidade_base_estoque,status,created_by)
  values('PRC03-LC','MP PRC03 Lifecycle','mp prc03 lifecycle','kg','active','15230000-0000-4000-8000-000000000001')
  returning id into v_mp;
  v_ref_one:=public.salvar_prc_valoracao_referencia_versao_idempotente(
    '15230000-0000-4000-8000-000000000015',null,v_mp,'MARKET','BRL','kg',10,current_date,
    transaction_timestamp()-interval '1 day',null,'Fonte concorrente','REF-LC-1',
    'Criar primeira referencia para concorrencia de lifecycle'
  );
  select referencia_id into v_ref_id from public.prc_valoracao_referencia_versoes where id=v_ref_one;
  v_ref_two:=public.salvar_prc_valoracao_referencia_versao_idempotente(
    '15230000-0000-4000-8000-000000000016',v_ref_id,v_mp,'MARKET','BRL','kg',11,current_date,
    transaction_timestamp()-interval '1 day',null,'Fonte concorrente','REF-LC-2',
    'Criar segunda referencia para concorrencia de lifecycle'
  );
  perform set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_referencia_idempotente('15230000-0000-4000-8000-000000000017',v_ref_one,'APPROVED','Aprovar primeira referencia concorrente');
  perform public.revisar_prc_valoracao_referencia_idempotente('15230000-0000-4000-8000-000000000018',v_ref_two,'APPROVED','Aprovar segunda referencia concorrente');
  perform set_config('request.jwt.claim.sub','15230000-0000-4000-8000-000000000001',true);

  insert into public.prc03_lifecycle_concurrency_probe values
    ('policy',v_policy_id,v_policy_one,v_policy_two),
    ('reference',v_ref_id,v_ref_one,v_ref_two);
end;
$setup$;

commit;
\echo PG_PRC03_LIFECYCLE_CONCURRENCY_SETUP_OK
