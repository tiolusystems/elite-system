-- Expedição owns the allocation of order quantities to romaneios. A quantity
-- already present in an active draft, separation or confirmation is committed
-- and cannot be offered to another romaneio.

do $$
declare
  v_overcommitted text;
begin
  select string_agg(
           format(
             'pedido_item_id=%s pedido=%s comprometido=%s',
             item.id,
             item.quantidade,
             active_quantities.quantidade_comprometida
           ),
           '; '
           order by item.id
         )
    into v_overcommitted
    from public.com_pedido_itens item
    join (
      select romaneio_item.pedido_item_id,
             sum(romaneio_item.quantidade_romaneada) as quantidade_comprometida
        from public.exp_romaneio_itens romaneio_item
        join public.exp_romaneios romaneio
          on romaneio.id = romaneio_item.romaneio_id
       where romaneio.status in ('draft', 'separacao', 'confirmado')
         and romaneio_item.status in ('draft', 'reservado', 'confirmado')
       group by romaneio_item.pedido_item_id
    ) active_quantities
      on active_quantities.pedido_item_id = item.id
   where active_quantities.quantidade_comprometida > item.quantidade;

  if v_overcommitted is not null then
    raise exception 'active romaneio quantities exceed order items: %', v_overcommitted;
  end if;
end;
$$;

create or replace view public.exp_pedido_item_romaneio_saldos
with (security_invoker = true)
as
with quantities as (
  select
    romaneio_item.pedido_item_id,
    coalesce(sum(romaneio_item.quantidade_romaneada) filter (
      where romaneio.status = 'confirmado'
        and romaneio_item.status = 'confirmado'
    ), 0) as quantidade_confirmada,
    coalesce(sum(romaneio_item.quantidade_romaneada) filter (
      where romaneio.status in ('draft', 'separacao')
        and romaneio_item.status in ('draft', 'reservado')
    ), 0) as quantidade_em_separacao,
    coalesce(sum(romaneio_item.quantidade_romaneada) filter (
      where romaneio.status in ('draft', 'separacao', 'confirmado')
        and romaneio_item.status in ('draft', 'reservado', 'confirmado')
    ), 0) as quantidade_comprometida
  from public.exp_romaneio_itens romaneio_item
  join public.exp_romaneios romaneio
    on romaneio.id = romaneio_item.romaneio_id
  group by romaneio_item.pedido_item_id
)
select
  item.id as pedido_item_id,
  item.pedido_id,
  item.produto_embalagem_id,
  item.quantidade as quantidade_pedido,
  coalesce(quantities.quantidade_confirmada, 0) as quantidade_confirmada,
  coalesce(quantities.quantidade_em_separacao, 0) as quantidade_em_separacao,
  greatest(item.quantidade - coalesce(quantities.quantidade_confirmada, 0), 0) as quantidade_pendente,
  coalesce(quantities.quantidade_comprometida, 0) as quantidade_comprometida,
  greatest(item.quantidade - coalesce(quantities.quantidade_comprometida, 0), 0) as quantidade_disponivel_romaneio,
  greatest(coalesce(quantities.quantidade_comprometida, 0) - item.quantidade, 0) as quantidade_excedente
from public.com_pedido_itens item
left join quantities on quantities.pedido_item_id = item.id
where item.status = 'active';

revoke all on table public.exp_pedido_item_romaneio_saldos from public, anon;
grant select on table public.exp_pedido_item_romaneio_saldos to authenticated;

comment on view public.exp_pedido_item_romaneio_saldos is
  'Separates pending fulfilment from quantity still free for a new romaneio. Draft, separation and confirmed items all consume allocation capacity until cancelled or reversed.';

create or replace function public.enforce_exp_romaneio_item_quantity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_quantity numeric;
  v_other_committed numeric;
  v_romaneio_status text;
  v_current_item_id bigint;
