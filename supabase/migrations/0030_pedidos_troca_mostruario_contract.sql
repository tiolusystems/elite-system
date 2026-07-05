insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.exchange.create', 'pedidos', 'Criar pedido de troca vinculado ao pedido e item de origem', true, 110)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

alter table public.com_pedidos
  add column if not exists pedido_origem_id bigint references public.com_pedidos(id);

alter table public.com_pedido_itens
  add column if not exists pedido_item_origem_id bigint references public.com_pedido_itens(id);

create index if not exists idx_com_pedidos_origem
  on public.com_pedidos(pedido_origem_id)
  where pedido_origem_id is not null;

create index if not exists idx_com_pedido_itens_origem
  on public.com_pedido_itens(pedido_item_origem_id)
  where pedido_item_origem_id is not null;

comment on column public.com_pedidos.pedido_origem_id is
  'Pedido de origem para eventos comerciais derivados, como troca. Nao substitui NF, romaneio ou estoque.';

comment on column public.com_pedido_itens.pedido_item_origem_id is
  'Item de pedido de origem para eventos comerciais derivados, como troca parcial ou total.';

alter table public.com_pedidos
  drop constraint if exists com_pedidos_tipo_check;

alter table public.com_pedidos
  add constraint com_pedidos_tipo_check check (
    tipo_pedido in ('venda', 'bonificacao', 'devolucao', 'troca', 'mostruario')
  );

alter table public.com_pedido_itens
  drop constraint if exists com_pedido_itens_tipo_check;

alter table public.com_pedido_itens
  add constraint com_pedido_itens_tipo_check check (
    tipo_item in ('venda', 'bonificacao', 'devolucao', 'troca', 'mostruario')
  );

alter table public.com_pedidos
  drop constraint if exists com_pedidos_troca_origem_check;

alter table public.com_pedidos
  add constraint com_pedidos_troca_origem_check check (
    tipo_pedido <> 'troca' or pedido_origem_id is not null
  );

alter table public.com_pedidos
  drop constraint if exists com_pedidos_origem_not_self_check;

alter table public.com_pedidos
  add constraint com_pedidos_origem_not_self_check check (
    pedido_origem_id is null or pedido_origem_id <> id
  );

alter table public.com_pedido_itens
  drop constraint if exists com_pedido_itens_troca_origem_check;

alter table public.com_pedido_itens
  add constraint com_pedido_itens_troca_origem_check check (
    tipo_item <> 'troca' or pedido_item_origem_id is not null
  );

alter table public.com_pedido_itens
  drop constraint if exists com_pedido_itens_origem_not_self_check;

