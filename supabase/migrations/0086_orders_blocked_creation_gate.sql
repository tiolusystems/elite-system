-- Every operational order must enter the approval queue before document emission.

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'blocked',
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
  v_seller_id bigint;
  v_link_id bigint;
  v_order_id bigint;
  v_limit numeric;
begin
  if p_status <> 'blocked' then raise exception 'order must start blocked'; end if;
  v_actor := public.current_actor_id();
  v_seller_id := public.current_commercial_person_id();
  if v_seller_id is null then
    if not public.current_user_is_admin() then raise exception 'commercial identity not linked to current user'; end if;
    if p_vendedor_id is null then raise exception 'responsible seller is required'; end if;
    perform public.require_current_user_permission('pedidos.create.any');
    v_order_id := public.create_com_pedido_operacional_impl_0037(
      p_cliente_id, p_produto_embalagem_id, p_quantidade, p_valor_unitario,
      p_propriedade_id, p_tipo_pedido, 'blocked', p_data_pedido,
      p_vendedor_id, p_percentual_comissao, p_observacao
    );
    select limits.limite_disponivel into v_limit
      from public.cad_limites_credito_cliente limits
     where limits.cliente_id = p_cliente_id
     order by limits.updated_at desc, limits.id desc limit 1;
    insert into public.com_pedido_credito_decisoes(
      pedido_id, decisao, status_anterior, status_resultante, motivo,
      limite_disponivel_snapshot, observacao, created_by
    ) values (
      v_order_id, 'pendente_aprovacao', 'blocked', 'blocked',
      'Aguardando liberacao gerencial', v_limit,
      'Pedido operacional encaminhado automaticamente para aprovacao.', v_actor
    );
    return v_order_id;
  end if;

  if p_tipo_pedido <> 'venda' then raise exception 'seller workspace accepts sale orders only'; end if;
  if p_vendedor_id is not null and p_vendedor_id <> v_seller_id then raise exception 'seller identity is derived from current session'; end if;
  perform public.require_current_user_permission('pedidos.create.own');
  select relation.id into v_link_id
    from public.cad_cliente_vendedores relation
    join public.cad_cliente_vinculo_papeis role_catalog on role_catalog.id = relation.papel_vinculo_id
   where relation.cliente_id = p_cliente_id
     and relation.pessoa_id = v_seller_id
     and relation.status = 'active'
     and role_catalog.concede_visibilidade = true
     and (relation.propriedade_id is null or relation.propriedade_id is not distinct from p_propriedade_id)
     and (relation.vigencia_inicio is null or relation.vigencia_inicio <= p_data_pedido)
     and (relation.vigencia_fim is null or relation.vigencia_fim >= p_data_pedido)
   order by (relation.propriedade_id is not null) desc, relation.id
   limit 1;
  if v_link_id is null then raise exception 'client is outside seller portfolio'; end if;
  return public.create_com_pedido_vendedor_core_0079(
    v_link_id, p_produto_embalagem_id, p_quantidade,
    p_valor_unitario, p_data_pedido, p_observacao
  );
end;
$$;

revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text)
  from public, anon;
grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text)
  to authenticated;

comment on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) is
  'Legacy governed entrypoint. Every order starts blocked and enters superior approval before printing or PDF emission.';
