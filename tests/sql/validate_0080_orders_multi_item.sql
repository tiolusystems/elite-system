\set ON_ERROR_STOP on
begin;

do $$ begin
  if has_function_privilege('authenticated', 'public.create_com_pedido_vendedor_itens(bigint,jsonb,date,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.create_com_pedido_vendedor_itens_idempotente(uuid,bigint,jsonb,date,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.create_com_pedido_vendedor_itens_idempotente(uuid,bigint,jsonb,date,text)', 'EXECUTE') then
    raise exception 'seller order grants are broader than the idempotent contract';
  end if;
end $$;

insert into auth.users(id, email) values
  ('80000000-0000-4000-8000-000000000001', 'seller-0080@test.invalid'),
  ('80000000-0000-4000-8000-000000000002', 'setup-0080@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('80000000-0000-4000-8000-000000000001', 'Vendedor 0080', 'comercial', 'active'),
  ('80000000-0000-4000-8000-000000000002', 'Setup 0080', 'admin', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select profile.id, action.action_key, true, '80000000-0000-4000-8000-000000000002'
  from public.user_profiles profile cross join public.permission_actions action
 where profile.id in ('80000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000002')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke 0080')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by)
values ('Vendedor 0080', 'vendedor 0080', 'vendedor_direto_elite', '["vendedor"]', 'active',
        '80000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000002');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
values ('Cliente 0080', 'cliente 0080', 'Campinas', 'SP', 'active', '80000000-0000-4000-8000-000000000002');
insert into public.cad_cliente_vendedores(cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by)
select client.id, seller.id, 2, 'active', current_date, 'sistema', '80000000-0000-4000-8000-000000000002'
  from public.cad_clientes client, public.cad_pessoas_comerciais seller
 where client.nome = 'Cliente 0080' and seller.nome = 'Vendedor 0080';
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by)
values ('0080', 'Produto 0080', 'produto 0080', 'active', '80000000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by)
values
  ('Frasco 0080 1 L', 'frasco 0080 1 l', 'UN', 1, 'active', 6, 'sistema', '80000000-0000-4000-8000-000000000002'),
  ('Frasco 0080 5 L', 'frasco 0080 5 l', 'UN', 5, 'active', 6, 'sistema', '80000000-0000-4000-8000-000000000002'),
  ('Bomba 0080 20 L', 'bomba 0080 20 l', 'UN', 20, 'active', 6, 'sistema', '80000000-0000-4000-8000-000000000002');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by)
select product.id, packaging.id,
       case packaging.volume_litros when 1 then '0080-1L' when 5 then '0080-5L' else '0080-20L' end,
       case packaging.volume_litros when 5 then 'inactive' else 'active' end,
       'sistema', '80000000-0000-4000-8000-000000000002'
  from public.cad_produtos_base product
  join public.cad_embalagens packaging on packaging.descricao like '%0080%'
 where product.codigo_produto = '0080';

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  v_link bigint;
  v_item_1 bigint;
  v_item_inactive bigint;
  v_item_20 bigint;
  v_order bigint;
  v_order_retry bigint;
begin
  select relation.id into v_link
    from public.cad_cliente_vendedores relation
    join public.cad_clientes client on client.id = relation.cliente_id
   where client.nome = 'Cliente 0080';
  select id into v_item_1 from public.cad_produto_embalagens where codigo_item = '0080-1L';
  select id into v_item_inactive from public.cad_produto_embalagens where codigo_item = '0080-5L';
  select id into v_item_20 from public.cad_produto_embalagens where codigo_item = '0080-20L';

  v_order := public.create_com_pedido_vendedor_itens_idempotente(
    '80000000-0000-4000-8000-000000000010',
    v_link,
    jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 10, 'valor_unitario', 25.50),
      jsonb_build_object('produto_embalagem_id', v_item_20, 'quantidade', 2, 'valor_unitario', 400)
    ),
    current_date,
    'Pedido sintetico com dois itens'
  );
  v_order_retry := public.create_com_pedido_vendedor_itens_idempotente(
    '80000000-0000-4000-8000-000000000010',
    v_link,
    jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 10, 'valor_unitario', 25.50),
      jsonb_build_object('produto_embalagem_id', v_item_20, 'quantidade', 2, 'valor_unitario', 400)
    ),
    current_date,
    'Pedido sintetico com dois itens'
  );
  if v_order_retry is distinct from v_order then
    raise exception 'seller order retry did not return the original order';
  end if;

  if (select count(*) from public.com_pedido_itens where pedido_id = v_order and status = 'active') <> 2 then
    raise exception 'multi-item order did not persist exactly two items';
  end if;
  if (select valor_total from public.com_pedidos where id = v_order) <> 1055 then
    raise exception 'multi-item order total is incorrect';
  end if;
  if (select status from public.com_pedidos where id = v_order) <> 'blocked' then
    raise exception 'multi-item order bypassed manager approval';
  end if;
  if (select count(*) from public.com_pedido_credito_decisoes where pedido_id = v_order and decisao = 'pendente_aprovacao') <> 1 then
    raise exception 'multi-item order created an invalid approval queue';
  end if;

  begin
    perform public.create_com_pedido_vendedor_itens_idempotente(
      '80000000-0000-4000-8000-000000000011',
      v_link,
      jsonb_build_array(jsonb_build_object('produto_embalagem_id', v_item_inactive, 'quantidade', 1, 'valor_unitario', 1)),
      current_date,
      null
    );
    raise exception 'inactive sale item was accepted';
  exception when others then
    if sqlerrm = 'inactive sale item was accepted' then raise; end if;
  end;
end $$;

reset role;
rollback;
select 'PG_VALIDATE_0080_MULTI_ITEM_OK';
