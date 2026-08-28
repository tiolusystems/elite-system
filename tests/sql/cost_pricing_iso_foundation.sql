\set ON_ERROR_STOP on
begin;

do $$ begin
  if has_function_privilege('anon','public.consultar_prc_workspace()','EXECUTE')
     or has_function_privilege('public','public.calcular_prc_cenario_idempotente(uuid,bigint,text)','EXECUTE')
     or has_table_privilege('authenticated','public.prc_calculos','INSERT') then
    raise exception 'precificacao excedeu default deny';
  end if;
  if not has_function_privilege('authenticated','public.consultar_prc_workspace()','EXECUTE') then raise exception 'consulta governada indisponivel'; end if;
end $$;

insert into auth.users(id,email) values
 ('13800000-0000-4000-8000-000000000001','prc-author@test.invalid'),
 ('13800000-0000-4000-8000-000000000002','prc-reviewer@test.invalid'),
 ('13800000-0000-4000-8000-000000000003','prc-admin@test.invalid'),
 ('13800000-0000-4000-8000-000000000004','prc-denied@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
 ('13800000-0000-4000-8000-000000000001','Autor PRC 01','comercial','active'),
 ('13800000-0000-4000-8000-000000000002','Revisor PRC 01','admin','active'),
 ('13800000-0000-4000-8000-000000000003','Setup PRC 01','admin','active'),
 ('13800000-0000-4000-8000-000000000004','Sem alcada PRC 01','comercial','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
select actor.id, action.action_key, true, '13800000-0000-4000-8000-000000000003'
from (values ('13800000-0000-4000-8000-000000000001'::uuid),('13800000-0000-4000-8000-000000000002'::uuid)) actor(id)
cross join public.permission_actions action where action.action_key like 'precificacao.%'
on conflict(user_id,action_key) do update set allowed=true,updated_by=excluded.updated_by;
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
values ('13800000-0000-4000-8000-000000000003','system.admin',true,'13800000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000003',true);
select public.set_system_runtime_environment('test','test_reset','PRC-01 disposable smoke') where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-01 disposable smoke');

insert into public.cad_produtos_base(codigo_produto,nome,nome_norm,status,created_by,updated_by)
values ('0138','Produto sintetico PRC-01','produto sintetico prc-01','active','13800000-0000-4000-8000-000000000003','13800000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao,descricao_norm,unidade,volume_litros,status,unidade_id,origem_dados,created_by,updated_by)
values ('Apresentacao sintetica PRC-01','apresentacao sintetica prc-01','UN',20,'active',(select id from public.cad_unidades_medida where lower(codigo)='un'),'sistema','13800000-0000-4000-8000-000000000003','13800000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id,embalagem_id,codigo_item,status,origem_dados,created_by,updated_by)
select p.id,e.id,'PRC0138-20L','active','sistema','13800000-0000-4000-8000-000000000003','13800000-0000-4000-8000-000000000003'
from public.cad_produtos_base p cross join public.cad_embalagens e where p.codigo_produto='0138' and e.descricao='Apresentacao sintetica PRC-01';

create function pg_temp.prc_components(p_mp numeric default 10,p_pack numeric default 2,p_source text default 'fixture_validacao') returns jsonb language sql as $$
 select jsonb_build_array(
  jsonb_build_object('campo','materia_prima','valor',p_mp,'unidade','BRL_L','source_kind',p_source,'source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','embalagem','valor',p_pack,'unidade','BRL_L','source_kind',p_source,'source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','custo_pontuacao_vendedor','valor',1,'unidade','BRL_L','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','custo_pontuacao_revenda','valor',1,'unidade','BRL_L','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','premiacao_revenda','valor',1,'unidade','BRL_L','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','premio_producao','valor',1,'unidade','BRL_L','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','frete','valor',1,'unidade','BRL_L','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Valor sintetico controlado para validacao'),
  jsonb_build_object('campo','comissao','valor',0.10,'unidade','FRACAO','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Taxa sintetica controlada para validacao'),
  jsonb_build_object('campo','risco','valor',0.02,'unidade','FRACAO','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Taxa sintetica controlada para validacao'),
  jsonb_build_object('campo','marketing','valor',0.05,'unidade','FRACAO','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Taxa sintetica controlada para validacao'),
  jsonb_build_object('campo','tributacao','valor',0.10,'unidade','FRACAO','source_kind','fixture_validacao','source_reference','FIXTURE-PRC-01','source_effective_date',current_date,'reason','Taxa sintetica controlada para validacao')
 ); $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000004',true);
do $$ begin
  begin perform public.consultar_prc_workspace(); raise exception 'usuario sem alcada consultou precificacao';
  exception when others then if sqlerrm='usuario sem alcada consultou precificacao' or sqlerrm<>'not allowed: precificacao.view' then raise; end if; end;
end $$;

do $$ declare v_lists bigint; begin
  begin
    select count(*) into v_lists from public.com_lista_preco_publicacoes;
    raise exception 'authenticated direct publication read was exposed';
  exception when others then
    if sqlerrm='authenticated direct publication read was exposed'
       or position('permission denied for table com_lista_preco_publicacoes' in sqlerrm)=0 then
      raise;
    end if;
  end;
end $$;

do $$ declare v_calculations bigint; v_terms bigint; begin
  begin
    select count(*) into v_calculations from public.prc_calculos;
    raise exception 'authenticated direct calculation read was exposed';
  exception when others then
    if sqlerrm='authenticated direct calculation read was exposed'
       or position('permission denied for table prc_calculos' in sqlerrm)=0 then
      raise;
    end if;
  end;
  begin
    select count(*) into v_terms from public.prc_calculo_precos_prazo;
    raise exception 'authenticated direct term read was exposed';
  exception when others then
    if sqlerrm='authenticated direct term read was exposed'
       or position('permission denied for table prc_calculo_precos_prazo' in sqlerrm)=0 then
      raise;
    end if;
  end;
end $$;

reset role;
do $$ declare v_lists bigint; v_payments bigint; begin
  select count(*) into v_lists from public.com_lista_preco_publicacoes;
  select count(*) into v_payments from public.fin_comissao_movimentos;
  perform set_config('prc.baseline_lists',v_lists::text,true);
  perform set_config('prc.baseline_payments',v_payments::text,true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000001',true);
do $$ declare v_margin bigint; v_markup bigint; v_bad bigint; v_scenario bigint; v_manual bigint; v_calc bigint; v_retry bigint; begin
  create temporary table pg_temp.prc_ids(margin bigint,markup bigint,bad bigint,scenario bigint,manual bigint,calc bigint,markup_calc bigint,decision bigint,lists bigint,payments bigint) on commit drop;
  insert into pg_temp.prc_ids values(null,null,null,null,null,null,null,null,current_setting('prc.baseline_lists')::bigint,current_setting('prc.baseline_payments')::bigint);
  v_margin:=public.salvar_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000010','MARGEM-01','Margem padrao','margem_liquida',0.20,null,0.01,'Politica sintetica de margem liquida');
  v_retry:=public.salvar_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000010','MARGEM-01','Margem padrao','margem_liquida',0.20,null,0.01,'Politica sintetica de margem liquida'); if v_retry<>v_margin then raise exception 'retry de politica duplicou fato'; end if;
  begin perform public.salvar_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000010','MARGEM-01','Margem padrao','margem_liquida',0.25,null,0.01,'Politica sintetica de margem liquida'); raise exception 'retry divergente aceito'; exception when others then if sqlerrm='retry divergente aceito' or position('divergente' in sqlerrm)=0 then raise; end if; end;
  v_markup:=public.salvar_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000011','MARKUP-01','Markup padrao','markup',null,0.25,0.01,'Politica sintetica de markup comercial');
  v_bad:=public.salvar_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000012','MARGEM-INVALIDA','Margem invalida controlada','margem_liquida',0.80,null,0.01,'Politica para validar denominador invalido');
  begin perform public.decidir_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000013',v_margin,'APPROVED','Autor nao pode aprovar a propria politica'); raise exception 'segregacao de politica falhou'; exception when others then if sqlerrm='segregacao de politica falhou' or position('criador' in sqlerrm)=0 then raise; end if; end;
  update pg_temp.prc_ids set margin=v_margin,markup=v_markup,bad=v_bad;
end $$;

select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000002',true);
do $$ declare v pg_temp.prc_ids%rowtype; begin select * into v from pg_temp.prc_ids;
 perform public.decidir_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000020',v.margin,'APPROVED','Revisao independente da politica de margem');
 perform public.decidir_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000021',v.markup,'APPROVED','Revisao independente da politica de markup');
 perform public.decidir_prc_politica_versao_idempotente('13800000-0000-4000-8000-000000000022',v.bad,'APPROVED','Revisao para teste de denominador bloqueado');
end $$;

select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000001',true);
do $$ declare v pg_temp.prc_ids%rowtype; v_presentation bigint; v_markup_s bigint; v_bad_s bigint; v_markup_calc bigint; begin select * into v from pg_temp.prc_ids; select id into v_presentation from public.cad_produto_embalagens where codigo_item='PRC0138-20L';
 v.scenario:=public.criar_prc_cenario_idempotente('13800000-0000-4000-8000-000000000030',v.margin,v_presentation,'Cenario base margem','Cenario sintetico de margem para revisao',pg_temp.prc_components());
 v.manual:=public.criar_prc_cenario_idempotente('13800000-0000-4000-8000-000000000031',v.margin,v_presentation,'Aumento manual de embalagem','Substituicao restrita ao cenario de embalagem',pg_temp.prc_components(10,3,'substituicao_manual'));
 v_markup_s:=public.criar_prc_cenario_idempotente('13800000-0000-4000-8000-000000000032',v.markup,v_presentation,'Cenario base markup','Cenario sintetico de markup para revisao',pg_temp.prc_components());
 v_bad_s:=public.criar_prc_cenario_idempotente('13800000-0000-4000-8000-000000000033',v.bad,v_presentation,'Denominador invalido','Cenario sintetico para bloqueio de denominador',pg_temp.prc_components());
 begin perform public.criar_prc_cenario_idempotente('13800000-0000-4000-8000-000000000034',v.margin,v_presentation,'Cenario incompleto','Componente ausente precisa bloquear o cenario',(pg_temp.prc_components()-10)); raise exception 'cenario incompleto aceito'; exception when others then if sqlerrm='cenario incompleto aceito' or position('11 componentes' in sqlerrm)=0 then raise; end if; end;
 v.calc:=public.calcular_prc_cenario_idempotente('13800000-0000-4000-8000-000000000040',v.scenario,'Calculo de margem para memoria governada');
 v_markup_calc:=public.calcular_prc_cenario_idempotente('13800000-0000-4000-8000-000000000041',v_markup_s,'Calculo de markup para memoria governada');
 begin perform public.calcular_prc_cenario_idempotente('13800000-0000-4000-8000-000000000042',v_bad_s,'Calculo precisa falhar por denominador invalido'); raise exception 'denominador invalido aceito'; exception when others then if sqlerrm='denominador invalido aceito' or position('denominador' in sqlerrm)=0 then raise; end if; end;
 update pg_temp.prc_ids set scenario=v.scenario,manual=v.manual,calc=v.calc,markup_calc=v_markup_calc;
end $$;

reset role;
do $$ declare v pg_temp.prc_ids%rowtype; begin
 select * into v from pg_temp.prc_ids;
 if (select preco_vista from public.prc_calculos where id=v.calc)<>30.91 then raise exception 'formula de margem ou HALF_UP divergente'; end if;
 if (select preco_vista from public.prc_calculos where id=v.markup_calc)<>28.33 then raise exception 'formula de markup divergente'; end if;
 if (select count(*) from public.prc_calculo_precos_prazo where calculo_id=v.calc)<>18 or not exists(select 1 from public.prc_calculo_precos_prazo where calculo_id=v.calc and prazo_dias=540) then raise exception 'grade 30..540 incompleta'; end if;
end $$;

set local role authenticated;
do $$ declare v pg_temp.prc_ids%rowtype; begin select * into v from pg_temp.prc_ids;
 begin update public.prc_calculos set motivo='tentativa' where id=v.calc; raise exception 'UPDATE de calculo aceito'; exception when sqlstate '42501' then null; when others then raise; end;
 begin delete from public.prc_calculo_componentes where calculo_id=v.calc; raise exception 'DELETE de componente aceito'; exception when sqlstate '42501' then null; when others then raise; end;
 begin truncate public.prc_calculo_precos_prazo; raise exception 'TRUNCATE de prazo aceito'; exception when sqlstate '42501' then null; when others then raise; end;
 begin insert into public.prc_calculos(cenario_id,politica_versao_id,politica_documento_sha256,metodo,custo_base_exato,preco_vista_exato,preco_vista,cmv_percentual,contribuicao_liquida,intermediarios_json,arredondamento,casas_decimais,motivo,correlation_id,result_sha256,created_by) values(v.scenario,v.margin,repeat('0',64),'markup',1,1,1,1,1,'{}','HALF_UP',2,'tentativa direta bloqueada','direct',repeat('0',64),'13800000-0000-4000-8000-000000000001'); raise exception 'INSERT direto aceito'; exception when sqlstate '42501' then null; when others then raise; end;
 begin perform public.decidir_prc_calculo_idempotente('13800000-0000-4000-8000-000000000050',v.calc,'APPROVED','Autor nao pode aprovar o proprio calculo'); raise exception 'segregacao de calculo falhou'; exception when others then if sqlerrm='segregacao de calculo falhou' or position('criador' in sqlerrm)=0 then raise; end if; end;
end $$;

reset role;
do $$ declare v pg_temp.prc_ids%rowtype; begin select * into v from pg_temp.prc_ids;
 begin update public.prc_calculos set motivo='tentativa proprietaria' where id=v.calc; raise exception 'UPDATE proprietario de calculo aceito'; exception when others then if sqlerrm='UPDATE proprietario de calculo aceito' or position('append-only' in lower(sqlerrm))=0 then raise; end if; end;
 begin delete from public.prc_calculo_componentes where calculo_id=v.calc; raise exception 'DELETE proprietario de componente aceito'; exception when others then if sqlerrm='DELETE proprietario de componente aceito' or position('append-only' in lower(sqlerrm))=0 then raise; end if; end;
end $$;

set local role authenticated; select set_config('request.jwt.claim.sub','13800000-0000-4000-8000-000000000002',true);
do $$ declare v pg_temp.prc_ids%rowtype; v_dec bigint; v_retry bigint; v_workspace jsonb; begin select * into v from pg_temp.prc_ids;
  v_dec:=public.decidir_prc_calculo_idempotente('13800000-0000-4000-8000-000000000051',v.calc,'APPROVED','Revisao independente do calculo sintetico');
  v_retry:=public.decidir_prc_calculo_idempotente('13800000-0000-4000-8000-000000000051',v.calc,'APPROVED','Revisao independente do calculo sintetico'); if v_dec<>v_retry then raise exception 'retry de decisao duplicou fato'; end if;
  update pg_temp.prc_ids set decision=v_dec;
  select public.consultar_prc_workspace() into v_workspace; if (v_workspace->>'publication_enabled')::boolean or jsonb_array_length(v_workspace->'cenarios')<2 then raise exception 'dossie governado ou limite de publicacao divergente'; end if;
end $$;

reset role;
do $$ declare v pg_temp.prc_ids%rowtype; begin
  select * into v from pg_temp.prc_ids;
  if not exists(select 1 from public.action_logs where domain='precificacao' and action_key='precificacao.calculation.review' and entity_id=v.decision::text) then
    raise exception 'auditoria da decisao ausente';
  end if;
  if (select count(*) from public.com_lista_preco_publicacoes)<>v.lists
     or (select count(*) from public.fin_comissao_movimentos)<>v.payments then
    raise exception 'PRC-01 gerou efeito comercial ou financeiro';
  end if;
end $$;

rollback;
