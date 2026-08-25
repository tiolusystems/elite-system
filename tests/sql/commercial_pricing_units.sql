\set ON_ERROR_STOP on
begin;

do $$
begin
  if not exists (
    select 1 from public.cad_unidades_medida
     where lower(codigo) in ('l', 'kg', 'un') and status = 'active'
  ) then raise exception 'catalogo canonico precisa conter L, kg e un ativos'; end if;
  if not has_function_privilege('authenticated', 'public.resolver_com_referencia_comercial_unidade(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resolver_com_referencia_comercial_unidade(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE')
     or has_function_privilege('public', 'public.resolver_com_referencia_comercial_unidade(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE') then
    raise exception 'grants do resolvedor generico excedem default deny';
  end if;
  if has_table_privilege('authenticated', 'public.com_lista_preco_versao_precos', 'INSERT') then
    raise exception 'preco comercial generico ampliou escrita direta';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('12900000-0000-4000-8000-000000000001', 'pricing-unit-authorized@test.invalid'),
  ('12900000-0000-4000-8000-000000000002', 'pricing-unit-setup@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12900000-0000-4000-8000-000000000001', 'Unidade comercial autorizada 0129', 'comercial', 'active'),
  ('12900000-0000-4000-8000-000000000002', 'Setup unidade comercial 0129', 'admin', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  ('12900000-0000-4000-8000-000000000001', 'pedidos.price_lists.draft.manage', true, '12900000-0000-4000-8000-000000000002'),
  ('12900000-0000-4000-8000-000000000001', 'pedidos.price_lists.publish', true, '12900000-0000-4000-8000-000000000002'),
  ('12900000-0000-4000-8000-000000000001', 'pedidos.price_lists.view', true, '12900000-0000-4000-8000-000000000002'),
  ('12900000-0000-4000-8000-000000000001', 'pedidos.price_reference.resolve', true, '12900000-0000-4000-8000-000000000002'),
  ('12900000-0000-4000-8000-000000000001', 'pedidos.commercial_context.manage', true, '12900000-0000-4000-8000-000000000002'),
  ('12900000-0000-4000-8000-000000000002', 'system.admin', true, '12900000-0000-4000-8000-000000000002')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '12900000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke unidade comercial 0129')
 where public.current_system_environment() = 'unconfigured';

