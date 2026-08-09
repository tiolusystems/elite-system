\set ON_ERROR_STOP on
begin;

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.create_com_pedido_vendedor_programado_idempotente(uuid,bigint,jsonb,jsonb,date,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute governed scheduled order creation';
  end if;
  if has_function_privilege(
    'anon',
    'public.create_com_pedido_vendedor_programado_idempotente(uuid,bigint,jsonb,jsonb,date,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.create_com_pedido_vendedor_programado_idempotente(uuid,bigint,jsonb,jsonb,date,text)',
    'EXECUTE'
  ) then
    raise exception 'scheduled order creation is exposed to anon or PUBLIC';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_entregas', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_entrega_itens', 'UPDATE')
     or has_table_privilege('authenticated', 'public.com_pedido_entrega_itens', 'DELETE') then
    raise exception 'direct scheduled delivery write is exposed';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('11600000-0000-4000-8000-000000000001', 'seller-0116@test.invalid'),
  ('11600000-0000-4000-8000-000000000002', 'setup-0116@test.invalid'),
  ('11600000-0000-4000-8000-000000000003', 'denied-0116@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('11600000-0000-4000-8000-000000000001', 'Vendedor 0116', 'comercial', 'active'),
  ('11600000-0000-4000-8000-000000000002', 'Setup 0116', 'admin', 'active'),
  ('11600000-0000-4000-8000-000000000003', 'Sem alcada 0116', 'comercial', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select profile.id, action.action_key, true, '11600000-0000-4000-8000-000000000002'
  from public.user_profiles profile
 cross join public.permission_actions action
 where profile.id in (
   '11600000-0000-4000-8000-000000000001',
   '11600000-0000-4000-8000-000000000002'
 )
on conflict (user_id, action_key)
do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '11600000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke 0116')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(
  nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by
) values (
  'Vendedor 0116', 'vendedor 0116', 'vendedor_direto_elite', '["vendedor"]',
  'active', '11600000-0000-4000-8000-000000000001',
  '11600000-0000-4000-8000-000000000002'
);
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
values
  ('Cliente 0116', 'cliente 0116', 'Campinas', 'SP', 'active', '11600000-0000-4000-8000-000000000002'),
  ('Outro cliente 0116', 'outro cliente 0116', 'Limeira', 'SP', 'active', '11600000-0000-4000-8000-000000000002');
insert into public.cad_cliente_documentos(cliente_id, tipo, numero, numero_norm, created_by)
select id, 'cnpj', '11.600.000/0001-16', '11600000000116', '11600000-0000-4000-8000-000000000002'
  from public.cad_clientes
 where nome = 'Cliente 0116';
insert into public.cad_cliente_propriedades(cliente_id, nome, cidade, uf, status, created_by)
select id, 'Fazenda 0116', 'Campinas', 'SP', 'active', '11600000-0000-4000-8000-000000000002'
  from public.cad_clientes
 where nome = 'Cliente 0116';
insert into public.cad_cliente_vendedores(
  cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by
)
select client.id, seller.id, 2, 'active', current_date, 'sistema',
       '11600000-0000-4000-8000-000000000002'
  from public.cad_clientes client
  join public.cad_pessoas_comerciais seller on seller.nome = 'Vendedor 0116'
 where client.nome = 'Cliente 0116';

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by)
values ('0116', 'Produto 0116', 'produto 0116', 'active', '11600000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(
  descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by
) values
  ('Frasco 0116 1 L', 'frasco 0116 1 l', 'UN', 1, 'active', 6, 'sistema', '11600000-0000-4000-8000-000000000002'),
  ('Bomba 0116 20 L', 'bomba 0116 20 l', 'UN', 20, 'active', 6, 'sistema', '11600000-0000-4000-8000-000000000002');
insert into public.cad_produto_embalagens(
  produto_id, embalagem_id, codigo_item, status, origem_dados, created_by
)
select product.id, packaging.id,
       case packaging.volume_litros when 1 then '0116-1L' else '0116-20L' end,
       'active', 'sistema', '11600000-0000-4000-8000-000000000002'
  from public.cad_produtos_base product
  join public.cad_embalagens packaging on packaging.descricao like '%0116%'
 where product.codigo_produto = '0116';

set local role authenticated;
select set_config('request.jwt.claim.sub', '11600000-0000-4000-8000-000000000001', true);

do $$
declare
  v_link bigint;
  v_property bigint;
  v_item_1 bigint;
  v_item_20 bigint;
  v_order bigint;
  v_retry bigint;
