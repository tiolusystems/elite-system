\set ON_ERROR_STOP on
begin;
set local time zone 'America/Sao_Paulo';

do $$
begin
  if not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.practiced_price.record'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'write'
  ) or not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.commercial_comparison.view'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'read'
  ) then raise exception 'alçadas da comparacao comercial devem nascer bloqueadas'; end if;
  if not has_function_privilege('authenticated', 'public.registrar_com_precos_praticados_pedido_idempotente(uuid,bigint,jsonb,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.registrar_com_precos_praticados_pedido_idempotente(uuid,bigint,jsonb,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.registrar_com_precos_praticados_pedido_idempotente(uuid,bigint,jsonb,text)', 'EXECUTE') then
    raise exception 'grants da RPC de preco praticado excedem default deny';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_item_precos_praticados', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_item_precos_praticados', 'UPDATE')
     or has_table_privilege('authenticated', 'public.com_pedido_preco_praticado_requisicoes', 'SELECT') then
    raise exception 'fato de preco praticado ampliou escrita direta';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('13000000-0000-4000-8000-000000000001', 'practiced-price-authorized@test.invalid'),
  ('13000000-0000-4000-8000-000000000002', 'practiced-price-denied@test.invalid'),
  ('13000000-0000-4000-8000-000000000003', 'practiced-price-setup@test.invalid'),
  ('13000000-0000-4000-8000-000000000004', 'practiced-price-scope@test.invalid'),
  ('13000000-0000-4000-8000-000000000005', 'practiced-price-outside@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('13000000-0000-4000-8000-000000000001', 'Preco praticado autorizado 0130', 'admin', 'active'),
  ('13000000-0000-4000-8000-000000000002', 'Preco praticado negado 0130', 'admin', 'active'),
  ('13000000-0000-4000-8000-000000000003', 'Setup preco praticado 0130', 'admin', 'active'),
  ('13000000-0000-4000-8000-000000000004', 'Preco praticado escopo 0130', 'comercial', 'active'),
  ('13000000-0000-4000-8000-000000000005', 'Preco praticado externo 0130', 'comercial', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  ('13000000-0000-4000-8000-000000000001', 'pedidos.practiced_price.record', true, '13000000-0000-4000-8000-000000000003'),
  ('13000000-0000-4000-8000-000000000001', 'pedidos.commercial_comparison.view', true, '13000000-0000-4000-8000-000000000003'),
  ('13000000-0000-4000-8000-000000000003', 'pedidos.practiced_price.record', true, '13000000-0000-4000-8000-000000000003'),
  ('13000000-0000-4000-8000-000000000004', 'pedidos.practiced_price.record', true, '13000000-0000-4000-8000-000000000003'),
  ('13000000-0000-4000-8000-000000000004', 'pedidos.commercial_comparison.view', true, '13000000-0000-4000-8000-000000000003'),
  ('13000000-0000-4000-8000-000000000003', 'system.admin', true, '13000000-0000-4000-8000-000000000003')
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de preco praticado 0130')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by)
values
  ('Vendedor de escopo preco praticado 0130', 'vendedor de escopo preco praticado 0130', 'vendedor_direto_elite', '["vendedor"]', 'active', '13000000-0000-4000-8000-000000000004', '13000000-0000-4000-8000-000000000003'),
  ('Vendedor externo preco praticado 0130', 'vendedor externo preco praticado 0130', 'vendedor_direto_elite', '["vendedor"]', 'active', '13000000-0000-4000-8000-000000000005', '13000000-0000-4000-8000-000000000003');

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente preco praticado 0130', 'cliente preco praticado 0130', 'Campinas', 'SP', 'active', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003');
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by) values
  ('1301', 'Produto preco praticado A 0130', 'produto preco praticado a 0130', 'active', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003'),
  ('1302', 'Produto preco praticado B 0130', 'produto preco praticado b 0130', 'active', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by) values
  ('Embalagem preco praticado A 0130', 'embalagem preco praticado a 0130', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003'),
  ('Embalagem preco praticado B 0130', 'embalagem preco praticado b 0130', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, packaging.id, case product.codigo_produto when '1301' then 'P0130A' else 'P0130B' end, 'active', 'sistema', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003'
from public.cad_produtos_base product
join public.cad_embalagens packaging on packaging.descricao = case product.codigo_produto when '1301' then 'Embalagem preco praticado A 0130' else 'Embalagem preco praticado B 0130' end
where product.codigo_produto in ('1301', '1302');

create temporary table f2a_context(
  cliente_id bigint, presentation_a_id bigint, presentation_b_id bigint,
  origin_id bigint, kg_unit_id bigint, un_unit_id bigint, commercial_date date,
  lista_id bigint, versao_id bigint, publicacao_id bigint, regra_id bigint,
  pedido_id bigint, pedido_rounding_id bigint, pedido_bonus_id bigint, pedido_outside_id bigint,
  item_a_id bigint, item_b_id bigint, rounding_a_id bigint, rounding_b_id bigint, item_outside_id bigint
) on commit drop;
insert into f2a_context(cliente_id, presentation_a_id, presentation_b_id, origin_id, kg_unit_id, un_unit_id, commercial_date)
select
  (select id from public.cad_clientes where nome = 'Cliente preco praticado 0130'),
  (select id from public.cad_produto_embalagens where codigo_item = 'P0130A'),
  (select id from public.cad_produto_embalagens where codigo_item = 'P0130B'),
  (select id from public.com_origens_comerciais where codigo = 'direto_elite'),
  (select id from public.cad_unidades_medida where lower(codigo) = 'kg'),
  (select id from public.cad_unidades_medida where lower(codigo) = 'un'),
  (clock_timestamp() at time zone 'America/Sao_Paulo')::date;

do $$
declare
  v f2a_context%rowtype;
  v_l_order_id bigint;
  v_l_item_id bigint;
  v_outside_order_id bigint;
  v_outside_item_id bigint;
  v_missing_snapshot_order_id bigint;
  v_missing_snapshot_item_id bigint;
  v_mismatch_order_id bigint;
  v_mismatch_item_id bigint;
begin
  select * into v from f2a_context;
  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('F2A0130', 'Lista fixture preco praticado 0130', '13000000-0000-4000-8000-000000000003') returning id into v.lista_id;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v.lista_id, 1, v.commercial_date, 'Versao fixture para fatos de preco praticado', '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.versao_id;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v.versao_id, 'GERAL', 'Regra fixture para comparacao comercial', 0, '13000000-0000-4000-8000-000000000003') returning id into v.regra_id;
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v.versao_id, md5('F2A0130'), 'Publicacao fixture para comparacao comercial', '13000000-0000-4000-8000-000000000003', clock_timestamp()) returning id into v.publicacao_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-MAIN', v.cliente_id, v.origin_id, 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.pedido_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, percentual_desconto, valor_total, created_by, updated_by) values
    (v.pedido_id, v.presentation_a_id, 'venda', 2, 999999, 99, 1999998, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.item_a_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, percentual_desconto, valor_total, created_by, updated_by) values
    (v.pedido_id, v.presentation_b_id, 'venda', 1, 888888, 88, 888888, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.item_b_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-RND', v.cliente_id, v.origin_id, 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.pedido_rounding_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v.pedido_rounding_id, v.presentation_a_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.rounding_a_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v.pedido_rounding_id, v.presentation_b_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.rounding_b_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-BONUS', v.cliente_id, v.origin_id, 'bonificacao', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v.pedido_bonus_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v.pedido_bonus_id, v.presentation_a_id, 'bonificacao', 1, 0, 0, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003');

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-L', v.cliente_id, v.origin_id, 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_l_order_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_l_order_id, v.presentation_a_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_l_item_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, vendedor_gerador_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-OUT', v.cliente_id, v.origin_id, (select id from public.cad_pessoas_comerciais where user_profile_id = '13000000-0000-4000-8000-000000000005'), 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_outside_order_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_outside_order_id, v.presentation_a_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_outside_item_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-NOSNAP', v.cliente_id, v.origin_id, 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_missing_snapshot_order_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_missing_snapshot_order_id, v.presentation_a_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_missing_snapshot_item_id;

  insert into public.com_pedidos(codigo_pedido, cliente_id, origem_comercial_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0130-MISMATCH', v.cliente_id, v.origin_id, 'venda', 'blocked', v.commercial_date, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_mismatch_order_id;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_mismatch_order_id, v.presentation_a_id, 'venda', 1, 1, 1, '13000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003') returning id into v_mismatch_item_id;

  insert into public.fin_pedido_planos_pagamento(pedido_id, versao, vigencia_inicio, review_status, origem_dados, data_base, valor_total_centavos, pmp_dias, created_by)
  values
    (v.pedido_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 100, 0, '13000000-0000-4000-8000-000000000003'),
    (v.pedido_rounding_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 100, 0, '13000000-0000-4000-8000-000000000003'),
    (v_l_order_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 100, 0, '13000000-0000-4000-8000-000000000003'),
    (v_outside_order_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 100, 0, '13000000-0000-4000-8000-000000000003'),
    (v_mismatch_order_id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 100, 0, '13000000-0000-4000-8000-000000000003');

  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v.pedido_id, v.item_a_id, v.origin_id, v.cliente_id, v.presentation_a_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.kg_unit_id, 10, 1000, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v.pedido_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v.pedido_id, v.item_b_id, v.origin_id, v.cliente_id, v.presentation_b_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.kg_unit_id, 5, 1000, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v.pedido_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v.pedido_rounding_id, v.rounding_a_id, v.origin_id, v.cliente_id, v.presentation_a_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.un_unit_id, 0.005, 100, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v.pedido_rounding_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v.pedido_rounding_id, v.rounding_b_id, v.origin_id, v.cliente_id, v.presentation_b_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.un_unit_id, 0.005, 100, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v.pedido_rounding_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v_l_order_id, v_l_item_id, v.origin_id, v.cliente_id, v.presentation_a_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    250, (select id from public.cad_unidades_medida where lower(codigo) = 'l'), 20, 250, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v_l_order_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v_outside_order_id, v_outside_item_id, v.origin_id, v.cliente_id, v.presentation_a_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.kg_unit_id, 10, 1000, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v_outside_order_id;
  insert into public.com_pedido_item_referencias_comerciais(
    pedido_id, pedido_item_id, origem_comercial_id, cliente_id, produto_embalagem_id, data_comercial,
    plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
    preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
    preco_referencia_centavos_por_unidade_precificacao, resolved_by
  )
  select v_mismatch_order_id, v_mismatch_item_id, v.origin_id, v.cliente_id, v.presentation_b_id, v.commercial_date,
    plan.id, 0, v.lista_id, v.versao_id, v.publicacao_id, v.regra_id, 0,
    null, v.kg_unit_id, 10, 1000, '13000000-0000-4000-8000-000000000003'
  from public.fin_pedido_planos_pagamento plan where plan.pedido_id = v_mismatch_order_id;

  update f2a_context set lista_id = v.lista_id, versao_id = v.versao_id, publicacao_id = v.publicacao_id, regra_id = v.regra_id,
    pedido_id = v.pedido_id, pedido_rounding_id = v.pedido_rounding_id, pedido_bonus_id = v.pedido_bonus_id, pedido_outside_id = v_outside_order_id,
    item_a_id = v.item_a_id, item_b_id = v.item_b_id, rounding_a_id = v.rounding_a_id, rounding_b_id = v.rounding_b_id, item_outside_id = v_outside_item_id;
end
$$;
grant select on f2a_context to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000003', true);
do $$
declare v f2a_context%rowtype;
begin
  select * into v from f2a_context;
  perform public.registrar_com_precos_praticados_pedido_idempotente(
    '13000000-0000-4000-8000-000000000020', v.pedido_outside_id,
    jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_outside_id, 'preco_praticado_centavos_por_unidade_precificacao', 1000)),
    'Congelar fato externo para validar escopo de leitura'
  );
end
$$;

select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000004', true);
do $$
declare v f2a_context%rowtype;
begin
  select * into v from f2a_context;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000021', v.pedido_outside_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_outside_id, 'preco_praticado_centavos_por_unidade_precificacao', 1000)),
      'Tentativa fora do escopo com alçada de preco praticado'
    );
    raise exception 'usuario fora do escopo registrou preco praticado';
  exception when others then
    if sqlerrm = 'usuario fora do escopo registrou preco praticado' then raise; end if;
    if sqlerrm <> 'pedido fora do escopo do usuario' then raise; end if;
  end;
  begin
    perform public.consultar_com_comparacao_comercial_pedido(v.pedido_outside_id);
    raise exception 'usuario fora do escopo consultou comparacao comercial';
  exception when others then
    if sqlerrm = 'usuario fora do escopo consultou comparacao comercial' then raise; end if;
    if sqlerrm <> 'pedido fora do escopo do usuario' then raise; end if;
  end;
end
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000002', true);
do $$
declare v f2a_context%rowtype;
begin
  select * into v from f2a_context;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000010', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
      'Tentativa sem alçada de registrar preco praticado'
    );
    raise exception 'usuario sem alçada registrou preco praticado';
  exception when others then
    if sqlerrm = 'usuario sem alçada registrou preco praticado' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.practiced_price.record' then raise; end if;
  end;
