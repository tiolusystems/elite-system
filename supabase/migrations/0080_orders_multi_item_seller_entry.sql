-- Multiple sale items in one seller order, preserving portfolio and approval scope.

create or replace function public.create_com_pedido_vendedor_itens(
  p_cliente_vendedor_vinculo_id bigint,
  p_itens_jsonb jsonb,
  p_data_pedido date default current_date,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_order_id bigint;
  v_first record;
  v_item record;
  v_count integer;
  v_total numeric;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.create.own');
  if p_data_pedido is null then raise exception 'order date is required'; end if;
  if jsonb_typeof(p_itens_jsonb) <> 'array' then raise exception 'items must be an array'; end if;
  v_count := jsonb_array_length(p_itens_jsonb);
  if v_count < 1 or v_count > 100 then raise exception 'order must contain between 1 and 100 items'; end if;

  select item.* into v_first
    from jsonb_to_recordset(p_itens_jsonb) as item(
      produto_embalagem_id bigint, quantidade numeric, valor_unitario numeric
    ) limit 1;
  if v_first.produto_embalagem_id is null or v_first.quantidade <= 0 or v_first.valor_unitario < 0 then
    raise exception 'invalid order item';
  end if;
  if not exists (
    select 1 from public.cad_produto_embalagens sale_item
     where sale_item.id = v_first.produto_embalagem_id
       and sale_item.status = 'active'
  ) then raise exception 'sale item is inactive or unknown at position 1'; end if;

  v_order_id := public.create_com_pedido_vendedor_core_0079(
    p_cliente_vendedor_vinculo_id, v_first.produto_embalagem_id,
    v_first.quantidade, v_first.valor_unitario, p_data_pedido, p_observacao
  );
  v_actor := public.current_actor_id();

  for v_item in
    select entry.item, entry.ordinality
      from jsonb_array_elements(p_itens_jsonb) with ordinality as entry(item, ordinality)
     where entry.ordinality > 1
     order by entry.ordinality
  loop
    if (v_item.item->>'produto_embalagem_id') is null
       or coalesce((v_item.item->>'quantidade')::numeric, 0) <= 0
       or coalesce((v_item.item->>'valor_unitario')::numeric, -1) < 0 then
      raise exception 'invalid order item at position %', v_item.ordinality;
    end if;
    if not exists (
      select 1 from public.cad_produto_embalagens sale_item
       where sale_item.id = (v_item.item->>'produto_embalagem_id')::bigint
         and sale_item.status = 'active'
    ) then raise exception 'sale item is inactive or unknown at position %', v_item.ordinality; end if;

    insert into public.com_pedido_itens(
      pedido_id, produto_embalagem_id, tipo_item, quantidade,
      valor_unitario, percentual_desconto, valor_total, status,
      created_by, updated_by
    ) values (
      v_order_id, (v_item.item->>'produto_embalagem_id')::bigint, 'venda',
      (v_item.item->>'quantidade')::numeric,
      (v_item.item->>'valor_unitario')::numeric, 0,
      (v_item.item->>'quantidade')::numeric * (v_item.item->>'valor_unitario')::numeric,
      'active', v_actor, v_actor
    );
  end loop;

  select sum(item.valor_total) into v_total
    from public.com_pedido_itens item
   where item.pedido_id = v_order_id and item.status = 'active';
  update public.com_pedidos set valor_total = coalesce(v_total, 0), updated_by = v_actor where id = v_order_id;

  v_context := public.begin_audited_rpc(
    'pedidos.create.own', 'pedidos', 'com_pedidos', 'own_any',
    jsonb_build_object('event', 'seller_multi_item_order')
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_order_id::text,
    'pedidos.itens_consolidados', 'pedidos.create.own', v_context,
    null, public.com_pedido_audit_snapshot(v_order_id),
    jsonb_build_object('source', 'create_com_pedido_vendedor_itens', 'item_count', v_count, 'valor_total', v_total)
  );
  return v_order_id;
end;
$$;

revoke all on function public.create_com_pedido_vendedor_itens(bigint, jsonb, date, text) from public, anon;
grant execute on function public.create_com_pedido_vendedor_itens(bigint, jsonb, date, text) to authenticated;

comment on function public.create_com_pedido_vendedor_itens(bigint, jsonb, date, text) is
  'Cria um unico pedido de venda com ate 100 itens, sempre na carteira da sessao e aguardando liberacao gerencial.';
