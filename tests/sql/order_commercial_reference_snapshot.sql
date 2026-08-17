\set ON_ERROR_STOP on
begin;
set local time zone 'America/Sao_Paulo';

do $$
begin
  if not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.commercial_context.manage'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'write'
  ) then raise exception 'alçada de contexto comercial nao nasceu default deny'; end if;
  if not has_function_privilege('authenticated', 'public.resolver_com_referencias_comerciais_pedido_idempotente(uuid,bigint,bigint,bigint,text,bigint[],text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resolver_com_referencias_comerciais_pedido_idempotente(uuid,bigint,bigint,bigint,text,bigint[],text)', 'EXECUTE')
     or has_function_privilege('public', 'public.resolver_com_referencias_comerciais_pedido_idempotente(uuid,bigint,bigint,bigint,text,bigint[],text)', 'EXECUTE') then
    raise exception 'grants da RPC de snapshot excedem o contrato';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_item_referencias_comerciais', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_participantes_comerciais', 'UPDATE') then
    raise exception 'snapshot ampliou escrita direta para authenticated';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('12800000-0000-4000-8000-000000000001', 'snapshot-authorized@test.invalid'),
  ('12800000-0000-4000-8000-000000000002', 'snapshot-denied@test.invalid'),
  ('12800000-0000-4000-8000-000000000003', 'snapshot-setup@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12800000-0000-4000-8000-000000000001', 'Snapshot autorizado 0128', 'comercial', 'active'),
  ('12800000-0000-4000-8000-000000000002', 'Snapshot negado 0128', 'comercial', 'active'),
  ('12800000-0000-4000-8000-000000000003', 'Setup snapshot 0128', 'admin', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by) values
  ('12800000-0000-4000-8000-000000000001', 'pedidos.commercial_context.manage', true, '12800000-0000-4000-8000-000000000003'),
  ('12800000-0000-4000-8000-000000000001', 'pedidos.price_reference.resolve', true, '12800000-0000-4000-8000-000000000003'),
  ('12800000-0000-4000-8000-000000000001', 'pedidos.payment_terms.manage', true, '12800000-0000-4000-8000-000000000003'),
  ('12800000-0000-4000-8000-000000000003', 'system.admin', true, '12800000-0000-4000-8000-000000000003')
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '12800000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de snapshot comercial 0128')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, created_by, updated_by) values
  ('Agente principal snapshot 0128', 'agente principal snapshot 0128', 'agente_vinculado', '["agente", "vendedor"]'::jsonb, 'active', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003'),
  ('Agente adicional snapshot 0128', 'agente adicional snapshot 0128', 'agente_vinculado', '["agente"]'::jsonb, 'active', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
insert into public.cad_areas_comerciais(nome, nome_norm, status, created_by, updated_by)
values ('Area snapshot 0128', 'area snapshot 0128', 'active', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente snapshot 0128', 'cliente snapshot 0128', 'Campinas', 'SP', 'active', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values ('0128', 'Produto snapshot 0128', 'produto snapshot 0128', 'active', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by)
values ('Bomba snapshot 0128 20 L', 'bomba snapshot 0128 20 l', 'UN', 20, 'active', 6, 'sistema', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, packaging.id, 'P0128-20L', 'active', 'sistema', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003'
  from public.cad_produtos_base product cross join public.cad_embalagens packaging
 where product.codigo_produto = '0128' and packaging.descricao = 'Bomba snapshot 0128 20 L';

create temporary table snapshot_context(
  cliente_id bigint, area_id bigint, presentation_id bigint, direct_origin_id bigint, agent_origin_id bigint,
  principal_agent_role_id bigint, principal_seller_role_id bigint, additional_agent_role_id bigint, commercial_date date
) on commit drop;
insert into snapshot_context
select
  (select id from public.cad_clientes where nome = 'Cliente snapshot 0128'),
  (select id from public.cad_areas_comerciais where nome = 'Area snapshot 0128'),
  (select id from public.cad_produto_embalagens where codigo_item = 'P0128-20L'),
  (select id from public.com_origens_comerciais where codigo = 'direto_elite'),
  (select id from public.com_origens_comerciais where codigo = 'agente'),
  (select role.id from public.cad_pessoa_papeis role join public.cad_pessoas_comerciais person on person.id = role.pessoa_id where person.nome = 'Agente principal snapshot 0128' and role.papel = 'agente'),
  (select role.id from public.cad_pessoa_papeis role join public.cad_pessoas_comerciais person on person.id = role.pessoa_id where person.nome = 'Agente principal snapshot 0128' and role.papel = 'vendedor'),
  (select role.id from public.cad_pessoa_papeis role join public.cad_pessoas_comerciais person on person.id = role.pessoa_id where person.nome = 'Agente adicional snapshot 0128' and role.papel = 'agente'),
  (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
grant select on snapshot_context to authenticated;

do $$
declare
  v snapshot_context%rowtype;
  v_general_list bigint;
  v_general_version bigint;
  v_agent_list bigint;
  v_agent_version bigint;
  v_agent_rule bigint;
begin
  select * into v from snapshot_context;
  insert into public.com_listas_preco(codigo, nome, created_by) values ('GERAL0128', 'Lista geral snapshot 0128', '12800000-0000-4000-8000-000000000003') returning id into v_general_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_general_list, 1, v.commercial_date - 1, 'Lista geral para snapshot comercial 0128', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_general_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by) values (v_general_version, v.presentation_id, '12800000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select id, 0, 3000, '12800000-0000-4000-8000-000000000003' from public.com_lista_preco_versao_itens where versao_id = v_general_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by) values (v_general_version, 'GERAL', 'Regra geral de snapshot comercial', 0, '12800000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_general_version, md5('GERAL0128'), 'Publicacao geral de snapshot 0128', '12800000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');

  insert into public.com_listas_preco(codigo, nome, created_by) values ('AGENTE0128', 'Lista agente snapshot 0128', '12800000-0000-4000-8000-000000000003') returning id into v_agent_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_agent_list, 1, v.commercial_date - 1, 'Lista de agente para snapshot comercial 0128', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_agent_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by) values (v_agent_version, v.presentation_id, '12800000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select id, 0, 4000, '12800000-0000-4000-8000-000000000003' from public.com_lista_preco_versao_itens where versao_id = v_agent_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_agent_version, 'AGENTE', 'Regra de agente com contexto completo', 100, '12800000-0000-4000-8000-000000000003') returning id into v_agent_rule;
  insert into public.com_lista_preco_regra_origens(regra_id, origem_comercial_id) values (v_agent_rule, v.agent_origin_id);
  insert into public.com_lista_preco_regra_pessoas(regra_id, pessoa_papel_id) values (v_agent_rule, v.principal_agent_role_id);
  insert into public.com_lista_preco_regra_areas(regra_id, area_id) values (v_agent_rule, v.area_id);
  insert into public.com_lista_preco_regra_ufs(regra_id, uf) values (v_agent_rule, 'SP');
  insert into public.com_lista_preco_regra_clientes(regra_id, cliente_id) values (v_agent_rule, v.cliente_id);
  insert into public.com_lista_preco_regra_apresentacoes(regra_id, produto_embalagem_id) values (v_agent_rule, v.presentation_id);
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_agent_version, md5('AGENTE0128'), 'Publicacao de agente para snapshot 0128', '12800000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');
end
$$;

do $$
declare
  v snapshot_context%rowtype;
  v_direct_order bigint;
  v_agent_order bigint;
  v_ambiguous_order bigint;
  v_excel_actor uuid;
  v_workbook_id bigint;
  v_batch_id bigint;
  v_source_table_id bigint;
  v_source_row_id bigint;
begin
  select * into v from snapshot_context;
  insert into public.com_pedidos(codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0128-D', v.cliente_id, 'venda', 'blocked', v.commercial_date, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_direct_order;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_direct_order, v.presentation_id, 'venda', 5, 20, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
  insert into public.com_pedidos(codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0128-A', v.cliente_id, 'venda', 'blocked', v.commercial_date, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_agent_order;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_agent_order, v.presentation_id, 'venda', 5, 20, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
  insert into public.com_pedidos(codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by) values
    ('PED-0128-X', v.cliente_id, 'venda', 'blocked', v.commercial_date, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_ambiguous_order;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, valor_total, created_by, updated_by) values
    (v_ambiguous_order, v.presentation_id, 'venda', 5, 20, 100, '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003');
  insert into public.fin_pedido_planos_pagamento(pedido_id, versao, vigencia_inicio, review_status, origem_dados, data_base, valor_total_centavos, pmp_dias, created_by)
  select order_header.id, 1, v.commercial_date, 'approved', 'sistema', v.commercial_date, 10000, 0, '12800000-0000-4000-8000-000000000003'
    from public.com_pedidos order_header where order_header.id in (v_direct_order, v_agent_order, v_ambiguous_order);
  insert into public.fin_pedido_parcelas(plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto, review_status, origem_dados, created_by, forma_pagamento, valor_centavos, dias_prazo)
  select plan.id, 1, v.commercial_date, 100, 'approved', 'sistema', '12800000-0000-4000-8000-000000000003', 'pix', 10000, 0
    from public.fin_pedido_planos_pagamento plan where plan.pedido_id in (v_direct_order, v_agent_order, v_ambiguous_order);
  insert into public.fin_pedido_planos_pagamento(pedido_id, versao, vigencia_inicio, vigencia_fim, review_status, origem_dados, data_base, valor_total_centavos, pmp_dias, created_by)
  values (v_direct_order, 3, v.commercial_date - 10, v.commercial_date - 1, 'approved', 'sistema', v.commercial_date, 10000, 90, '12800000-0000-4000-8000-000000000003');
  select public.historical_migration_actor_id() into v_excel_actor;
  insert into public.source_workbooks(file_name, sha256, size_bytes, created_by)
  values ('snapshot-0128.xlsx', repeat('a', 64), 1, v_excel_actor) returning id into v_workbook_id;
  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'completed', 'Fixture legado para precedencia de plano 0128', v_excel_actor, v_excel_actor) returning id into v_batch_id;
  insert into public.source_tables(workbook_id, sheet_name, table_name, ref, column_count, row_count)
  values (v_workbook_id, 'Planos', 'Planos', 'A1:A2', 1, 1) returning id into v_source_table_id;
  insert into public.source_rows(table_id, excel_row_number, row_index, row_hash, payload_json)
  values (v_source_table_id, 2, 1, repeat('b', 32), '{}'::jsonb) returning id into v_source_row_id;
  execute 'alter table public.fin_pedido_planos_pagamento disable trigger trg_fin_pedido_planos_historical_contract';
  insert into public.fin_pedido_planos_pagamento(pedido_id, versao, vigencia_inicio, review_status, origem_dados, source_batch_id, source_row_id, data_base, valor_total_centavos, pmp_dias, created_by)
  values (v_direct_order, 4, v.commercial_date, 'approved', 'excel_legado', v_batch_id, v_source_row_id, v.commercial_date, 10000, 120, v_excel_actor);
  execute 'alter table public.fin_pedido_planos_pagamento enable trigger trg_fin_pedido_planos_historical_contract';
  create temporary table snapshot_orders(direct_order_id bigint, agent_order_id bigint, ambiguous_order_id bigint) on commit drop;
  insert into snapshot_orders values (v_direct_order, v_agent_order, v_ambiguous_order);
end
$$;
grant select on snapshot_orders to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12800000-0000-4000-8000-000000000002', true);
do $$
declare v snapshot_context%rowtype; v_orders snapshot_orders%rowtype;
begin
  select * into v from snapshot_context; select * into v_orders from snapshot_orders;
  begin
    perform public.resolver_com_referencias_comerciais_pedido_idempotente('12800000-0000-4000-8000-000000000010', v_orders.direct_order_id, v.direct_origin_id, null, null, null, 'Tentativa valida sem alçada');
    raise exception 'usuario sem alçada criou snapshot';
  exception when others then
    if sqlerrm = 'usuario sem alçada criou snapshot' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.commercial_context.manage' then raise; end if;
  end;
end
$$;

reset role;
select set_config('request.jwt.claim.sub', '12800000-0000-4000-8000-000000000001', true);
do $$
declare
  v snapshot_context%rowtype;
  v_orders snapshot_orders%rowtype;
  v_direct_retry bigint;
  v_agent_result bigint;
  v_direct_snapshot public.com_pedido_item_referencias_comerciais%rowtype;
  v_agent_snapshot public.com_pedido_item_referencias_comerciais%rowtype;
  v_general_version bigint;
  v_ambiguous_list bigint;
  v_ambiguous_version bigint;
  v_commissions_before bigint;
  v_deliveries_before bigint;
  v_planos_before bigint;
  v_snapshot_pmp numeric;
begin
  select * into v from snapshot_context; select * into v_orders from snapshot_orders;
  select count(*) into v_commissions_before from public.com_pedido_comissionados;
  select count(*) into v_deliveries_before from public.com_pedido_entregas;
  perform public.resolver_com_referencias_comerciais_pedido_idempotente('12800000-0000-4000-8000-000000000011', v_orders.direct_order_id, v.direct_origin_id, null, null, null, 'Congelar referencia direta do pedido 0128');
  v_direct_retry := public.resolver_com_referencias_comerciais_pedido_idempotente('12800000-0000-4000-8000-000000000011', v_orders.direct_order_id, v.direct_origin_id, null, null, '{}'::bigint[], 'Congelar referencia direta do pedido 0128');
  if v_direct_retry <> v_orders.direct_order_id then raise exception 'retry nao retornou o pedido original'; end if;
  select * into v_direct_snapshot from public.com_pedido_item_referencias_comerciais where pedido_id = v_orders.direct_order_id;
  select version.id into v_general_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'GERAL0128';
  if v_direct_snapshot.lista_versao_id <> v_general_version or v_direct_snapshot.pmp_dias <> 0 or v_direct_snapshot.preco_referencia_centavos_por_litro <> 3000
     or (select plan.origem_dados from public.fin_pedido_planos_pagamento plan where plan.id = v_direct_snapshot.plano_pagamento_id) <> 'sistema'
     or (select plan.versao from public.fin_pedido_planos_pagamento plan where plan.id = v_direct_snapshot.plano_pagamento_id) <> 1 then
    raise exception 'snapshot direto nao preservou lista, PMP ou preco';
  end if;
  if (select status from public.com_pedidos where id = v_orders.direct_order_id) <> 'blocked'
     or (select origem_comercial_id from public.com_pedidos where id = v_orders.direct_order_id) <> v.direct_origin_id then
    raise exception 'pedido direto deixou de estar bloqueado ou nao congelou origem explicita';
  end if;
  if exists (select 1 from public.cad_cliente_vendedores relation where relation.cliente_id = v.cliente_id) then
    raise exception 'fixture possui relacionamento que poderia derivar origem';
  end if;
  select count(*) into v_planos_before
    from public.fin_pedido_planos_pagamento where pedido_id = v_orders.direct_order_id;
  v_snapshot_pmp := v_direct_snapshot.pmp_dias;
  begin
    perform public.replace_com_pedido_condicao_financeira_idempotente(
      '12800000-0000-4000-8000-000000000014', v_orders.direct_order_id,
      jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'forma_pagamento', 'boleto', 'valor_centavos', 10000, 'data_vencimento', v.commercial_date + 30)),
      'Nova condicao financeira apos snapshot comercial'
    );
    raise exception 'condicao financeira foi alterada apos snapshot';
  exception when others then
    if sqlerrm = 'condicao financeira foi alterada apos snapshot' then raise; end if;
    if sqlerrm <> 'snapshot comercial ja foi congelado; nova condicao financeira exige revisao governada' then raise; end if;
  end;
  if (select count(*) from public.fin_pedido_planos_pagamento where pedido_id = v_orders.direct_order_id) <> v_planos_before
     or (select pmp_dias from public.com_pedido_item_referencias_comerciais where id = v_direct_snapshot.id) <> v_snapshot_pmp
     or (select status from public.com_pedidos where id = v_orders.direct_order_id) <> 'blocked' then
    raise exception 'trava financeira alterou plano, snapshot ou status do pedido';
  end if;

  v_agent_result := public.resolver_com_referencias_comerciais_pedido_idempotente(
    '12800000-0000-4000-8000-000000000012', v_orders.agent_order_id, v.agent_origin_id, v.area_id, ' sp ',
    array[v.additional_agent_role_id, v.principal_agent_role_id, v.principal_seller_role_id], 'Congelar referencia de agente do pedido 0128'
  );
  if v_agent_result <> v_orders.agent_order_id then raise exception 'snapshot agente nao retornou pedido'; end if;
  select * into v_agent_snapshot from public.com_pedido_item_referencias_comerciais where pedido_id = v_orders.agent_order_id;
  if v_agent_snapshot.preco_referencia_centavos_por_litro <> 4000 or v_agent_snapshot.uf <> 'SP'
     or cardinality(v_agent_snapshot.pessoa_papel_ids) <> 3
     or (select count(*) from public.com_pedido_participantes_comerciais where pedido_id = v_orders.agent_order_id) <> 3 then
    raise exception 'snapshot agente nao preservou participantes ou referencia especifica';
  end if;

  insert into public.com_listas_preco(codigo, nome, created_by) values ('AMB0128', 'Lista ambigua snapshot 0128', '12800000-0000-4000-8000-000000000003') returning id into v_ambiguous_list;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_ambiguous_list, 1, v.commercial_date - 1, 'Lista ambigua para bloquear snapshot comercial', '12800000-0000-4000-8000-000000000003', '12800000-0000-4000-8000-000000000003') returning id into v_ambiguous_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by) values (v_ambiguous_version, v.presentation_id, '12800000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select id, 0, 5000, '12800000-0000-4000-8000-000000000003' from public.com_lista_preco_versao_itens where versao_id = v_ambiguous_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by) values (v_ambiguous_version, 'AMBIGUA', 'Regra generica ambigua para bloqueio', 0, '12800000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_ambiguous_version, md5('AMB0128'), 'Publicacao ambigua para bloquear snapshot', '12800000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');
  begin
    perform public.resolver_com_referencias_comerciais_pedido_idempotente('12800000-0000-4000-8000-000000000013', v_orders.ambiguous_order_id, v.direct_origin_id, null, null, null, 'Tentativa ambigua deve falhar sem efeito parcial');
    raise exception 'ambiguidade criou snapshot';
  exception when others then
    if sqlerrm = 'ambiguidade criou snapshot' then raise; end if;
    if sqlerrm <> 'ambiguidade entre listas comerciais de mesma precedencia e especificidade' then raise; end if;
  end;
  if exists (select 1 from public.com_pedido_item_referencias_comerciais where pedido_id = v_orders.ambiguous_order_id)
     or exists (select 1 from public.com_pedido_participantes_comerciais where pedido_id = v_orders.ambiguous_order_id)
     or (select origem_comercial_id from public.com_pedidos where id = v_orders.ambiguous_order_id) is not null then
    raise exception 'falha de resolucao deixou contexto parcial';
  end if;

  update public.cad_pessoas_comerciais set status = 'inactive' where nome = 'Agente principal snapshot 0128';
  if (select preco_referencia_centavos_por_litro from public.com_pedido_item_referencias_comerciais where id = v_direct_snapshot.id) <> 3000
     or (select count(*) from public.com_pedido_participantes_comerciais where pedido_id = v_orders.agent_order_id) <> 3 then
    raise exception 'alteracao cadastral reinterpretou snapshot historico';
  end if;
  begin
    update public.com_pedido_item_referencias_comerciais set pmp_dias = 1 where id = v_direct_snapshot.id;
    raise exception 'snapshot aceitou update';
  exception when others then
    if sqlerrm = 'snapshot aceitou update' then raise; end if;
  end;
  begin
    delete from public.com_pedido_item_referencias_comerciais where id = v_direct_snapshot.id;
    raise exception 'snapshot aceitou delete';
  exception when others then
    if sqlerrm = 'snapshot aceitou delete' then raise; end if;
  end;
  if (select count(*) from public.com_pedido_comissionados) <> v_commissions_before
     or (select count(*) from public.com_pedido_entregas) <> v_deliveries_before then
    raise exception 'snapshot gerou efeito de comissao ou logistica';
  end if;
end
$$;

rollback;
