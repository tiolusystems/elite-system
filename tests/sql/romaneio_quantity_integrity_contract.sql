\set ON_ERROR_STOP on

begin;

do $romaneio_quantity_integrity$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000060';
  v_denied_actor uuid := '00000000-0000-4000-8000-000000000160';
  v_client_id bigint;
  v_product_id bigint;
  v_package_id bigint;
  v_product_package_id bigint;
  v_order_id bigint;
  v_order_item_id bigint;
  v_romaneio_1_id bigint;
  v_romaneio_2_id bigint;
  v_romaneio_3_id bigint;
  v_direct_romaneio_id bigint;
  v_balance record;
begin
  if has_function_privilege(
    'anon',
    'public.create_exp_romaneio(bigint,bigint,numeric,text,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute create_exp_romaneio';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.create_exp_romaneio(bigint,bigint,numeric,text,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute create_exp_romaneio';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.registrar_exp_romaneio_separacao(bigint,text,text)',
    'EXECUTE'
  ) then
    raise exception 'legacy text-only separation RPC remains executable';
  end if;
  if not exists (
    select 1
      from pg_class relation
     where relation.oid = 'public.exp_pedido_item_romaneio_saldos'::regclass
       and coalesce((relation.reloptions @> array['security_invoker=true']), false)
  ) then
    raise exception 'romaneio balance view is not security_invoker';
  end if;

  insert into auth.users(id) values (v_actor), (v_denied_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor, 'Romaneio Quantity Smoke Actor', 'admin', 'active'),
    (v_denied_actor, 'Romaneio Quantity Denied Actor', 'expedicao', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor
    from public.permission_actions action
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_denied_actor, 'romaneios.create', false, v_actor)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test', 'test_reset', 'Smoke 0060 de integridade quantitativa do romaneio'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'romaneio quantity smoke requires unconfigured or test environment';
  end if;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    '8060', 'Produto Smoke 0060', 'produto smoke 0060', 'active', '{}'::jsonb,
    v_actor, v_actor, 'sistema'
  ) returning id into v_product_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, controla_estoque,
    status, origem_dados, created_by, updated_by
  ) values (
    'Frasco Smoke 0060', 'frasco smoke 0060', 'l', 5, false,
    'active', 'sistema', v_actor, v_actor
  ) returning id into v_package_id;

  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, created_by, updated_by, origem_dados
  ) values (
    v_product_id, v_package_id, '8060-5L', 'active', v_actor, v_actor, 'sistema'
  ) returning id into v_product_package_id;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente Smoke 0060', 'cliente smoke 0060', 'Campinas', 'SP', 'active',
    '[]'::jsonb, '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    origem_canal, valor_total, created_by, updated_by, origem_dados
  ) values (
    'SMOKE-0060-PED', v_client_id, 'venda', 'open', current_date,
    'interno', 0, v_actor, v_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.com_pedido_itens(
    pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario,
    percentual_desconto, valor_total, status, created_by, updated_by, origem_dados
  ) values (
    v_order_id, v_product_package_id, 'venda', 20, 0, 0, 0, 'active',
    v_actor, v_actor, 'sistema'
  ) returning id into v_order_item_id;

  perform set_config('request.jwt.claim.sub', v_denied_actor::text, true);
  begin
    perform public.create_exp_romaneio(null, null, null, null, null, null, null);
    raise exception 'zero-grant actor reached input validation';
  exception when others then
    if sqlerrm <> 'not allowed: romaneios.create' then
      raise;
    end if;
  end;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  v_romaneio_1_id := public.create_exp_romaneio(
    v_order_id, v_order_item_id, 10, null, 'parcial', 'draft', 'Primeira parcela'
  );
  v_romaneio_2_id := public.create_exp_romaneio(
    v_order_id, v_order_item_id, 10, null, 'parcial', 'draft', 'Segunda parcela'
  );

  select * into v_balance
    from public.exp_pedido_item_romaneio_saldos
   where pedido_item_id = v_order_item_id;

  if v_balance.quantidade_pedido <> 20
     or v_balance.quantidade_confirmada <> 0
     or v_balance.quantidade_pendente <> 20
     or v_balance.quantidade_comprometida <> 20
     or v_balance.quantidade_disponivel_romaneio <> 0
     or v_balance.quantidade_excedente <> 0 then
    raise exception 'unexpected balance after two drafts: %', to_jsonb(v_balance);
  end if;

  begin
    perform public.create_exp_romaneio(
      v_order_id, v_order_item_id, 1, null, 'parcial', 'draft', 'Excesso proibido'
    );
    raise exception 'RPC accepted quantity above the free order balance';
  exception when others then
    if sqlerrm <> 'romaneio exceeds pending order quantity' then
      raise;
    end if;
  end;

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio,
    created_by, updated_by, origem_dados
  ) values (
    'SMOKE-0060-DIRECT', v_order_id, 'parcial', 'draft', current_date,
    v_actor, v_actor, 'sistema'
  ) returning id into v_direct_romaneio_id;

  begin
    insert into public.exp_romaneio_itens(
      romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id,
      quantidade_romaneada, quantidade_reservada, status, created_by, updated_by, origem_dados
    ) values (
      v_direct_romaneio_id, v_order_id, v_order_item_id, v_product_package_id,
      1, 0, 'draft', v_actor, v_actor, 'sistema'
    );
    raise exception 'table trigger accepted an overcommitted romaneio item';
  exception when check_violation then
    if sqlerrm <> 'romaneio exceeds pending order quantity' then
      raise;
    end if;
  end;

  perform public.cancelar_exp_romaneio(v_romaneio_1_id, 'Liberar saldo do smoke');

  select * into v_balance
    from public.exp_pedido_item_romaneio_saldos
   where pedido_item_id = v_order_item_id;

  if v_balance.quantidade_comprometida <> 10
     or v_balance.quantidade_disponivel_romaneio <> 10 then
    raise exception 'cancelled romaneio did not release allocation: %', to_jsonb(v_balance);
  end if;

  v_romaneio_3_id := public.create_exp_romaneio(
    v_order_id, v_order_item_id, 10, null, 'parcial', 'draft', 'Saldo liberado'
  );

  if v_romaneio_3_id is null or v_romaneio_3_id = v_romaneio_2_id then
    raise exception 'released allocation did not create a new romaneio';
  end if;

  if not exists (
    select 1
      from public.action_logs log
     where log.entity_type = 'exp_romaneios'
       and log.entity_id = v_romaneio_3_id::text
       and log.action_key = 'romaneios.create'
       and log.metadata_json->>'correlation_id' = format('romaneio:%s:create', v_romaneio_3_id)
       and log.after_json->>'quantidade_disponivel_depois' = '0'
  ) then
    raise exception 'audited romaneio creation log was not recorded';
  end if;
end;
$romaneio_quantity_integrity$;

rollback;

select 'PG_VALIDATE_0060_WITH_SMOKE_OK' as validation_result;
