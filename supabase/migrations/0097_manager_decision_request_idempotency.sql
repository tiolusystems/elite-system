-- A repeated manager submit must not duplicate a credit decision event.

create table public.com_pedido_decisao_requisicoes (
  idempotency_key uuid primary key,
  decisao_id bigint not null unique references public.com_pedido_credito_decisoes(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.com_pedido_decisao_requisicoes is
  'Append-only manager request keys. Identical retries return the original audited credit decision.';

create or replace function public.prevent_order_decision_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'order decision request keys are append-only';
end;
$$;
revoke all on function public.prevent_order_decision_request_changes() from public, anon, authenticated;

create trigger trg_com_pedido_decisao_requisicoes_no_update
before update or delete on public.com_pedido_decisao_requisicoes
for each row execute function public.prevent_order_decision_request_changes();
create trigger trg_com_pedido_decisao_requisicoes_no_truncate
before truncate on public.com_pedido_decisao_requisicoes
for each statement execute function public.prevent_order_decision_request_changes();

alter table public.com_pedido_decisao_requisicoes enable row level security;
revoke all on table public.com_pedido_decisao_requisicoes from public, anon, authenticated;

create or replace function public.registrar_com_pedido_decisao_gerencial_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_decisao text,
  p_justificativa text
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_decisao_requisicoes%rowtype;
  v_decisao_id bigint;
begin
  perform public.require_current_user_permission('pedidos.credit.review');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'decisao', p_decisao,
    'justificativa', btrim(p_justificativa)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_decisao_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different manager decision request';
    end if;
    return v_existing.decisao_id;
  end if;

  v_decisao_id := public.registrar_com_pedido_decisao_gerencial(
    p_pedido_id, p_decisao, p_justificativa
  );
  insert into public.com_pedido_decisao_requisicoes(
    idempotency_key, decisao_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_decisao_id, v_actor, v_payload_hash);
  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_gerencial(bigint, text, text)
  from public, anon, authenticated;
revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  from public, anon, authenticated;
revoke all on function public.registrar_com_pedido_decisao_gerencial_idempotente(uuid, bigint, text, text)
  from public, anon;
grant execute on function public.registrar_com_pedido_decisao_gerencial_idempotente(uuid, bigint, text, text)
  to authenticated;

comment on function public.registrar_com_pedido_decisao_gerencial_idempotente(uuid, bigint, text, text) is
  'Only public manager decision entrypoint. One request key creates at most one audited decision.';
