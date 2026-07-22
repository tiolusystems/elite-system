\set ON_ERROR_STOP on
begin;

do $$ begin
  if has_function_privilege('anon', 'public.create_com_pedido_vendedor(bigint,bigint,numeric,numeric,date,text)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.cad_limite_credito_eventos', 'INSERT') then
    raise exception '0078 grants are broader than the contract';
  end if;
end $$;

insert into auth.users(id, email) values
  ('78000000-0000-4000-8000-000000000001', 'manager@test.invalid'),
  ('78000000-0000-4000-8000-000000000002', 'seller-a@test.invalid'),
  ('78000000-0000-4000-8000-000000000003', 'seller-b@test.invalid'),
  ('78000000-0000-4000-8000-000000000004', 'setup-admin@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('78000000-0000-4000-8000-000000000001', 'Gerente Teste', 'comercial', 'active'),
  ('78000000-0000-4000-8000-000000000002', 'Vendedor A', 'comercial', 'active'),
  ('78000000-0000-4000-8000-000000000003', 'Vendedor B', 'comercial', 'active'),
  ('78000000-0000-4000-8000-000000000004', 'Administrador Setup', 'admin', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select profile.id, action.action_key, true, '78000000-0000-4000-8000-000000000001'
  from public.user_profiles profile cross join public.permission_actions action
 where profile.id in (
   '78000000-0000-4000-8000-000000000001',
   '78000000-0000-4000-8000-000000000002',
   '78000000-0000-4000-8000-000000000003',
   '78000000-0000-4000-8000-000000000004'
 )
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
select set_config('request.jwt.claim.sub', '78000000-0000-4000-8000-000000000004', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke 0078')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by)
values
  ('Gerente Teste', 'gerente teste', 'gerente', '["gerente"]', 'active', '78000000-0000-4000-8000-000000000001', '78000000-0000-4000-8000-000000000001'),
  ('Vendedor A', 'vendedor a', 'vendedor_direto_elite', '["vendedor"]', 'active', '78000000-0000-4000-8000-000000000002', '78000000-0000-4000-8000-000000000001'),
  ('Vendedor B', 'vendedor b', 'vendedor_direto_elite', '["vendedor"]', 'active', '78000000-0000-4000-8000-000000000003', '78000000-0000-4000-8000-000000000001');
update public.cad_pessoas_comerciais seller
   set vendedor_responsavel_id = manager.id
  from public.cad_pessoas_comerciais manager
 where seller.nome = 'Vendedor A' and manager.nome = 'Gerente Teste';

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
values
  ('Cliente Carteira A', 'cliente carteira a', 'Campinas', 'SP', 'active', '78000000-0000-4000-8000-000000000001'),
  ('Cliente Carteira B', 'cliente carteira b', 'Ribeirao Preto', 'SP', 'active', '78000000-0000-4000-8000-000000000001');

insert into public.cad_cliente_vendedores(cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by)
select client.id, seller.id, 2, 'active', current_date, 'sistema', '78000000-0000-4000-8000-000000000001'
  from public.cad_clientes client
  join public.cad_pessoas_comerciais seller on seller.nome = case client.nome when 'Cliente Carteira A' then 'Vendedor A' else 'Vendedor B' end
 where client.nome in ('Cliente Carteira A', 'Cliente Carteira B');

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by)
values ('0078', 'Produto Teste 0078', 'produto teste 0078', 'active', '78000000-0000-4000-8000-000000000001');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by)
values ('Frasco teste 1 L', 'frasco teste 1 l', 'UN', 1, 'active', 6, 'sistema', '78000000-0000-4000-8000-000000000001');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by)
select product.id, packaging.id, '0078-1L', 'active', 'sistema', '78000000-0000-4000-8000-000000000001'
  from public.cad_produtos_base product, public.cad_embalagens packaging
 where product.codigo_produto = '0078' and packaging.descricao = 'Frasco teste 1 L';

set local role authenticated;
select set_config('request.jwt.claim.sub', '78000000-0000-4000-8000-000000000002', true);

do $$
declare v_link bigint; v_item bigint; v_order bigint;
begin
  select relation.id into v_link from public.cad_cliente_vendedores relation
    join public.cad_clientes client on client.id = relation.cliente_id where client.nome = 'Cliente Carteira A';
  select id into v_item from public.cad_produto_embalagens where codigo_item = '0078-1L';
  v_order := public.create_com_pedido_vendedor(v_link, v_item, 10, 25, current_date, 'Pedido sintetico 0078');
  if not exists (select 1 from public.com_pedidos where id = v_order and status = 'blocked' and cliente_vendedor_vinculo_id = v_link) then
    raise exception 'seller order did not enter pending approval';
  end if;
