-- A repeated exchange request must not create a second blocked order.

create table public.com_pedido_troca_requisicoes (
  idempotency_key uuid primary key,
  pedido_troca_id bigint not null unique references public.com_pedidos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.com_pedido_troca_requisicoes is
  'Append-only request keys. Identical retries return the original blocked exchange order.';

create or replace function public.prevent_exchange_order_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'exchange order request keys are append-only';
end;
$$;
revoke all on function public.prevent_exchange_order_request_changes() from public, anon, authenticated;

create trigger trg_com_pedido_troca_requisicoes_no_update
before update or delete on public.com_pedido_troca_requisicoes
for each row execute function public.prevent_exchange_order_request_changes();
create trigger trg_com_pedido_troca_requisicoes_no_truncate
before truncate on public.com_pedido_troca_requisicoes
for each statement execute function public.prevent_exchange_order_request_changes();

alter table public.com_pedido_troca_requisicoes enable row level security;
revoke all on table public.com_pedido_troca_requisicoes from public, anon, authenticated;

create or replace function public.create_com_pedido_troca_idempotente(
  p_idempotency_key uuid,
  p_pedido_origem_id bigint,
  p_pedido_item_origem_id bigint,
  p_produto_embalagem_id bigint default null,
  p_quantidade numeric default null,
  p_status text default 'blocked',
  p_data_pedido date default current_date,
  p_motivo_troca text default 'qualidade',
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_troca_requisicoes%rowtype;
  v_pedido_troca_id bigint;
begin
  perform public.require_current_user_permission('pedidos.exchange.create');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_origem_id', p_pedido_origem_id,
    'pedido_item_origem_id', p_pedido_item_origem_id,
    'produto_embalagem_id', p_produto_embalagem_id,
    'quantidade', p_quantidade,
    'status', p_status,
    'data_pedido', p_data_pedido,
    'motivo_troca', p_motivo_troca,
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_troca_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different exchange order request';
    end if;
    return v_existing.pedido_troca_id;
  end if;

  v_pedido_troca_id := public.create_com_pedido_troca(
    p_pedido_origem_id,
    p_pedido_item_origem_id,
    p_produto_embalagem_id,
    p_quantidade,
    p_status,
    p_data_pedido,
    p_motivo_troca,
    p_observacao
  );
  insert into public.com_pedido_troca_requisicoes(
    idempotency_key, pedido_troca_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_pedido_troca_id, v_actor, v_payload_hash);
  return v_pedido_troca_id;
end;
$$;

revoke all on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text)
  from public, anon, authenticated;
revoke all on function public.create_com_pedido_troca_idempotente(uuid, bigint, bigint, bigint, numeric, text, date, text, text)
  from public, anon;
grant execute on function public.create_com_pedido_troca_idempotente(uuid, bigint, bigint, bigint, numeric, text, date, text, text)
  to authenticated;

comment on function public.create_com_pedido_troca_idempotente(uuid, bigint, bigint, bigint, numeric, text, date, text, text) is
  'Only public exchange creation entrypoint. One request key creates at most one blocked exchange order.';
