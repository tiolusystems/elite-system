\set ON_ERROR_STOP on
begin;
set local time zone 'America/Sao_Paulo';

do $$
begin
  if not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.commercial_review.preview'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'read'
  ) or not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.commercial_review.confirm'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'write'
  ) then raise exception 'alcadas F2B devem nascer bloqueadas'; end if;
  if not has_function_privilege('authenticated', 'public.prever_com_revisao_comercial_venda(jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.confirmar_com_revisao_comercial_venda_idempotente(uuid,jsonb,text,text,boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'public.confirmar_com_revisao_comercial_venda_idempotente(uuid,jsonb,text,text,boolean)', 'EXECUTE')
     or has_function_privilege('public', 'public.confirmar_com_revisao_comercial_venda_idempotente(uuid,jsonb,text,text,boolean)', 'EXECUTE') then
    raise exception 'grants das RPCs F2B excedem o contrato';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_confirmacoes_comerciais', 'SELECT')
     or has_table_privilege('authenticated', 'public.com_pedido_confirmacoes_comerciais', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_confirmacao_comercial_requisicoes', 'SELECT') then
    raise exception 'fatos ou metadados internos F2B foram expostos diretamente';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('13100000-0000-4000-8000-000000000001', 'f2b-seller@test.invalid'),
  ('13100000-0000-4000-8000-000000000002', 'f2b-denied@test.invalid'),
  ('13100000-0000-4000-8000-000000000003', 'f2b-setup@test.invalid'),
  ('13100000-0000-4000-8000-000000000004', 'f2b-manager@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('13100000-0000-4000-8000-000000000001', 'Vendedor F2B 0131', 'comercial', 'active'),
  ('13100000-0000-4000-8000-000000000002', 'Usuario negado F2B 0131', 'comercial', 'active'),
  ('13100000-0000-4000-8000-000000000003', 'Setup F2B 0131', 'admin', 'active'),
  ('13100000-0000-4000-8000-000000000004', 'Gestor F2B 0131', 'admin', 'active');

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select '13100000-0000-4000-8000-000000000001'::uuid, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
  from unnest(array[
    'pedidos.create.own', 'pedidos.price_reference.resolve', 'pedidos.payment_terms.manage',
    'pedidos.commercial_context.manage', 'pedidos.practiced_price.record',
    'pedidos.commercial_review.preview', 'pedidos.commercial_review.confirm',
    'pedidos.commercial_comparison.view'
  ]) action_key
union all
select '13100000-0000-4000-8000-000000000002'::uuid, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
  from unnest(array['pedidos.create.own', 'pedidos.price_reference.resolve']) action_key
union all
select '13100000-0000-4000-8000-000000000003'::uuid, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
  from unnest(array['system.admin', 'pedidos.price_reference.resolve']) action_key
union all
select '13100000-0000-4000-8000-000000000004'::uuid, 'pedidos.credit.review', true, '13100000-0000-4000-8000-000000000003'::uuid
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de confirmacao comercial F2B 0131')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by, updated_by)
values ('Vendedor F2B 0131', 'vendedor f2b 0131', 'vendedor_direto_elite', '["vendedor"]', 'active',
  '13100000-0000-4000-8000-000000000001', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente F2B 0131', 'cliente f2b 0131', 'Campinas', 'SP', 'active',
  '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003');
insert into public.cad_cliente_propriedades(cliente_id, nome, cidade, uf, status, created_by, updated_by)
select id, 'Propriedade F2B 0131', 'Campinas', 'SP', 'active',
  '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'
  from public.cad_clientes where nome = 'Cliente F2B 0131';
insert into public.cad_cliente_vendedores(cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by, updated_by)
select client.id, seller.id, (select id from public.cad_cliente_vinculo_papeis where codigo_norm = 'atende'),
  'active', (clock_timestamp() at time zone 'America/Sao_Paulo')::date, 'sistema',
  '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'
  from public.cad_clientes client cross join public.cad_pessoas_comerciais seller
 where client.nome = 'Cliente F2B 0131' and seller.user_profile_id = '13100000-0000-4000-8000-000000000001';

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by) values
  ('1311', 'Produto desconto F2B 0131', 'produto desconto f2b 0131', 'active', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'),
  ('1312', 'Produto acima F2B 0131', 'produto acima f2b 0131', 'active', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by) values
  ('Embalagem A F2B 0131', 'embalagem a f2b 0131', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'),
  ('Embalagem B F2B 0131', 'embalagem b f2b 0131', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, packaging.id, case product.codigo_produto when '1311' then 'P0131A' else 'P0131B' end,
  'active', 'sistema', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'
  from public.cad_produtos_base product
  join public.cad_embalagens packaging on packaging.descricao = case product.codigo_produto when '1311' then 'Embalagem A F2B 0131' else 'Embalagem B F2B 0131' end
 where product.codigo_produto in ('1311', '1312');

create temporary table f2b_context(
  seller_id bigint, client_id bigint, property_id bigint, relation_id bigint,
  presentation_a_id bigint, presentation_b_id bigint, origin_id bigint,
  proposal jsonb, preview jsonb, order_id bigint, confirmation_id bigint, legacy_order_id bigint
) on commit drop;
insert into f2b_context(seller_id, client_id, property_id, relation_id, presentation_a_id, presentation_b_id, origin_id)
select seller.id, client.id, property.id, relation.id,
  (select id from public.cad_produto_embalagens where codigo_item = 'P0131A'),
  (select id from public.cad_produto_embalagens where codigo_item = 'P0131B'),
  (select id from public.com_origens_comerciais where codigo = 'direto_elite')
  from public.cad_pessoas_comerciais seller
  join public.cad_cliente_vendedores relation on relation.pessoa_id = seller.id
  join public.cad_clientes client on client.id = relation.cliente_id
  join public.cad_cliente_propriedades property on property.cliente_id = client.id
 where seller.user_profile_id = '13100000-0000-4000-8000-000000000001';

do $$
declare
  v f2b_context%rowtype;
  v_list_id bigint;
  v_version_id bigint;
  v_rule_id bigint;
  v_unit_id bigint;
  v_item_id bigint;
  v_today date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select * into v from f2b_context;
  select id into v_unit_id from public.cad_unidades_medida where lower(codigo) = 'l';
  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('F2B0131', 'Lista F2B 0131', '13100000-0000-4000-8000-000000000003') returning id into v_list_id;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_list_id, 1, v_today, 'Versao fixture F2B', '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003') returning id into v_version_id;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao, created_by)
  values (v_version_id, v.presentation_a_id, v_unit_id, 20, '13100000-0000-4000-8000-000000000003') returning id into v_item_id;
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, valor_centavos_por_unidade_precificacao, created_by)
  values (v_item_id, 0, 100, 100, '13100000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao, created_by)
  values (v_version_id, v.presentation_b_id, v_unit_id, 20, '13100000-0000-4000-8000-000000000003') returning id into v_item_id;
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, valor_centavos_por_unidade_precificacao, created_by)
  values (v_item_id, 0, 100, 100, '13100000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_version_id, 'GERAL', 'Regra geral F2B', 0, '13100000-0000-4000-8000-000000000003') returning id into v_rule_id;
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_version_id, md5('F2B0131'), 'Publicacao fixture F2B', '13100000-0000-4000-8000-000000000003', clock_timestamp());

  insert into public.com_pedidos(codigo_pedido, cliente_id, vendedor_gerador_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by)
  values ('PED-0131-LEGACY', v.client_id, v.seller_id, 'venda', 'blocked', v_today, 100,
    '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003') returning id into v.legacy_order_id;

  v.proposal := jsonb_build_object(
    'cliente_vendedor_vinculo_id', v.relation_id,
    'data_pedido', v_today,
    'origem_comercial_id', v.origin_id,
    'area_comercial_id', null,
    'uf', 'SP',
    'pessoa_papel_ids', '[]'::jsonb,
    'itens', jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v.presentation_a_id, 'quantidade', 1, 'preco_praticado_centavos_por_unidade_precificacao', 90),
      jsonb_build_object('produto_embalagem_id', v.presentation_b_id, 'quantidade', 1, 'preco_praticado_centavos_por_unidade_precificacao', 120)
    ),
    'parcelas', jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'forma_pagamento', 'pix', 'valor_centavos', 4200, 'data_vencimento', v_today)),
    'entregas', jsonb_build_array(jsonb_build_object(
      'data_prevista', v_today, 'propriedade_id', v.property_id,
      'estabelecimento_id', null, 'endereco_id', null,
      'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 1), jsonb_build_object('item_index', 2, 'quantidade', 1))
    )),
    'observacao', 'Venda fixture F2B'
  );
  update f2b_context set proposal = v.proposal, legacy_order_id = v.legacy_order_id;
