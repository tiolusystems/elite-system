-- A repeated save request must not create a second draft for the same load.

create table public.exp_romaneio_requisicoes (
  idempotency_key uuid primary key,
  romaneio_id bigint not null unique references public.exp_romaneios(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.exp_romaneio_requisicoes is
  'Append-only request keys. Identical retries return the original romaneio draft.';

create or replace function public.prevent_romaneio_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'romaneio request keys are append-only';
end;
$$;
revoke all on function public.prevent_romaneio_request_changes() from public, anon, authenticated;

create trigger trg_exp_romaneio_requisicoes_no_update
before update or delete on public.exp_romaneio_requisicoes
for each row execute function public.prevent_romaneio_request_changes();
create trigger trg_exp_romaneio_requisicoes_no_truncate
before truncate on public.exp_romaneio_requisicoes
for each statement execute function public.prevent_romaneio_request_changes();

alter table public.exp_romaneio_requisicoes enable row level security;
revoke all on table public.exp_romaneio_requisicoes from public, anon, authenticated;

create or replace function public.gravar_exp_romaneio_pedido_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_itens jsonb
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.exp_romaneio_requisicoes%rowtype;
  v_romaneio_id bigint;
begin
  perform public.require_current_user_permission('romaneios.create');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'itens', p_itens
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.exp_romaneio_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different romaneio request';
    end if;
    return v_existing.romaneio_id;
  end if;

  v_romaneio_id := public.gravar_exp_romaneio_pedido(p_pedido_id, p_itens);
  insert into public.exp_romaneio_requisicoes(
    idempotency_key, romaneio_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_romaneio_id, v_actor, v_payload_hash);
  return v_romaneio_id;
end;
$$;

revoke all on function public.gravar_exp_romaneio_pedido(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.gravar_exp_romaneio_pedido_idempotente(uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.gravar_exp_romaneio_pedido_idempotente(uuid, bigint, jsonb)
  to authenticated;

comment on function public.gravar_exp_romaneio_pedido_idempotente(uuid, bigint, jsonb) is
  'Only public order-load save entrypoint. One request key creates at most one audited romaneio draft.';
