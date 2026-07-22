-- Prevent duplicate receipt events caused by double submit or network retries.
-- Distinct partial receipts still use distinct request keys.

create table public.fin_recebimento_requisicoes (
  idempotency_key uuid primary key,
  recebimento_id bigint not null unique references public.com_recebimentos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.fin_recebimento_requisicoes is
  'Append-only receipt request keys. A browser retry returns the original receipt instead of creating another financial event.';
comment on column public.fin_recebimento_requisicoes.payload_hash is
  'Comparison hash of the normalized request payload; it is not a credential or document hash.';

create trigger trg_fin_recebimento_requisicoes_no_update
before update or delete on public.fin_recebimento_requisicoes
for each row execute function public.prevent_financial_event_changes();

create trigger trg_fin_recebimento_requisicoes_no_truncate
before truncate on public.fin_recebimento_requisicoes
for each statement execute function public.prevent_financial_event_changes();

alter table public.fin_recebimento_requisicoes enable row level security;

revoke all on table public.fin_recebimento_requisicoes from public, anon, authenticated;

create or replace function public.registrar_com_recebimento_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date default current_date,
  p_forma_recebimento text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_recebimento_requisicoes%rowtype;
  v_recebimento_id bigint;
begin
  perform public.require_current_user_permission('financeiro.receipts.register');

  if p_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'valor_recebido', p_valor_recebido,
    'data_recebimento', p_data_recebimento,
    'forma_recebimento', nullif(btrim(p_forma_recebimento), ''),
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select *
    into v_existing
    from public.fin_recebimento_requisicoes request
   where request.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different receipt request';
    end if;
    return v_existing.recebimento_id;
  end if;

  v_recebimento_id := public.registrar_com_recebimento(
    p_pedido_id,
    p_valor_recebido,
    p_data_recebimento,
    p_forma_recebimento,
    p_observacao
  );

  insert into public.fin_recebimento_requisicoes(
    idempotency_key,
    recebimento_id,
    actor_id,
    payload_hash
  ) values (
    p_idempotency_key,
    v_recebimento_id,
    v_actor,
    v_payload_hash
  );

  return v_recebimento_id;
end;
$$;

comment on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text) is
  'Public audited receipt entrypoint. Reusing the same request key and payload returns the original receipt.';

-- The unkeyed compatibility function remains callable by trusted composing
-- functions owned by postgres, but cannot be invoked directly through the API.
revoke all on function public.registrar_com_recebimento(bigint, numeric, date, text, text)
  from public, anon, authenticated;
revoke all on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text)
  from public, anon;
grant execute on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text)
  to authenticated;
