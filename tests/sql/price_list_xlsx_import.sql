\set ON_ERROR_STOP on
begin;

do $$
begin
  if exists (
    select 1 from public.permission_actions
     where action_key in ('pedidos.price_lists.import.stage', 'pedidos.price_lists.import.apply')
       and default_allowed
  ) then
    raise exception 'permissoes de importacao de lista nao nasceram bloqueadas';
  end if;
  if has_function_privilege('anon', 'public.stage_com_lista_preco_xlsx_import_idempotente(uuid,text,text,bigint,jsonb,jsonb,jsonb,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.apply_com_lista_preco_import_idempotente(uuid,bigint,bigint,date,date,text,jsonb,text)', 'EXECUTE') then
    raise exception 'RPC de importacao esta exposta a anon ou PUBLIC';
  end if;
  if has_table_privilege('authenticated', 'public.com_lista_preco_import_linhas', 'INSERT') then
    raise exception 'escrita direta no staging de listas esta exposta';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('12500000-0000-4000-8000-000000000001', 'price-import-author-0125@test.invalid'),
  ('12500000-0000-4000-8000-000000000002', 'price-import-setup-0125@test.invalid'),
  ('12500000-0000-4000-8000-000000000003', 'price-import-denied-0125@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12500000-0000-4000-8000-000000000001', 'Autor importacao 0125', 'comercial', 'active'),
  ('12500000-0000-4000-8000-000000000002', 'Setup importacao 0125', 'admin', 'active'),
  ('12500000-0000-4000-8000-000000000003', 'Sem alcada importacao 0125', 'comercial', 'active');

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select '12500000-0000-4000-8000-000000000001', action.action_key, true,
       '12500000-0000-4000-8000-000000000002'
  from public.permission_actions action
 where action.action_key in (
   'pedidos.price_lists.view', 'pedidos.price_lists.draft.manage',
   'pedidos.price_lists.import.stage', 'pedidos.price_lists.import.apply'
 )
on conflict (user_id, action_key)
do update set allowed = true, updated_by = excluded.updated_by;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values (
  '12500000-0000-4000-8000-000000000002', 'system.admin', true,
  '12500000-0000-4000-8000-000000000002'
)
on conflict (user_id, action_key)
do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '12500000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de importacao de listas 0125')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values
  ('0125', 'Produto Importado 0125', 'produto importado 0125', 'active',
   '12500000-0000-4000-8000-000000000002', '12500000-0000-4000-8000-000000000002'),
  ('1251', 'Produto Ambiguo 0125', 'produto ambiguo 0125', 'active',
   '12500000-0000-4000-8000-000000000002', '12500000-0000-4000-8000-000000000002'),
  ('1252', 'Produto Ambiguo 0125', 'produto ambiguo 0125', 'active',
   '12500000-0000-4000-8000-000000000002', '12500000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(
  descricao, descricao_norm, unidade, volume_litros, status, unidade_id,
  origem_dados, created_by, updated_by
) values (
  'Bomba 0125 20 L', 'bomba 0125 20 l', 'UN', 20, 'active', 6, 'sistema',
  '12500000-0000-4000-8000-000000000002', '12500000-0000-4000-8000-000000000002'
);
insert into public.cad_produto_embalagens(
  produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
)
select product.id, package.id, 'P0125-20L', 'active', 'sistema',
       '12500000-0000-4000-8000-000000000002', '12500000-0000-4000-8000-000000000002'
  from public.cad_produtos_base product
 cross join public.cad_embalagens package
 where product.codigo_produto = '0125'
   and package.descricao = 'Bomba 0125 20 L';

set local role authenticated;
select set_config('request.jwt.claim.sub', '12500000-0000-4000-8000-000000000003', true);
do $$
begin
  begin
    perform public.stage_com_lista_preco_xlsx_import_idempotente(
      '12500000-0000-4000-8000-000000000004', 'negada.xlsx', repeat('0', 64), 10,
      '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, 'Tentativa valida sem permissao'
    );
    raise exception 'usuario sem alcada registrou importacao';
  exception when others then
    if sqlerrm = 'usuario sem alcada registrou importacao' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.price_lists.import.stage' then
      raise exception 'negacao nao veio da camada de permissao: %', sqlerrm;
    end if;
  end;
end
$$;

