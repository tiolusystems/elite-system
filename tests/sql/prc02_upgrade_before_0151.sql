\set ON_ERROR_STOP on
begin;

do $$ begin
  if (select max(version) from supabase_migrations.schema_migrations)<>'0150'
     or to_regclass('public.prc_formula_versoes') is not null then
    raise exception 'upgrade fixture exige ledger 0150 sem PRC-02';
  end if;
end $$;

create table public.prc02_upgrade_probe (
  policy_id bigint not null,
  policy_sha text not null,
  legacy_id bigint not null,
  legacy_sha text not null,
  calculation_id bigint not null,
  calculation_sha text not null,
  calculation_json jsonb not null
);
insert into auth.users(id,email) values
 ('15110000-0000-4000-8000-000000000001','prc02-upgrade-author@test.invalid'),
 ('15110000-0000-4000-8000-000000000002','prc02-upgrade-reviewer@test.invalid'),
 ('15110000-0000-4000-8000-000000000003','prc02-upgrade-setup@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
 ('15110000-0000-4000-8000-000000000001','PRC02 Upgrade Author','admin','active'),
 ('15110000-0000-4000-8000-000000000002','PRC02 Upgrade Reviewer','admin','active'),
 ('15110000-0000-4000-8000-000000000003','PRC02 Upgrade Setup','admin','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
select actor.id, action.action_key, true, '15110000-0000-4000-8000-000000000003'
from (values ('15110000-0000-4000-8000-000000000001'::uuid),('15110000-0000-4000-8000-000000000002'::uuid)) actor(id)
cross join public.permission_actions action where action.action_key like 'precificacao.%';
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
values ('15110000-0000-4000-8000-000000000003','system.admin',true,'15110000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub','15110000-0000-4000-8000-000000000003',true);
select public.set_system_runtime_environment('test','test_reset','PRC-02 upgrade fixture') where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-02 upgrade fixture');
insert into public.cad_produtos_base(codigo_produto,nome,nome_norm,status,created_by,updated_by)
values ('1511','Produto PRC02 Upgrade','produto prc02 upgrade','active','15110000-0000-4000-8000-000000000003','15110000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao,descricao_norm,unidade,volume_litros,status,unidade_id,origem_dados,created_by,updated_by)
values ('Embalagem PRC02 Upgrade','embalagem prc02 upgrade','UN',20,'active',
 (select id from public.cad_unidades_medida where lower(codigo)='un'),'sistema',
 '15110000-0000-4000-8000-000000000003','15110000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id,embalagem_id,codigo_item,status,origem_dados,created_by,updated_by)
select p.id,e.id,'PRC02-UP-20L','active','sistema','15110000-0000-4000-8000-000000000003','15110000-0000-4000-8000-000000000003'
from public.cad_produtos_base p cross join public.cad_embalagens e
where p.codigo_produto='1511' and e.descricao='Embalagem PRC02 Upgrade';

do $fixture$
declare v_policy bigint; v_legacy bigint; v_scenario bigint; v_calc bigint; v_components jsonb;
begin
  perform set_config('request.jwt.claim.sub','15110000-0000-4000-8000-000000000001',true);
  v_policy:=public.salvar_prc_politica_versao_v2_idempotente('15110000-0000-4000-8000-000000000011',null,'Upgrade margem','margem_liquida',0.20,null,0.01,'Politica criada antes da migration 0151');
  v_legacy:=public.salvar_prc_politica_versao_idempotente('15110000-0000-4000-8000-000000000012','POL-LEGACY','Upgrade legado','markup',null,0.20,0.01,'Wrapper legado antes da migration 0151');
  perform set_config('request.jwt.claim.sub','15110000-0000-4000-8000-000000000002',true);
  perform public.decidir_prc_politica_versao_idempotente('15110000-0000-4000-8000-000000000013',v_policy,'APPROVED','Aprovacao independente no upgrade PRC02');
  perform set_config('request.jwt.claim.sub','15110000-0000-4000-8000-000000000001',true);
  select jsonb_agg(jsonb_build_object('campo',campo,'valor',valor,'unidade',unidade,
    'source_kind','fixture_validacao','source_reference','PRC02-UPGRADE',
    'source_effective_date',current_date,'reason','Valor controlado para upgrade PRC02') order by campo)
    into v_components
    from (values
      ('materia_prima',10.0,'BRL_L'),('embalagem',2.0,'BRL_L'),
      ('custo_pontuacao_vendedor',1.0,'BRL_L'),('custo_pontuacao_revenda',1.0,'BRL_L'),
      ('premiacao_revenda',1.0,'BRL_L'),('premio_producao',1.0,'BRL_L'),
      ('frete',1.0,'BRL_L'),('comissao',0.10,'FRACAO'),('risco',0.02,'FRACAO'),
      ('marketing',0.05,'FRACAO'),('tributacao',0.10,'FRACAO')) c(campo,valor,unidade);
  v_scenario:=public.criar_prc_cenario_idempotente('15110000-0000-4000-8000-000000000014',v_policy,
    (select id from public.cad_produto_embalagens where codigo_item='PRC02-UP-20L'),
    'Cenario anterior a 0151','Cenario PRC01 valido antes do upgrade',v_components);
  v_calc:=public.calcular_prc_cenario_idempotente('15110000-0000-4000-8000-000000000015',v_scenario,'Calculo PRC01 valido antes do upgrade');
  insert into public.prc02_upgrade_probe
  select v_policy,p.documento_sha256,v_legacy,l.documento_sha256,v_calc,c.result_sha256,c.intermediarios_json
    from public.prc_politica_versoes p cross join public.prc_politica_versoes l cross join public.prc_calculos c
   where p.id=v_policy and l.id=v_legacy and c.id=v_calc;
end $fixture$;

commit;
\echo PG_PRC02_PRE_0151_FACTS_OK
