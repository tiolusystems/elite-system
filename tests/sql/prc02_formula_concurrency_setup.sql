\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values ('15120000-0000-4000-8000-000000000001','prc02-concurrency@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
 ('15120000-0000-4000-8000-000000000001','PRC02 Concurrency','admin','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
values
 ('15120000-0000-4000-8000-000000000001','system.admin',true,'15120000-0000-4000-8000-000000000001'),
 ('15120000-0000-4000-8000-000000000001','precificacao.formula.manage',true,'15120000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','15120000-0000-4000-8000-000000000001',true);
select public.set_system_runtime_environment('test','test_reset','PRC-02 concurrent formula test') where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-02 concurrent formula test');
create table public.prc02_formula_concurrency_probe (worker text primary key, version_id bigint not null);
do $$ declare v_grade bigint; begin
  v_grade:=public.salvar_prc_grade_prazo_versao_idempotente('15120000-0000-4000-8000-000000000011',null,'Grade concorrente',
    jsonb_build_array(jsonb_build_object('ordem',1,'prazo_dias',30,'fator_periodo','1')),
    'Grade para concorrencia real de perfis');
  perform set_config('prc02.concurrency.grid',v_grade::text,true);
end $$;
commit;
\echo PG_PRC02_CONCURRENCY_SETUP_OK