create temporary table unit_context(
  presentation_id bigint, product_id bigint, client_id bigint, direct_origin_id bigint, agent_origin_id bigint,
  kg_unit_id bigint, l_unit_id bigint, un_unit_id bigint, commercial_date date
) on commit drop;

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente unidade comercial 0129', 'cliente unidade comercial 0129', 'Campinas', 'SP', 'active', '12900000-0000-4000-8000-000000000002', '12900000-0000-4000-8000-000000000002');
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values ('0129', 'Produto unidade comercial 0129', 'produto unidade comercial 0129', 'active', '12900000-0000-4000-8000-000000000002', '12900000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by)
values ('Embalagem unidade comercial 0129', 'embalagem unidade comercial 0129', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '12900000-0000-4000-8000-000000000002', '12900000-0000-4000-8000-000000000002');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, packaging.id, 'P0129', 'active', 'sistema', '12900000-0000-4000-8000-000000000002', '12900000-0000-4000-8000-000000000002'
from public.cad_produtos_base product cross join public.cad_embalagens packaging
where product.codigo_produto = '0129' and packaging.descricao = 'Embalagem unidade comercial 0129';
insert into unit_context
select (select id from public.cad_produto_embalagens where codigo_item = 'P0129'),
  (select id from public.cad_produtos_base where codigo_produto = '0129'),
  (select id from public.cad_clientes where nome = 'Cliente unidade comercial 0129'),
  (select id from public.com_origens_comerciais where codigo = 'direto_elite'),
  (select id from public.com_origens_comerciais where codigo = 'agente'),
  (select id from public.cad_unidades_medida where lower(codigo) = 'kg'),
  (select id from public.cad_unidades_medida where lower(codigo) = 'l'),
  (select id from public.cad_unidades_medida where lower(codigo) = 'un'),
  (clock_timestamp() at time zone 'America/Sao_Paulo')::date;

select set_config('request.jwt.claim.sub', '12900000-0000-4000-8000-000000000001', true);

do $$
declare
  v unit_context%rowtype; v_kg_list bigint; v_kg_version bigint; v_l_list bigint; v_l_version bigint; v_result record;
  v_pedido_id bigint; v_item_id bigint; v_plano_id bigint; v_snapshot record;
  v_un_list bigint; v_un_version bigint; v_legacy_list bigint; v_legacy_version bigint; v_legacy_item record;
  v_missing_factor_list bigint; v_missing_factor_version bigint;
  v_document jsonb;
begin
  select * into v from unit_context;
  insert into public.com_listas_preco(codigo, nome, created_by) values ('KG0129', 'Lista kg 0129', '12900000-0000-4000-8000-000000000001') returning id into v_kg_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_kg_list, 1, v.commercial_date, 'Versao generica em quilograma para smoke 0129', '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001') returning id into v_kg_version;
  perform public.replace_com_lista_preco_rascunho_idempotente('12900000-0000-4000-8000-000000000011', v_kg_version, v.commercial_date, null, 'Preco por quilograma',
    jsonb_build_array(jsonb_build_object('produto_embalagem_id', v.presentation_id, 'unidade_precificacao_id', v.kg_unit_id, 'quantidade_unidade_precificacao_por_apresentacao', 25, 'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_unidade_precificacao', 400)))),
    jsonb_build_array(jsonb_build_object('codigo', 'GERAL', 'descricao', 'Regra geral generica por quilograma')), 'Substituicao generica por quilograma');
  perform public.publish_com_lista_preco_versao_idempotente('12900000-0000-4000-8000-000000000012', v_kg_version, 'Publicacao generica por quilograma');

  select * into v_result from public.resolver_com_referencia_comercial_unidade(v.commercial_date, 0, v.direct_origin_id, null, 'SP', v.client_id, '{}'::bigint[], v.presentation_id);
  if v_result.unidade_precificacao_id <> v.kg_unit_id or v_result.quantidade_unidade_precificacao_por_apresentacao <> 25 or v_result.preco_referencia_centavos_por_unidade_precificacao <> 400 or v_result.preco_referencia_centavos_por_litro is not null then
    raise exception 'resolvedor generico kg nao congelou unidade, fator e preco corretos';
  end if;

  insert into public.com_listas_preco(codigo, nome, created_by) values ('L0129', 'Lista litro 0129', '12900000-0000-4000-8000-000000000001') returning id into v_l_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_l_list, 1, v.commercial_date, 'Versao generica em litro para smoke 0129', '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001') returning id into v_l_version;
  perform public.replace_com_lista_preco_rascunho_idempotente('12900000-0000-4000-8000-000000000013', v_l_version, v.commercial_date, null, 'Preco por litro',
    jsonb_build_array(jsonb_build_object('produto_embalagem_id', v.presentation_id, 'unidade_precificacao_id', v.l_unit_id, 'quantidade_unidade_precificacao_por_apresentacao', 20, 'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_unidade_precificacao', 3000)))),
    jsonb_build_array(jsonb_build_object('codigo', 'AGENTE', 'descricao', 'Regra especifica de agente por litro', 'origens_comerciais', jsonb_build_array(v.agent_origin_id))), 'Substituicao generica por litro');
  perform public.publish_com_lista_preco_versao_idempotente('12900000-0000-4000-8000-000000000014', v_l_version, 'Publicacao generica por litro');
  select * into v_result from public.resolver_com_referencia_comercial_unidade(v.commercial_date, 0, v.agent_origin_id, null, 'SP', v.client_id, '{}'::bigint[], v.presentation_id);
  if v_result.unidade_precificacao_id <> v.l_unit_id or v_result.quantidade_unidade_precificacao_por_apresentacao <> 20 or v_result.preco_referencia_centavos_por_unidade_precificacao <> 3000 or v_result.preco_referencia_centavos_por_litro <> 3000 then
    raise exception 'mesma apresentacao nao resolveu lista alternativa em litro';
  end if;
  select public.consultar_com_lista_preco_versao(v_l_version) into v_document;
  if (v_document#>>'{documento,itens,0,precos,0,valor_centavos_por_unidade_precificacao}') is distinct from '3000'
     or (v_document#>>'{documento,itens,0,precos,0,valor_centavos_por_litro}') is distinct from '3000' then
    raise exception 'consulta de lista L nao preservou espelho legado e preco generico';
  end if;

  insert into public.com_listas_preco(codigo, nome, created_by) values ('UN0129', 'Lista unidade 0129', '12900000-0000-4000-8000-000000000001') returning id into v_un_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_un_list, 1, v.commercial_date, 'Versao generica em unidade para smoke 0129', '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001') returning id into v_un_version;
  perform public.replace_com_lista_preco_rascunho_idempotente('12900000-0000-4000-8000-000000000016', v_un_version, v.commercial_date, null, 'Preco por unidade',
    jsonb_build_array(jsonb_build_object('produto_embalagem_id', v.presentation_id, 'unidade_precificacao_id', v.un_unit_id, 'quantidade_unidade_precificacao_por_apresentacao', 1, 'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_unidade_precificacao', 1500)))),
    jsonb_build_array(jsonb_build_object('codigo', 'UNIDADE', 'descricao', 'Rascunho generico por unidade')), 'Substituicao generica por unidade');
  if not exists (
    select 1 from public.com_lista_preco_versao_itens item
    join public.com_lista_preco_versao_precos price on price.versao_item_id = item.id
    where item.versao_id = v_un_version and item.unidade_precificacao_id = v.un_unit_id
      and item.quantidade_unidade_precificacao_por_apresentacao = 1
      and price.valor_centavos_por_unidade_precificacao = 1500 and price.valor_centavos_por_litro is null
  ) then raise exception 'unidade comercial un nao foi persistida genericamente'; end if;

  update public.cad_embalagens embalagem
     set volume_litros = 99
    from public.cad_produto_embalagens presentation
   where presentation.id = v.presentation_id and embalagem.id = presentation.embalagem_id;
  select * into v_result from public.resolver_com_referencia_comercial_unidade(v.commercial_date, 0, v.agent_origin_id, null, 'SP', v.client_id, '{}'::bigint[], v.presentation_id);
  if v_result.quantidade_unidade_precificacao_por_apresentacao <> 20 then
    raise exception 'fator L publicado foi reinterpretado pela embalagem mutavel';
  end if;

  insert into public.com_listas_preco(codigo, nome, created_by) values ('LEG0129', 'Lista legado normalizada 0129', '12900000-0000-4000-8000-000000000001') returning id into v_legacy_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_legacy_list, 1, v.commercial_date, 'Entrada legado L normalizada no smoke 0129', '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001') returning id into v_legacy_version;
  perform public.replace_com_lista_preco_rascunho_idempotente('12900000-0000-4000-8000-000000000017', v_legacy_version, v.commercial_date, null, 'Preco legado por litro',
    jsonb_build_array(jsonb_build_object('produto_embalagem_id', v.presentation_id, 'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_litro', 3126)))),
    jsonb_build_array(jsonb_build_object('codigo', 'LEGADO', 'descricao', 'Entrada legado normalizada para L')), 'Normalizacao de entrada legado por litro');
  select item.*, price.valor_centavos_por_litro, price.valor_centavos_por_unidade_precificacao into v_legacy_item
    from public.com_lista_preco_versao_itens item
    join public.com_lista_preco_versao_precos price on price.versao_item_id = item.id
   where item.versao_id = v_legacy_version;
  if v_legacy_item.unidade_precificacao_id <> v.l_unit_id
     or v_legacy_item.quantidade_unidade_precificacao_por_apresentacao <> 99
     or v_legacy_item.valor_centavos_por_litro <> 3126
     or v_legacy_item.valor_centavos_por_unidade_precificacao <> 3126 then
    raise exception 'payload legado nao foi normalizado para contrato generico L';
  end if;

  insert into public.com_listas_preco(codigo, nome, created_by) values ('SEM0129', 'Lista sem fator 0129', '12900000-0000-4000-8000-000000000001') returning id into v_missing_factor_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_missing_factor_list, 1, v.commercial_date, 'Falha sem fator no smoke 0129', '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001') returning id into v_missing_factor_version;
  begin
    perform public.replace_com_lista_preco_rascunho_idempotente('12900000-0000-4000-8000-000000000018', v_missing_factor_version, v.commercial_date, null, 'Preco generico sem contexto',
      jsonb_build_array(jsonb_build_object('produto_embalagem_id', v.presentation_id, 'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_unidade_precificacao', 3126)))),
      jsonb_build_array(jsonb_build_object('codigo', 'SEM_FATOR', 'descricao', 'Falha esperada sem capacidade')), 'Falha esperada por ausencia de fator');
    raise exception 'preco generico sem unidade e fator deveria ter sido bloqueado';
  exception when others then
    if position('item generico exige unidade e fator comercial' in sqlerrm) = 0 then raise; end if;
  end;

  insert into public.com_pedidos(codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by)
  values ('ORD0129', v.client_id, 'venda', 'blocked', v.commercial_date, 200, '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001')
  returning id into v_pedido_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by)
  values (v_pedido_id, v.presentation_id, 'venda', 2, 100, 200, '12900000-0000-4000-8000-000000000001', '12900000-0000-4000-8000-000000000001')
  returning id into v_item_id;
  insert into public.fin_pedido_planos_pagamento(pedido_id, versao, vigencia_inicio, review_status, origem_dados, data_base, valor_total_centavos, pmp_dias, created_by)
  values (v_pedido_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 20000, 0, '12900000-0000-4000-8000-000000000001')
  returning id into v_plano_id;
  perform public.resolver_com_referencias_comerciais_pedido_idempotente(
    '12900000-0000-4000-8000-000000000015', v_pedido_id, v.direct_origin_id, null, 'SP', '{}'::bigint[], 'Congelamento generico por quilograma no smoke'
  );
  select * into v_snapshot from public.com_pedido_item_referencias_comerciais where pedido_item_id = v_item_id;
  if v_snapshot.plano_pagamento_id <> v_plano_id or v_snapshot.unidade_precificacao_id <> v.kg_unit_id
     or v_snapshot.quantidade_unidade_precificacao_por_apresentacao <> 25
     or v_snapshot.preco_referencia_centavos_por_unidade_precificacao <> 400
     or v_snapshot.preco_referencia_centavos_por_litro is not null then
    raise exception 'snapshot comercial nao congelou contexto generico por quilograma';
  end if;

  begin
    insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, valor_centavos_por_unidade_precificacao, created_by)
    select item.id, 30, null, 500, '12900000-0000-4000-8000-000000000001' from public.com_lista_preco_versao_itens item where item.versao_id = v_l_version;
    raise exception 'espelho L divergente deveria ter sido negado';
  exception when others then
    if position('versao publicada e imutavel' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;

rollback;
\echo COMMERCIAL_PRICING_UNITS_OK
