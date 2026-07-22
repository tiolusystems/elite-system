-- A repeated manager request must not duplicate a credit limit event.

create table public.fin_limite_credito_requisicoes (
  idempotency_key uuid primary key,
  limite_credito_evento_id bigint not null unique references public.cad_limite_credito_eventos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.fin_limite_credito_requisicoes is
  'Append-only request keys for manager credit limit adjustments. Identical retries return the original event.';

create or replace function public.prevent_credit_limit_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'credit limit request keys are append-only';
end;
$$;
revoke all on function public.prevent_credit_limit_request_changes() from public, anon, authenticated;

create trigger trg_fin_limite_credito_requisicoes_no_update
before update or delete on public.fin_limite_credito_requisicoes
for each row execute function public.prevent_credit_limit_request_changes();
create trigger trg_fin_limite_credito_requisicoes_no_truncate
before truncate on public.fin_limite_credito_requisicoes
for each statement execute function public.prevent_credit_limit_request_changes();

alter table public.fin_limite_credito_requisicoes enable row level security;
revoke all on table public.fin_limite_credito_requisicoes from public, anon, authenticated;

create or replace function public.ajustar_com_limite_credito_cliente_idempotente(
  p_idempotency_key uuid,
  p_cliente_id bigint,
  p_limite_novo numeric,
  p_justificativa text
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_limite_credito_requisicoes%rowtype;
  v_event_id bigint;
begin
  perform public.require_current_user_permission('pedidos.credit.limit.adjust');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'cliente_id', p_cliente_id,
    'limite_novo', p_limite_novo,
    'justificativa', btrim(p_justificativa)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.fin_limite_credito_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different credit limit request';
    end if;
    return v_existing.limite_credito_evento_id;
  end if;

  v_event_id := public.ajustar_com_limite_credito_cliente(
    p_cliente_id, p_limite_novo, p_justificativa
  );
  insert into public.fin_limite_credito_requisicoes(
    idempotency_key, limite_credito_evento_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_event_id, v_actor, v_payload_hash);
  return v_event_id;
end;
$$;

revoke all on function public.ajustar_com_limite_credito_cliente(bigint, numeric, text)
  from public, anon, authenticated;
revoke all on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text)
  from public, anon;
grant execute on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text)
  to authenticated;

comment on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text) is
  'Governed manager credit limit entrypoint. One request key creates at most one audited adjustment event.';
