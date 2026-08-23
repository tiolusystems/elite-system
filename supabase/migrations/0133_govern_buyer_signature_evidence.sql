-- ORD-01 SIG01: buyer signature evidence is separate from Elite approval.
-- The bucket is private; application servers mediate artifact access.
insert into storage.buckets (id, name, public)
values ('order-signature-evidence', 'order-signature-evidence', false)
on conflict (id) do update set public = false;

create table public.com_pedido_assinatura_evidencias (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  confirmacao_comercial_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  documento_canonico_sha256 text not null check (documento_canonico_sha256 ~ '^[0-9a-f]{64}$'),
  fonte text not null check (fonte in ('integrated_api', 'gov_br', 'external_digital', 'physical_digitized')),
  contato_id bigint references public.cad_cliente_contatos(id) on delete restrict,
  contato_nome_snapshot text not null,
  contato_papel_snapshot text not null,
  contato_email_snapshot text,
  artefato_storage_path text,
  artefato_sha256 text not null check (artefato_sha256 ~ '^[0-9a-f]{64}$'),
  artefato_content_type text,
  artefato_size_bytes bigint check (artefato_size_bytes is null or artefato_size_bytes > 0),
  referencia_externa text,
  declarado_assinado_em timestamptz,
  submitted_by uuid not null references public.user_profiles(id) on delete restrict,
  submitted_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_assinatura_evidencias_source_check check (
    (fonte = 'physical_digitized' and artefato_storage_path is not null)
    or (fonte <> 'physical_digitized' and (artefato_storage_path is not null or referencia_externa is not null))
  ),
  constraint com_pedido_assinatura_evidencias_path_check check (
    artefato_storage_path is null or artefato_storage_path ~ '^pending/[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{64}$'
  )
);

create index idx_com_pedido_assinatura_evidencias_pedido
  on public.com_pedido_assinatura_evidencias(pedido_id, submitted_at desc);
create index idx_com_pedido_assinatura_evidencias_confirmacao
  on public.com_pedido_assinatura_evidencias(confirmacao_comercial_id, submitted_at desc);

create table public.com_pedido_assinatura_decisoes (
  id bigint generated always as identity primary key,
  evidencia_id bigint not null unique references public.com_pedido_assinatura_evidencias(id) on delete restrict,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  confirmacao_comercial_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  documento_canonico_sha256 text not null check (documento_canonico_sha256 ~ '^[0-9a-f]{64}$'),
  decisao text not null check (decisao in ('ACCEPTED', 'REJECTED')),
  justificativa text,
  decided_by uuid not null references public.user_profiles(id) on delete restrict,
  decided_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_assinatura_decisoes_justificativa_check check (
    decisao = 'ACCEPTED' or length(btrim(coalesce(justificativa, ''))) >= 10
  )
);

