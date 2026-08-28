-- Keep the authenticated order-gate RPCs as the only application entrypoints.
-- The 0135 rename retained the old helper ACL, so this migration closes that
-- internal surface and makes the wrapper authorization visible to the gate.

create or replace function public.registrar_com_pedido_decisao_desconto_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_confirmacao_comercial_id bigint,
  p_comparacao_sha256 text,
  p_decisao text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decisao_id bigint;
begin
  perform public.require_current_user_permission('pedidos.commercial_discount.review');
  v_decisao_id := public.registrar_com_pedido_decisao_desconto_idempotente_impl_0135(
    p_idempotency_key,
    p_pedido_id,
    p_confirmacao_comercial_id,
    p_comparacao_sha256,
    p_decisao,
    p_justificativa
  );
  perform public.avaliar_com_pedido_efetividade(p_pedido_id);
  return v_decisao_id;
end;
$$;

create or replace function public.decidir_com_pedido_assinatura_idempotente(
  p_idempotency_key uuid,
  p_evidencia_id bigint,
  p_decisao text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decisao_id bigint;
  v_pedido_id bigint;
begin
  -- Permission is checked before the evidence or order is read. The helper
  -- performs the governed scope, version, idempotency and audit checks.
  perform public.require_current_user_permission('pedidos.buyer_signature.review');
  v_decisao_id := public.decidir_com_pedido_assinatura_idempotente_impl_0135(
    p_idempotency_key,
    p_evidencia_id,
    p_decisao,
    p_justificativa
  );
  select decisao.pedido_id
    into v_pedido_id
    from public.com_pedido_assinatura_decisoes decisao
   where decisao.id = v_decisao_id;
  if v_pedido_id is null then
    raise exception 'decisao de assinatura sem pedido';
  end if;
  perform public.avaliar_com_pedido_efetividade(v_pedido_id);
  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_desconto_idempotente_impl_0135(uuid,bigint,bigint,text,text,text)
  from public, anon, authenticated;
revoke all on function public.decidir_com_pedido_assinatura_idempotente_impl_0135(uuid,bigint,text,text)
  from public, anon, authenticated;

revoke all on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text)
  from public, anon;
revoke all on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text)
  from public, anon;
grant execute on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text)
  to authenticated;
grant execute on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text)
  to authenticated;

comment on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text) is
  'ORD-01: authenticated entrypoint with permission checked before the private audited implementation.';
comment on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text) is
  'ORD-01: authenticated entrypoint with permission checked before any evidence read; private audited implementation follows.';
