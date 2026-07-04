create or replace function public.add_exp_romaneio_item(
  p_romaneio_id bigint,
  p_pedido_item_id bigint,
  p_quantidade_romaneada numeric,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_romaneio record;
  v_pedido record;
  v_item record;
  v_quantidade_comprometida numeric;
  v_quantidade_pendente numeric;
  v_romaneio_item_id bigint;
begin
  perform public.require_current_user_permission('romaneios.create');

  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if p_pedido_item_id is null or p_pedido_item_id <= 0 then
    raise exception 'pedido_item_id is required';
  end if;
  if p_quantidade_romaneada is null or p_quantidade_romaneada <= 0 then
    raise exception 'quantidade_romaneada must be greater than zero';
  end if;

  select *
    into v_romaneio
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio.status not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow adding items';
  end if;

  select id, status, tipo_pedido
    into v_pedido
    from public.com_pedidos
    where id = v_romaneio.pedido_id
    for update;

  if not found then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status <> 'open' then
    raise exception 'pedido status does not allow romaneio';
  end if;
  if v_pedido.tipo_pedido not in ('venda', 'bonificacao') then
    raise exception 'pedido type does not allow romaneio';
  end if;

  select id, pedido_id, produto_embalagem_id, quantidade, status
    into v_item
    from public.com_pedido_itens
    where id = p_pedido_item_id
      and pedido_id = v_romaneio.pedido_id
    for update;

  if not found then
    raise exception 'pedido item not found';
  end if;
  if v_item.status <> 'active' then
    raise exception 'pedido item status does not allow romaneio';
  end if;
  if exists (
    select 1
      from public.exp_romaneio_itens
      where romaneio_id = p_romaneio_id
        and pedido_item_id = p_pedido_item_id
        and status in ('draft', 'reservado', 'confirmado')
  ) then
    raise exception 'pedido item already exists in romaneio';
  end if;

  select coalesce(sum(rom_item.quantidade_romaneada), 0)
    into v_quantidade_comprometida
    from public.exp_romaneio_itens rom_item
    join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
    where rom_item.pedido_item_id = p_pedido_item_id
      and rom.status in ('draft', 'separacao', 'confirmado')
      and rom_item.status in ('draft', 'reservado', 'confirmado');

  v_quantidade_pendente := v_item.quantidade - v_quantidade_comprometida;

  if p_quantidade_romaneada > v_quantidade_pendente then
    raise exception 'romaneio exceeds pending order quantity';
  end if;
  if v_romaneio.tipo_separacao = 'total' and p_quantidade_romaneada <> v_quantidade_pendente then
    raise exception 'total romaneio item must match pending quantity';
  end if;

  v_actor := public.current_actor_id();

  insert into public.exp_romaneio_itens(
    romaneio_id,
    pedido_id,
    pedido_item_id,
    produto_embalagem_id,
    quantidade_romaneada,
    quantidade_reservada,
    status,
    created_by,
    updated_by
  )
  values (
    p_romaneio_id,
    v_romaneio.pedido_id,
    p_pedido_item_id,
    v_item.produto_embalagem_id,
    p_quantidade_romaneada,
    0,
    'draft',
    v_actor,
    v_actor
  )
  returning id into v_romaneio_item_id;

  update public.exp_romaneios
     set observacao = coalesce(nullif(trim(p_observacao), ''), observacao),
         updated_by = v_actor
   where id = p_romaneio_id;

  perform public.log_action(
    'expedicao.romaneio_item_added',
    'exp_romaneio_itens',
    v_romaneio_item_id::text,
    'success',
    null,
    jsonb_build_object(
      'romaneio_id', p_romaneio_id,
      'pedido_id', v_romaneio.pedido_id,
      'pedido_item_id', p_pedido_item_id,
      'quantidade_romaneada', p_quantidade_romaneada,
      'quantidade_pendente_antes', v_quantidade_pendente
    ),
    jsonb_build_object('source', 'add_exp_romaneio_item')
  );

  return v_romaneio_item_id;
end;
$$;

revoke all on function public.add_exp_romaneio_item(bigint, bigint, numeric, text) from public;
grant execute on function public.add_exp_romaneio_item(bigint, bigint, numeric, text) to authenticated;