alter table public.com_pedido_itens
  add constraint com_pedido_itens_origem_not_self_check check (
    pedido_item_origem_id is null or pedido_item_origem_id <> id
  );

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_action_key text;
  v_scope text;
  v_permission_context jsonb;
  v_codigo_pedido text;
  v_pedido_id bigint;
  v_item_id bigint;
  v_item_valor_total numeric;
  v_valor_base_comissao numeric;
  v_valor_previsto_comissao numeric;
  v_sequencia integer;
  v_produto_embalagem_status text;
  v_after jsonb;
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'quantidade must be greater than zero';
  end if;
  if p_valor_unitario is null or p_valor_unitario < 0 then
    raise exception 'valor_unitario must be greater than or equal to zero';
  end if;
  if p_tipo_pedido = 'troca' then
    raise exception 'use create_com_pedido_troca for exchange orders';
  end if;
  if p_tipo_pedido not in ('venda', 'bonificacao', 'devolucao', 'mostruario') then
    raise exception 'invalid tipo_pedido';
  end if;
  if p_status not in ('draft', 'open', 'blocked') then
    raise exception 'invalid initial status';
  end if;
  if p_percentual_comissao is not null and p_percentual_comissao < 0 then
    raise exception 'percentual_comissao must be greater than or equal to zero';
  end if;
  if p_data_pedido is null then
    raise exception 'data_pedido is required';
  end if;

  v_actor := public.current_actor_id();
  if p_vendedor_id is not null and exists (
    select 1
      from public.cad_pessoas_comerciais vendedor
     where vendedor.id = p_vendedor_id
       and vendedor.user_profile_id = v_actor
  ) then
    v_scope := 'own';
    v_action_key := 'pedidos.create.own';
  else
    v_scope := 'any';
    v_action_key := 'pedidos.create.any';
  end if;

  v_permission_context := public.begin_audited_rpc(
    v_action_key,
    'pedidos',
    'com_pedidos',
    'own_any',
    jsonb_build_object('scope', v_scope, 'event', 'order_create')
  );

  if not exists (select 1 from public.cad_clientes where id = p_cliente_id and status = 'active') then
    raise exception 'active cliente not found';
  end if;
  if p_propriedade_id is not null and not exists (
    select 1
    from public.cad_cliente_propriedades
    where id = p_propriedade_id
      and cliente_id = p_cliente_id
      and status = 'active'
  ) then
    raise exception 'active propriedade does not belong to cliente';
  end if;
  if p_vendedor_id is not null and not exists (
    select 1
    from public.cad_pessoas_comerciais
    where id = p_vendedor_id
      and status = 'active'
  ) then
    raise exception 'active vendedor not found';
  end if;

  select status
    into v_produto_embalagem_status
    from public.cad_produto_embalagens
    where id = p_produto_embalagem_id;

  if v_produto_embalagem_status is null then
    raise exception 'produto_embalagem not found';
  end if;
  if v_produto_embalagem_status <> 'active' then
    raise exception 'produto_embalagem status does not allow order creation';
  end if;

  v_sequencia := public.next_com_pedido_sequencia(p_cliente_id, p_propriedade_id);

  v_codigo_pedido := concat(
    'PED-',
    case
      when p_propriedade_id is null then concat('C', p_cliente_id::text)
      else concat('P', p_propriedade_id::text)
    end,
    '-',
    lpad(v_sequencia::text, 6, '0')
  );

  if p_tipo_pedido in ('bonificacao', 'mostruario') then
    v_item_valor_total := 0;
  elsif p_tipo_pedido = 'devolucao' then
    v_item_valor_total := -1 * p_quantidade * p_valor_unitario;
  else
    v_item_valor_total := p_quantidade * p_valor_unitario;
  end if;

  insert into public.com_pedidos(
    codigo_pedido,
    cliente_id,
    propriedade_id,
    sequencia_propriedade,
    vendedor_gerador_id,
    tipo_pedido,
    status,
    data_pedido,
    origem_canal,
    valor_total,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_pedido,
    p_cliente_id,
    p_propriedade_id,
    v_sequencia,
    p_vendedor_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    case when p_vendedor_id is null then 'interno' else 'vendedor' end,
    v_item_valor_total,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_pedido_id;

  insert into public.com_pedido_itens(
    pedido_id,
    produto_embalagem_id,
    tipo_item,
    quantidade,
    valor_unitario,
    valor_total,
    created_by,
    updated_by
  )
  values (
    v_pedido_id,
    p_produto_embalagem_id,
    p_tipo_pedido,
    p_quantidade,
    p_valor_unitario,
    v_item_valor_total,
    v_actor,
    v_actor
  )
  returning id into v_item_id;

  if p_vendedor_id is not null and p_percentual_comissao is not null and p_percentual_comissao > 0 and p_tipo_pedido = 'venda' then
    v_valor_base_comissao := v_item_valor_total;
    v_valor_previsto_comissao := v_valor_base_comissao * p_percentual_comissao / 100;

    insert into public.com_pedido_comissionados(
      pedido_id,
      pedido_item_id,
      pessoa_id,
      papel_comissao,
      percentual_comissao,
      valor_base,
      valor_previsto,
      created_by,
      updated_by
    )
    values (
      v_pedido_id,
      v_item_id,
      p_vendedor_id,
      'vendedor',
      p_percentual_comissao,
      v_valor_base_comissao,
      v_valor_previsto_comissao,
      v_actor,
      v_actor
    );
  end if;

  v_after := public.com_pedido_audit_snapshot(v_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    v_pedido_id::text,
    'pedidos.pedido_criado',
    v_action_key,
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_com_pedido_operacional',
      'codigo_pedido', v_codigo_pedido,
      'cliente_id', p_cliente_id,
      'propriedade_id', p_propriedade_id,
      'sequencia_propriedade', v_sequencia,
      'produto_embalagem_id', p_produto_embalagem_id,
      'tipo_pedido', p_tipo_pedido,
      'initial_status', p_status,
      'quantidade', p_quantidade,
      'valor_unitario', p_valor_unitario,
      'valor_total', v_item_valor_total,
      'vendedor_id', p_vendedor_id,
      'percentual_comissao', p_percentual_comissao,
      'scope', v_scope
    )
  );

  return v_pedido_id;
