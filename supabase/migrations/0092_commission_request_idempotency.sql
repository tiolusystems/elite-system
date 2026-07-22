-- Prevent duplicate commission payments and manual adjustments caused by
-- double submit, retries, or concurrent requests against the same balance.

create table public.fin_comissao_requisicoes (
  idempotency_key uuid primary key,
  tipo_operacao text not null check (tipo_operacao in ('pagamento', 'ajuste')),
  movimento_id bigint not null unique references public.fin_comissao_movimentos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.fin_comissao_requisicoes is
  'Append-only keys for commission payment and adjustment requests. Identical retries return the original movement.';

create trigger trg_fin_comissao_requisicoes_no_update
before update or delete on public.fin_comissao_requisicoes
for each row execute function public.prevent_financial_event_changes();

create trigger trg_fin_comissao_requisicoes_no_truncate
before truncate on public.fin_comissao_requisicoes
for each statement execute function public.prevent_financial_event_changes();

alter table public.fin_comissao_requisicoes enable row level security;
revoke all on table public.fin_comissao_requisicoes from public, anon, authenticated;

create or replace function public.registrar_fin_comissao_pagamento_idempotente(
  p_idempotency_key uuid,
  p_pessoa_id bigint,
  p_valor_pago numeric,
  p_data_pagamento date default current_date,
  p_forma_pagamento text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_comissao_requisicoes%rowtype;
  v_movimento_id bigint;
begin
  perform public.require_current_user_permission('financeiro.commissions.pay');
  if p_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo_operacao', 'pagamento',
    'pessoa_id', p_pessoa_id,
    'valor_pago', p_valor_pago,
    'data_pagamento', p_data_pagamento,
    'forma_pagamento', nullif(btrim(p_forma_pagamento), ''),
    'motivo', nullif(btrim(p_motivo), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended('commission-person:' || p_pessoa_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select * into v_existing
    from public.fin_comissao_requisicoes request
   where request.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.tipo_operacao <> 'pagamento'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different commission request';
    end if;
    return v_existing.movimento_id;
  end if;

  v_movimento_id := public.registrar_fin_comissao_pagamento(
    p_pessoa_id, p_valor_pago, p_data_pagamento, p_forma_pagamento, p_motivo
  );

  insert into public.fin_comissao_requisicoes(
    idempotency_key, tipo_operacao, movimento_id, actor_id, payload_hash
  ) values (
    p_idempotency_key, 'pagamento', v_movimento_id, v_actor, v_payload_hash
  );
  return v_movimento_id;
end;
$$;

create or replace function public.registrar_fin_comissao_ajuste_idempotente(
  p_idempotency_key uuid,
  p_pessoa_id bigint,
  p_valor_ajuste numeric,
  p_motivo text,
  p_referencia_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_comissao_requisicoes%rowtype;
  v_movimento_id bigint;
begin
  perform public.require_current_user_permission('financeiro.commissions.adjust');
  if p_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo_operacao', 'ajuste',
    'pessoa_id', p_pessoa_id,
    'valor_ajuste', p_valor_ajuste,
    'motivo', nullif(btrim(p_motivo), ''),
    'referencia_json', coalesce(p_referencia_json, '{}'::jsonb)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended('commission-person:' || p_pessoa_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select * into v_existing
    from public.fin_comissao_requisicoes request
   where request.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.tipo_operacao <> 'ajuste'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different commission request';
    end if;
    return v_existing.movimento_id;
  end if;

  v_movimento_id := public.registrar_fin_comissao_ajuste(
    p_pessoa_id, p_valor_ajuste, p_motivo, p_referencia_json
  );

  insert into public.fin_comissao_requisicoes(
    idempotency_key, tipo_operacao, movimento_id, actor_id, payload_hash
  ) values (
    p_idempotency_key, 'ajuste', v_movimento_id, v_actor, v_payload_hash
  );
  return v_movimento_id;
end;
$$;

comment on function public.registrar_fin_comissao_pagamento_idempotente(uuid, bigint, numeric, date, text, text) is
  'Public governed payment entrypoint. Serializes commission balance changes and safely reuses one request key.';
comment on function public.registrar_fin_comissao_ajuste_idempotente(uuid, bigint, numeric, text, jsonb) is
  'Public governed adjustment entrypoint. Serializes commission balance changes and safely reuses one request key.';

revoke all on function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text)
  from public, anon, authenticated;
revoke all on function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.registrar_fin_comissao_pagamento_idempotente(uuid, bigint, numeric, date, text, text)
  from public, anon;
revoke all on function public.registrar_fin_comissao_ajuste_idempotente(uuid, bigint, numeric, text, jsonb)
  from public, anon;
grant execute on function public.registrar_fin_comissao_pagamento_idempotente(uuid, bigint, numeric, date, text, text)
  to authenticated;
grant execute on function public.registrar_fin_comissao_ajuste_idempotente(uuid, bigint, numeric, text, jsonb)
  to authenticated;
