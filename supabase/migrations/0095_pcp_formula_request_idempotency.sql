-- One authoring request creates at most one immutable formula version.

create table public.pcp_formula_requisicoes (
  idempotency_key uuid primary key,
  formula_versao_id bigint not null unique references public.pcp_formula_versoes(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.pcp_formula_requisicoes is
  'Append-only request keys for formula authoring. Identical retries return the original immutable version.';

create or replace function public.prevent_pcp_formula_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'formula request keys are append-only';
end;
$$;
revoke all on function public.prevent_pcp_formula_request_changes() from public, anon, authenticated;

create trigger trg_pcp_formula_requisicoes_no_update
before update or delete on public.pcp_formula_requisicoes
for each row execute function public.prevent_pcp_formula_request_changes();
create trigger trg_pcp_formula_requisicoes_no_truncate
before truncate on public.pcp_formula_requisicoes
for each statement execute function public.prevent_pcp_formula_request_changes();

alter table public.pcp_formula_requisicoes enable row level security;
revoke all on table public.pcp_formula_requisicoes from public, anon, authenticated;

create or replace function public.create_pcp_formula_versao_idempotente(
  p_idempotency_key uuid,
  p_produto_id bigint,
  p_tipo_receita text,
  p_justificativa text,
  p_componentes_jsonb jsonb default '[]'::jsonb,
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_action_key text;
  v_payload_hash text;
  v_existing public.pcp_formula_requisicoes%rowtype;
  v_formula_id bigint;
begin
  v_action_key := public.resolve_pcp_formula_action_key(p_produto_id, p_tipo_receita);
  perform public.require_current_user_permission(v_action_key);
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'produto_id', p_produto_id,
    'tipo_receita', p_tipo_receita,
    'justificativa', btrim(p_justificativa),
    'componentes', p_componentes_jsonb,
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.pcp_formula_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different formula request';
    end if;
    return v_existing.formula_versao_id;
  end if;

  v_formula_id := public.create_pcp_formula_versao(
    p_produto_id, p_tipo_receita, p_justificativa, p_componentes_jsonb, p_observacao
  );
  insert into public.pcp_formula_requisicoes(
    idempotency_key, formula_versao_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_formula_id, v_actor, v_payload_hash);
  return v_formula_id;
end;
$$;

revoke all on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.create_pcp_formula_versao_idempotente(uuid, bigint, text, text, jsonb, text)
  from public, anon;
grant execute on function public.create_pcp_formula_versao_idempotente(uuid, bigint, text, text, jsonb, text)
  to authenticated;

comment on function public.create_pcp_formula_versao_idempotente(uuid, bigint, text, text, jsonb, text) is
  'Governed formula authoring entrypoint. One request key creates at most one immutable formula version.';
