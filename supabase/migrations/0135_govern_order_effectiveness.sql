-- ORD-01: a venda somente se torna efetiva quando todos os fatos da mesma
-- versao comercial governada estiverem presentes.

alter table public.com_pedidos
  add column if not exists pedido_efetivado_em timestamptz;

insert into public.com_pedido_status_transicoes(status_from, status_to, evento, descricao)
values (
  'blocked', 'open', 'effectiveness_recognized',
  'Pedido de venda efetivado quando todos os gates governados foram satisfeitos'
)
on conflict (status_from, status_to, evento) do update
  set descricao = excluded.descricao;

create or replace function public.prevent_com_pedido_effectiveness_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_internal boolean := current_setting('elite.effectiveness_context', true) = '1';
begin
  if old.pedido_efetivado_em is not null
     and new.pedido_efetivado_em is distinct from old.pedido_efetivado_em then
    raise exception 'data de efetivacao do pedido e imutavel';
  end if;

  if old.pedido_efetivado_em is null and new.pedido_efetivado_em is not null
     and (not v_internal or old.tipo_pedido <> 'venda'
          or old.status <> 'blocked' or new.status <> 'open') then
    raise exception 'efetivacao do pedido exige o avaliador governado';
  end if;

  if old.tipo_pedido = 'venda' and old.status = 'blocked' and new.status = 'open'
     and (not v_internal or new.pedido_efetivado_em is null) then
    raise exception 'venda bloqueada somente pode abrir por efetivacao governada';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_com_pedido_effectiveness_mutation() from public, anon, authenticated;
drop trigger if exists trg_com_pedidos_effectiveness_guard on public.com_pedidos;
create trigger trg_com_pedidos_effectiveness_guard
before update on public.com_pedidos
for each row execute function public.prevent_com_pedido_effectiveness_mutation();