begin
  if new.status not in ('draft', 'reservado', 'confirmado') then
    return new;
  end if;

  select romaneio.status
    into v_romaneio_status
    from public.exp_romaneios romaneio
   where romaneio.id = new.romaneio_id;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio_status not in ('draft', 'separacao', 'confirmado') then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_current_item_id := old.id;
  end if;

  select item.quantidade
    into v_order_quantity
    from public.com_pedido_itens item
   where item.id = new.pedido_item_id
     and item.pedido_id = new.pedido_id
   for update;

  if not found then
    raise exception 'pedido item not found';
  end if;

  select coalesce(sum(romaneio_item.quantidade_romaneada), 0)
    into v_other_committed
    from public.exp_romaneio_itens romaneio_item
    join public.exp_romaneios romaneio
      on romaneio.id = romaneio_item.romaneio_id
   where romaneio_item.pedido_item_id = new.pedido_item_id
     and romaneio.status in ('draft', 'separacao', 'confirmado')
     and romaneio_item.status in ('draft', 'reservado', 'confirmado')
     and (v_current_item_id is null or romaneio_item.id <> v_current_item_id);

  if v_other_committed + new.quantidade_romaneada > v_order_quantity then
    raise exception 'romaneio exceeds pending order quantity'
      using errcode = '23514',
            detail = format(
              'pedido_item_id=%s pedido=%s comprometido=%s solicitado=%s',
              new.pedido_item_id,
              v_order_quantity,
              v_other_committed,
              new.quantidade_romaneada
            );
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_exp_romaneio_item_quantity() from public, anon, authenticated;

drop trigger if exists trg_exp_romaneio_item_quantity on public.exp_romaneio_itens;
create trigger trg_exp_romaneio_item_quantity
before insert or update of romaneio_id, pedido_id, pedido_item_id, quantidade_romaneada, status
on public.exp_romaneio_itens
for each row execute function public.enforce_exp_romaneio_item_quantity();

