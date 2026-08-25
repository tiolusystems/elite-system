\set ON_ERROR_STOP on
begin;

insert into auth.users(id, email) values
  ('86000000-0000-4000-8000-000000000001', 'manager-0086@test.invalid'),
  ('86000000-0000-4000-8000-000000000002', 'seller-0086@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('86000000-0000-4000-8000-000000000001', 'Gerente 0086', 'admin', 'active'),
  ('86000000-0000-4000-8000-000000000002', 'Vendedor 0086', 'comercial', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select profile.id, action.action_key, true, '86000000-0000-4000-8000-000000000001'
  from public.user_profiles profile cross join public.permission_actions action
 where profile.id in ('86000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000002')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
select set_config('request.jwt.claim.sub', '86000000-0000-4000-8000-000000000001', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke 0086')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by)
values ('Vendedor 0086', 'vendedor 0086', 'vendedor_direto_elite', '["vendedor"]', 'active',
        '86000000-0000-4000-8000-000000000002', '86000000-0000-4000-8000-000000000001');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
values ('Cliente 0086', 'cliente 0086', 'Campinas', 'SP', 'active', '86000000-0000-4000-8000-000000000001');
insert into public.cad_cliente_vendedores(cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by)
select client.id, seller.id, 2, 'active', current_date, 'sistema', '86000000-0000-4000-8000-000000000001'
  from public.cad_clientes client, public.cad_pessoas_comerciais seller
 where client.nome = 'Cliente 0086' and seller.nome = 'Vendedor 0086';
insert into public.cad_cliente_propriedades(cliente_id, nome, cidade, uf, status, created_by)
select id, 'Fazenda 0086', 'Campinas', 'SP', 'active', '86000000-0000-4000-8000-000000000001'
  from public.cad_clientes
 where nome = 'Cliente 0086';
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by)
values ('8686', 'Produto 0086', 'produto 0086', 'active', '86000000-0000-4000-8000-000000000001');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by)
values ('Frasco 0086 1 L', 'frasco 0086 1 l', 'UN', 1, 'active', 6, 'sistema', '86000000-0000-4000-8000-000000000001');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by)
select product.id, packaging.id, '8686-1L', 'active', 'sistema', '86000000-0000-4000-8000-000000000001'
  from public.cad_produtos_base product, public.cad_embalagens packaging
 where product.codigo_produto = '8686' and packaging.descricao = 'Frasco 0086 1 L';

set local role authenticated;
select set_config('request.jwt.claim.sub', '86000000-0000-4000-8000-000000000002', true);
do $$
declare
  v_client bigint;
  v_item bigint;
  v_link bigint;
  v_property bigint;
  v_order bigint;
  v_order_item bigint;
  v_exchange bigint;
  v_exchange_retry bigint;
begin
  select id into v_client from public.cad_clientes where nome = 'Cliente 0086';
  select id into v_item from public.cad_produto_embalagens where codigo_item = '8686-1L';
  select id into v_link
    from public.cad_cliente_vendedores
   where cliente_id = v_client;
  select id into v_property
    from public.cad_cliente_propriedades
   where cliente_id = v_client and nome = 'Fazenda 0086';

  if has_function_privilege(
    'authenticated',
    'public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'legacy operational order entrypoint remains executable';
  end if;

  v_order := public.create_com_pedido_vendedor_programado_idempotente(
    '86000000-0000-4000-8000-000000000090',
    v_link,
    jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v_item, 'quantidade', 1, 'valor_unitario', 100)
    ),
    jsonb_build_array(
      jsonb_build_object(
        'data_prevista', current_date,
        'propriedade_id', v_property,
        'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 1))
      )
    ),
    current_date,
    'Pedido bloqueado via fluxo programado'
  );
  if (select status from public.com_pedidos where id = v_order) <> 'blocked' then
    raise exception 'operational order did not start blocked';
  end if;
  if not exists (
    select 1 from public.com_pedido_credito_decisoes
     where pedido_id = v_order and decisao = 'pendente_aprovacao' and status_resultante = 'blocked'
  ) then raise exception 'operational order did not enter approval queue'; end if;

  select id into v_order_item from public.com_pedido_itens where pedido_id = v_order;
  v_exchange := public.create_com_pedido_troca_idempotente(
    '86000000-0000-4000-8000-000000000100', v_order, v_order_item, v_item,
    1, 'blocked', current_date, 'qualidade', 'Troca sintetica idempotente'
  );
  v_exchange_retry := public.create_com_pedido_troca_idempotente(
    '86000000-0000-4000-8000-000000000100', v_order, v_order_item, v_item,
    1, 'blocked', current_date, 'qualidade', 'Troca sintetica idempotente'
  );
  if v_exchange_retry is distinct from v_exchange then
    raise exception 'identical exchange retry created a different order';
  end if;
  if (select count(*) from public.com_pedidos where pedido_origem_id = v_order and tipo_pedido = 'troca') <> 1 then
    raise exception 'exchange retry created more than one operational order';
  end if;
  begin
    perform public.create_com_pedido_troca_idempotente(
      '86000000-0000-4000-8000-000000000100', v_order, v_order_item, v_item,
      2, 'blocked', current_date, 'qualidade', 'Troca sintetica idempotente'
    );
    raise exception 'exchange request key accepted changed quantity';
  exception when others then
    if sqlerrm <> 'idempotency key reused with different exchange order request' then raise; end if;
  end;
end $$;

reset role;
rollback;
select 'PG_VALIDATE_0086_BLOCKED_CREATION_OK';
