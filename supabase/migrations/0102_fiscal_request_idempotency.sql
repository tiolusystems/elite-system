-- Fiscal documents and post-payment returns must survive network retries without
-- duplicating invoices or physical stock movements.

create table public.fat_nota_fiscal_emissao_requisicoes (
  idempotency_key uuid primary key,
  nota_fiscal_id bigint not null unique references public.fat_notas_fiscais(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

create table public.com_pedido_estorno_requisicoes (
  idempotency_key uuid primary key,
  nota_fiscal_devolucao_id bigint not null unique references public.fat_notas_fiscais(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

comment on table public.fat_nota_fiscal_emissao_requisicoes is
  'Append-only request keys. Identical retries return the original fiscal invoice.';
comment on table public.com_pedido_estorno_requisicoes is
  'Append-only request keys. Identical retries return the original return invoice without duplicating stock.';

create or replace function public.prevent_fiscal_request_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'fiscal request keys are append-only';
end;
$$;
revoke all on function public.prevent_fiscal_request_changes() from public, anon, authenticated;

create trigger trg_fat_nota_fiscal_emissao_requisicoes_no_update
before update or delete on public.fat_nota_fiscal_emissao_requisicoes
for each row execute function public.prevent_fiscal_request_changes();
create trigger trg_fat_nota_fiscal_emissao_requisicoes_no_truncate
before truncate on public.fat_nota_fiscal_emissao_requisicoes
for each statement execute function public.prevent_fiscal_request_changes();
create trigger trg_com_pedido_estorno_requisicoes_no_update
before update or delete on public.com_pedido_estorno_requisicoes
for each row execute function public.prevent_fiscal_request_changes();
create trigger trg_com_pedido_estorno_requisicoes_no_truncate
before truncate on public.com_pedido_estorno_requisicoes
for each statement execute function public.prevent_fiscal_request_changes();

alter table public.fat_nota_fiscal_emissao_requisicoes enable row level security;
alter table public.com_pedido_estorno_requisicoes enable row level security;
revoke all on table public.fat_nota_fiscal_emissao_requisicoes from public, anon, authenticated;
revoke all on table public.com_pedido_estorno_requisicoes from public, anon, authenticated;

create or replace function public.emitir_fat_nota_fiscal_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_tipo text,
  p_itens_jsonb jsonb,
  p_chave_nfe text default null,
  p_numero text default null,
  p_serie text default null,
  p_data_emissao date default current_date,
  p_valor_nf numeric default 0,
  p_romaneio_id bigint default null,
  p_nota_pai_id bigint default null,
  p_nota_complementada_id bigint default null,
  p_payload_json jsonb default '{}'::jsonb,
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fat_nota_fiscal_emissao_requisicoes%rowtype;
  v_nota_fiscal_id bigint;
begin
  perform public.require_current_user_permission('faturamento.nf.issue');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'tipo', lower(btrim(p_tipo)),
    'itens', coalesce(p_itens_jsonb, '[]'::jsonb),
    'chave_nfe', nullif(regexp_replace(coalesce(p_chave_nfe, ''), '\D', '', 'g'), ''),
    'numero', nullif(btrim(p_numero), ''),
    'serie', nullif(btrim(p_serie), ''),
    'data_emissao', p_data_emissao,
    'valor_nf', p_valor_nf,
    'romaneio_id', p_romaneio_id,
    'nota_pai_id', p_nota_pai_id,
    'nota_complementada_id', p_nota_complementada_id,
    'payload', coalesce(p_payload_json, '{}'::jsonb),
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.fat_nota_fiscal_emissao_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different fiscal invoice request';
    end if;
    return v_existing.nota_fiscal_id;
  end if;

  v_nota_fiscal_id := public.emitir_fat_nota_fiscal(
    p_pedido_id, p_tipo, p_itens_jsonb, p_chave_nfe, p_numero, p_serie,
    p_data_emissao, p_valor_nf, p_romaneio_id, p_nota_pai_id,
    p_nota_complementada_id, p_payload_json, p_observacao
  );
  insert into public.fat_nota_fiscal_emissao_requisicoes(
    idempotency_key, nota_fiscal_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_nota_fiscal_id, v_actor, v_payload_hash);
  return v_nota_fiscal_id;
end;
$$;

create or replace function public.registrar_com_pedido_estorno_pos_pagamento_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_nota_fiscal_origem_id bigint,
  p_itens_jsonb jsonb,
  p_motivo_devolucao text,
  p_chave_nfe text default null,
  p_numero text default null,
  p_serie text default null,
  p_data_emissao date default current_date,
  p_payload_json jsonb default '{}'::jsonb,
  p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_estorno_requisicoes%rowtype;
  v_nota_fiscal_devolucao_id bigint;
begin
  perform public.require_current_user_permission('pedidos.post_payment_reversal');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'nota_fiscal_origem_id', p_nota_fiscal_origem_id,
    'itens', coalesce(p_itens_jsonb, '[]'::jsonb),
    'motivo_devolucao', lower(btrim(p_motivo_devolucao)),
    'chave_nfe', nullif(regexp_replace(coalesce(p_chave_nfe, ''), '\D', '', 'g'), ''),
    'numero', nullif(btrim(p_numero), ''),
    'serie', nullif(btrim(p_serie), ''),
    'data_emissao', p_data_emissao,
    'payload', coalesce(p_payload_json, '{}'::jsonb),
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_estorno_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different post-payment reversal request';
    end if;
    return v_existing.nota_fiscal_devolucao_id;
  end if;

  v_nota_fiscal_devolucao_id := public.registrar_com_pedido_estorno_pos_pagamento(
    p_pedido_id, p_nota_fiscal_origem_id, p_itens_jsonb, p_motivo_devolucao,
    p_chave_nfe, p_numero, p_serie, p_data_emissao, p_payload_json, p_observacao
  );
  insert into public.com_pedido_estorno_requisicoes(
    idempotency_key, nota_fiscal_devolucao_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_nota_fiscal_devolucao_id, v_actor, v_payload_hash);
  return v_nota_fiscal_devolucao_id;
end;
$$;

revoke all on function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.emitir_fat_nota_fiscal_idempotente(uuid, bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text)
  from public, anon;
revoke all on function public.registrar_com_pedido_estorno_pos_pagamento_idempotente(uuid, bigint, bigint, jsonb, text, text, text, text, date, jsonb, text)
  from public, anon;
grant execute on function public.emitir_fat_nota_fiscal_idempotente(uuid, bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text)
  to authenticated;
grant execute on function public.registrar_com_pedido_estorno_pos_pagamento_idempotente(uuid, bigint, bigint, jsonb, text, text, text, text, date, jsonb, text)
  to authenticated;

comment on function public.emitir_fat_nota_fiscal_idempotente(uuid, bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) is
  'Only public fiscal issue entrypoint. One request key creates at most one invoice.';
comment on function public.registrar_com_pedido_estorno_pos_pagamento_idempotente(uuid, bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) is
  'Only public post-payment reversal entrypoint. One request key creates at most one return invoice and stock reversal.';
