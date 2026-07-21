-- Keep the legacy frontend safe while it is being replaced by the seller workspace.

create or replace function public.create_com_pedido_vendedor_core_0079(
  p_cliente_vendedor_vinculo_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_data_pedido date,
  p_observacao text
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
    jsonb_build_object('event', 'seller_order_pending_approval')
  );
  v_order_id := public.create_com_pedido_operacional_impl_0037(
    v_link.cliente_id, p_produto_embalagem_id, p_quantidade, p_valor_unitario,
    v_link.propriedade_id, 'venda', 'blocked', p_data_pedido,
    v_seller_id, null, p_observacao
  );
  update public.com_pedidos set cliente_vendedor_vinculo_id = v_link.id where id = v_order_id;

  select limits.limite_disponivel into v_limit
    from public.cad_limites_credito_cliente limits
   where limits.cliente_id = v_link.cliente_id
   order by limits.updated_at desc, limits.id desc limit 1;
  insert into public.com_pedido_credito_decisoes(
    pedido_id, decisao, status_anterior, status_resultante, motivo,
    limite_disponivel_snapshot, observacao, created_by
  ) values (
    v_order_id, 'pendente_aprovacao', 'blocked', 'blocked',
    'Aguardando liberacao gerencial', v_limit,
    'Pedido criado pelo vendedor e encaminhado automaticamente para aprovacao.', v_actor
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_order_id::text,
    'pedidos.pedido_enviado_aprovacao', 'pedidos.create.own', v_context,
    null, public.com_pedido_audit_snapshot(v_order_id),
    jsonb_build_object('source', 'create_com_pedido_vendedor_core_0079', 'cliente_vendedor_vinculo_id', v_link.id)
  );
  return v_order_id;
end;
$$;

revoke all on function public.create_com_pedido_vendedor_core_0079(bigint, bigint, numeric, numeric, date, text)
  from public, anon, authenticated;

create or replace function public.create_com_pedido_vendedor(
  p_cliente_vendedor_vinculo_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_data_pedido date default current_date,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.create.own');
  return public.create_com_pedido_vendedor_core_0079(
    p_cliente_vendedor_vinculo_id, p_produto_embalagem_id,
    p_quantidade, p_valor_unitario, p_data_pedido, p_observacao
  );
end;
$$;

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
  v_seller_id bigint;
  v_link_id bigint;
begin
  v_seller_id := public.current_commercial_person_id();
  if v_seller_id is null then
    if not public.current_user_is_admin() then raise exception 'commercial identity not linked to current user'; end if;
    perform public.require_current_user_permission('pedidos.create.any');
    return public.create_com_pedido_operacional_impl_0037(
      p_cliente_id, p_produto_embalagem_id, p_quantidade, p_valor_unitario,
      p_propriedade_id, p_tipo_pedido, p_status, p_data_pedido,
      p_vendedor_id, p_percentual_comissao, p_observacao
    );
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

create or replace function public.registrar_com_pedido_decisao_credito(
  p_pedido_id bigint,
  p_decisao text,
  p_motivo text default null,
  p_limite_disponivel_snapshot numeric default null,
  p_inadimplencia_snapshot numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_seller_id bigint;
begin
  perform public.require_current_user_permission('pedidos.credit.review');
  select pedido.vendedor_gerador_id into v_seller_id from public.com_pedidos pedido where pedido.id = p_pedido_id;
  if v_seller_id is null then raise exception 'pedido not found or has no seller'; end if;
  if not public.current_user_manages_seller(v_seller_id) then raise exception 'order is outside manager team'; end if;
  return public.registrar_com_pedido_decisao_credito_impl_0037(
    p_pedido_id, p_decisao, p_motivo, p_limite_disponivel_snapshot,
    p_inadimplencia_snapshot, p_observacao
  );
end;
$$;

revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public, anon;
revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) from public, anon;
grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) to authenticated;

comment on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) is
  'Compatibilidade segura: vendedor e carteira derivam da sessao e venda sempre aguarda liberacao. Somente admin sem identidade comercial usa o fluxo legado any.';