select set_config('request.jwt.claim.sub', '12500000-0000-4000-8000-000000000001', true);
do $$
declare
  v_table jsonb := jsonb_build_array(jsonb_build_object(
    'table_key', 'lista-a', 'sheet_name', 'Lista geral', 'table_name', 'PRICE_LIST_SHEET_1',
    'ref', 'A1:E2', 'header_row', 1, 'data_first_row', 2, 'data_last_row', 2,
    'column_count', 5, 'row_count', 2, 'metadata_json', jsonb_build_object('origem', 'fixture')
  ));
  v_rows jsonb := jsonb_build_array(jsonb_build_object(
    'table_key', 'lista-a', 'row_key', 'lista-a:row:2', 'excel_row_number', 2,
    'row_index', 2, 'row_hash', repeat('a', 64),
    'payload_json', jsonb_build_object('A', 'Grupo bruta', 'B', 'Produto Importado 0125', 'C', 'Bomba 0125 20 L', 'D', '31,255', 'E', '32,50'),
    'formulas_json', '{}'::jsonb
  ));
  v_lines jsonb := jsonb_build_array(
    jsonb_build_object('source_table_key', 'lista-a', 'source_row_key', 'lista-a:row:2', 'coluna_produto', 'B', 'coluna_embalagem', 'C', 'coluna_grupo', 'A', 'coluna_preco', 'D', 'celula_preco', 'D2', 'grupo_bruto', 'Grupo bruta',
      'produto_bruto', 'Produto Importado 0125', 'embalagem_bruta', 'Bomba 0125 20 L',
      'prazo_dias', 0, 'valor_bruto_texto', '31,255', 'valor_bruto_normalizado', '31.255'),
    jsonb_build_object('source_table_key', 'lista-a', 'source_row_key', 'lista-a:row:2', 'coluna_produto', 'B', 'coluna_embalagem', 'C', 'coluna_grupo', 'A', 'coluna_preco', 'E', 'celula_preco', 'E2', 'grupo_bruto', 'Grupo bruta',
      'produto_bruto', 'Produto Importado 0125', 'embalagem_bruta', 'Bomba 0125 20 L',
      'prazo_dias', 30, 'valor_bruto_texto', '32,50', 'valor_bruto_normalizado', '32.50')
  );
  v_result jsonb;
  v_repetida jsonb;
  v_adulterada jsonb;
  v_duplicada jsonb;
  v_importacao bigint;
  v_importacao_adulterada bigint;
  v_importacao_duplicada bigint;
  v_version bigint;
  v_applied bigint;
  v_rules jsonb := jsonb_build_array(jsonb_build_object(
    'codigo', 'GERAL', 'descricao', 'Regra geral explicita do smoke de importacao', 'prioridade', 1
  ));