create or replace function public.com_pedido_efetividade_estado(p_pedido_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_credit public.com_pedido_credito_decisoes%rowtype;
  v_current_version integer;
  v_comparison jsonb;
  v_comparison_sha256 text;
  v_active_items bigint;
  v_priced_items bigint;
  v_has_below boolean := false;
  v_f2a_ok boolean := false;
  v_credit_ok boolean := false;
  v_signature_ok boolean := false;
  v_discount_ok boolean := false;
  v_credit_decision_id bigint;
  v_signature_evidence_id bigint;
  v_signature_decision_id bigint;
  v_discount_decision_id bigint;
  v_pending text[] := '{}'::text[];
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id;
  if not found then raise exception 'pedido nao encontrado'; end if;

  select max(confirmation.numero_versao)
    into v_current_version
    from public.com_pedido_confirmacoes_comerciais confirmation
   where confirmation.pedido_id = p_pedido_id;

  if v_current_version is not null then
    select * into v_confirmation
      from public.com_pedido_confirmacoes_comerciais confirmation
     where confirmation.pedido_id = p_pedido_id
       and confirmation.numero_versao = v_current_version;
  end if;

  if v_confirmation.id is not null then
    v_comparison := public.com_pedido_comparacao_comercial_documento(p_pedido_id);
    v_comparison_sha256 := encode(
      extensions.digest(convert_to(v_comparison::text, 'UTF8'), 'sha256'), 'hex'
    );

    select count(*) into v_active_items
      from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id
       and item.status = 'active'
       and item.tipo_item = 'venda';
    select count(*) into v_priced_items
      from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_itens item on item.id = fact.pedido_item_id
     where fact.pedido_id = p_pedido_id
       and item.pedido_id = p_pedido_id
       and item.status = 'active'
       and item.tipo_item = 'venda';

    v_f2a_ok := v_active_items > 0
      and v_active_items = v_priced_items
      and v_comparison_sha256 = v_confirmation.comparacao_sha256;

    select * into v_credit
      from public.com_pedido_credito_decisoes decision
     where decision.pedido_id = p_pedido_id
     order by decision.created_at desc, decision.id desc
     limit 1;
    v_credit_decision_id := v_credit.id;
    v_credit_ok := v_credit.id is not null
      and v_credit.decisao = 'liberado'
      and v_credit.confirmacao_comercial_id = v_confirmation.id
      and v_credit.documento_comercial_sha256 = v_confirmation.documento_canonico_sha256;

    select evidence.id, decision.id
      into v_signature_evidence_id, v_signature_decision_id
      from public.com_pedido_assinatura_evidencias evidence
      join public.com_pedido_assinatura_decisoes decision
        on decision.evidencia_id = evidence.id
       where evidence.pedido_id = p_pedido_id
         and evidence.confirmacao_comercial_id = v_confirmation.id
         and evidence.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256
         and decision.pedido_id = p_pedido_id
         and decision.confirmacao_comercial_id = v_confirmation.id
         and decision.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256
         and decision.decisao = 'ACCEPTED'
      order by decision.created_at desc, decision.id desc
      limit 1;
    v_signature_ok := found;

    select exists (
      select 1
        from public.com_pedido_item_precos_praticados fact
       where fact.pedido_id = p_pedido_id
         and fact.classificacao = 'BELOW_REFERENCE'
    ) into v_has_below;

    if v_has_below then
      select decision.id
        into v_discount_decision_id
        from public.com_pedido_decisoes_desconto decision
       where decision.pedido_id = p_pedido_id
         and decision.confirmacao_comercial_id = v_confirmation.id
         and decision.comparacao_sha256 = v_confirmation.comparacao_sha256
         and decision.decisao = 'APPROVED'
        order by decision.created_at desc, decision.id desc
        limit 1;
      v_discount_ok := found;
    else
      v_discount_ok := true;
    end if;
  end if;

  if v_confirmation.id is null then v_pending := array_append(v_pending, 'F2B'); end if;
  if not v_f2a_ok then v_pending := array_append(v_pending, 'F2A'); end if;
  if not v_credit_ok then v_pending := array_append(v_pending, 'CREDITO'); end if;
  if not v_signature_ok then v_pending := array_append(v_pending, 'ASSINATURA_COMPRADOR'); end if;
  if v_has_below and not v_discount_ok then v_pending := array_append(v_pending, 'APROVACAO_DESCONTO'); end if;

  return jsonb_build_object(
    'pedido_id', p_pedido_id,
    'tipo_pedido', v_order.tipo_pedido,
    'status', v_order.status,
    'pedido_efetivado_em', v_order.pedido_efetivado_em,
    'current_f2b_version', v_current_version,
    'current_f2b_confirmation_id', nullif(v_confirmation.id, 0),
    'current_f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'credit_decision_id', v_credit_decision_id,
    'signature_evidence_id', v_signature_evidence_id,
    'signature_decision_id', v_signature_decision_id,
    'discount_decision_id', v_discount_decision_id,
    'f2a_valid', v_f2a_ok,
    'credit_valid', v_credit_ok,
    'signature_valid', v_signature_ok,
    'discount_required', v_has_below,
    'discount_valid', v_discount_ok,
    'complete', v_confirmation.id is not null and v_f2a_ok and v_credit_ok
      and v_signature_ok and v_discount_ok,
    'pending_conditions', to_jsonb(v_pending)
  );
end;
$$;

revoke all on function public.com_pedido_efetividade_estado(bigint) from public, anon, authenticated;

create or replace function public.avaliar_com_pedido_efetividade(p_pedido_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_state jsonb;
  v_actor uuid;
  v_effective_at timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_previous_effectiveness_context text;
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found then raise exception 'pedido nao encontrado'; end if;

  if v_order.pedido_efetivado_em is not null then
    return jsonb_build_object(
      'pedido_id', p_pedido_id,
      'effective', true,
      'pedido_efetivado_em', v_order.pedido_efetivado_em,
      'idempotent_retry', true
    );
  end if;

  if v_order.tipo_pedido <> 'venda' or v_order.status <> 'blocked' then
    return jsonb_build_object(
      'pedido_id', p_pedido_id,
      'effective', false,
      'status', v_order.status,
      'reason', 'pedido fora do gate de venda bloqueada'
    );
  end if;

  v_state := public.com_pedido_efetividade_estado(p_pedido_id);
  if coalesce((v_state->>'complete')::boolean, false) is not true then
    return v_state || jsonb_build_object('effective', false, 'idempotent_retry', false);
  end if;

  perform public.validate_com_pedido_status_transition(
    v_order.status, 'open', 'effectiveness_recognized'
  );
  v_actor := public.current_actor_id();
  v_effective_at := clock_timestamp();
  v_before := public.com_pedido_audit_snapshot(p_pedido_id);
  v_previous_effectiveness_context := current_setting('elite.effectiveness_context', true);
  perform set_config('elite.effectiveness_context', '1', true);
  begin
    update public.com_pedidos
       set status = 'open', pedido_efetivado_em = v_effective_at, updated_by = v_actor
     where id = p_pedido_id
       and status = 'blocked'
       and pedido_efetivado_em is null;
  exception when others then
    perform set_config('elite.effectiveness_context', coalesce(v_previous_effectiveness_context, ''), true);
    raise;
  end;
  perform set_config('elite.effectiveness_context', coalesce(v_previous_effectiveness_context, ''), true);
  v_after := public.com_pedido_audit_snapshot(p_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', p_pedido_id::text,
    'pedidos.pedido_efetivado', 'pedidos.effectiveness.internal',
    jsonb_build_object(
      'alcada_usada', 'pedidos.effectiveness.internal',
      'axis', 'status_transition', 'domain', 'pedidos', 'entity_type', 'com_pedidos',
      'actor_id', v_actor
    ),
    v_before, v_after,
    jsonb_build_object(
      'pedido_id', p_pedido_id,
      'pedido_efetivado_em', v_effective_at,
      'credit_decision_id', v_state->'credit_decision_id',
      'signature_evidence_id', v_state->'signature_evidence_id',
      'signature_decision_id', v_state->'signature_decision_id',
      'discount_decision_id', v_state->'discount_decision_id',
      'current_f2b_confirmation_id', v_state->'current_f2b_confirmation_id',
      'f2b_version', v_state->'current_f2b_version',
      'f2b_document_sha256', v_state->'current_f2b_document_sha256',
      'last_condition_actor_id', v_actor,
      'pending_conditions', v_state->'pending_conditions'
    ),
    'database_rpc'
  );

  return v_state || jsonb_build_object(
    'effective', true,
    'pedido_efetivado_em', v_effective_at,
    'idempotent_retry', false
  );
end;
$$;

revoke all on function public.avaliar_com_pedido_efetividade(bigint) from public, anon, authenticated;

create or replace function public.consultar_com_pedido_efetividade(p_pedido_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.can_current_user_view_order(p_pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  return public.com_pedido_efetividade_estado(p_pedido_id);
end;
$$;

revoke all on function public.consultar_com_pedido_efetividade(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_efetividade(bigint) to authenticated;

drop trigger if exists trg_com_pedido_credito_effectiveness on public.com_pedido_credito_decisoes;
drop trigger if exists trg_com_pedido_discount_effectiveness on public.com_pedido_decisoes_desconto;
drop trigger if exists trg_com_pedido_signature_effectiveness on public.com_pedido_assinatura_decisoes;

-- O credito e um fato independente: pode ser reconhecido antes de F2C.
-- A efetividade continua bloqueada pelo avaliador ate que F2C seja satisfeito.
create or replace function public.validate_com_pedido_credito_desconto_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.com_pedidos%rowtype;
begin
  if new.decisao <> 'liberado' then
    return new;
  end if;
  select * into v_pedido
    from public.com_pedidos
   where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' then
    return new;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_com_pedido_credito_desconto_gate() from public, anon, authenticated;

alter function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  rename to registrar_com_pedido_decisao_credito_impl_0135;

create or replace function public.registrar_com_pedido_decisao_credito(
  p_pedido_id bigint,
  p_decisao text,
  p_motivo text default null,
  p_limite_disponivel_snapshot numeric default null,
  p_inadimplencia_snapshot numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decisao_id bigint;
begin
  v_decisao_id := public.registrar_com_pedido_decisao_credito_impl_0135(
    p_pedido_id, p_decisao, p_motivo, p_limite_disponivel_snapshot,
    p_inadimplencia_snapshot, p_observacao
  );
  perform public.avaliar_com_pedido_efetividade(p_pedido_id);
  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  from public, anon, authenticated;
grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  to authenticated;

alter function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text)
  rename to registrar_com_pedido_decisao_desconto_idempotente_impl_0135;

create or replace function public.registrar_com_pedido_decisao_desconto_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_confirmacao_comercial_id bigint,
  p_comparacao_sha256 text,
  p_decisao text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decisao_id bigint;
begin
  v_decisao_id := public.registrar_com_pedido_decisao_desconto_idempotente_impl_0135(
    p_idempotency_key, p_pedido_id, p_confirmacao_comercial_id,
    p_comparacao_sha256, p_decisao, p_justificativa
  );
  perform public.avaliar_com_pedido_efetividade(p_pedido_id);
  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text)
  from public, anon;
grant execute on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text)
  to authenticated;

alter function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text)
  rename to decidir_com_pedido_assinatura_idempotente_impl_0135;

create or replace function public.decidir_com_pedido_assinatura_idempotente(
  p_idempotency_key uuid,
  p_evidencia_id bigint,
  p_decisao text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decisao_id bigint;
  v_pedido_id bigint;
begin
  select evidencia.pedido_id into v_pedido_id
    from public.com_pedido_assinatura_evidencias evidencia
   where evidencia.id = p_evidencia_id;
  v_decisao_id := public.decidir_com_pedido_assinatura_idempotente_impl_0135(
    p_idempotency_key, p_evidencia_id, p_decisao, p_justificativa
  );
  perform public.avaliar_com_pedido_efetividade(v_pedido_id);
  return v_decisao_id;
end;
$$;

revoke all on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text)
  from public, anon;
grant execute on function public.decidir_com_pedido_assinatura_idempotente(uuid,bigint,text,text)
  to authenticated;

comment on column public.com_pedidos.pedido_efetivado_em is
  'ORD-01: timestamp de efetividade definido uma unica vez pelo avaliador governado quando a ultima condicao da venda e reconhecida. Nunca deriva de declarado_assinado_at.';
comment on function public.avaliar_com_pedido_efetividade(bigint) is
  'ORD-01: avaliador interno fail-closed de F2B, F2A, credito, SIG01 e F2C. A efetividade e atomica, idempotente e nao retroativa.';
comment on function public.consultar_com_pedido_efetividade(bigint) is
  'ORD-01: consulta governada do estado de efetividade e das condicoes pendentes, sem alterar fatos.';
