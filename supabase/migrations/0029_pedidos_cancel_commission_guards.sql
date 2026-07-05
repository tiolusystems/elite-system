alter table public.pcp_ordens_producao
  add column if not exists pedido_id bigint references public.com_pedidos(id);

create index if not exists idx_pcp_ordens_pedido_status
  on public.pcp_ordens_producao(pedido_id, status)
  where pedido_id is not null;

comment on column public.pcp_ordens_producao.pedido_id is
  'Pedido comercial que originou ou justificou a OP, quando houver producao vinculada a pedido especifico.';

alter table public.com_pedido_comissionados
  drop constraint if exists com_pedido_comissionados_status_check;

alter table public.com_pedido_comissionados
  add constraint com_pedido_comissionados_status_check check (
    status in ('prevista', 'liberada', 'paga', 'estornada', 'bloqueada', 'cancelada')
  );

comment on constraint com_pedido_comissionados_status_check on public.com_pedido_comissionados is
  'bloqueada = temporaria; cancelada = definitiva por cancelamento do pedido antes de comissao paga.';

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
  if p_tipo_pedido not in ('venda', 'bonificacao', 'devolucao') then
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

  if p_tipo_pedido = 'bonificacao' then
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

create or replace function public.cancelar_com_pedido(
  p_pedido_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_before jsonb;
  v_after jsonb;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'pedidos.cancel',
    'pedidos',
    'com_pedidos',
    'status_transition',
    jsonb_build_object('event', 'cancel')
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status in ('cancelled', 'fulfilled') then
    raise exception 'pedido status does not allow cancellation';
  end if;
  if exists (
    select 1
      from public.exp_romaneios romaneio
     where romaneio.pedido_id = p_pedido_id
       and romaneio.status not in ('cancelado', 'estornado')
  ) then
    raise exception 'pedido has active romaneio; cancel romaneio first';
  end if;
  if exists (
    select 1
      from public.fat_notas_fiscais nota
     where nota.pedido_id = p_pedido_id
       and nota.status_atual not in ('cancelada', 'inutilizada')
  ) then
    raise exception 'pedido has active nota fiscal; cancel fiscal document first';
  end if;
  if exists (
    select 1
      from public.com_recebimentos recebimento
     where recebimento.pedido_id = p_pedido_id
       and coalesce(recebimento.status, 'active') = 'active'
  ) then
    raise exception 'pedido has active receipt; reverse receipt first';
  end if;
  if exists (
    select 1
      from public.com_pedido_comissionados comissionado
     where comissionado.pedido_id = p_pedido_id
       and comissionado.status = 'paga'
  ) or exists (
    select 1
      from public.fin_comissao_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'debito_pagamento'
  ) then
    raise exception 'pedido has paid commission; use post-payment reversal flow';
  end if;
  if exists (
    select 1
      from public.pcp_ordens_producao op
     where op.pedido_id = p_pedido_id
       and op.status in ('draft', 'planned', 'in_process')
  ) then
    raise exception 'pedido has active OP; cancel OP first';
  end if;

  perform public.validate_com_pedido_status_transition(v_pedido.status, 'cancelled', 'cancel');

  v_actor := public.current_actor_id();
  v_before := public.com_pedido_audit_snapshot(p_pedido_id);

  update public.com_pedidos
     set status = 'cancelled',
         updated_by = v_actor
   where id = p_pedido_id;

  update public.com_pedido_itens
     set status = 'cancelled',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status = 'active';

  update public.com_pedido_comissionados
     set status = 'cancelada',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status in ('prevista', 'bloqueada');

  v_after := public.com_pedido_audit_snapshot(p_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    p_pedido_id::text,
    'pedidos.pedido_cancelado',
    'pedidos.cancel',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'cancelar_com_pedido',
      'pedido_id', p_pedido_id,
      'motivo', trim(p_motivo),
      'status_anterior', v_pedido.status,
      'status_resultante', 'cancelled'
    )
  );

  return p_pedido_id;
end;
$$;

revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.cancelar_com_pedido(bigint, text) from public;

grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.cancelar_com_pedido(bigint, text) to authenticated;
