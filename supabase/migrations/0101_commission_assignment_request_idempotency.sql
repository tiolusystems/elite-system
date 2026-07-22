-- A repeated commission assignment must not duplicate an audited revision.

create table public.com_pedido_comissao_requisicoes (
  idempotency_key uuid primary key,
  comissionado_id bigint not null references public.com_pedido_comissionados(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.com_pedido_comissao_requisicoes is
  'Append-only request keys. Identical retries return the original commission assignment result.';

create or replace function public.prevent_commission_assignment_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'commission assignment request keys are append-only';
end;
$$;
revoke all on function public.prevent_commission_assignment_request_changes() from public, anon, authenticated;

create trigger trg_com_pedido_comissao_requisicoes_no_update
before update or delete on public.com_pedido_comissao_requisicoes
for each row execute function public.prevent_commission_assignment_request_changes();
create trigger trg_com_pedido_comissao_requisicoes_no_truncate
before truncate on public.com_pedido_comissao_requisicoes
for each statement execute function public.prevent_commission_assignment_request_changes();

alter table public.com_pedido_comissao_requisicoes enable row level security;
revoke all on table public.com_pedido_comissao_requisicoes from public, anon, authenticated;

create or replace function public.definir_com_pedido_comissao_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_pessoa_id bigint,
  p_papel_comissao text,
  p_percentual_comissao numeric,
  p_justificativa text
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_comissao_requisicoes%rowtype;
  v_comissionado_id bigint;
begin
  perform public.require_current_user_permission('pedidos.commissions.assign');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'pessoa_id', p_pessoa_id,
    'papel_comissao', lower(btrim(p_papel_comissao)),
    'percentual_comissao', p_percentual_comissao,
    'justificativa', btrim(p_justificativa)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_comissao_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different commission assignment request';
    end if;
    return v_existing.comissionado_id;
  end if;

  v_comissionado_id := public.definir_com_pedido_comissao(
    p_pedido_id, p_pessoa_id, p_papel_comissao, p_percentual_comissao, p_justificativa
  );
  insert into public.com_pedido_comissao_requisicoes(
    idempotency_key, comissionado_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_comissionado_id, v_actor, v_payload_hash);
  return v_comissionado_id;
end;
$$;

revoke all on function public.definir_com_pedido_comissao(bigint, bigint, text, numeric, text)
  from public, anon, authenticated;
revoke all on function public.definir_com_pedido_comissao_idempotente(uuid, bigint, bigint, text, numeric, text)
  from public, anon;
grant execute on function public.definir_com_pedido_comissao_idempotente(uuid, bigint, bigint, text, numeric, text)
  to authenticated;

comment on function public.definir_com_pedido_comissao_idempotente(uuid, bigint, bigint, text, numeric, text) is
  'Only public manual commission assignment entrypoint. One request key records at most one audited revision.';