create or replace function public.create_exp_romaneio(
  p_pedido_id bigint,
  p_pedido_item_id bigint,
  p_quantidade_romaneada numeric,
  p_lote_pa_ref text default null,
  p_tipo_separacao text default 'parcial',
  p_status text default 'draft',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_permission_context jsonb;
  v_actor uuid;
  v_codigo_romaneio text;
  v_romaneio_id bigint;
  v_romaneio_item_id bigint;
  v_pedido_status text;
  v_tipo_pedido text;
  v_produto_embalagem_id bigint;
  v_quantidade_disponivel numeric;
  v_quantidade_disponivel_depois numeric;
  v_item_status text;
begin
  v_permission_context := public.begin_audited_rpc(
    'romaneios.create',
    'expedicao',
    'exp_romaneios',
    'movement_event',
    jsonb_build_object('event', 'romaneio_create', 'source', 'create_exp_romaneio')
  );

  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_pedido_item_id is null or p_pedido_item_id <= 0 then
    raise exception 'pedido_item_id is required';
  end if;
  if p_quantidade_romaneada is null or p_quantidade_romaneada <= 0 then
    raise exception 'quantidade_romaneada must be greater than zero';
  end if;
  if p_tipo_separacao not in ('total', 'parcial') then
    raise exception 'invalid tipo_separacao';
  end if;
  if p_status <> 'draft' then
    raise exception 'romaneio must start as draft';
  end if;
  if nullif(trim(p_lote_pa_ref), '') is not null then
    raise exception 'PA lot must be reserved after romaneio creation';
  end if;

  select pedido.status, pedido.tipo_pedido
    into v_pedido_status, v_tipo_pedido
    from public.com_pedidos pedido
   where pedido.id = p_pedido_id
   for update;

  if v_pedido_status is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido_status <> 'open' then
    raise exception 'pedido status does not allow romaneio';
  end if;
  if v_tipo_pedido not in ('venda', 'troca') then
    raise exception 'pedido type does not allow romaneio';
  end if;

  select item.produto_embalagem_id, item.status
    into v_produto_embalagem_id, v_item_status
    from public.com_pedido_itens item
   where item.id = p_pedido_item_id
     and item.pedido_id = p_pedido_id
   for update;

  if v_produto_embalagem_id is null then
    raise exception 'pedido item not found';
  end if;
  if v_item_status <> 'active' then
    raise exception 'pedido item status does not allow romaneio';
  end if;

  select saldo.quantidade_disponivel_romaneio
    into v_quantidade_disponivel
    from public.exp_pedido_item_romaneio_saldos saldo
   where saldo.pedido_item_id = p_pedido_item_id;

  if p_quantidade_romaneada > coalesce(v_quantidade_disponivel, 0) then
    raise exception 'romaneio exceeds pending order quantity';
  end if;
  if p_tipo_separacao = 'total'
     and p_quantidade_romaneada <> coalesce(v_quantidade_disponivel, 0) then
    raise exception 'total romaneio must match pending quantity';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_romaneio := concat(
    'ROM-',
    to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'),
    '-',
    upper(substr(md5(random()::text), 1, 4))
  );

  insert into public.exp_romaneios(
    codigo_romaneio,
    pedido_id,
    tipo_separacao,
    status,
    data_romaneio,
    observacao,
    created_by,
    updated_by
  ) values (
    v_codigo_romaneio,
    p_pedido_id,
    p_tipo_separacao,
    p_status,
    current_date,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  ) returning id into v_romaneio_id;

  insert into public.exp_romaneio_itens(
    romaneio_id,
    pedido_id,
    pedido_item_id,
    produto_embalagem_id,
    lote_pa_ref,
    quantidade_romaneada,
    quantidade_reservada,
    status,
    created_by,
    updated_by
  ) values (
    v_romaneio_id,
    p_pedido_id,
    p_pedido_item_id,
    v_produto_embalagem_id,
    null,
    p_quantidade_romaneada,
    0,
    'draft',
    v_actor,
    v_actor
  ) returning id into v_romaneio_item_id;

  select saldo.quantidade_disponivel_romaneio
    into v_quantidade_disponivel_depois
    from public.exp_pedido_item_romaneio_saldos saldo
   where saldo.pedido_item_id = p_pedido_item_id;

  perform public.log_audited_rpc_change(
    'expedicao',
    'exp_romaneios',
    v_romaneio_id::text,
    'expedicao.romaneio_created',
    'romaneios.create',
    v_permission_context,
    null,
    jsonb_build_object(
      'codigo_romaneio', v_codigo_romaneio,
      'pedido_id', p_pedido_id,
      'pedido_item_id', p_pedido_item_id,
      'romaneio_item_id', v_romaneio_item_id,
      'tipo_separacao', p_tipo_separacao,
      'status', p_status,
      'quantidade_romaneada', p_quantidade_romaneada,
      'quantidade_disponivel_antes', v_quantidade_disponivel,
      'quantidade_disponivel_depois', v_quantidade_disponivel_depois
    ),
    jsonb_build_object(
      'source', 'create_exp_romaneio',
      'correlation_id', format('romaneio:%s:create', v_romaneio_id)
    )
  );

  return v_romaneio_id;
end;
$$;

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
  v_permission_context jsonb;
  v_actor uuid;
  v_romaneio record;
  v_pedido record;
  v_item record;
  v_quantidade_disponivel numeric;
  v_quantidade_disponivel_depois numeric;
  v_romaneio_item_id bigint;
begin
  v_permission_context := public.begin_audited_rpc(
    'romaneios.create',
    'expedicao',
    'exp_romaneio_itens',
    'movement_event',
    jsonb_build_object('event', 'romaneio_item_add', 'source', 'add_exp_romaneio_item')
  );

  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if p_pedido_item_id is null or p_pedido_item_id <= 0 then
    raise exception 'pedido_item_id is required';
  end if;
  if p_quantidade_romaneada is null or p_quantidade_romaneada <= 0 then
    raise exception 'quantidade_romaneada must be greater than zero';
  end if;

  select romaneio.*
    into v_romaneio
    from public.exp_romaneios romaneio
   where romaneio.id = p_romaneio_id
   for update;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio.status not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow adding items';
  end if;

  select pedido.id, pedido.status, pedido.tipo_pedido
    into v_pedido
    from public.com_pedidos pedido
   where pedido.id = v_romaneio.pedido_id
   for update;

  if not found or v_pedido.status <> 'open' then
    raise exception 'pedido status does not allow romaneio';
  end if;
  if v_pedido.tipo_pedido not in ('venda', 'troca') then
    raise exception 'pedido type does not allow romaneio';
  end if;

  select item.id, item.pedido_id, item.produto_embalagem_id, item.status
    into v_item
    from public.com_pedido_itens item
   where item.id = p_pedido_item_id
     and item.pedido_id = v_romaneio.pedido_id
   for update;

  if not found then
    raise exception 'pedido item not found';
  end if;
  if v_item.status <> 'active' then
    raise exception 'pedido item status does not allow romaneio';
  end if;
  if exists (
    select 1
      from public.exp_romaneio_itens romaneio_item
     where romaneio_item.romaneio_id = p_romaneio_id
       and romaneio_item.pedido_item_id = p_pedido_item_id
       and romaneio_item.status in ('draft', 'reservado', 'confirmado')
  ) then
    raise exception 'pedido item already exists in romaneio';
  end if;

  select saldo.quantidade_disponivel_romaneio
    into v_quantidade_disponivel
    from public.exp_pedido_item_romaneio_saldos saldo
   where saldo.pedido_item_id = p_pedido_item_id;

  if p_quantidade_romaneada > coalesce(v_quantidade_disponivel, 0) then
    raise exception 'romaneio exceeds pending order quantity';
  end if;
  if v_romaneio.tipo_separacao = 'total'
     and p_quantidade_romaneada <> coalesce(v_quantidade_disponivel, 0) then
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
  ) values (
    p_romaneio_id,
    v_romaneio.pedido_id,
    p_pedido_item_id,
    v_item.produto_embalagem_id,
    p_quantidade_romaneada,
    0,
    'draft',
    v_actor,
    v_actor
  ) returning id into v_romaneio_item_id;

  update public.exp_romaneios
     set observacao = coalesce(nullif(trim(p_observacao), ''), observacao),
         updated_by = v_actor
   where id = p_romaneio_id;

  select saldo.quantidade_disponivel_romaneio
    into v_quantidade_disponivel_depois
    from public.exp_pedido_item_romaneio_saldos saldo
   where saldo.pedido_item_id = p_pedido_item_id;

  perform public.log_audited_rpc_change(
    'expedicao',
    'exp_romaneio_itens',
    v_romaneio_item_id::text,
    'expedicao.romaneio_item_added',
    'romaneios.create',
    v_permission_context,
    null,
    jsonb_build_object(
      'romaneio_id', p_romaneio_id,
      'pedido_id', v_romaneio.pedido_id,
      'pedido_item_id', p_pedido_item_id,
      'quantidade_romaneada', p_quantidade_romaneada,
      'quantidade_disponivel_antes', v_quantidade_disponivel,
      'quantidade_disponivel_depois', v_quantidade_disponivel_depois
    ),
    jsonb_build_object(
      'source', 'add_exp_romaneio_item',
      'correlation_id', format('romaneio:%s:item:%s:add', p_romaneio_id, v_romaneio_item_id)
    )
  );

  return v_romaneio_item_id;