end;
$$;

create or replace function public.create_com_pedido_troca(
  p_pedido_origem_id bigint,
  p_pedido_item_origem_id bigint,
  p_produto_embalagem_id bigint default null,
  p_quantidade numeric default null,
  p_status text default 'open',
  p_data_pedido date default current_date,
  p_motivo_troca text default 'qualidade',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido_origem record;
  v_item_origem record;
  v_produto_embalagem_id bigint;
  v_quantidade numeric;
  v_quantidade_trocada_anterior numeric;
  v_sequencia integer;
  v_codigo_pedido text;
  v_pedido_id bigint;
  v_item_id bigint;
  v_motivo_troca text;
  v_before jsonb;
  v_after jsonb;
begin
  if p_pedido_origem_id is null or p_pedido_origem_id <= 0 then
    raise exception 'pedido_origem_id is required';
  end if;
  if p_pedido_item_origem_id is null or p_pedido_item_origem_id <= 0 then
    raise exception 'pedido_item_origem_id is required';
  end if;
  if p_status not in ('draft', 'open', 'blocked') then
    raise exception 'invalid initial status';
  end if;
  if p_data_pedido is null then
    raise exception 'data_pedido is required';
  end if;

  v_motivo_troca := lower(nullif(trim(p_motivo_troca), ''));
  if v_motivo_troca not in ('qualidade', 'avaria_transporte', 'erro_separacao', 'erro_comercial', 'acordo_comercial', 'outro') then
    raise exception 'invalid motivo_troca';
  end if;
  if v_motivo_troca = 'outro' and nullif(trim(p_observacao), '') is null then
    raise exception 'observacao is required when motivo_troca is outro';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'pedidos.exchange.create',
    'pedidos',
    'com_pedidos',
    'change_type',
    jsonb_build_object('event', 'exchange_create', 'tipo_pedido', 'troca', 'motivo_troca', v_motivo_troca)
  );

  select *
    into v_pedido_origem
    from public.com_pedidos
   where id = p_pedido_origem_id
   for update;

  if v_pedido_origem.id is null then
    raise exception 'pedido origem not found';
  end if;
  if v_pedido_origem.status = 'cancelled' then
    raise exception 'pedido origem cancelled does not allow exchange';
  end if;
  if v_pedido_origem.tipo_pedido not in ('venda', 'bonificacao') then
    raise exception 'pedido origem tipo does not allow exchange';
  end if;

  select *
    into v_item_origem
    from public.com_pedido_itens
   where id = p_pedido_item_origem_id
     and pedido_id = p_pedido_origem_id
   for update;

  if v_item_origem.id is null then
    raise exception 'pedido item origem not found';
  end if;
  if v_item_origem.status <> 'active' then
    raise exception 'pedido item origem status does not allow exchange';
  end if;
  if v_item_origem.tipo_item not in ('venda', 'bonificacao') then
    raise exception 'pedido item origem tipo does not allow exchange';
  end if;

  v_produto_embalagem_id := coalesce(p_produto_embalagem_id, v_item_origem.produto_embalagem_id);
  if v_produto_embalagem_id is null or v_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;

  if not exists (
    select 1
      from public.cad_produto_embalagens item_vendavel
     where item_vendavel.id = v_produto_embalagem_id
       and item_vendavel.status = 'active'
  ) then
    raise exception 'active produto_embalagem not found';
  end if;

  v_quantidade := coalesce(p_quantidade, v_item_origem.quantidade);
  if v_quantidade is null or v_quantidade <= 0 then
    raise exception 'quantidade must be greater than zero';
  end if;

  select coalesce(sum(item.quantidade), 0)
    into v_quantidade_trocada_anterior
    from public.com_pedido_itens item
    join public.com_pedidos pedido on pedido.id = item.pedido_id
   where item.pedido_item_origem_id = p_pedido_item_origem_id
     and item.status = 'active'
     and pedido.tipo_pedido = 'troca'
     and pedido.status <> 'cancelled';

  if v_quantidade_trocada_anterior + v_quantidade > v_item_origem.quantidade then
    raise exception 'exchange quantity exceeds original item quantity';
  end if;

  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'pedido_origem', public.com_pedido_audit_snapshot(p_pedido_origem_id),
    'pedido_item_origem_id', p_pedido_item_origem_id,
    'quantidade_trocada_anterior', v_quantidade_trocada_anterior
  );

  v_sequencia := public.next_com_pedido_sequencia(v_pedido_origem.cliente_id, v_pedido_origem.propriedade_id);

  v_codigo_pedido := concat(
    'PED-',
    case
      when v_pedido_origem.propriedade_id is null then concat('C', v_pedido_origem.cliente_id::text)
      else concat('P', v_pedido_origem.propriedade_id::text)
    end,
    '-',
    lpad(v_sequencia::text, 6, '0')
  );

  insert into public.com_pedidos(
    codigo_pedido,
    cliente_id,
    propriedade_id,
    pedido_origem_id,
    sequencia_propriedade,
    vendedor_gerador_id,
    tipo_pedido,
    status,
    data_pedido,
    origem_canal,
    valor_total,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_pedido,
    v_pedido_origem.cliente_id,
    v_pedido_origem.propriedade_id,
    p_pedido_origem_id,
    v_sequencia,
    v_pedido_origem.vendedor_gerador_id,
    'troca',
    p_status,
    p_data_pedido,
    'interno',
    0,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_pedido_id;

  insert into public.com_pedido_itens(
    pedido_id,
    pedido_item_origem_id,
    produto_embalagem_id,
    tipo_item,
    quantidade,
    valor_unitario,
    valor_total,
    created_by,
    updated_by
  )
  values (
    v_pedido_id,
    p_pedido_item_origem_id,
    v_produto_embalagem_id,
    'troca',
    v_quantidade,
    0,
    0,
    v_actor,
    v_actor
  )
  returning id into v_item_id;

  v_after := public.com_pedido_audit_snapshot(v_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    v_pedido_id::text,
    'pedidos.troca_criada',
    'pedidos.exchange.create',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'create_com_pedido_troca',
      'pedido_id', v_pedido_id,
      'pedido_item_id', v_item_id,
      'pedido_origem_id', p_pedido_origem_id,
      'pedido_item_origem_id', p_pedido_item_origem_id,
      'produto_embalagem_origem_id', v_item_origem.produto_embalagem_id,
      'produto_embalagem_destino_id', v_produto_embalagem_id,
      'quantidade_troca', v_quantidade,
      'motivo_troca', v_motivo_troca,
      'status_resultante', p_status,
      'correlation_id', concat('pedido_troca:', p_pedido_origem_id::text, ':', v_pedido_id::text, ':create')
    )
  );

  return v_pedido_id;
end;
$$;

revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) from public;

grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) to authenticated;