begin
  v_result := public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000010', 'lista-0125.xlsx', repeat('1', 64), 100,
    v_table, v_rows, v_lines, 'Staging governado de fixture de preco 0125'
  );
  if v_result->>'status' <> 'ready' or (v_result->>'linhas_validas')::integer <> 2 then
    raise exception 'staging valido nao ficou pronto: %', v_result;
  end if;
  v_importacao := (v_result->>'importacao_id')::bigint;
  if not exists (
    select 1 from public.com_lista_preco_import_linhas
     where importacao_id = v_importacao and prazo_dias = 0
       and valor_bruto_texto = '31,255' and valor_normalizado = 31.26
       and valor_centavos_por_litro = 3126
       and coluna_preco = 'D' and celula_preco = 'D2'
  ) then raise exception 'preco bruto arredondado nao preservou texto e centavos'; end if;
  if (public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000010', 'lista-0125.xlsx', repeat('1', 64), 100,
    v_table, v_rows, v_lines, 'Staging governado de fixture de preco 0125'
  )->>'importacao_id')::bigint <> v_importacao then raise exception 'retry do staging duplicou a importacao'; end if;

  v_repetida := public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000013', 'lista-0125-copia.xlsx', repeat('1', 64), 100,
    v_table, v_rows, v_lines, 'Tentativa com workbook repetido'
  );
  if (v_repetida->>'importacao_id')::bigint <> v_importacao
     or coalesce((v_repetida->>'workbook_repetido')::boolean, false) is not true
     or not exists (
       select 1 from jsonb_array_elements_text(v_repetida->'alertas') alerta
        where alerta = 'Esta planilha ja foi importada.'
     ) then
    raise exception 'workbook repetido nao retornou staging existente: %', v_repetida;
  end if;

  v_adulterada := public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000014', 'lista-0125-adulterada.xlsx', repeat('3', 64), 100,
    v_table, v_rows,
    jsonb_set(v_lines, '{0,valor_bruto_normalizado}', '"99.99"'::jsonb),
    'Valor normalizado divergente da celula de origem'
  );
  v_importacao_adulterada := (v_adulterada->>'importacao_id')::bigint;
  if v_adulterada->>'status' <> 'blocked'
     or not exists (
       select 1 from public.com_lista_preco_import_linhas
        where importacao_id = v_importacao_adulterada
          and status_reconciliacao = 'valor_invalido'
     ) then
    raise exception 'valor normalizado adulterado nao foi bloqueado: %', v_adulterada;
  end if;

  v_duplicada := public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000015', 'lista-0125-duplicada.xlsx', repeat('4', 64), 100,
    v_table,
    v_rows,
    jsonb_build_array(v_lines->0, jsonb_build_object(
      'source_table_key', 'lista-a', 'source_row_key', 'lista-a:row:2',
      'coluna_produto', 'B', 'coluna_embalagem', 'C', 'coluna_grupo', 'A',
      'coluna_preco', 'E', 'celula_preco', 'E2', 'grupo_bruto', 'Grupo bruta',
      'produto_bruto', 'Produto Importado 0125', 'embalagem_bruta', 'Bomba 0125 20 L',
      'prazo_dias', 0, 'valor_bruto_texto', '32,50', 'valor_bruto_normalizado', '32.50'
    )),
    'Duplicidade na mesma linha deve ser bloqueada sem abortar staging'
  );
  v_importacao_duplicada := (v_duplicada->>'importacao_id')::bigint;
  if v_duplicada->>'status' <> 'blocked'
     or not exists (
       select 1 from public.com_lista_preco_import_linhas
        where importacao_id = v_importacao_duplicada
          and status_reconciliacao = 'duplicidade_preco'
          and motivo_erro = 'faixa de preco duplicada para a mesma apresentacao'
     ) then
    raise exception 'duplicidade de apresentacao e prazo nao foi bloqueada: %', v_duplicada;
  end if;

  begin
    perform public.stage_com_lista_preco_xlsx_import_idempotente(
      '12500000-0000-4000-8000-000000000016', 'lista-0125-celula-invalida.xlsx', repeat('5', 64), 100,
      v_table, v_rows, jsonb_set(v_lines, '{0,celula_preco}', '"D999"'::jsonb),
      'Celula declarada diferente da linha de origem'
    );
    raise exception 'celula de origem divergente foi aceita';
  exception when others then
    if sqlerrm = 'celula de origem divergente foi aceita' then raise; end if;
    if sqlerrm <> 'celula de preco diverge da linha de origem' then raise; end if;
  end;

  v_version := public.create_com_lista_preco_rascunho_idempotente(
    '12500000-0000-4000-8000-000000000011', 'IMP0125', 'Lista importada 0125',
    'Rascunho preparado para aplicacao da importacao', current_date, current_date + 30,
    'Criacao de rascunho para importacao de lista'
  );
  v_applied := public.apply_com_lista_preco_import_idempotente(
    '12500000-0000-4000-8000-000000000012', v_importacao, v_version,
    current_date, current_date + 30, 'Rascunho aplicado pela fixture 0125', v_rules,
    'Aplicacao governada de importacao reconciliada'
  );
  if v_applied <> v_version then raise exception 'aplicacao valida nao retornou a versao do rascunho'; end if;
  if public.apply_com_lista_preco_import_idempotente(
    '12500000-0000-4000-8000-000000000012', v_importacao, v_version,
    current_date, current_date + 30, 'Rascunho aplicado pela fixture 0125', v_rules,
    'Aplicacao governada de importacao reconciliada'
  ) <> v_version then raise exception 'retry da aplicacao nao retornou a versao original'; end if;
end
$$;

reset role;
do $$
begin
  if not exists (
    select 1 from public.com_lista_preco_versao_precos price
    join public.com_lista_preco_versao_itens item on item.id = price.versao_item_id
    join public.com_lista_preco_versoes version on version.id = item.versao_id
    join public.com_listas_preco list on list.id = version.lista_id
    where list.codigo = 'IMP0125' and price.prazo_dias = 30 and price.valor_centavos_por_litro = 3250
  ) then raise exception 'aplicacao valida nao preencheu o rascunho canonico'; end if;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12500000-0000-4000-8000-000000000001', true);