end;
$$;

-- The text-only separation RPC predates relational PA reservations. It is not
-- part of the web flow and remains unavailable to API roles; use
-- registrar_est_reserva_pa instead.
revoke all on function public.registrar_exp_romaneio_separacao(bigint, text, text)
  from public, anon, authenticated;
comment on function public.registrar_exp_romaneio_separacao(bigint, text, text) is
  'Deprecated and unavailable to API roles. Use registrar_est_reserva_pa for relational, lot-based reservation.';

revoke all on function public.create_exp_romaneio(bigint, bigint, numeric, text, text, text, text)
  from public, anon;
revoke all on function public.add_exp_romaneio_item(bigint, bigint, numeric, text)
  from public, anon;
revoke all on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text)
  from public, anon;
revoke all on function public.confirmar_exp_romaneio(bigint, text)
  from public, anon;
revoke all on function public.cancelar_exp_romaneio(bigint, text)
  from public, anon;
revoke all on function public.estornar_exp_romaneio(bigint, text)
  from public, anon;
revoke all on function public.registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text)
  from public, anon;
revoke all on function public.registrar_exp_romaneio_logistica_remocao(bigint, text)
  from public, anon;

grant execute on function public.create_exp_romaneio(bigint, bigint, numeric, text, text, text, text)
  to authenticated;
grant execute on function public.add_exp_romaneio_item(bigint, bigint, numeric, text)
  to authenticated;
grant execute on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text)
  to authenticated;
grant execute on function public.confirmar_exp_romaneio(bigint, text)
  to authenticated;
grant execute on function public.cancelar_exp_romaneio(bigint, text)
  to authenticated;
grant execute on function public.estornar_exp_romaneio(bigint, text)
  to authenticated;
grant execute on function public.registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text)
  to authenticated;
grant execute on function public.registrar_exp_romaneio_logistica_remocao(bigint, text)
  to authenticated;

comment on function public.create_exp_romaneio(bigint, bigint, numeric, text, text, text, text) is
  'Creates an audited romaneio only within the order item quantity still free after every active allocation.';
comment on function public.add_exp_romaneio_item(bigint, bigint, numeric, text) is
  'Adds an audited item only within the order item quantity still free after every active allocation.';
