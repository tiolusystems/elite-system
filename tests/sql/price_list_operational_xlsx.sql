\set ON_ERROR_STOP on
begin;

do $$
begin
  if has_function_privilege('authenticated', 'public.stage_com_lista_preco_xlsx_import_idempotente(uuid,text,text,bigint,jsonb,jsonb,jsonb,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.apply_com_lista_preco_import_idempotente(uuid,bigint,bigint,date,date,text,jsonb,text)', 'EXECUTE') then
    raise exception 'entrypoints legados por nome continuam expostos ao papel de aplicacao';
  end if;
  if has_function_privilege('anon', 'public.analisar_com_lista_preco_xlsx_operacional_idempotente(uuid,text,text,bigint,jsonb,jsonb,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.publicar_com_lista_preco_xlsx_operacional_idempotente(uuid,bigint,text,boolean,text)', 'EXECUTE') then
    raise exception 'RPC operacional XLSX exposta a anon ou PUBLIC';
  end if;
  if has_table_privilege('authenticated', 'public.com_lista_preco_xlsx_linhas', 'INSERT') then
    raise exception 'escrita direta no staging operacional esta exposta';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('13700000-0000-4000-8000-000000000001', 'price-list-ui-author@test.invalid'),
  ('13700000-0000-4000-8000-000000000002', 'price-list-ui-admin@test.invalid'),
  ('13700000-0000-4000-8000-000000000003', 'price-list-ui-denied@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('13700000-0000-4000-8000-000000000001', 'Autor lista 0137', 'comercial', 'active'),
  ('13700000-0000-4000-8000-000000000002', 'Setup lista 0137', 'admin', 'active'),
  ('13700000-0000-4000-8000-000000000003', 'Sem alcada lista 0137', 'comercial', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select '13700000-0000-4000-8000-000000000001', action.action_key, true, '13700000-0000-4000-8000-000000000002'
from public.permission_actions action
where action.action_key in ('pedidos.price_lists.view', 'pedidos.price_lists.import.stage', 'pedidos.price_lists.draft.manage', 'pedidos.price_lists.publish', 'pedidos.price_reference.resolve')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values ('13700000-0000-4000-8000-000000000002', 'system.admin', true, '13700000-0000-4000-8000-000000000002')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '13700000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke da UI operacional de listas 0137')
where public.current_system_environment() = 'unconfigured';

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values
  ('0137', 'Produto Canonico 0137', 'produto canonico 0137', 'active', '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002'),
  ('1371', 'Outro Produto 0137', 'outro produto 0137', 'active', '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by)
values
  ('Bomba Canonica 20 L 0137', 'bomba canonica 20 l 0137', 'UN', 20, 'active', 6, 'sistema', '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002'),
  ('Bomba Outro Produto 20 L 0137', 'bomba outro produto 20 l 0137', 'UN', 20, 'active', 6, 'sistema', '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, package.id,
       case when product.codigo_produto = '0137' then 'P0137-20L' else 'P1371-20L' end,
       'active', 'sistema', '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002'
from public.cad_produtos_base product
join public.cad_embalagens package on package.descricao = case when product.codigo_produto = '0137' then 'Bomba Canonica 20 L 0137' else 'Bomba Outro Produto 20 L 0137' end
where product.codigo_produto in ('0137', '1371');

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente lista operacional 0137', 'cliente lista operacional 0137', 'Campinas', 'SP', 'active',
  '13700000-0000-4000-8000-000000000002', '13700000-0000-4000-8000-000000000002');
insert into public.com_listas_preco(codigo, nome, descricao, created_by)
values ('LST137', 'Lista Canonica Existente 0137', 'Lista preexistente para identidade por codigo',
  '13700000-0000-4000-8000-000000000002');

create function pg_temp.with_operational_row_hash(p_line jsonb)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select p_line || jsonb_build_object('row_sha256', public.ord01_price_list_xlsx_row_sha256(p_line));
$$;

create function pg_temp.price_list_id_by_code(p_codigo text)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select id from public.com_listas_preco where codigo = p_codigo;
$$;

create function pg_temp.price_list_name(p_lista_id bigint)
returns text
language sql
security definer
set search_path = public, pg_temp
as $$
  select nome from public.com_listas_preco where id = p_lista_id;
$$;

create function pg_temp.client_id_by_name(p_nome text)
returns bigint language sql security definer set search_path = public, pg_temp
as $$ select id from public.cad_clientes where nome = p_nome; $$;

create function pg_temp.origin_id_by_code(p_codigo text)
returns bigint language sql security definer set search_path = public, pg_temp
as $$ select id from public.com_origens_comerciais where codigo = p_codigo; $$;

create function pg_temp.presentation_id_by_code(p_codigo text)
returns bigint language sql security definer set search_path = public, pg_temp
as $$ select id from public.cad_produto_embalagens where codigo_item = p_codigo; $$;

create function pg_temp.price_list_version_count(p_lista_id bigint)
returns bigint language sql security definer set search_path = public, pg_temp
as $$ select count(*) from public.com_lista_preco_versoes where lista_id = p_lista_id; $$;

create function pg_temp.audit_event_count(p_action text, p_entity_id text)
returns bigint language sql security definer set search_path = public, pg_temp
as $$ select count(*) from public.action_logs where action = p_action and entity_id = p_entity_id; $$;

do $$
begin
  if public.ord01_price_list_xlsx_row_sha256(jsonb_build_object(
    'excel_row',2,'codigo_produto','9137','nome_produto','Produto parser','codigo_apresentacao','PLX137-20L','nome_apresentacao','Embalagem parser',
    'unidade_precificacao','l','fator_por_apresentacao',20,'pmp_min_dias',0,'pmp_max_dias',30,'preco_unitario',31.255,'observacao',null,
    'source_payload',jsonb_build_object('A','9137','B','Produto parser','C','PLX137-20L','D','Embalagem parser','E','l','F',20,'G',0,'H',30,'I',31.255,'J',null),
    'formulas','{}'::jsonb,
    'celulas',jsonb_build_object('codigo_produto','A2','nome_produto','B2','codigo_apresentacao','C2','nome_apresentacao','D2','unidade_precificacao','E2','fator_por_apresentacao','F2','pmp_min_dias','G2','pmp_max_dias','H2','preco_unitario','I2','observacao','J2')
  )) <> '1bdd9a313e3a4df12c9d4e45f25e4feed9539fa742fdee26ad81deb3186ad5c4' then
    raise exception 'hash PostgreSQL diverge do vetor canonico compartilhado com TypeScript';
  end if;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13700000-0000-4000-8000-000000000003', true);
do $$
begin
  begin
    perform public.analisar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000010', 'negada.xlsx', repeat('0', 64), 100,
      jsonb_build_object('codigo_lista','NEGADA','nome_lista','Negada','vigencia_inicio',current_date),
      jsonb_build_array(jsonb_build_object('excel_row',2)), 'Tentativa sem alcada individual'
    );
    raise exception 'usuario sem alcada analisou planilha';
  exception when others then
    if sqlerrm = 'usuario sem alcada analisou planilha' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.price_lists.import.stage' then raise exception 'negacao ocorreu fora da permissao: %', sqlerrm; end if;
  end;
end
$$;

select set_config('request.jwt.claim.sub', '13700000-0000-4000-8000-000000000001', true);
do $$
declare
  v_lista jsonb := jsonb_build_object(
    'codigo_lista', 'LST137', 'nome_lista', 'Nome Importado Divergente 0137',
    'vigencia_inicio', current_date, 'vigencia_fim', current_date + 60,
    'uf', 'SP', 'canal', 'direto_elite', 'observacao', 'Lista governada pelo smoke 0137'
  );
  v_line_1 jsonb := jsonb_build_object(
    'excel_row', 2, 'codigo_produto', '0137', 'nome_produto', 'Nome divergente para aviso',
    'codigo_apresentacao', 'P0137-20L', 'nome_apresentacao', 'Bomba Canonica 20 L 0137',
    'unidade_precificacao', 'l', 'fator_por_apresentacao', 20, 'pmp_min_dias', 0, 'pmp_max_dias', 30,
    'preco_unitario', 31.255, 'observacao', null,
    'source_payload', jsonb_build_object('A','0137','B','Nome divergente para aviso','C','P0137-20L','D','Bomba Canonica 20 L 0137','E','l','F',20,'G',0,'H',30,'I',31.255),
    'formulas', '{}'::jsonb, 'celulas', jsonb_build_object(
      'codigo_produto','A2','nome_produto','B2','codigo_apresentacao','C2','nome_apresentacao','D2','unidade_precificacao','E2',
      'fator_por_apresentacao','F2','pmp_min_dias','G2','pmp_max_dias','H2','preco_unitario','I2','observacao','J2')
  );
  v_line_2 jsonb := jsonb_build_object(
    'excel_row', 3, 'codigo_produto', '0137', 'nome_produto', 'Produto Canonico 0137',
    'codigo_apresentacao', 'P0137-20L', 'nome_apresentacao', 'Bomba Canonica 20 L 0137',
    'unidade_precificacao', 'l', 'fator_por_apresentacao', 20, 'pmp_min_dias', 31, 'pmp_max_dias', 60,
    'preco_unitario', 32.50, 'observacao', null,
    'source_payload', jsonb_build_object('A','0137','B','Produto Canonico 0137','C','P0137-20L','D','Bomba Canonica 20 L 0137','E','l','F',20,'G',31,'H',60,'I',32.50),
    'formulas', '{}'::jsonb, 'celulas', jsonb_build_object(
      'codigo_produto','A3','nome_produto','B3','codigo_apresentacao','C3','nome_apresentacao','D3','unidade_precificacao','E3',
      'fator_por_apresentacao','F3','pmp_min_dias','G3','pmp_max_dias','H3','preco_unitario','I3','observacao','J3')
  );
  v_valid jsonb; v_repeat jsonb; v_workbook_repeat jsonb; v_invalid jsonb; v_publish jsonb; v_retry jsonb;
  v_case jsonb; v_case_document jsonb; v_new_publish jsonb; v_clean_line jsonb;
  v_analysis_document jsonb; v_version_document jsonb;
  v_analysis_id bigint; v_invalid_id bigint; v_hash text; v_publication bigint; v_version bigint;
  v_client_id bigint; v_origin_id bigint; v_presentation_id bigint; v_resolution record;
begin
  v_line_1 := pg_temp.with_operational_row_hash(v_line_1);
  v_line_2 := pg_temp.with_operational_row_hash(v_line_2);
  if (pg_temp.with_operational_row_hash(v_line_1 - 'row_sha256')->>'row_sha256')
     is distinct from (pg_temp.with_operational_row_hash(jsonb_build_object(
       'celulas', v_line_1->'celulas', 'formulas', v_line_1->'formulas', 'source_payload', v_line_1->'source_payload',
       'observacao', v_line_1->'observacao', 'preco_unitario', v_line_1->'preco_unitario', 'pmp_max_dias', v_line_1->'pmp_max_dias',
       'pmp_min_dias', v_line_1->'pmp_min_dias', 'fator_por_apresentacao', v_line_1->'fator_por_apresentacao',
       'unidade_precificacao', v_line_1->'unidade_precificacao', 'nome_apresentacao', v_line_1->'nome_apresentacao',
       'codigo_apresentacao', v_line_1->'codigo_apresentacao', 'nome_produto', v_line_1->'nome_produto',
       'codigo_produto', v_line_1->'codigo_produto', 'excel_row', v_line_1->'excel_row'
     ))->>'row_sha256') then raise exception 'ordem dos campos alterou hash canonico da linha'; end if;
  begin
    perform public.analisar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000018', 'linha-adulterada-0137.xlsx', repeat('c',64), 2048,
      v_lista, jsonb_build_array(jsonb_set(v_line_1, '{preco_unitario}', '99')), 'Hash antigo nao pode validar preco alterado'
    );
    raise exception 'preco alterado com hash antigo foi aceito';
  exception when others then
    if sqlerrm = 'preco alterado com hash antigo foi aceito' then raise; end if;
    if sqlerrm <> 'hash canonico da linha XLSX diverge do conteudo informado' then raise; end if;
  end;
  if exists (select 1 from public.source_workbooks where sha256 = repeat('c',64)) then raise exception 'falha de hash deixou lineage parcial'; end if;
  begin
    perform public.analisar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000019', 'codigo-adulterado-0137.xlsx', repeat('3',64), 2048,
      v_lista, jsonb_build_array(jsonb_set(v_line_1, '{codigo_produto}', '"ALTERADO"')), 'Hash antigo nao pode validar codigo alterado'
    );
    raise exception 'codigo alterado com hash antigo foi aceito';
  exception when others then
    if sqlerrm = 'codigo alterado com hash antigo foi aceito' then raise; end if;
    if sqlerrm <> 'hash canonico da linha XLSX diverge do conteudo informado' then raise; end if;
  end;
  begin
    perform public.analisar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000020', 'lineage-adulterado-0137.xlsx', repeat('4',64), 2048,
      v_lista, jsonb_build_array(jsonb_set(v_line_1, '{source_payload,I}', '99')), 'Hash antigo nao pode validar celula alterada'
    );
    raise exception 'source payload alterado com hash antigo foi aceito';
  exception when others then
    if sqlerrm = 'source payload alterado com hash antigo foi aceito' then raise; end if;
    if sqlerrm <> 'hash canonico da linha XLSX diverge do conteudo informado' then raise; end if;
  end;
  v_valid := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000011', 'lista-operacional-0137.xlsx', repeat('a',64), 2048,
    v_lista, jsonb_build_array(v_line_2, v_line_1), 'Analise operacional valida 0137'
  );
  v_analysis_id := (v_valid->>'analise_id')::bigint;
  v_hash := v_valid->>'canonical_payload_sha256';
  if v_valid->>'status' <> 'ready' or (v_valid->>'avisos')::integer <> 1 or (v_valid->>'erros')::integer <> 0 then raise exception 'analise valida nao ficou pronta: %', v_valid; end if;
  v_analysis_document := public.consultar_com_lista_preco_xlsx_analise(v_analysis_id);
  if (v_analysis_document->>'lista_id')::bigint is distinct from pg_temp.price_list_id_by_code('LST137')
     or v_analysis_document->>'nome_lista_canonico' <> 'Lista Canonica Existente 0137'
     or jsonb_array_length(v_analysis_document->'avisos') <> 1 then
    raise exception 'codigo existente nao vinculou lista ou aviso de nome: %', v_analysis_document;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_analysis_document->'linhas') line
     where (line->>'excel_row')::integer = 2 and line->>'status' = 'AVISO'
       and (line->>'preco_centavos_por_unidade')::bigint = 3126
  ) then raise exception 'aviso por nome ou HALF_UP nao foi preservado'; end if;
  if not exists (
    select 1 from jsonb_array_elements(v_analysis_document->'linhas') line
     where (line->>'excel_row')::integer = 2 and line#>>'{celulas,preco_unitario}' = 'I2'
  ) then raise exception 'lineage da celula de preco nao foi preservado'; end if;

  v_clean_line := v_line_1 - 'row_sha256';
  v_clean_line := jsonb_set(jsonb_set(v_clean_line, '{nome_produto}', '"Produto Canonico 0137"'),
    '{source_payload,B}', '"Produto Canonico 0137"');
  v_clean_line := pg_temp.with_operational_row_hash(v_clean_line);
  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000021', 'lista-mesmo-nome-0137.xlsx', repeat('d',64), 2048,
    jsonb_set(v_lista, '{nome_lista}', '"Lista Canonica Existente 0137"'), jsonb_build_array(v_clean_line),
    'Mesmo codigo e nome nao geram aviso'
  );
  v_case_document := public.consultar_com_lista_preco_xlsx_analise((v_case->>'analise_id')::bigint);
  if jsonb_array_length(v_case_document->'avisos') <> 0 or (v_case->>'avisos')::integer <> 0 then
    raise exception 'nome canonico identico gerou aviso';
  end if;

  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000022', 'pmp-inicial-invalido-0137.xlsx', repeat('e',64), 2048,
    jsonb_set(v_lista, '{codigo_lista}', '"PMPINI137"'),
    jsonb_build_array(pg_temp.with_operational_row_hash(
      jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_clean_line - 'row_sha256', '{pmp_min_dias}', '31'), '{pmp_max_dias}', '60'), '{source_payload,G}', '31'), '{source_payload,H}', '60')
    )), 'Primeira faixa deve iniciar no prazo zero'
  );
  v_case_document := public.consultar_com_lista_preco_xlsx_analise((v_case->>'analise_id')::bigint);
  if v_case->>'status' <> 'blocked' or not exists (
    select 1 from jsonb_array_elements(v_case_document#>'{linhas,0,erros}') error where error #>> '{}' like 'A primeira faixa%'
  ) then raise exception 'faixa inicial 31-60 nao foi bloqueada'; end if;

  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000023', 'pmp-lacuna-0137.xlsx', repeat('f',64), 2048,
    jsonb_set(v_lista, '{codigo_lista}', '"PMPGAP137"'), jsonb_build_array(
      v_clean_line,
      pg_temp.with_operational_row_hash(jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_line_2 - 'row_sha256', '{pmp_min_dias}', '61'), '{pmp_max_dias}', '90'), '{source_payload,G}', '61'), '{source_payload,H}', '90'))
    ), 'Lacuna entre faixas deve bloquear'
  );
  v_case_document := public.consultar_com_lista_preco_xlsx_analise((v_case->>'analise_id')::bigint);
  if v_case->>'status' <> 'blocked' or not exists (
    select 1 from jsonb_array_elements(v_case_document->'linhas') line, jsonb_array_elements(line->'erros') error
     where error #>> '{}' like 'As faixas de PMP%lacuna%'
  ) then raise exception 'faixas 0-30 e 61-90 nao registraram lacuna'; end if;

  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000024', 'pmp-sobreposto-0137.xlsx', repeat('1',64), 2048,
    jsonb_set(v_lista, '{codigo_lista}', '"PMPOVL137"'), jsonb_build_array(
      v_clean_line,
      pg_temp.with_operational_row_hash(jsonb_set(jsonb_set(v_line_2 - 'row_sha256', '{pmp_min_dias}', '20'), '{source_payload,G}', '20'))
    ), 'Sobreposicao de faixas deve bloquear'
  );
  v_case_document := public.consultar_com_lista_preco_xlsx_analise((v_case->>'analise_id')::bigint);
  if v_case->>'status' <> 'blocked' or not exists (
    select 1 from jsonb_array_elements(v_case_document->'linhas') line, jsonb_array_elements(line->'erros') error
     where error #>> '{}' like 'Faixa de PMP duplicada ou sobreposta%'
  ) then raise exception 'sobreposicao nao foi bloqueada'; end if;

  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000025', 'pmp-limite-duplicado-0137.xlsx', repeat('2',64), 2048,
    jsonb_set(v_lista, '{codigo_lista}', '"PMPDUP137"'), jsonb_build_array(
      pg_temp.with_operational_row_hash(jsonb_set(jsonb_set(v_clean_line - 'row_sha256', '{pmp_max_dias}', '60'), '{source_payload,H}', '60')),
      v_line_2
    ), 'Limite superior duplicado deve bloquear'
  );
  v_case_document := public.consultar_com_lista_preco_xlsx_analise((v_case->>'analise_id')::bigint);
  if v_case->>'status' <> 'blocked' or not exists (
    select 1 from jsonb_array_elements(v_case_document->'linhas') line, jsonb_array_elements(line->'erros') error
     where error #>> '{}' like 'O limite superior%unico%'
  ) then raise exception 'limite superior duplicado nao foi bloqueado'; end if;
  v_repeat := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000011', 'lista-operacional-0137.xlsx', repeat('a',64), 2048,
    v_lista, jsonb_build_array(v_line_2, v_line_1), 'Analise operacional valida 0137'
  );
  if (v_repeat->>'analise_id')::bigint <> v_analysis_id or coalesce((v_repeat->>'idempotente')::boolean, false) is not true then raise exception 'retry identico duplicou analise'; end if;
  v_workbook_repeat := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000016', 'lista-operacional-0137.xlsx', repeat('a',64), 2048,
    v_lista, jsonb_build_array(v_line_2, v_line_1), 'consulta de workbook ja analisado 0137'
  );
  if (v_workbook_repeat->>'analise_id')::bigint <> v_analysis_id
     or coalesce((v_workbook_repeat->>'workbook_repetido')::boolean, false) is not true then
    raise exception 'workbook repetido nao retornou a analise existente';
  end if;
  begin
    perform public.analisar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000017', 'lista-operacional-0137.xlsx', repeat('a',64), 2048,
      v_lista, jsonb_build_array(jsonb_set(v_line_1, '{preco_unitario}', '99'), v_line_2),
      'tentativa divergente para o mesmo workbook'
    );
    raise exception 'mesmo SHA aceitou payload canonico divergente';
  exception when others then
    if sqlerrm = 'mesmo SHA aceitou payload canonico divergente' then raise; end if;
    if sqlerrm <> 'SHA-256 ja registrado com payload canonico divergente' then raise; end if;
  end;

  v_invalid := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000012', 'lista-invalida-0137.xlsx', repeat('b',64), 2048,
    jsonb_set(v_lista, '{codigo_lista}', '"ERR137"'),
    jsonb_build_array(
      pg_temp.with_operational_row_hash(jsonb_set(v_line_1 - 'row_sha256', '{codigo_produto}', '"INEXISTENTE"')),
      pg_temp.with_operational_row_hash(jsonb_set(jsonb_set(jsonb_set(v_line_2 - 'row_sha256', '{excel_row}', '4'), '{pmp_min_dias}', '20'), '{formulas}', '{"I":"=1+1"}'))
    ), 'Analise com erros deve bloquear integralmente'
  );
  v_invalid_id := (v_invalid->>'analise_id')::bigint;
  if v_invalid->>'status' <> 'blocked' or (v_invalid->>'erros')::integer < 1 then raise exception 'analise invalida nao bloqueou: %', v_invalid; end if;
  begin
    perform public.publicar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000013', v_invalid_id, v_invalid->>'canonical_payload_sha256', true,
      'Publicacao invalida deve ser recusada'
    );
    raise exception 'analise parcial foi publicada';
  exception when others then
    if sqlerrm = 'analise parcial foi publicada' then raise; end if;
    if sqlerrm <> 'analise possui erros e nao pode ser publicada' then raise; end if;
  end;
  begin
    perform public.publicar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000014', v_analysis_id, v_hash, false,
      'Aviso sem reconhecimento deve bloquear'
    );
    raise exception 'aviso nao confirmado foi publicado';
  exception when others then
    if sqlerrm = 'aviso nao confirmado foi publicado' then raise; end if;
    if sqlerrm <> 'confirme os avisos antes de publicar' then raise; end if;
  end;
  if pg_temp.price_list_version_count(pg_temp.price_list_id_by_code('LST137')) <> 0 then
    raise exception 'falha de publicacao deixou versao parcial';
  end if;

  v_publish := public.publicar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000015', v_analysis_id, v_hash, true,
    'Publicacao atomica da lista operacional 0137'
  );
  v_publication := (v_publish->>'publicacao_id')::bigint;
  v_version := (v_publish->>'versao_id')::bigint;
  v_version_document := public.consultar_com_lista_preco_versao(v_version);
  if (v_version_document#>>'{publicacao,publicacao_id}')::bigint is distinct from v_publication then raise exception 'fato de publicacao nao foi criado'; end if;
  if jsonb_array_length(v_version_document#>'{documento,itens}') <> 1
     or jsonb_array_length(v_version_document#>'{documento,itens,0,precos}') <> 2 then
    raise exception 'versao publicada nao possui todas as faixas';
  end if;
  if pg_temp.price_list_name((v_publish->>'lista_id')::bigint) <> 'Lista Canonica Existente 0137' then
    raise exception 'publicacao renomeou lista existente a partir do XLSX';
  end if;
  if pg_temp.audit_event_count('pedidos.lista_preco_xlsx_analisada', v_analysis_id::text) <> 1
     or pg_temp.audit_event_count('pedidos.lista_preco_xlsx_publicada', v_analysis_id::text) <> 1 then
    raise exception 'auditoria da analise ou publicacao XLSX esta ausente';
  end if;
  if (v_version_document#>>'{documento,itens,0,precos,0,prazo_dias}')::integer <> 30
     or (v_version_document#>>'{documento,itens,0,precos,1,prazo_dias}')::integer <> 60 then
    raise exception 'faixas fora de ordem no documento publicado';
  end if;
  v_client_id := pg_temp.client_id_by_name('Cliente lista operacional 0137');
  v_origin_id := pg_temp.origin_id_by_code('direto_elite');
  v_presentation_id := pg_temp.presentation_id_by_code('P0137-20L');
  select * into v_resolution from public.resolver_com_referencia_comercial(current_date, 0, v_origin_id, null, 'SP', v_client_id, null::bigint[], v_presentation_id);
  if v_resolution.prazo_faixa_dias <> 30 or v_resolution.preco_referencia_centavos_por_litro <> 3126 then raise exception 'PMP 0 nao resolveu faixa 0-30'; end if;
  select * into v_resolution from public.resolver_com_referencia_comercial(current_date, 30, v_origin_id, null, 'SP', v_client_id, null::bigint[], v_presentation_id);
  if v_resolution.prazo_faixa_dias <> 30 or v_resolution.preco_referencia_centavos_por_litro <> 3126 then raise exception 'PMP 30 nao resolveu limite exato'; end if;
  select * into v_resolution from public.resolver_com_referencia_comercial(current_date, 31, v_origin_id, null, 'SP', v_client_id, null::bigint[], v_presentation_id);
  if v_resolution.prazo_faixa_dias <> 60 or v_resolution.preco_referencia_centavos_por_litro <> 3250 then raise exception 'PMP 31 nao resolveu somente faixa 31-60'; end if;
  select * into v_resolution from public.resolver_com_referencia_comercial(current_date, 47, v_origin_id, null, 'SP', v_client_id, null::bigint[], v_presentation_id);
  if v_resolution.prazo_faixa_dias <> 60 or v_resolution.preco_referencia_centavos_por_litro <> 3250 then raise exception 'PMP intermediario nao resolveu teto autorizado'; end if;
  select * into v_resolution from public.resolver_com_referencia_comercial(current_date, 60, v_origin_id, null, 'SP', v_client_id, null::bigint[], v_presentation_id);
  if v_resolution.prazo_faixa_dias <> 60 or v_resolution.preco_referencia_centavos_por_litro <> 3250 then raise exception 'PMP 60 nao resolveu limite exato'; end if;
  v_retry := public.publicar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000015', v_analysis_id, v_hash, true,
    'Publicacao atomica da lista operacional 0137'
  );
  if (v_retry->>'publicacao_id')::bigint <> v_publication or coalesce((v_retry->>'idempotente')::boolean, false) is not true then raise exception 'retry de publicacao duplicou versao'; end if;
  begin
    perform public.publicar_com_lista_preco_xlsx_operacional_idempotente(
      '13700000-0000-4000-8000-000000000015', v_analysis_id, repeat('f',64), true,
      'Publicacao atomica da lista operacional 0137'
    );
    raise exception 'retry divergente foi aceito';
  exception when others then
    if sqlerrm = 'retry divergente foi aceito' then raise; end if;
    if sqlerrm <> 'chave de idempotencia reutilizada com conteudo diferente' then raise; end if;
  end;
  v_case := public.analisar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000026', 'lista-nova-0137.xlsx', repeat('5',64), 2048,
    jsonb_set(jsonb_set(jsonb_set(v_lista, '{codigo_lista}', '"NEW137"'), '{nome_lista}', '"Lista Nova pelo Codigo 0137"'), '{uf}', '"RJ"'),
    jsonb_build_array(v_clean_line), 'Codigo novo deve criar lista com nome importado'
  );
  v_new_publish := public.publicar_com_lista_preco_xlsx_operacional_idempotente(
    '13700000-0000-4000-8000-000000000027', (v_case->>'analise_id')::bigint, v_case->>'canonical_payload_sha256', true,
    'Publicar lista nova mantendo nome importado'
  );
  if pg_temp.price_list_name((v_new_publish->>'lista_id')::bigint) <> 'Lista Nova pelo Codigo 0137' then
    raise exception 'codigo novo nao criou lista com nome importado';
  end if;
  begin
    update public.com_lista_preco_versao_precos
       set valor_centavos_por_unidade_precificacao = 1
     where versao_item_id in (select id from public.com_lista_preco_versao_itens where versao_id = v_version);
    raise exception 'versao publicada foi alterada diretamente';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

do $$
begin
  begin
    insert into public.com_lista_preco_xlsx_linhas(analise_id, source_row_id, excel_row, status, avisos_json, erros_json, celulas_json)
    values (1, 1, 2, 'ERRO', '[]', '["direto"]', '{}');
    raise exception 'escrita direta foi aceita';
  exception when insufficient_privilege then null; end;
  begin
    truncate public.com_lista_preco_xlsx_analises;
    raise exception 'truncate foi aceito';
  exception when insufficient_privilege then null; end;
  begin
    update public.com_lista_preco_xlsx_analises set status = status;
    raise exception 'update direto de fato XLSX foi aceito';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.com_lista_preco_xlsx_analises;
    raise exception 'delete direto de fato XLSX foi aceito';
  exception when insufficient_privilege then null; end;
end
$$;

rollback;
