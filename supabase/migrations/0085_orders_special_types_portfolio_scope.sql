-- Keep special commercial orders inside the same seller/manager portfolio contract.

create or replace function public.create_com_pedido_vendedor_especial(
  p_cliente_vendedor_vinculo_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_tipo_pedido text,
  p_data_pedido date default current_date,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_seller_id bigint;
  v_link public.cad_cliente_vendedores%rowtype;
  v_order_id bigint;
  v_limit numeric;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.create.own');
  if p_tipo_pedido not in ('bonificacao', 'mostruario') then raise exception 'invalid special order type'; end if;
  if p_tipo_pedido = 'bonificacao' and char_length(trim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'bonus justification must have at least 10 characters';
  end if;
  if p_produto_embalagem_id is null or p_quantidade is null or p_quantidade <= 0 or p_data_pedido is null then
    raise exception 'invalid special order item';
  end if;

  v_actor := public.current_actor_id();
  v_seller_id := public.current_commercial_person_id();
  if v_seller_id is null then raise exception 'commercial identity not linked to current user'; end if;
  select * into v_link from public.cad_cliente_vendedores
   where id = p_cliente_vendedor_vinculo_id for share;
  if not found or v_link.pessoa_id <> v_seller_id or v_link.status <> 'active' then
    raise exception 'client is outside seller portfolio';
  end if;
  if (v_link.vigencia_inicio is not null and v_link.vigencia_inicio > p_data_pedido)
     or (v_link.vigencia_fim is not null and v_link.vigencia_fim < p_data_pedido) then
    raise exception 'client seller link is outside effective period';
  end if;

  v_context := public.begin_audited_rpc(
    'pedidos.create.own', 'pedidos', 'com_pedidos', 'own_any',
    jsonb_build_object('event', 'seller_special_order_pending_approval', 'tipo_pedido', p_tipo_pedido)
  );
  v_order_id := public.create_com_pedido_operacional_impl_0037(
    v_link.cliente_id, p_produto_embalagem_id, p_quantidade, 0,
    v_link.propriedade_id, p_tipo_pedido, 'blocked', p_data_pedido,
    v_seller_id, null, p_justificativa
  );
  update public.com_pedidos set cliente_vendedor_vinculo_id = v_link.id where id = v_order_id;

  select limits.limite_disponivel into v_limit from public.cad_limites_credito_cliente limits
   where limits.cliente_id = v_link.cliente_id order by limits.updated_at desc, limits.id desc limit 1;
  insert into public.com_pedido_credito_decisoes(
    pedido_id, decisao, status_anterior, status_resultante, motivo,
    limite_disponivel_snapshot, observacao, created_by
  ) values (
    v_order_id, 'pendente_aprovacao', 'blocked', 'blocked',
    'Aguardando liberacao gerencial', v_limit,
    concat('Pedido ', p_tipo_pedido, ' criado pelo vendedor e encaminhado para aprovacao.'), v_actor
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_order_id::text,
    'pedidos.pedido_especial_enviado_aprovacao', 'pedidos.create.own', v_context,
    null, public.com_pedido_audit_snapshot(v_order_id),
    jsonb_build_object('source', 'create_com_pedido_vendedor_especial', 'cliente_vendedor_vinculo_id', v_link.id, 'tipo_pedido', p_tipo_pedido)
  );
  return v_order_id;
end;
$$;

revoke all on function public.create_com_pedido_vendedor_especial(bigint, bigint, numeric, text, date, text) from public, anon;
grant execute on function public.create_com_pedido_vendedor_especial(bigint, bigint, numeric, text, date, text) to authenticated;

alter function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text)
  rename to create_com_pedido_troca_impl_0085;
revoke all on function public.create_com_pedido_troca_impl_0085(bigint, bigint, bigint, numeric, text, date, text, text)
  from public, anon, authenticated;

create function public.create_com_pedido_troca(
  p_pedido_origem_id bigint,
  p_pedido_item_origem_id bigint,
  p_produto_embalagem_id bigint default null,
  p_quantidade numeric default null,
  p_status text default 'blocked',
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
  v_actor_seller bigint;
  v_origin_seller bigint;
begin
  perform public.require_current_user_permission('pedidos.exchange.create');
  if p_status <> 'blocked' then raise exception 'exchange order must start blocked'; end if;
  v_actor_seller := public.current_commercial_person_id();
  select pedido.vendedor_gerador_id into v_origin_seller
    from public.com_pedidos pedido where pedido.id = p_pedido_origem_id for share;
  if v_origin_seller is null then raise exception 'pedido origem not found or has no seller'; end if;
  if not public.current_user_is_admin()
     and v_actor_seller is distinct from v_origin_seller
     and not public.current_user_manages_seller(v_origin_seller) then
    raise exception 'order is outside commercial scope';
  end if;
  return public.create_com_pedido_troca_impl_0085(
    p_pedido_origem_id, p_pedido_item_origem_id, p_produto_embalagem_id,
    p_quantidade, 'blocked', p_data_pedido, p_motivo_troca, p_observacao
  );
end;
$$;

revoke all on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) from public, anon;
grant execute on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) to authenticated;
