\set ON_ERROR_STOP on
begin;

-- Golden master Elite: 30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510,540.
-- The alternative profile uses 28,56,84 and is deliberately sem risco and sem recomposicao comercial.

insert into auth.users(id,email) values
  ('15100000-0000-4000-8000-000000000001','prc02-manager@test.invalid'),
  ('15100000-0000-4000-8000-000000000002','prc02-reviewer@test.invalid'),
  ('15100000-0000-4000-8000-000000000003','prc02-denied@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
  ('15100000-0000-4000-8000-000000000001','PRC02 Manager','admin','active'),
  ('15100000-0000-4000-8000-000000000002','PRC02 Reviewer','admin','active'),
  ('15100000-0000-4000-8000-000000000003','PRC02 Denied','comercial','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
values
  ('15100000-0000-4000-8000-000000000001','precificacao.formula.manage',true,'15100000-0000-4000-8000-000000000001'),
  ('15100000-0000-4000-8000-000000000001','precificacao.formula.lifecycle',true,'15100000-0000-4000-8000-000000000001'),
  ('15100000-0000-4000-8000-000000000002','precificacao.formula.review',true,'15100000-0000-4000-8000-000000000001'),
  ('15100000-0000-4000-8000-000000000002','precificacao.formula.lifecycle',true,'15100000-0000-4000-8000-000000000001');

select set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
values ('15100000-0000-4000-8000-000000000001','system.admin',true,'15100000-0000-4000-8000-000000000001');
select public.set_system_runtime_environment('test','test_reset','PRC-02 disposable smoke') where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-02 disposable smoke');

create function pg_temp.c(p_value text,p_unit text) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','constant','value',p_value,'unit',p_unit)
$$;
create function pg_temp.p(p_code text) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','parameter','code',p_code)
$$;
create function pg_temp.v(p_name text) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','variable','name',p_name)
$$;
create function pg_temp.o(p_op text,p_left jsonb,p_right jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','operation','op',p_op,'args',jsonb_build_array(p_left,p_right))
$$;
create function pg_temp.ast(p_root jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('schema','prc-formula-ast-v1','result_unit','BRL_L','root',p_root)
$$;
create function pg_temp.cost_base() returns jsonb language sql immutable as $$
  select pg_temp.o('add',
    pg_temp.o('add',pg_temp.o('add',pg_temp.p('materia_prima'),pg_temp.p('embalagem')),pg_temp.o('add',pg_temp.p('custo_pontuacao_vendedor'),pg_temp.p('custo_pontuacao_revenda'))),
    pg_temp.o('add',pg_temp.o('add',pg_temp.p('premiacao_revenda'),pg_temp.p('premio_producao')),pg_temp.p('frete')))
$$;
create function pg_temp.commercial_sum(p_include_profit boolean,p_profit text default 'lucro_minimo') returns jsonb language plpgsql immutable as $$
declare v_sum jsonb;
begin
  v_sum:=pg_temp.o('add',pg_temp.p('comissao'),pg_temp.o('add',pg_temp.p('tributacao'),pg_temp.p('marketing')));
  if p_include_profit then v_sum:=pg_temp.o('add',v_sum,pg_temp.p(p_profit)); end if;
  return v_sum;
end $$;
create function pg_temp.term_formula() returns jsonb language sql immutable as $$
  select pg_temp.ast(pg_temp.o('add',pg_temp.v('cash_price'),pg_temp.o('mul',pg_temp.v('cash_price'),
    pg_temp.o('div',pg_temp.o('add',pg_temp.o('sub',pg_temp.o('pow',pg_temp.o('add',pg_temp.c('1','FRACTION'),pg_temp.p('juros_mensais')),pg_temp.v('term_period')),pg_temp.c('1','FRACTION')),pg_temp.p('risco')),
      pg_temp.o('sub',pg_temp.c('1','FRACTION'),pg_temp.commercial_sum(false))))))
$$;
create function pg_temp.values_margin() returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'materia_prima','10','embalagem','2','custo_pontuacao_vendedor','1','custo_pontuacao_revenda','1',
    'premiacao_revenda','1','premio_producao','1','frete','1','comissao','0.10','risco','0.02',
    'marketing','0.05','tributacao','0.10','lucro_minimo','0.20','juros_mensais','0.01')
$$;

do $security$
begin
  if (select count(*) from public.prc_formula_parametros) <> 14 then raise exception 'catalogo inicial deve conter 14 parametros'; end if;
  if exists(select 1 from public.permission_actions where action_key like 'precificacao.formula.%' and default_allowed) then raise exception 'permissao de formula nao e default deny'; end if;
  if has_schema_privilege('authenticated','precificacao_internal','usage')
     or has_function_privilege('authenticated','precificacao_internal.avaliar_prc_formula_ast(jsonb,jsonb,jsonb)','execute')
     or has_function_privilege('anon','precificacao_internal.validar_prc_formula_ast(jsonb,jsonb,jsonb)','execute') then
    raise exception 'helper privado do motor foi exposto';
  end if;
  if has_table_privilege('authenticated','public.prc_formula_versoes','select')
     or has_table_privilege('authenticated','public.prc_formula_versoes','insert')
     or has_table_privilege('anon','public.prc_formula_perfis','select') then
    raise exception 'tabelas do motor excederam default deny';
  end if;
  if not has_function_privilege('authenticated','public.salvar_prc_formula_versao_idempotente(uuid,bigint,text,jsonb,jsonb,text[],bigint,integer,text)','execute') then
    raise exception 'RPC governada de formula indisponivel';
  end if;
end $security$;

set local role authenticated;
select set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000003',true);
do $$ begin
  begin
    perform public.salvar_prc_grade_prazo_versao_idempotente(gen_random_uuid(),null,'Negada',jsonb_build_array(jsonb_build_object('ordem',1,'prazo_dias',30,'fator_periodo','1')),'Tentativa sem permissao adequada');
    raise exception 'usuario sem permissao criou grade';
  exception when others then
    if sqlerrm='usuario sem permissao criou grade' or sqlerrm<>'not allowed: precificacao.formula.manage' then raise; end if;
  end;
end $$;

reset role;

select set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
do $engine$
declare
  v_grid bigint;
  v_alt_grid bigint;
  v_margin bigint;
  v_margin_retry bigint;
  v_margin_v2 bigint;
  v_markup bigint;
  v_alt bigint;
  v_alt_shadow bigint;
  v_rejected bigint;
  v_formula_id bigint;
  v_review bigint;
  v_shadow bigint;
  v_shadow_retry bigint;
  v_result jsonb;
  v_cash numeric;
  v_expected numeric;
  v_code1 text;
  v_code2 text;
  v_count bigint;
  v_failed boolean;
  v_margin_key uuid := '15100000-0000-4000-8000-000000000101';
  v_shadow_key uuid := '15100000-0000-4000-8000-000000000201';
  v_margin_params text[] := array['materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete','comissao','risco','marketing','tributacao','lucro_minimo','juros_mensais'];
  v_markup_params text[] := array['materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete','comissao','risco','marketing','tributacao','markup','juros_mensais'];
  v_margin_ast jsonb := pg_temp.ast(pg_temp.o('div',pg_temp.cost_base(),pg_temp.o('sub',pg_temp.c('1','FRACTION'),pg_temp.commercial_sum(true))));
  v_markup_ast jsonb := pg_temp.ast(pg_temp.o('div',pg_temp.o('mul',pg_temp.cost_base(),pg_temp.o('add',pg_temp.c('1','FRACTION'),pg_temp.p('markup'))),pg_temp.o('sub',pg_temp.c('1','FRACTION'),pg_temp.commercial_sum(false))));
begin
  v_grid:=public.salvar_prc_grade_prazo_versao_idempotente(
    '15100000-0000-4000-8000-000000000011',null,'Grade Elite 18 prazos',
    (select jsonb_agg(jsonb_build_object('ordem',n,'prazo_dias',n*30,'fator_periodo',n::text) order by n) from generate_series(1,18)n),
    'Golden master Elite com dezoito prazos');
  if (select string_agg(prazo_dias::text,',' order by ordem) from public.prc_grade_prazo_itens where grade_versao_id=v_grid) <> '30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510,540' then raise exception 'grade Elite divergente'; end if;

  v_margin:=public.salvar_prc_formula_versao_idempotente(v_margin_key,null,'elite_margem_liquida_v1',v_margin_ast,pg_temp.term_formula(),v_margin_params,v_grid,2,'Golden master Elite para margem liquida');
  v_margin_retry:=public.salvar_prc_formula_versao_idempotente(v_margin_key,null,'elite_margem_liquida_v1',v_margin_ast,pg_temp.term_formula(),v_margin_params,v_grid,2,'Golden master Elite para margem liquida');
  if v_margin_retry<>v_margin then raise exception 'retry idempotente criou segunda formula'; end if;
  v_failed:=false;
  begin perform public.salvar_prc_formula_versao_idempotente(v_margin_key,null,'elite_margem_liquida_v1',v_margin_ast,pg_temp.term_formula(),v_margin_params,v_grid,3,'Golden master Elite para margem liquida');
  exception when others then v_failed:=position('divergente' in sqlerrm)>0; end;
  if not v_failed then raise exception 'retry divergente nao foi recusado'; end if;

  v_markup:=public.salvar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000102',null,'elite_markup_v1',v_markup_ast,pg_temp.term_formula(),v_markup_params,v_grid,2,'Golden master Elite para markup');
  select f1.codigo,f2.codigo into v_code1,v_code2 from public.prc_formula_versoes v1 join public.prc_formula_perfis f1 on f1.id=v1.formula_id cross join public.prc_formula_versoes v2 join public.prc_formula_perfis f2 on f2.id=v2.formula_id where v1.id=v_margin and v2.id=v_markup;
  if v_code1 !~ '^FML-[0-9]{8}$' or v_code2 !~ '^FML-[0-9]{8}$' or v_code1=v_code2 then raise exception 'codigo FML automatico/unico falhou'; end if;
  select formula_id into v_formula_id from public.prc_formula_versoes where id=v_margin;
  v_margin_v2:=public.salvar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000103',v_formula_id,null,v_margin_ast,pg_temp.term_formula(),v_margin_params,v_grid,2,'Nova versao append only da margem Elite');
  if (select versao from public.prc_formula_versoes where id=v_margin_v2)<>2 then raise exception 'versionamento de formula falhou'; end if;

  v_failed:=false;
  begin perform public.salvar_prc_formula_versao_idempotente(gen_random_uuid(),null,'AST SQL proibida',jsonb_build_object('schema','prc-formula-ast-v1','result_unit','BRL_L','root',jsonb_build_object('kind','sql','query','select 1')),pg_temp.term_formula(),v_margin_params,v_grid,2,'Documento arbitrario deve falhar fechado');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'execucao arbitraria foi aceita'; end if;
  v_failed:=false;
  begin perform public.salvar_prc_formula_versao_idempotente(gen_random_uuid(),null,'Unidade invalida',pg_temp.ast(pg_temp.o('add',pg_temp.p('materia_prima'),pg_temp.p('comissao'))),pg_temp.term_formula(),v_margin_params,v_grid,2,'Unidade incompativel deve falhar fechado');
  exception when others then v_failed:=position('unidade incompativel' in sqlerrm)>0; end;
  if not v_failed then raise exception 'unidade incompativel foi aceita'; end if;
  v_failed:=false;
  begin perform public.salvar_prc_formula_versao_idempotente(gen_random_uuid(),null,'Parametro ausente',pg_temp.ast(pg_temp.p('nao_existe')),pg_temp.term_formula(),array['materia_prima'],v_grid,2,'Parametro inexistente deve falhar fechado');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'parametro inexistente foi aceito'; end if;

  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000002',true);
  v_review:=public.revisar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000111',v_margin,'APPROVED','Revisao segregada do golden master Elite');
  perform public.revisar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000112',v_margin_v2,'APPROVED','Revisao segregada da segunda versao');
  perform public.revisar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000113',v_markup,'APPROVED','Revisao segregada do perfil markup');
  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
  v_failed:=false;
  begin perform public.revisar_prc_formula_versao_idempotente(gen_random_uuid(),v_margin_v2,'APPROVED','Autor tenta aprovar a propria formula'); exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'segregacao de revisao falhou'; end if;

  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000002',true);
  perform public.alterar_prc_formula_lifecycle_idempotente('15100000-0000-4000-8000-000000000121',v_margin,'ACTIVE','Ativacao explicita do golden master Elite');
  perform public.alterar_prc_formula_lifecycle_idempotente('15100000-0000-4000-8000-000000000122',v_margin_v2,'ACTIVE','Ativacao atomica da segunda versao Elite');
  if precificacao_internal.prc_formula_estado_atual(v_margin)<>'SUPERSEDED' or precificacao_internal.prc_formula_estado_atual(v_margin_v2)<>'ACTIVE' then raise exception 'supersessao atomica falhou'; end if;
  perform public.alterar_prc_formula_lifecycle_idempotente('15100000-0000-4000-8000-000000000123',v_margin_v2,'WITHDRAWN','Retirada explicita da segunda versao Elite');
  v_failed:=false;
  begin perform public.alterar_prc_formula_lifecycle_idempotente(gen_random_uuid(),v_margin_v2,'ACTIVE','Reativacao indevida da formula retirada'); exception when others then v_failed:=position('historica' in sqlerrm)>0; end;
  if not v_failed then raise exception 'formula retirada foi reativada'; end if;

  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
  v_rejected:=public.salvar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000104',null,'Formula rejeitada',v_margin_ast,pg_temp.term_formula(),v_margin_params,v_grid,2,'Formula criada para provar rejeicao');
  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000114',v_rejected,'REJECTED','Formula rejeitada para prova de lifecycle');
  v_failed:=false;
  begin perform public.alterar_prc_formula_lifecycle_idempotente(gen_random_uuid(),v_rejected,'ACTIVE','Tentativa de ativar formula rejeitada'); exception when others then v_failed:=position('aprovada' in sqlerrm)>0; end;
  if not v_failed then raise exception 'formula rejeitada foi ativada'; end if;

  perform public.alterar_prc_formula_lifecycle_idempotente('15100000-0000-4000-8000-000000000124',v_markup,'ACTIVE','Ativacao explicita do golden master markup');
  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
  v_shadow:=public.executar_prc_formula_shadow_idempotente(v_shadow_key,v_markup,pg_temp.values_margin()-'lucro_minimo'||jsonb_build_object('markup','0.20'),null,'Golden master Elite em shadow mode');
  v_shadow_retry:=public.executar_prc_formula_shadow_idempotente(v_shadow_key,v_markup,pg_temp.values_margin()-'lucro_minimo'||jsonb_build_object('markup','0.20'),null,'Golden master Elite em shadow mode');
  if v_shadow<>v_shadow_retry then raise exception 'shadow retry nao foi idempotente'; end if;
  select resultado_json into v_result from public.prc_formula_shadow_execucoes where id=v_shadow;
  v_cash:=(v_result#>>'{cash,exact}')::numeric;
  v_expected:=17*1.20/(1-0.10-0.10-0.05);
  if v_cash<>v_expected or jsonb_array_length(v_result->'terms')<>18 then raise exception 'golden master Elite markup divergente'; end if;
  if (v_result#>>'{terms,0,exact}')::numeric <> v_cash + v_cash*((power(1.01::numeric,1)-1)+0.02)/(1-0.10-0.10-0.05) then raise exception 'golden master Elite prazo divergente'; end if;

  v_alt_grid:=public.salvar_prc_grade_prazo_versao_idempotente('15100000-0000-4000-8000-000000000012',null,'Grade alternativa 28 dias',jsonb_build_array(jsonb_build_object('ordem',1,'prazo_dias',28,'fator_periodo','1'),jsonb_build_object('ordem',2,'prazo_dias',56,'fator_periodo','2'),jsonb_build_object('ordem',3,'prazo_dias',84,'fator_periodo','3')),'Perfil alternativo com tres prazos');
  v_alt:=public.salvar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000105',null,'Perfil alternativo sem risco',pg_temp.ast(pg_temp.o('div',pg_temp.cost_base(),pg_temp.o('sub',pg_temp.c('1','FRACTION'),pg_temp.p('lucro_minimo')))),pg_temp.ast(pg_temp.o('mul',pg_temp.v('cash_price'),pg_temp.o('pow',pg_temp.o('add',pg_temp.c('1','FRACTION'),pg_temp.p('juros_mensais')),pg_temp.v('term_period')))),array['materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete','lucro_minimo','juros_mensais'],v_alt_grid,2,'Perfil alternativo declarativo sem risco');
  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_formula_versao_idempotente('15100000-0000-4000-8000-000000000115',v_alt,'APPROVED','Revisao segregada do perfil alternativo');
  perform public.alterar_prc_formula_lifecycle_idempotente('15100000-0000-4000-8000-000000000125',v_alt,'ACTIVE','Ativacao explicita do perfil alternativo');
  perform set_config('request.jwt.claim.sub','15100000-0000-4000-8000-000000000001',true);
  v_alt_shadow:=public.executar_prc_formula_shadow_idempotente('15100000-0000-4000-8000-000000000202',v_alt,pg_temp.values_margin()-array['comissao','risco','marketing','tributacao'],null,'Perfil alternativo avaliado sem risco comercial');
  select resultado_json into v_result from public.prc_formula_shadow_execucoes where id=v_alt_shadow;
  if jsonb_array_length(v_result->'terms')<>3
     or (v_result#>>'{cash,exact}')::numeric<>17/(1-0.20)
     or (v_result#>>'{terms,0,exact}')::numeric<>(17/(1-0.20))*power(1.01::numeric,1) then
    raise exception 'perfil alternativo divergente';
  end if;

  v_failed:=false;
  begin perform public.executar_prc_formula_shadow_idempotente(gen_random_uuid(),v_alt,pg_temp.values_margin()-array['comissao','risco','marketing','tributacao']||jsonb_build_object('lucro_minimo','1'),null,'Divisao por zero deve falhar fechado');
  exception when others then v_failed:=position('divisao por zero' in sqlerrm)>0; end;
  if not v_failed then raise exception 'divisao por zero nao falhou fechado'; end if;
end $engine$;

-- The previous block intentionally reaches every governance gate before rollback.
-- Correct a typo guard in the alternative parameter list by requiring the catalog name.
-- This assertion remains outside the write path and documents the canonical token.
do $$ begin
  if not exists(select 1 from public.prc_formula_parametros where codigo='custo_pontuacao_vendedor') then raise exception 'catalogo canonico incompleto'; end if;
end $$;

reset role;

do $append_only$
declare v_blocked boolean:=false;
begin
  begin
    update public.prc_formula_versoes set motivo='Alteracao proibida em fato append only'
     where id=(select min(id) from public.prc_formula_versoes);
  exception when others then v_blocked:=position('append-only' in sqlerrm)>0; end;
  if not v_blocked then raise exception 'append-only update nao foi bloqueado'; end if;
end $append_only$;

rollback;
\echo PG_PRC02_VERSIONED_FORMULA_ENGINE_OK
