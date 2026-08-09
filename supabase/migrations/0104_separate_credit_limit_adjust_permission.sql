-- Credit review and permanent customer credit-limit maintenance are independent authorities.

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values (
  'financeiro.credit_limits.adjust',
  'financeiro',
  'Alterar limite de crédito de cliente',
  false,
  604,
  'financeiro',
  'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

-- Preserve the legacy catalog row and its override history, but never use it
-- as an operational grant after this migration.
update public.permission_actions
   set default_allowed = false,
       description = 'LEGADA - não utilizar: alterar limite de crédito de cliente'
 where action_key = 'pedidos.credit.limit.adjust';

create or replace function public.ajustar_com_limite_credito_cliente(
  p_cliente_id bigint,
  p_limite_novo numeric,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_current public.cad_limites_credito_cliente%rowtype;
  v_before jsonb;
  v_event_id bigint;
  v_event_type text;
  v_has_current boolean;
  v_previous_limit numeric;
  v_previous_status text;
  v_context jsonb;
begin
  perform public.require_current_user_permission('financeiro.credit_limits.adjust');

  if p_cliente_id is null or not exists (
    select 1 from public.cad_clientes client where client.id = p_cliente_id
  ) then
    raise exception 'client not found';
  end if;
  if p_limite_novo is null or p_limite_novo < 0 then
    raise exception 'new credit limit must be non-negative';
  end if;
  if char_length(trim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'justification must have at least 10 characters';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('credit_limit:' || p_cliente_id::text, 0));
  select *
    into v_current
    from public.cad_limites_credito_cliente limits
   where limits.cliente_id = p_cliente_id
   order by limits.updated_at desc, limits.id desc
   limit 1
   for update;
  v_has_current := found;

  v_actor := public.current_actor_id();
  v_context := public.begin_audited_rpc(
    'financeiro.credit_limits.adjust',
    'financeiro',
    'cad_limite_credito_eventos',
    'change_type',
    jsonb_build_object('event', 'credit_limit_adjustment')
  );

  if not v_has_current then
    v_before := null;
    v_previous_limit := null;
    v_previous_status := null;
    v_event_type := 'liberacao';

    insert into public.cad_limites_credito_cliente(
      cliente_id,
      limite_manual,
      limite_disponivel,
      status_credito,
      motivo,
      updated_by
    ) values (
      p_cliente_id,
      p_limite_novo,
      p_limite_novo,
      'liberado',
      trim(p_justificativa),
      v_actor
    )
    returning * into v_current;
  else
    v_before := to_jsonb(v_current);
    v_previous_limit := v_current.limite_disponivel;
    v_previous_status := v_current.status_credito;
    v_event_type := case
      when p_limite_novo > v_previous_limit then 'aumento'
      when p_limite_novo < v_previous_limit then 'reducao'
      else 'liberacao'
    end;

    update public.cad_limites_credito_cliente limits
       set limite_manual = p_limite_novo,
           limite_disponivel = p_limite_novo,
           status_credito = 'liberado',
           motivo = trim(p_justificativa),
           updated_by = v_actor
     where limits.id = v_current.id
    returning * into v_current;
  end if;

  insert into public.cad_limite_credito_eventos(
    limite_credito_id,
    cliente_id,
    tipo_evento,
    limite_anterior,
    limite_novo,
    status_anterior,
    status_novo,
    justificativa,
    created_by
  ) values (
    v_current.id,
    p_cliente_id,
    v_event_type,
    v_previous_limit,
    p_limite_novo,
    v_previous_status,
    'liberado',
    trim(p_justificativa),
    v_actor
  )
  returning id into v_event_id;

  perform public.log_audited_rpc_change(
    'financeiro',
    'cad_limite_credito_eventos',
    v_event_id::text,
    'financeiro.limite_credito_ajustado',
    'financeiro.credit_limits.adjust',
    v_context,
    v_before,
    to_jsonb(v_current),
    jsonb_build_object(
      'source', 'ajustar_com_limite_credito_cliente',
      'cliente_id', p_cliente_id,
      'justificativa', trim(p_justificativa)
    )
  );

  return v_event_id;
end;
$$;

create or replace function public.ajustar_com_limite_credito_cliente_idempotente(
  p_idempotency_key uuid,
  p_cliente_id bigint,
  p_limite_novo numeric,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_limite_credito_requisicoes%rowtype;
  v_event_id bigint;
begin
  perform public.require_current_user_permission('financeiro.credit_limits.adjust');
  if p_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'cliente_id', p_cliente_id,
    'limite_novo', p_limite_novo,
    'justificativa', btrim(p_justificativa)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select *
    into v_existing
    from public.fin_limite_credito_requisicoes request
   where request.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different credit limit request';
    end if;
    return v_existing.limite_credito_evento_id;
  end if;

  v_event_id := public.ajustar_com_limite_credito_cliente(
    p_cliente_id,
    p_limite_novo,
    p_justificativa
  );

  insert into public.fin_limite_credito_requisicoes(
    idempotency_key,
    limite_credito_evento_id,
    actor_id,
    payload_hash
  ) values (
    p_idempotency_key,
    v_event_id,
    v_actor,
    v_payload_hash
  );

  return v_event_id;
end;
$$;

revoke all on function public.ajustar_com_limite_credito_cliente(bigint, numeric, text)
  from public, anon, authenticated;
revoke all on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text)
  from public, anon;
grant execute on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text)
  to authenticated;

comment on table public.cad_limite_credito_eventos is
  'Historico append-only de alteracoes autorizadas no limite de credito do cliente.';
comment on table public.fin_limite_credito_requisicoes is
  'Chaves append-only para ajustes idempotentes do limite de credito do cliente.';
comment on function public.ajustar_com_limite_credito_cliente(bigint, numeric, text) is
  'Implementacao interna do ajuste financeiro de limite; sem EXECUTE para authenticated.';
comment on function public.ajustar_com_limite_credito_cliente_idempotente(uuid, bigint, numeric, text) is
  'Entrada governada por alcada financeira individual. Uma chave cria no maximo um evento auditado.';