end $$;

do $$ begin
  perform public.registrar_com_pedido_decisao_gerencial((select id from public.com_pedidos limit 1), 'liberado', 'Tentativa indevida do vendedor');
  raise exception 'seller unexpectedly approved own order';
exception when others then
  if sqlerrm = 'seller unexpectedly approved own order' then raise; end if;
end $$;

do $$ begin
  perform public.registrar_com_pedido_decisao_credito((select id from public.com_pedidos limit 1), 'liberado', 'Tentativa pela RPC legada', null, null, null);
  raise exception 'legacy credit RPC allowed seller approval';
exception when others then
  if sqlerrm = 'legacy credit RPC allowed seller approval' then raise; end if;
end $$;

do $$
declare v_item bigint; v_client bigint; v_manager bigint;
begin
  select id into v_item from public.cad_produto_embalagens where codigo_item = '0078-1L';
  select id into v_client from public.cad_clientes where nome = 'Cliente Carteira A';
  select id into v_manager from public.cad_pessoas_comerciais where nome = 'Gerente Teste';
  perform public.create_com_pedido_operacional(v_client, v_item, 1, 10, null, 'venda', 'open', current_date, v_manager, null, null);
  raise exception 'legacy order RPC allowed seller spoofing';
exception when others then
  if sqlerrm = 'legacy order RPC allowed seller spoofing' then raise; end if;
end $$;

select set_config('request.jwt.claim.sub', '78000000-0000-4000-8000-000000000003', true);
do $$ begin
  if (select count(*) from public.com_pedidos) <> 0 then raise exception 'unrelated seller can read another portfolio'; end if;
  if (select count(*) from public.consultar_com_pedidos_escopo(100)) <> 0 then raise exception 'scoped order RPC leaked another portfolio'; end if;
end $$;

select set_config('request.jwt.claim.sub', '78000000-0000-4000-8000-000000000001', true);
do $$
declare v_order bigint; v_client bigint; v_limit_event bigint;
begin
  if not public.current_user_manages_seller((select id from public.cad_pessoas_comerciais where nome = 'Vendedor A')) then raise exception 'direct manager hierarchy failed'; end if;
  if public.current_user_manages_seller((select id from public.cad_pessoas_comerciais where nome = 'Vendedor B')) then raise exception 'manager hierarchy leaked unrelated seller'; end if;
  if (select count(*) from public.consultar_com_carteira_clientes('Carteira A')) <> 1 then raise exception 'manager cannot find subordinate client'; end if;
  if (select count(*) from public.consultar_com_carteira_clientes('Carteira B')) <> 0 then raise exception 'manager client search leaked unrelated seller'; end if;
  if (select count(*) from public.consultar_com_carteira_clientes(null)) <> 0 then raise exception 'portfolio search preloaded clients without query'; end if;
  select id, cliente_id into v_order, v_client from public.com_pedidos limit 1;
  if (select count(*) from public.consultar_com_pedidos_aprovacao()) <> 1 then raise exception 'manager queue scope failed'; end if;
  v_limit_event := public.ajustar_com_limite_credito_cliente_idempotente(
    '78000000-0000-4000-8000-000000000010', v_client, 5000, 'Aumento aprovado para teste 0078'
  );
  if public.ajustar_com_limite_credito_cliente_idempotente(
    '78000000-0000-4000-8000-000000000010', v_client, 5000, 'Aumento aprovado para teste 0078'
  ) <> v_limit_event then raise exception 'credit limit retry duplicated the event'; end if;
  perform public.registrar_com_pedido_decisao_gerencial(v_order, 'liberado', 'Credito revisado e aprovado no teste');
  if (select status from public.com_pedidos where id = v_order) <> 'open' then raise exception 'manager approval failed'; end if;
  if not exists (select 1 from public.cad_limite_credito_eventos where cliente_id = v_client and limite_novo = 5000) then raise exception 'credit ledger failed'; end if;
end $$;

do $$ begin
  update public.com_pedidos set valor_total = 1;
  raise exception 'direct update unexpectedly allowed';
exception when insufficient_privilege then null;
end $$;

reset role;
rollback;
select 'PG_VALIDATE_0078_SELLER_MANAGER_OK';