begin
  select relation.id into v_link
    from public.cad_cliente_vendedores relation
    join public.cad_clientes client on client.id = relation.cliente_id
   where client.nome = 'Cliente 0116';
  select property.id into v_property
    from public.cad_cliente_propriedades property
   where property.nome = 'Fazenda 0116';
  select id into v_item_1
    from public.cad_produto_embalagens
   where codigo_item = '0116-1L';
  select id into v_item_20
    from public.cad_produto_embalagens
   where codigo_item = '0116-20L';

  if (select count(*) from public.consultar_com_carteira_clientes_paginada(null, 20, 0)) <> 1 then
    raise exception 'initial portfolio did not return the scoped client';
  end if;
  if (select count(*) from public.consultar_com_carteira_clientes_paginada('11600000000116', 20, 0)) <> 1 then
    raise exception 'portfolio document search did not locate the scoped client';
  end if;
  if not exists (
    select 1
      from public.consultar_com_locais_entrega_cliente(
        (select id from public.cad_clientes where nome = 'Cliente 0116')
      )
     where propriedade_id = v_property
  ) then
    raise exception 'governed delivery location was not returned';
  end if;

  v_order := public.create_com_pedido_vendedor_programado_idempotente(
    '11600000-0000-4000-8000-000000000010',
    v_link,
    jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 10, 'valor_unitario', 25),
      jsonb_build_object('produto_embalagem_id', v_item_20, 'quantidade', 2, 'valor_unitario', 400)
    ),
    jsonb_build_array(
      jsonb_build_object(
        'data_prevista', current_date + 2,
        'propriedade_id', v_property,
        'itens', jsonb_build_array(
          jsonb_build_object('item_index', 1, 'quantidade', 6),
          jsonb_build_object('item_index', 2, 'quantidade', 1)
        )
      ),
      jsonb_build_object(
        'data_prevista', current_date + 5,
        'propriedade_id', v_property,
        'itens', jsonb_build_array(
          jsonb_build_object('item_index', 1, 'quantidade', 4),
          jsonb_build_object('item_index', 2, 'quantidade', 1)
        )
      )
    ),
    current_date,
    'Pedido 0116 com duas entregas'
  );

  v_retry := public.create_com_pedido_vendedor_programado_idempotente(
    '11600000-0000-4000-8000-000000000010',
    v_link,
    jsonb_build_array(
      jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 10, 'valor_unitario', 25),
      jsonb_build_object('produto_embalagem_id', v_item_20, 'quantidade', 2, 'valor_unitario', 400)
    ),
    jsonb_build_array(
      jsonb_build_object(
        'data_prevista', current_date + 2,
        'propriedade_id', v_property,
        'itens', jsonb_build_array(
          jsonb_build_object('item_index', 1, 'quantidade', 6),
          jsonb_build_object('item_index', 2, 'quantidade', 1)
        )
      ),
      jsonb_build_object(
        'data_prevista', current_date + 5,
        'propriedade_id', v_property,
        'itens', jsonb_build_array(
          jsonb_build_object('item_index', 1, 'quantidade', 4),
          jsonb_build_object('item_index', 2, 'quantidade', 1)
        )
      )
    ),
    current_date,
    'Pedido 0116 com duas entregas'
  );
  if v_retry is distinct from v_order then
    raise exception 'scheduled order retry did not return the original order';
  end if;
  if (select count(*) from public.com_pedido_entregas where pedido_id = v_order) <> 2 then
    raise exception 'scheduled order did not create two deliveries';
  end if;
  if (select count(*) from public.com_pedido_entrega_itens where pedido_id = v_order) <> 4 then
    raise exception 'scheduled order did not persist item allocations';
  end if;
  if (select previsao_entrega from public.com_pedidos where id = v_order) <> current_date + 2 then
    raise exception 'legacy delivery forecast did not retain the earliest schedule date';
  end if;

  begin
    perform public.create_com_pedido_vendedor_programado_idempotente(
      '11600000-0000-4000-8000-000000000011',
      v_link,
      jsonb_build_array(
        jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 2, 'valor_unitario', 10),
        jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 1, 'valor_unitario', 10)
      ),
      jsonb_build_array(
        jsonb_build_object(
          'data_prevista', current_date + 1,
          'propriedade_id', v_property,
          'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 3))
        )
      ),
      current_date,
      null
    );
    raise exception 'duplicate presentation was accepted';
  exception when others then
    if sqlerrm = 'duplicate presentation was accepted' then raise; end if;
  end;

  begin
    perform public.create_com_pedido_vendedor_programado_idempotente(
      '11600000-0000-4000-8000-000000000012',
      v_link,
      jsonb_build_array(
        jsonb_build_object('produto_embalagem_id', v_item_1, 'quantidade', 5, 'valor_unitario', 10)
      ),
      jsonb_build_array(
        jsonb_build_object(
          'data_prevista', current_date + 1,
          'propriedade_id', v_property,
          'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 4))
        )
      ),
      current_date,
      null
    );
    raise exception 'incomplete delivery allocation was accepted';
  exception when others then
    if sqlerrm = 'incomplete delivery allocation was accepted' then raise; end if;
  end;
end
$$;

select set_config('request.jwt.claim.sub', '11600000-0000-4000-8000-000000000003', true);
do $$
declare
  v_link bigint;
begin
  select relation.id into v_link
    from public.cad_cliente_vendedores relation
    join public.cad_clientes client on client.id = relation.cliente_id
   where client.nome = 'Cliente 0116';
  begin
    perform public.create_com_pedido_vendedor_programado_idempotente(
      '11600000-0000-4000-8000-000000000013',
      v_link,
      '[]'::jsonb,
      '[]'::jsonb,
      current_date,
      null
    );
    raise exception 'user without permission created a scheduled order';
  exception when others then
    if sqlerrm = 'user without permission created a scheduled order' then raise; end if;
  end;
end
$$;

reset role;
rollback;
select 'ORDER_DELIVERY_SCHEDULES_OK';