do $$
declare
  v_table jsonb := jsonb_build_array(jsonb_build_object(
    'table_key', 'lista-b', 'sheet_name', 'Erros', 'table_name', 'PRICE_LIST_SHEET_2',
    'ref', 'A1:E4', 'header_row', 1, 'data_first_row', 2, 'data_last_row', 4,
    'column_count', 5, 'row_count', 4, 'metadata_json', '{}'::jsonb
  ));
  v_rows jsonb := jsonb_build_array(
    jsonb_build_object('table_key', 'lista-b', 'row_key', 'lista-b:row:2', 'excel_row_number', 2, 'row_index', 2, 'row_hash', repeat('b',64), 'payload_json', jsonb_build_object('B','Nao existe 0125','C','Bomba 0125 20 L','D','10,00'), 'formulas_json','{}'::jsonb),
    jsonb_build_object('table_key', 'lista-b', 'row_key', 'lista-b:row:3', 'excel_row_number', 3, 'row_index', 3, 'row_hash', repeat('c',64), 'payload_json', jsonb_build_object('B','Produto Ambiguo 0125','C','Bomba 0125 20 L','D','10,00'), 'formulas_json','{}'::jsonb),
    jsonb_build_object('table_key', 'lista-b', 'row_key', 'lista-b:row:4', 'excel_row_number', 4, 'row_index', 4, 'row_hash', repeat('d',64), 'payload_json', jsonb_build_object('B','Produto Importado 0125','C','Sem embalagem 0125','D','10,00'), 'formulas_json','{}'::jsonb)
  );
  v_lines jsonb := jsonb_build_array(
    jsonb_build_object('source_table_key','lista-b','source_row_key','lista-b:row:2','coluna_produto','B','coluna_embalagem','C','coluna_preco','D','celula_preco','D2','produto_bruto','Nao existe 0125','embalagem_bruta','Bomba 0125 20 L','prazo_dias',0,'valor_bruto_texto','10,00','valor_bruto_normalizado','10.00'),
    jsonb_build_object('source_table_key','lista-b','source_row_key','lista-b:row:3','coluna_produto','B','coluna_embalagem','C','coluna_preco','D','celula_preco','D3','produto_bruto','Produto Ambiguo 0125','embalagem_bruta','Bomba 0125 20 L','prazo_dias',0,'valor_bruto_texto','10,00','valor_bruto_normalizado','10.00'),
    jsonb_build_object('source_table_key','lista-b','source_row_key','lista-b:row:4','coluna_produto','B','coluna_embalagem','C','coluna_preco','D','celula_preco','D4','produto_bruto','Produto Importado 0125','embalagem_bruta','Sem embalagem 0125','prazo_dias',0,'valor_bruto_texto','10,00','valor_bruto_normalizado','10.00')
  );
  v_importacao bigint;
begin
  v_importacao := (public.stage_com_lista_preco_xlsx_import_idempotente(
    '12500000-0000-4000-8000-000000000020', 'erros-0125.xlsx', repeat('2',64), 100,
    v_table, v_rows, v_lines, 'Fixture com reconciliacoes bloqueadas 0125'
  )->>'importacao_id')::bigint;
  if (select status from public.com_lista_preco_importacoes where id = v_importacao) <> 'blocked'
     or not exists (select 1 from public.com_lista_preco_import_linhas where importacao_id = v_importacao and status_reconciliacao = 'produto_nao_encontrado')
     or not exists (select 1 from public.com_lista_preco_import_linhas where importacao_id = v_importacao and status_reconciliacao = 'produto_ambiguo')
     or not exists (select 1 from public.com_lista_preco_import_linhas where importacao_id = v_importacao and status_reconciliacao = 'apresentacao_nao_encontrada') then
    raise exception 'reconciliacoes bloqueadas nao foram classificadas';
  end if;
  begin
    perform public.apply_com_lista_preco_import_idempotente(
      '12500000-0000-4000-8000-000000000021', v_importacao, 999999999,
      current_date, current_date + 1, 'Nunca deve aplicar', '[]'::jsonb,
      'Tentativa de aplicacao de importacao bloqueada'
    );
    raise exception 'importacao bloqueada foi aplicada';
  exception when others then
    if sqlerrm = 'importacao bloqueada foi aplicada' then raise; end if;
    if sqlerrm <> 'importacao possui linhas nao conciliadas; nao pode aplicar' then raise; end if;
  end;
end
$$;

reset role;
rollback;
