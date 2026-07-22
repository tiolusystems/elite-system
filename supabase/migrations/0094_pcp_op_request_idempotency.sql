-- One operator request creates at most one operational production order.

create table public.pcp_op_requisicoes (
  idempotency_key uuid primary key,
  op_id bigint not null unique references public.pcp_ordens_producao(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.pcp_op_requisicoes is
  'Append-only request keys for operational OP creation. Identical retries return the original OP.';

create or replace function public.prevent_pcp_op_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'production order request keys are append-only';
end;
$$;
revoke all on function public.prevent_pcp_op_request_changes() from public, anon, authenticated;

create trigger trg_pcp_op_requisicoes_no_update
before update or delete on public.pcp_op_requisicoes
for each row execute function public.prevent_pcp_op_request_changes();
create trigger trg_pcp_op_requisicoes_no_truncate
before truncate on public.pcp_op_requisicoes
for each statement execute function public.prevent_pcp_op_request_changes();

alter table public.pcp_op_requisicoes enable row level security;
revoke all on table public.pcp_op_requisicoes from public, anon, authenticated;

create or replace function public.create_pcp_op_idempotente(
  p_idempotency_key uuid,
  p_formula_versao_id bigint,
  p_tipo_op text,
  p_quantidade_planejada numeric default null,
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.pcp_op_requisicoes%rowtype;
  v_op_id bigint;
begin
  perform public.require_current_user_permission('pcp.op.create');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'formula_versao_id', p_formula_versao_id,
    'tipo_op', p_tipo_op,
    'quantidade_planejada', p_quantidade_planejada,
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.pcp_op_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different production order request';
    end if;
    return v_existing.op_id;
  end if;

  v_op_id := public.create_pcp_op(
    p_formula_versao_id, p_tipo_op, p_quantidade_planejada, p_observacao
  );
  insert into public.pcp_op_requisicoes(idempotency_key, op_id, actor_id, payload_hash)
  values (p_idempotency_key, v_op_id, v_actor, v_payload_hash);
  return v_op_id;
end;
$$;

revoke all on function public.create_pcp_op(bigint, text, numeric, text)
  from public, anon, authenticated;
revoke all on function public.create_pcp_op_idempotente(uuid, bigint, text, numeric, text)
  from public, anon;
grant execute on function public.create_pcp_op_idempotente(uuid, bigint, text, numeric, text)
  to authenticated;

comment on function public.create_pcp_op_idempotente(uuid, bigint, text, numeric, text) is
  'Governed operational OP entrypoint. One request key creates at most one production order.';