end
$$;

reset role;
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $$
declare
  v f2a_context%rowtype;
  v_document jsonb;
  v_retry bigint;
  v_rounding_item_id bigint;
  v_missing_snapshot_order_id bigint;
  v_missing_snapshot_item_id bigint;
  v_mismatch_order_id bigint;
  v_mismatch_item_id bigint;
  v_l_order_id bigint;
  v_l_item_id bigint;
begin
  select * into v from f2a_context;
  select item.id into v_rounding_item_id
    from public.com_pedido_itens item join public.com_pedidos order_row on order_row.id = item.pedido_id
   where order_row.codigo_pedido = 'PED-0130-RND' order by item.id limit 1;
  select order_row.id, item.id into v_missing_snapshot_order_id, v_missing_snapshot_item_id
    from public.com_pedidos order_row join public.com_pedido_itens item on item.pedido_id = order_row.id
   where order_row.codigo_pedido = 'PED-0130-NOSNAP';
  select order_row.id, item.id into v_mismatch_order_id, v_mismatch_item_id
    from public.com_pedidos order_row join public.com_pedido_itens item on item.pedido_id = order_row.id
   where order_row.codigo_pedido = 'PED-0130-MISMATCH';
  select order_row.id, item.id into v_l_order_id, v_l_item_id
    from public.com_pedidos order_row join public.com_pedido_itens item on item.pedido_id = order_row.id
   where order_row.codigo_pedido = 'PED-0130-L';
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000011', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900)),
      'Tentativa incompleta de registrar preco praticado'
    );
    raise exception 'conjunto incompleto foi aceito';
  exception when others then
    if sqlerrm = 'conjunto incompleto foi aceito' then raise; end if;
    if sqlerrm <> 'precos praticados devem informar exatamente todos os itens ativos do pedido' then raise; end if;
  end;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000012', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 0), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
      'Tentativa com preco zero em pedido de venda'
    );
    raise exception 'preco zero foi aceito em venda';
  exception when others then
    if sqlerrm = 'preco zero foi aceito em venda' then raise; end if;
    if sqlerrm <> 'preco praticado de venda deve ser maior que zero em centavos inteiros' then raise; end if;
  end;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000013', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', -1), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
      'Tentativa com preco negativo em pedido de venda'
    );
    raise exception 'preco negativo foi aceito em venda';
  exception when others then
    if sqlerrm = 'preco negativo foi aceito em venda' then raise; end if;
    if sqlerrm <> 'preco praticado de venda deve ser maior que zero em centavos inteiros' then raise; end if;
  end;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000017', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900), jsonb_build_object('pedido_item_id', v_rounding_item_id, 'preco_praticado_centavos_por_unidade_precificacao', 100)),
      'Tentativa com item pertencente a outro pedido'
    );
    raise exception 'item de outro pedido foi aceito';
  exception when others then
    if sqlerrm = 'item de outro pedido foi aceito' then raise; end if;
    if sqlerrm <> 'precos praticados devem informar exatamente todos os itens ativos do pedido' then raise; end if;
  end;
  if exists (select 1 from public.com_pedido_item_precos_praticados where pedido_id = v.pedido_id) then
    raise exception 'tentativa com item de outro pedido deixou efeito parcial';
  end if;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000018', v_missing_snapshot_order_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v_missing_snapshot_item_id, 'preco_praticado_centavos_por_unidade_precificacao', 1000)),
      'Tentativa sem referencia comercial congelada'
    );
    raise exception 'item sem referencia comercial foi aceito';
  exception when others then
    if sqlerrm = 'item sem referencia comercial foi aceito' then raise; end if;
    if sqlerrm <> 'todos os itens de venda exigem referencia comercial generica congelada e materialmente coerente' then raise; end if;
  end;
  if exists (select 1 from public.com_pedido_item_precos_praticados where pedido_id = v_missing_snapshot_order_id) then
    raise exception 'tentativa sem referencia comercial deixou efeito parcial';
  end if;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000019', v_mismatch_order_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v_mismatch_item_id, 'preco_praticado_centavos_por_unidade_precificacao', 900)),
      'Tentativa com snapshot materialmente divergente'
    );
    raise exception 'snapshot materialmente divergente foi aceito';
  exception when others then
    if sqlerrm = 'snapshot materialmente divergente foi aceito' then raise; end if;
    if sqlerrm <> 'todos os itens de venda exigem referencia comercial generica congelada e materialmente coerente' then raise; end if;
  end;
  if exists (select 1 from public.com_pedido_item_precos_praticados where pedido_id = v_mismatch_order_id) then
    raise exception 'snapshot divergente deixou efeito parcial';
  end if;

  perform public.registrar_com_precos_praticados_pedido_idempotente(
    '13000000-0000-4000-8000-000000000014', v.pedido_id,
    jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
    'Congelar precos praticados com desconto e overprice'
  );
  v_retry := public.registrar_com_precos_praticados_pedido_idempotente(
    '13000000-0000-4000-8000-000000000014', v.pedido_id,
    jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500), jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900)),
    'Congelar precos praticados com desconto e overprice'
  );
  if v_retry <> v.pedido_id then raise exception 'retry nao retornou pedido original'; end if;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000014', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 901), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
      'Congelar precos praticados com desconto e overprice'
    );
    raise exception 'retry divergente foi aceito';
  exception when others then
    if sqlerrm = 'retry divergente foi aceito' then raise; end if;
    if sqlerrm <> 'chave de idempotencia reutilizada com conteudo diferente' then raise; end if;
  end;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000022', v.pedido_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', v.item_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 900), jsonb_build_object('pedido_item_id', v.item_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 1500)),
      'Segunda tentativa apos congelamento imutavel'
    );
    raise exception 'segunda chave apos congelamento foi aceita';
  exception when others then
    if sqlerrm = 'segunda chave apos congelamento foi aceita' then raise; end if;
    if sqlerrm <> 'pedido ja possui preco praticado imutavel' then raise; end if;
  end;
  select public.consultar_com_comparacao_comercial_pedido(v.pedido_id) into v_document;
  if (v_document#>>'{totais,total_referencia_centavos}')::bigint <> 25000
     or (v_document#>>'{totais,total_praticado_centavos}')::bigint <> 25500
     or (v_document#>>'{totais,descontos_brutos_centavos}')::bigint <> 2000
     or (v_document#>>'{totais,overprice_bruto_centavos}')::bigint <> 2500
     or (v_document#>>'{totais,resultado_liquido_centavos}')::bigint <> 500
     or (v_document#>>'{totais,percentual_resultado_liquido}')::numeric <> 2 then
    raise exception 'totais de comparacao comercial nao reconciliaram';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_document->'itens') item
     where item->>'pedido_item_id' = v.item_a_id::text
       and item->>'classificacao' = 'BELOW_REFERENCE'
       and (item->>'impacto_financeiro_centavos')::bigint = -2000
       and (item->>'percentual_diferenca')::numeric = -10
  ) then raise exception 'item com desconto foi mascarado pelo resultado positivo do pedido'; end if;
  if not exists (
    select 1 from jsonb_array_elements(v_document->'itens') item
     where item->>'pedido_item_id' = v.item_b_id::text
       and item->>'classificacao' = 'ABOVE_REFERENCE'
       and (item->>'impacto_financeiro_centavos')::bigint = 2500
       and (item->>'percentual_diferenca')::numeric = 50
  ) then raise exception 'item com overprice nao foi exposto corretamente'; end if;
  if exists (
    select 1 from public.com_pedido_item_precos_praticados fact
     where fact.pedido_id = v.pedido_id and fact.preco_referencia_centavos_por_unidade_precificacao in (999999, 888888)
  ) then raise exception 'comparacao usou campo legado do item como referencia'; end if;

  perform public.registrar_com_precos_praticados_pedido_idempotente(
    '13000000-0000-4000-8000-000000000015', v.pedido_rounding_id,
    jsonb_build_array(jsonb_build_object('pedido_item_id', v.rounding_a_id, 'preco_praticado_centavos_por_unidade_precificacao', 100), jsonb_build_object('pedido_item_id', v.rounding_b_id, 'preco_praticado_centavos_por_unidade_precificacao', 100)),
    'Validar arredondamento comercial por linha HALF UP'
  );
  select public.consultar_com_comparacao_comercial_pedido(v.pedido_rounding_id) into v_document;
  if (v_document#>>'{totais,total_referencia_centavos}')::bigint <> 2
     or (v_document#>>'{totais,total_praticado_centavos}')::bigint <> 2 then
    raise exception 'arredondamento por linha nao preservou dois meios centavos';
  end if;
  perform public.registrar_com_precos_praticados_pedido_idempotente(
    '13000000-0000-4000-8000-000000000023', v_l_order_id,
    jsonb_build_array(jsonb_build_object('pedido_item_id', v_l_item_id, 'preco_praticado_centavos_por_unidade_precificacao', 250)),
    'Validar preco praticado com unidade comercial em litros'
  );
  select public.consultar_com_comparacao_comercial_pedido(v_l_order_id) into v_document;
  if v_document#>>'{itens,0,unidade_precificacao_codigo}' is distinct from 'l'
     or (v_document#>>'{itens,0,preco_referencia_centavos_por_unidade_precificacao}')::bigint <> 250
     or (v_document#>>'{itens,0,preco_praticado_centavos_por_unidade_precificacao}')::bigint <> 250 then
    raise exception 'F2A nao preservou contrato generico para litros';
  end if;
  begin
    perform public.registrar_com_precos_praticados_pedido_idempotente(
      '13000000-0000-4000-8000-000000000016', v.pedido_bonus_id,
      jsonb_build_array(jsonb_build_object('pedido_item_id', 1, 'preco_praticado_centavos_por_unidade_precificacao', 1)),
      'Tentativa fora do escopo de venda da F2A'
    );
    raise exception 'bonificacao foi aceita pela F2A';
  exception when others then
    if sqlerrm = 'bonificacao foi aceita pela F2A' then raise; end if;
    if sqlerrm <> 'preco praticado exige pedido de venda bloqueado' then raise; end if;
  end;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000001', true);
do $$
declare v f2a_context%rowtype;
begin
  select * into v from f2a_context;
  begin
    insert into public.com_pedido_item_precos_praticados(pedido_id, pedido_item_id, referencia_comercial_id, unidade_precificacao_id, quantidade_apresentacoes, quantidade_unidade_precificacao_por_apresentacao, quantidade_unidade_precificacao, preco_referencia_centavos_por_unidade_precificacao, preco_praticado_centavos_por_unidade_precificacao, diferenca_centavos_por_unidade_precificacao, percentual_diferenca, valor_referencia_centavos, valor_praticado_centavos, impacto_financeiro_centavos, classificacao, motivo, recorded_by)
    values (v.pedido_id, v.item_a_id, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 'AT_REFERENCE', 'Tentativa direta deve ser negada', '13000000-0000-4000-8000-000000000001');
    raise exception 'authenticated escreveu fato diretamente';
  exception when insufficient_privilege then
    null;
  end;
end
$$;

reset role;
do $$
declare
  v f2a_context%rowtype;
  v_mismatch_snapshot_id bigint;
  v_mismatch_order_id bigint;
  v_mismatch_item_id bigint;
  v_kg_unit_id bigint;
begin
  select * into v from f2a_context;
  select snapshot.id, snapshot.pedido_id, snapshot.pedido_item_id, snapshot.unidade_precificacao_id
    into v_mismatch_snapshot_id, v_mismatch_order_id, v_mismatch_item_id, v_kg_unit_id
    from public.com_pedido_item_referencias_comerciais snapshot
    join public.com_pedidos order_row on order_row.id = snapshot.pedido_id
   where order_row.codigo_pedido = 'PED-0130-MISMATCH';
  begin
    insert into public.com_pedido_item_precos_praticados(
      pedido_id, pedido_item_id, referencia_comercial_id, unidade_precificacao_id,
      quantidade_apresentacoes, quantidade_unidade_precificacao_por_apresentacao, quantidade_unidade_precificacao,
      preco_referencia_centavos_por_unidade_precificacao, preco_praticado_centavos_por_unidade_precificacao,
      diferenca_centavos_por_unidade_precificacao, percentual_diferenca,
      valor_referencia_centavos, valor_praticado_centavos, impacto_financeiro_centavos, classificacao,
      motivo, recorded_by
    ) values (
      v_mismatch_order_id, v_mismatch_item_id, v_mismatch_snapshot_id, v_kg_unit_id,
      1, 10, 10, 1000, 900, -100, -10, 10000, 9000, -1000, 'BELOW_REFERENCE',
      'Provar trigger de coerencia material do snapshot', '13000000-0000-4000-8000-000000000003'
    );
    raise exception 'trigger aceitou snapshot materialmente divergente';
  exception when others then
    if sqlerrm = 'trigger aceitou snapshot materialmente divergente' then raise; end if;
    if sqlerrm <> 'referencia comercial congelada diverge da identidade material do pedido' then raise; end if;
  end;
  begin
    update public.com_pedido_item_precos_praticados set motivo = 'Alteracao proibida de fato append only' where pedido_id = v.pedido_id;
    raise exception 'fato de preco praticado aceitou update';
  exception when others then
    if sqlerrm = 'fato de preco praticado aceitou update' then raise; end if;
    if sqlerrm <> 'com_pedido_item_precos_praticados is append-only; create a new version or historical position' then raise; end if;
  end;
  begin
    delete from public.com_pedido_item_precos_praticados where pedido_id = v.pedido_id;
    raise exception 'fato de preco praticado aceitou delete';
  exception when others then
    if sqlerrm = 'fato de preco praticado aceitou delete' then raise; end if;
    if sqlerrm <> 'com_pedido_item_precos_praticados is append-only; create a new version or historical position' then raise; end if;
  end;
  begin
    truncate public.com_pedido_item_precos_praticados;
    raise exception 'fato de preco praticado aceitou truncate';
  exception when others then
    if sqlerrm = 'fato de preco praticado aceitou truncate' then raise; end if;
    if sqlerrm <> 'com_pedido_item_precos_praticados is append-only; create a new version or historical position' then raise; end if;
  end;
end
$$;

rollback;
\echo ORDER_PRACTICED_PRICE_COMPARISON_OK