create table public.com_pedido_assinatura_evidencia_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  evidencia_id bigint not null references public.com_pedido_assinatura_evidencias(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

create table public.com_pedido_assinatura_decisao_requisicoes (
  idempotency_key uuid primary key,
  evidencia_id bigint not null references public.com_pedido_assinatura_evidencias(id) on delete restrict,
  decisao_id bigint not null references public.com_pedido_assinatura_decisoes(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

alter table public.com_pedido_assinatura_evidencias enable row level security;
alter table public.com_pedido_assinatura_decisoes enable row level security;
alter table public.com_pedido_assinatura_evidencia_requisicoes enable row level security;
alter table public.com_pedido_assinatura_decisao_requisicoes enable row level security;

revoke all on public.com_pedido_assinatura_evidencias from public, anon, authenticated;
revoke all on public.com_pedido_assinatura_decisoes from public, anon, authenticated;
revoke all on public.com_pedido_assinatura_evidencia_requisicoes from public, anon, authenticated;
revoke all on public.com_pedido_assinatura_decisao_requisicoes from public, anon, authenticated;

create trigger trg_com_pedido_assinatura_evidencias_append_only
before update or delete on public.com_pedido_assinatura_evidencias
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_evidencias_no_truncate
before truncate on public.com_pedido_assinatura_evidencias
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_decisoes_append_only
before update or delete on public.com_pedido_assinatura_decisoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_decisoes_no_truncate
before truncate on public.com_pedido_assinatura_decisoes
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_evidencia_requisicoes_append_only
before update or delete on public.com_pedido_assinatura_evidencia_requisicoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_evidencia_requisicoes_no_truncate
before truncate on public.com_pedido_assinatura_evidencia_requisicoes
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_decisao_requisicoes_append_only
before update or delete on public.com_pedido_assinatura_decisao_requisicoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_assinatura_decisao_requisicoes_no_truncate
before truncate on public.com_pedido_assinatura_decisao_requisicoes
for each statement execute function public.prevent_dec009_fact_changes();

create or replace function public.validate_com_pedido_assinatura_evidencia()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_confirmacao public.com_pedido_confirmacoes_comerciais%rowtype;
  v_contato public.cad_cliente_contatos%rowtype;
begin
  select * into v_pedido from public.com_pedidos where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'assinatura exige pedido de venda bloqueado';
  end if;
  select * into v_confirmacao
    from public.com_pedido_confirmacoes_comerciais
   where id = new.confirmacao_comercial_id and pedido_id = new.pedido_id;
  if not found or v_confirmacao.documento_canonico_sha256 is distinct from new.documento_canonico_sha256 then
    raise exception 'evidencia nao corresponde ao documento comercial canonico';
  end if;
  if new.contato_id is null then
    raise exception 'contato comprador e obrigatorio';
  end if;
  select * into v_contato from public.cad_cliente_contatos
   where id = new.contato_id and cliente_id = v_pedido.cliente_id and status = 'active';
  if not found then raise exception 'contato comprador nao pertence ao cliente ativo'; end if;
  if new.contato_nome_snapshot is distinct from v_contato.nome
     or new.contato_papel_snapshot is distinct from v_contato.papel
     or new.contato_email_snapshot is distinct from v_contato.email then
    raise exception 'snapshot do contato comprador divergente';
  end if;
  if new.artefato_storage_path is null and new.referencia_externa is null then
    raise exception 'evidencia exige artefato privado ou referencia externa';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_com_pedido_assinatura_evidencia() from public, anon, authenticated;
create trigger trg_com_pedido_assinatura_evidencias_validate
before insert on public.com_pedido_assinatura_evidencias
for each row execute function public.validate_com_pedido_assinatura_evidencia();

create or replace function public.validate_com_pedido_assinatura_decisao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_evidencia public.com_pedido_assinatura_evidencias%rowtype;
  v_current public.com_pedido_confirmacoes_comerciais%rowtype;
begin
  select * into v_evidencia from public.com_pedido_assinatura_evidencias where id = new.evidencia_id;
  if not found or v_evidencia.pedido_id <> new.pedido_id then raise exception 'evidencia de assinatura invalida'; end if;
  select * into v_current from public.com_pedido_confirmacoes_comerciais
   where pedido_id = new.pedido_id order by numero_versao desc limit 1;
  if not found or v_current.id <> new.confirmacao_comercial_id
     or v_current.documento_canonico_sha256 is distinct from new.documento_canonico_sha256 then
    raise exception 'decisao exige a versao comercial vigente';
  end if;
  if new.decisao = 'ACCEPTED' and v_evidencia.confirmacao_comercial_id <> v_current.id then
    raise exception 'evidencia antiga e historica para esta versao';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_com_pedido_assinatura_decisao() from public, anon, authenticated;
create trigger trg_com_pedido_assinatura_decisoes_validate
before insert on public.com_pedido_assinatura_decisoes
for each row execute function public.validate_com_pedido_assinatura_decisao();

create or replace function public.consultar_com_pedido_documento_assinavel(p_pedido_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.view');
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  select jsonb_build_object(
    'confirmacao_comercial_id', confirmation.id,
    'pedido_id', confirmation.pedido_id,
    'numero_versao', confirmation.numero_versao,
    'documento_canonico_sha256', confirmation.documento_canonico_sha256,
    'confirmed_at', confirmation.confirmed_at,
    'status_pedido', orders.status,
    'documento', confirmation.documento_canonico_json
  ) into v_result
    from public.com_pedido_confirmacoes_comerciais confirmation
    join public.com_pedidos orders on orders.id = confirmation.pedido_id
   where confirmation.pedido_id = p_pedido_id
   order by confirmation.numero_versao desc
   limit 1;
  if v_result is null then raise exception 'pedido nao possui confirmacao comercial'; end if;
  return v_result;
end;
$$;

create or replace function public.consultar_com_pedido_assinaturas(p_pedido_id bigint)
returns table(
  evidencia_id bigint, confirmacao_comercial_id bigint, documento_canonico_sha256 text,
  fonte text, contato_id bigint, contato_nome text, artefato_sha256 text,
  referencia_externa text, declarado_assinado_em timestamptz, submitted_at timestamptz,
  status text, justificativa text, decided_at timestamptz, is_current_version boolean,
  artefato_disponivel boolean
) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.view');
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  return query
  select evidence.id, evidence.confirmacao_comercial_id, evidence.documento_canonico_sha256,
         evidence.fonte, evidence.contato_id, evidence.contato_nome_snapshot,
         evidence.artefato_sha256, evidence.referencia_externa, evidence.declarado_assinado_em,
         evidence.submitted_at, coalesce(decision.decisao, 'PENDING'), decision.justificativa,
         decision.decided_at,
         evidence.confirmacao_comercial_id = current_confirmation.id,
         evidence.artefato_storage_path is not null
    from public.com_pedido_assinatura_evidencias evidence
    left join public.com_pedido_assinatura_decisoes decision on decision.evidencia_id = evidence.id
    left join lateral (
      select id from public.com_pedido_confirmacoes_comerciais
       where pedido_id = p_pedido_id order by numero_versao desc limit 1
    ) current_confirmation on true
   where evidence.pedido_id = p_pedido_id
   order by evidence.submitted_at desc;
end;
$$;

create or replace function public.consultar_com_pedido_assinatura_artefato(p_evidencia_id bigint)
returns table(artefato_storage_path text, artefato_content_type text, artefato_sha256 text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.view');
  return query
  select evidence.artefato_storage_path, evidence.artefato_content_type, evidence.artefato_sha256
    from public.com_pedido_assinatura_evidencias evidence
   where evidence.id = p_evidencia_id
     and public.can_current_user_view_order(evidence.pedido_id)
     and evidence.artefato_storage_path is not null;
  if not found then raise exception 'artefato fora do escopo ou indisponivel'; end if;
end;
$$;

create or replace function public.autorizar_com_pedido_assinatura_evidencia(
  p_pedido_id bigint, p_confirmacao_comercial_id bigint, p_documento_canonico_sha256 text
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_current public.com_pedido_confirmacoes_comerciais%rowtype;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.submit');
  if p_pedido_id is null or not public.can_current_user_view_order(p_pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  select * into v_current
    from public.com_pedido_confirmacoes_comerciais
   where pedido_id = p_pedido_id
   order by numero_versao desc
   limit 1;
  if not found
     or v_current.id is distinct from p_confirmacao_comercial_id
     or v_current.documento_canonico_sha256 is distinct from lower(p_documento_canonico_sha256) then
    raise exception 'evidencia nao corresponde ao documento comercial vigente';
  end if;
  return jsonb_build_object(
    'pedido_id', p_pedido_id,
    'confirmacao_comercial_id', v_current.id,
    'documento_canonico_sha256', v_current.documento_canonico_sha256
  );
end;
$$;

create or replace function public.registrar_com_pedido_assinatura_evidencia_idempotente(
  p_idempotency_key uuid, p_pedido_id bigint, p_confirmacao_comercial_id bigint,
  p_documento_canonico_sha256 text, p_fonte text, p_contato_id bigint,
  p_artefato_storage_path text, p_artefato_sha256 text, p_artefato_content_type text,
  p_artefato_size_bytes bigint, p_referencia_externa text,
  p_declarado_assinado_em timestamptz
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.current_actor_id();
  v_payload_hash text;
  v_existing public.com_pedido_assinatura_evidencia_requisicoes%rowtype;
  v_contato public.cad_cliente_contatos%rowtype;
  v_id bigint;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.submit');
  if p_idempotency_key is null or p_pedido_id is null or p_confirmacao_comercial_id is null then raise exception 'identidade da evidencia e obrigatoria'; end if;
  if p_documento_canonico_sha256 !~ '^[0-9a-f]{64}$' or p_artefato_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'hash da evidencia invalido'; end if;
  if p_fonte not in ('external_digital', 'physical_digitized') then raise exception 'fonte de assinatura manual invalida'; end if;
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'pedido_id', p_pedido_id, 'confirmacao_comercial_id', p_confirmacao_comercial_id,
    'documento_canonico_sha256', lower(p_documento_canonico_sha256), 'fonte', p_fonte,
    'contato_id', p_contato_id, 'artefato_storage_path', p_artefato_storage_path,
    'artefato_sha256', lower(p_artefato_sha256), 'referencia_externa', p_referencia_externa,
    'declarado_assinado_em', p_declarado_assinado_em
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_assinatura_evidencia_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com payload divergente'; end if;
    return v_existing.evidencia_id;
  end if;
  select * into v_contato from public.cad_cliente_contatos where id = p_contato_id and status = 'active';
  if not found then raise exception 'contato comprador nao encontrado'; end if;
  v_context := public.begin_audited_rpc('pedidos.buyer_signature.submit', 'pedidos', 'com_pedido_assinatura_evidencias', 'change_type', jsonb_build_object('pedido_id', p_pedido_id, 'source', p_fonte));
  insert into public.com_pedido_assinatura_evidencias(
    pedido_id, confirmacao_comercial_id, documento_canonico_sha256, fonte, contato_id,
    contato_nome_snapshot, contato_papel_snapshot, contato_email_snapshot,
    artefato_storage_path, artefato_sha256, artefato_content_type, artefato_size_bytes,
    referencia_externa, declarado_assinado_em, submitted_by
  ) values (
    p_pedido_id, p_confirmacao_comercial_id, lower(p_documento_canonico_sha256), p_fonte, p_contato_id,
    v_contato.nome, v_contato.papel, v_contato.email, p_artefato_storage_path,
    lower(p_artefato_sha256), p_artefato_content_type, p_artefato_size_bytes,
    nullif(btrim(p_referencia_externa), ''), p_declarado_assinado_em, v_actor
  ) returning id into v_id;
  insert into public.com_pedido_assinatura_evidencia_requisicoes(idempotency_key, pedido_id, evidencia_id, actor_id, payload_hash)
  values (p_idempotency_key, p_pedido_id, v_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_pedido_assinatura_evidencias', v_id::text, 'pedidos.buyer_signature.submitted', 'pedidos.buyer_signature.submit', v_context, null, jsonb_build_object('pedido_id', p_pedido_id, 'status', 'PENDING', 'accepted', false), 'database_rpc');
  return v_id;
end;
$$;

create or replace function public.decidir_com_pedido_assinatura_idempotente(
  p_idempotency_key uuid, p_evidencia_id bigint, p_decisao text, p_justificativa text
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.current_actor_id();
  v_existing public.com_pedido_assinatura_decisao_requisicoes%rowtype;
  v_evidence public.com_pedido_assinatura_evidencias%rowtype;
  v_current public.com_pedido_confirmacoes_comerciais%rowtype;
  v_hash text;
  v_decision_id bigint;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.review');
  if p_idempotency_key is null or p_evidencia_id is null then raise exception 'identidade da decisao e obrigatoria'; end if;
  if p_decisao not in ('ACCEPTED', 'REJECTED') then raise exception 'decisao de assinatura invalida'; end if;
  if p_decisao = 'REJECTED' and length(btrim(coalesce(p_justificativa, ''))) < 10 then raise exception 'justificativa deve possuir ao menos 10 caracteres'; end if;
  select * into v_evidence from public.com_pedido_assinatura_evidencias where id = p_evidencia_id for update;
  if not found or not public.can_current_user_view_order(v_evidence.pedido_id) then raise exception 'evidencia fora do escopo do usuario'; end if;
  select * into v_current from public.com_pedido_confirmacoes_comerciais where pedido_id = v_evidence.pedido_id order by numero_versao desc limit 1;
  if not found or v_current.id <> v_evidence.confirmacao_comercial_id or v_current.documento_canonico_sha256 is distinct from v_evidence.documento_canonico_sha256 then raise exception 'evidencia nao corresponde a versao comercial vigente'; end if;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object('evidencia_id', p_evidencia_id, 'decisao', p_decisao, 'justificativa', btrim(p_justificativa))::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_assinatura_decisao_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_hash then raise exception 'chave de idempotencia reutilizada com payload divergente'; end if;
    return v_existing.decisao_id;
  end if;
  if exists (select 1 from public.com_pedido_assinatura_decisoes where evidencia_id = p_evidencia_id) then raise exception 'evidencia de assinatura ja decidida'; end if;
  v_context := public.begin_audited_rpc('pedidos.buyer_signature.review', 'pedidos', 'com_pedido_assinatura_decisoes', 'change_type', jsonb_build_object('evidencia_id', p_evidencia_id, 'decision', p_decisao));
  insert into public.com_pedido_assinatura_decisoes(evidencia_id, pedido_id, confirmacao_comercial_id, documento_canonico_sha256, decisao, justificativa, decided_by)
  values (p_evidencia_id, v_evidence.pedido_id, v_evidence.confirmacao_comercial_id, v_evidence.documento_canonico_sha256, p_decisao, btrim(p_justificativa), v_actor)
  returning id into v_decision_id;
  insert into public.com_pedido_assinatura_decisao_requisicoes(idempotency_key, evidencia_id, decisao_id, actor_id, payload_hash)
  values (p_idempotency_key, p_evidencia_id, v_decision_id, v_actor, v_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_pedido_assinatura_decisoes', v_decision_id::text, case when p_decisao = 'ACCEPTED' then 'pedidos.buyer_signature.accepted' else 'pedidos.buyer_signature.rejected' end, 'pedidos.buyer_signature.review', v_context, null, jsonb_build_object('pedido_id', v_evidence.pedido_id, 'status', p_decisao, 'pedido_permanece_bloqueado', true), 'database_rpc');
  return v_decision_id;
end;
$$;

revoke all on function public.consultar_com_pedido_documento_assinavel(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_documento_assinavel(bigint) to authenticated;
revoke all on function public.consultar_com_pedido_assinaturas(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_assinaturas(bigint) to authenticated;
revoke all on function public.consultar_com_pedido_assinatura_artefato(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_assinatura_artefato(bigint) to authenticated;
revoke all on function public.autorizar_com_pedido_assinatura_evidencia(bigint,bigint,text) from public, anon;
grant execute on function public.autorizar_com_pedido_assinatura_evidencia(bigint,bigint,text) to authenticated;
revoke all on function public.registrar_com_pedido_assinatura_evidencia_idempotente(uuid,bigint,bigint,text,text,bigint,text,text,text,bigint,text,timestamptz) from public, anon;
grant execute on function public.registrar_com_pedido_assinatura_evidencia_idempotente(uuid,bigint,bigint,text,text,bigint,text,text,text,bigint,text,timestamptz) to authenticated;
revoke all on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text) from public, anon;
grant execute on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text) to authenticated;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order, runtime_module_key, runtime_access_kind)
values
  ('pedidos.buyer_signature.view', 'pedidos', 'Consultar documento e evidencias de assinatura do comprador', false, 145, 'pedidos', 'read'),
  ('pedidos.buyer_signature.submit', 'pedidos', 'Registrar evidencia de assinatura do comprador', false, 146, 'pedidos', 'write'),
  ('pedidos.buyer_signature.review', 'pedidos', 'Revisar evidencia de assinatura do comprador', false, 147, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module, description = excluded.description, default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order, runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

comment on table public.com_pedido_assinatura_evidencias is
  'ORD-01 SIG01: evidencia append-only de assinatura do comprador, vinculada ao hash e confirmacao F2B exatos. Upload isolado permanece PENDING.';
comment on table public.com_pedido_assinatura_decisoes is
  'ORD-01 SIG01: decisao append-only ACCEPTED ou REJECTED; aceite nao e aprovacao Elite, pedido permanece bloqueado e nao abre.';
comment on function public.consultar_com_pedido_documento_assinavel(bigint) is
  'ORD-01 SIG01: disponibiliza o documento comercial congelado desde a existencia da confirmacao F2B, sem dependencia de credito.';