end
$$;
grant select, update on f2b_context to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000002', true);
do $$
declare v f2b_context%rowtype;
begin
  select * into v from f2b_context;
  begin
    perform public.prever_com_revisao_comercial_venda(v.proposal);
    raise exception 'usuario sem alçada previsualizou revisao';
  exception when others then
    if position('not allowed' in lower(sqlerrm)) = 0 then raise exception 'negacao ocorreu pelo motivo incorreto: %', sqlerrm; end if;
  end;
end
$$;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v f2b_context%rowtype;
  v_preview jsonb;
  v_incomplete jsonb;
  v_orders_before bigint;
begin
  select * into v from f2b_context;
  v_incomplete := jsonb_set(jsonb_set(v.proposal, '{itens,0}', (v.proposal#>'{itens,0}') - 'preco_praticado_centavos_por_unidade_precificacao'), '{itens,1}', (v.proposal#>'{itens,1}') - 'preco_praticado_centavos_por_unidade_precificacao');
  v_preview := public.prever_com_revisao_comercial_venda(v_incomplete);
  if (v_preview->>'complete_for_confirmation')::boolean is not false
     or (v_preview#>>'{itens,0,preco_referencia_centavos_por_unidade_precificacao}')::bigint <> 100 then
    raise exception 'preview incompleto nao devolveu referencia governada';
  end if;

  v_preview := public.prever_com_revisao_comercial_venda(v.proposal);
  if (v_preview->>'complete_for_confirmation')::boolean is not true
     or v_preview#>>'{itens,0,classificacao}' <> 'BELOW_REFERENCE'
     or v_preview#>>'{itens,1,classificacao}' <> 'ABOVE_REFERENCE'
     or (v_preview#>>'{totais,descontos_brutos_centavos}')::bigint <> 200
     or (v_preview#>>'{totais,overprice_bruto_centavos}')::bigint <> 400
     or (v_preview#>>'{totais,resultado_liquido_centavos}')::bigint <> 200 then
    raise exception 'comparacao mista F2B divergiu do contrato';
  end if;
  if (v_preview#>>'{totais,percentual_resultado_liquido}')::numeric <> 5 then
    raise exception 'percentual liquido deve ser ponderado pelo valor economico';
  end if;
  update f2b_context set preview = v_preview;

  select count(*) into v_orders_before from public.com_pedidos;
  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000010',
      jsonb_set(v.proposal, '{observacao}', '"Proposta materialmente alterada"'),
      v_preview->>'preview_hash', 'Desconto solicitado para teste dirigido', true
    );
    raise exception 'preview desatualizado foi aceito';
  exception when others then
    if position('desatualizada' in lower(sqlerrm)) = 0 then raise exception 'stale preview falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
  if (select count(*) from public.com_pedidos) <> v_orders_before then raise exception 'stale preview deixou pedido parcial'; end if;

  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000011', v.proposal, v_preview->>'preview_hash', null, true
    );
    raise exception 'desconto sem justificativa foi aceito';
  exception when others then
    if position('justificativa' in lower(sqlerrm)) = 0 then raise exception 'justificativa falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
  if (select count(*) from public.com_pedidos) <> v_orders_before then raise exception 'falha de justificativa deixou efeito parcial'; end if;

  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000012', v.proposal, v_preview->>'preview_hash', 'Desconto solicitado para teste dirigido', false
    );
    raise exception 'desconto sem confirmacao explicita foi aceito';
  exception when others then
    if position('confirmacao explicita' in lower(sqlerrm)) = 0 then raise exception 'checkbox falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;

  select (result->>'pedido_id')::bigint, (result->>'confirmacao_comercial_id')::bigint
    into v.order_id, v.confirmation_id
    from (select public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000013', v.proposal, v_preview->>'preview_hash',
      'Desconto solicitado para teste dirigido', true
    ) result) confirmed;
  update f2b_context set order_id = v.order_id, confirmation_id = v.confirmation_id;
end
$$;

do $$
declare
  v f2b_context%rowtype;
  v_retry jsonb;
  v_confirmation jsonb;
begin
  select * into v from f2b_context;
  v_confirmation := public.consultar_com_confirmacao_comercial_pedido(v.order_id);
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked' then raise exception 'confirmacao F2B tornou pedido efetivo'; end if;
  if (v_confirmation->>'possui_desconto')::boolean is not true
     or v_confirmation->>'documento_canonico_sha256' <> encode(extensions.digest(convert_to((v_confirmation->'documento')::text, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'ancora comercial nao corresponde aos fatos canonicos';
  end if;
  if not exists (select 1 from public.com_pedido_item_precos_praticados fact join public.cad_unidades_medida unit on unit.id = fact.unidade_precificacao_id where fact.pedido_id = v.order_id and lower(unit.codigo) = 'l') then
    raise exception 'fluxo F2B nao preservou unidade L congelada';
  end if;
  v_retry := public.confirmar_com_revisao_comercial_venda_idempotente(
    '13100000-0000-4000-8000-000000000013', v.proposal, v.preview->>'preview_hash',
    'Desconto solicitado para teste dirigido', true
  );
  if (v_retry->>'idempotent_retry')::boolean is not true or (v_retry->>'pedido_id')::bigint <> v.order_id then
    raise exception 'retry identico nao retornou o fato original';
  end if;
  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000013', v.proposal, v.preview->>'preview_hash',
      'Justificativa divergente para a mesma chave', true
    );
    raise exception 'retry divergente foi aceito';
  exception when others then
    if position('conteudo diferente' in lower(sqlerrm)) = 0 then raise exception 'retry divergente falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
  begin
    insert into public.com_pedido_confirmacoes_comerciais(
      pedido_id, numero_versao, possui_desconto, descontos_confirmados, comparacao_sha256,
      preview_hash, documento_canonico_json, documento_canonico_sha256, confirmed_by, confirmed_at
    ) values (v.order_id, 2, false, false, repeat('0', 64), repeat('0', 64), '{}'::jsonb, repeat('0', 64), '13100000-0000-4000-8000-000000000001', clock_timestamp());
    raise exception 'escrita direta authenticated foi aceita';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;
create function public.test_f2b_corromper_fato_persistido()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.preco_praticado_centavos_por_unidade_precificacao :=
    new.preco_praticado_centavos_por_unidade_precificacao + 1;
  new.diferenca_centavos_por_unidade_precificacao :=
    new.preco_praticado_centavos_por_unidade_precificacao
      - new.preco_referencia_centavos_por_unidade_precificacao;
  new.percentual_diferenca := round(
    new.diferenca_centavos_por_unidade_precificacao::numeric * 100
      / new.preco_referencia_centavos_por_unidade_precificacao::numeric,
    6
  );
  new.valor_praticado_centavos := round(
    new.quantidade_unidade_precificacao
      * new.preco_praticado_centavos_por_unidade_precificacao::numeric,
    0
  )::bigint;
  new.impacto_financeiro_centavos :=
    new.valor_praticado_centavos - new.valor_referencia_centavos;
  new.classificacao := case
    when new.preco_praticado_centavos_por_unidade_precificacao
      < new.preco_referencia_centavos_por_unidade_precificacao then 'BELOW_REFERENCE'
    when new.preco_praticado_centavos_por_unidade_precificacao
      = new.preco_referencia_centavos_por_unidade_precificacao then 'AT_REFERENCE'
    else 'ABOVE_REFERENCE'
  end;
  return new;
end;
$$;
create trigger zz_test_f2b_corromper_fato_persistido
before insert on public.com_pedido_item_precos_praticados
for each row execute function public.test_f2b_corromper_fato_persistido();

create temporary table f2b_atomic_counts as
select
  (select count(*) from public.com_pedidos) as orders_count,
  (select count(*) from public.fin_pedido_planos_pagamento) as plans_count,
  (select count(*) from public.com_pedido_item_referencias_comerciais) as references_count,
  (select count(*) from public.com_pedido_item_precos_praticados) as facts_count,
  (select count(*) from public.com_pedido_confirmacoes_comerciais) as confirmations_count;
grant select on f2b_atomic_counts to authenticated;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $$
declare
  v f2b_context%rowtype;
begin
  select * into v from f2b_context;
  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '13100000-0000-4000-8000-000000000014', v.proposal, v.preview->>'preview_hash',
      'Desconto solicitado para testar divergencia atomica', true
    );
    raise exception 'divergencia entre preview e fatos persistidos foi aceita';
  exception when others then
    if position('persistidos divergem' in lower(sqlerrm)) = 0 then
      raise exception 'divergencia persistida falhou pelo motivo incorreto: %', sqlerrm;
    end if;
  end;
end
$$;
reset role;
do $$
declare v_counts f2b_atomic_counts%rowtype;
begin
  select * into v_counts from f2b_atomic_counts;
  if (select count(*) from public.com_pedidos) <> v_counts.orders_count
     or (select count(*) from public.fin_pedido_planos_pagamento) <> v_counts.plans_count
     or (select count(*) from public.com_pedido_item_referencias_comerciais) <> v_counts.references_count
     or (select count(*) from public.com_pedido_item_precos_praticados) <> v_counts.facts_count
     or (select count(*) from public.com_pedido_confirmacoes_comerciais) <> v_counts.confirmations_count then
    raise exception 'divergencia persistida deixou efeito parcial';
  end if;
end
$$;
drop trigger zz_test_f2b_corromper_fato_persistido on public.com_pedido_item_precos_praticados;
drop function public.test_f2b_corromper_fato_persistido();

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $$
declare v f2b_context%rowtype; v_decision_id bigint;
begin
  select * into v from f2b_context;
  begin
    perform public.registrar_com_pedido_decisao_gerencial_idempotente(
      '13100000-0000-4000-8000-000000000020', v.legacy_order_id, 'liberado', 'Aprovacao de credito sem F2B deve falhar'
    );
    raise exception 'pedido legado sem F2B atravessou gate gerencial';
  exception when others then
    if position('revisao comercial confirmada' in lower(sqlerrm)) = 0 then raise exception 'gate gerencial falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
  v_decision_id := public.registrar_com_pedido_decisao_gerencial_idempotente(
    '13100000-0000-4000-8000-000000000021', v.order_id, 'liberado', 'Credito aprovado sem efetivar pedido'
  );
  if public.registrar_com_pedido_decisao_gerencial_idempotente(
    '13100000-0000-4000-8000-000000000021', v.order_id, 'liberado', 'Credito aprovado sem efetivar pedido'
  ) <> v_decision_id then raise exception 'retry da decisao gerencial duplicou o fato'; end if;
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked' then raise exception 'decisao gerencial abriu pedido F2B'; end if;
  if not exists (
    select 1 from public.com_pedido_credito_decisoes decision
     where decision.id = v_decision_id
       and decision.confirmacao_comercial_id = v.confirmation_id
       and decision.status_resultante = 'blocked'
  ) then raise exception 'decisao de credito nao foi vinculada a versao comercial'; end if;
end
$$;

reset role;
do $$
declare
  v f2b_context%rowtype;
  v_comparacao_esperada jsonb;
  v_comparacao_persistida jsonb;
begin
  select * into v from f2b_context;
  v_comparacao_esperada := public.com_revisao_comercial_venda_comparacao_esperada(v.order_id, v.preview);
  v_comparacao_persistida := public.com_revisao_comercial_venda_comparacao_persistida(v.order_id);
  if v_comparacao_esperada is distinct from v_comparacao_persistida then
    raise exception 'comparacao persistida nao corresponde exatamente ao preview confirmado';
  end if;
  if not ((v_comparacao_persistida#>'{itens,0}') ?& array[
    'pedido_item_id', 'produto_embalagem_id', 'unidade_precificacao_id',
    'quantidade_unidade_precificacao_por_apresentacao',
    'preco_referencia_centavos_por_unidade_precificacao',
    'preco_praticado_centavos_por_unidade_precificacao', 'classificacao',
    'valor_referencia_centavos', 'valor_praticado_centavos', 'impacto_financeiro_centavos'
  ]) or not ((v_comparacao_persistida->'totais') ?& array[
    'total_referencia_centavos', 'total_praticado_centavos', 'descontos_brutos_centavos',
    'overprice_bruto_centavos', 'resultado_liquido_centavos', 'percentual_resultado_liquido'
  ]) then
    raise exception 'fingerprint material nao cobre itens e totais comerciais';
  end if;
  if (select comparacao_sha256 from public.com_pedido_confirmacoes_comerciais where id = v.confirmation_id)
     <> encode(extensions.digest(convert_to(public.com_pedido_comparacao_comercial_documento(v.order_id)::text, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'ancora comercial nao esta vinculada ao fingerprint F2A';
  end if;
  begin
    update public.com_pedido_confirmacoes_comerciais set justificativa_comercial = 'alterada' where id = v.confirmation_id;
    raise exception 'UPDATE de confirmacao append-only foi aceito';
  exception when others then
    if position('append-only' in lower(sqlerrm)) = 0 then raise exception 'UPDATE foi negado pelo motivo incorreto: %', sqlerrm; end if;
  end;
  begin
    truncate public.com_pedido_confirmacoes_comerciais cascade;
    raise exception 'TRUNCATE de confirmacao append-only foi aceito';
  exception when others then
    if position('append-only' in lower(sqlerrm)) = 0 then raise exception 'TRUNCATE foi negado pelo motivo incorreto: %', sqlerrm; end if;
  end;
  if not exists (
    select 1 from public.action_logs event
     where event.entity_type = 'com_pedido_confirmacoes_comerciais'
       and event.entity_id = v.confirmation_id::text
       and event.action_key = 'pedidos.commercial_review.confirm'
  ) then raise exception 'confirmacao comercial nao gerou auditoria'; end if;
end
$$;

rollback;
