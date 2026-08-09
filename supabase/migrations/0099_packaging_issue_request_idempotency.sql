-- A repeated issue request must not duplicate the MAPA OP and packaging order.

create table public.pcp_ordem_envase_emissao_requisicoes (
  idempotency_key uuid primary key,
  ordem_envase_id bigint not null unique references public.pcp_ordens_envase(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.pcp_ordem_envase_emissao_requisicoes is
  'Append-only request keys. Identical retries return the original MAPA and packaging order pair.';

create or replace function public.prevent_packaging_issue_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'packaging issue request keys are append-only';
end;
$$;
revoke all on function public.prevent_packaging_issue_request_changes() from public, anon, authenticated;

create trigger trg_pcp_ordem_envase_emissao_requisicoes_no_update
before update or delete on public.pcp_ordem_envase_emissao_requisicoes
for each row execute function public.prevent_packaging_issue_request_changes();
create trigger trg_pcp_ordem_envase_emissao_requisicoes_no_truncate
before truncate on public.pcp_ordem_envase_emissao_requisicoes
for each statement execute function public.prevent_packaging_issue_request_changes();

alter table public.pcp_ordem_envase_emissao_requisicoes enable row level security;
revoke all on table public.pcp_ordem_envase_emissao_requisicoes from public, anon, authenticated;

create or replace function public.emitir_pcp_op_mapa_com_envase_idempotente(
  p_idempotency_key uuid,
  p_formula_mapa_versao_id bigint,
  p_lote_pi_origem_id bigint,
  p_produto_embalagem_id bigint,
  p_volume_planejado_l numeric,
  p_terminal_emissor text,
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.pcp_ordem_envase_emissao_requisicoes%rowtype;
  v_ordem_envase_id bigint;
begin
  perform public.require_current_user_permission('pcp.envase.issue');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'formula_mapa_versao_id', p_formula_mapa_versao_id,
    'lote_pi_origem_id', p_lote_pi_origem_id,
    'produto_embalagem_id', p_produto_embalagem_id,
    'volume_planejado_l', p_volume_planejado_l,
    'terminal_emissor', btrim(p_terminal_emissor),
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.pcp_ordem_envase_emissao_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different packaging issue request';
    end if;
    return v_existing.ordem_envase_id;
  end if;

  v_ordem_envase_id := public.emitir_pcp_op_mapa_com_envase(
    p_formula_mapa_versao_id,
    p_lote_pi_origem_id,
    p_produto_embalagem_id,
    p_volume_planejado_l,
    p_terminal_emissor,
    p_observacao
  );
  insert into public.pcp_ordem_envase_emissao_requisicoes(
    idempotency_key, ordem_envase_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_ordem_envase_id, v_actor, v_payload_hash);
  return v_ordem_envase_id;
end;
$$;

revoke all on function public.emitir_pcp_op_mapa_com_envase(bigint, bigint, bigint, numeric, text, text)
  from public, anon, authenticated;
revoke all on function public.emitir_pcp_op_mapa_com_envase_idempotente(uuid, bigint, bigint, bigint, numeric, text, text)
  from public, anon;
grant execute on function public.emitir_pcp_op_mapa_com_envase_idempotente(uuid, bigint, bigint, bigint, numeric, text, text)
  to authenticated;

comment on function public.emitir_pcp_op_mapa_com_envase_idempotente(uuid, bigint, bigint, bigint, numeric, text, text) is
  'Only public packaging issue entrypoint. One request key creates at most one MAPA OP and packaging order pair.';
