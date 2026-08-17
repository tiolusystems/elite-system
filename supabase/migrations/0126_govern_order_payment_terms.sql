-- ORD-01 tranche 1B: governed order-level payment terms, installments and PMP.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pedidos.payment_terms.manage', 'pedidos', 'Gerenciar condicao financeira e parcelas do pedido', false, 132,
  'pedidos', 'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

alter table public.fin_pedido_planos_pagamento
  add column if not exists data_base date,
  add column if not exists valor_total_centavos bigint,
  add column if not exists pmp_dias numeric(18,6);

alter table public.fin_pedido_parcelas
  add column if not exists forma_pagamento text,
  add column if not exists valor_centavos bigint,
  add column if not exists dias_prazo integer;

alter table public.fin_pedido_planos_pagamento
  add constraint fin_pedido_planos_valor_centavos_check
  check (valor_total_centavos is null or valor_total_centavos > 0),
  add constraint fin_pedido_planos_pmp_check
  check (pmp_dias is null or pmp_dias >= 0);

alter table public.fin_pedido_parcelas
  add constraint fin_pedido_parcelas_forma_check
  check (forma_pagamento is null or forma_pagamento in ('boleto', 'pix', 'ted', 'cessao_credito')),
  add constraint fin_pedido_parcelas_centavos_check
  check (valor_centavos is null or valor_centavos > 0),
  add constraint fin_pedido_parcelas_dias_check
  check (dias_prazo is null or dias_prazo >= 0);

create table public.fin_pedido_condicao_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  plano_pagamento_id bigint not null references public.fin_pedido_planos_pagamento(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default clock_timestamp()
);

create index idx_fin_pedido_condicao_requisicoes_pedido
  on public.fin_pedido_condicao_requisicoes(pedido_id, created_at desc);

create trigger trg_fin_pedido_condicao_requisicoes_append_only
before update or delete on public.fin_pedido_condicao_requisicoes
for each row execute function public.prevent_dec009_fact_changes();

alter table public.fin_pedido_condicao_requisicoes enable row level security;
create policy "governed read order payment term requests"
  on public.fin_pedido_condicao_requisicoes for select to authenticated
  using (public.can_current_user('pedidos.payment_terms.manage'));
revoke all on table public.fin_pedido_condicao_requisicoes from public, anon, authenticated;
grant select on public.fin_pedido_condicao_requisicoes to authenticated;

create or replace function public.replace_com_pedido_condicao_financeira_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_parcelas jsonb,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_pedido_condicao_requisicoes%rowtype;
  v_pedido_valor numeric;
  v_data_pedido date;
  v_valor_esperado_centavos bigint;
  v_plano_anterior_id bigint;
  v_plano_id bigint;
  v_versao integer;
  v_parcela jsonb;
  v_parcelas_normalizadas jsonb := '[]'::jsonb;
  v_numeros integer[] := '{}'::integer[];
  v_numero integer;
  v_forma text;
  v_vencimento date;
  v_valor_centavos bigint;
  v_dias integer;
  v_total_centavos bigint := 0;
  v_peso numeric := 0;
  v_pmp_dias numeric(18,6);
begin
  v_context := public.begin_audited_rpc(
    'pedidos.payment_terms.manage', 'pedidos', 'fin_pedido_planos_pagamento',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );

  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido e obrigatorio'; end if;
  if jsonb_typeof(p_parcelas) <> 'array' or jsonb_array_length(p_parcelas) = 0
     or jsonb_array_length(p_parcelas) > 999 then
    raise exception 'parcelas devem conter entre 1 e 999 registros';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'order_payment_terms', 'pedido_id', p_pedido_id,
    'parcelas', p_parcelas, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('order_payment_terms:' || p_pedido_id::text, 0));

  select * into v_existing
    from public.fin_pedido_condicao_requisicoes
   where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash
       or v_existing.pedido_id <> p_pedido_id then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.plano_pagamento_id;
  end if;

  select pedido.valor_total, pedido.data_pedido into v_pedido_valor, v_data_pedido
    from public.com_pedidos pedido
   where pedido.id = p_pedido_id
   for share;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_data_pedido is null then raise exception 'pedido sem data de emissao'; end if;
  if v_pedido_valor <= 0 or v_pedido_valor <> round(v_pedido_valor, 2) then
    raise exception 'pedido deve possuir valor financeiro positivo em centavos';
  end if;
  v_valor_esperado_centavos := (v_pedido_valor * 100)::bigint;

  for v_parcela in select value from jsonb_array_elements(p_parcelas)
  loop
    if jsonb_typeof(v_parcela) <> 'object' then raise exception 'cada parcela deve ser um objeto'; end if;
    begin
      v_numero := nullif(v_parcela->>'numero_parcela', '')::integer;
    exception when others then
      raise exception 'numero da parcela invalido';
    end;
    if v_numero is null or v_numero < 1 or v_numero > 999 or v_numero = any(v_numeros) then
      raise exception 'numero da parcela deve ser unico entre 1 e 999';
    end if;
    v_numeros := array_append(v_numeros, v_numero);

    v_forma := lower(nullif(btrim(v_parcela->>'forma_pagamento'), ''));
    if v_forma is null or v_forma not in ('boleto', 'pix', 'ted', 'cessao_credito') then
      raise exception 'forma de pagamento invalida';
    end if;
    if coalesce(v_parcela->>'valor_centavos', '') !~ '^[0-9]+$' then
      raise exception 'valor da parcela deve ser informado em centavos inteiros';
    end if;
    begin
      v_valor_centavos := (v_parcela->>'valor_centavos')::bigint;
    exception when others then
      raise exception 'valor da parcela invalido';
    end;
    if v_valor_centavos <= 0 then raise exception 'valor da parcela deve ser maior que zero'; end if;
    if coalesce(v_parcela->>'data_vencimento', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'data de vencimento invalida';
    end if;
    begin
      v_vencimento := (v_parcela->>'data_vencimento')::date;
    exception when others then
      raise exception 'data de vencimento invalida';
    end;
    v_dias := v_vencimento - v_data_pedido;
    if v_dias < 0 then raise exception 'vencimento nao pode ser anterior a data de emissao do pedido'; end if;

    v_total_centavos := v_total_centavos + v_valor_centavos;
    v_peso := v_peso + (v_valor_centavos::numeric * v_dias::numeric);
    v_parcelas_normalizadas := v_parcelas_normalizadas || jsonb_build_array(jsonb_build_object(
      'numero_parcela', v_numero, 'forma_pagamento', v_forma, 'valor_centavos', v_valor_centavos,
      'data_vencimento', v_vencimento, 'dias_prazo', v_dias
    ));
  end loop;

  if v_total_centavos <> v_valor_esperado_centavos then
    raise exception 'soma das parcelas nao reconcilia com o valor financeiro do pedido';
  end if;
  v_pmp_dias := round(v_peso / v_total_centavos::numeric, 6);

  select plan.id into v_plano_anterior_id
    from public.fin_pedido_planos_pagamento plan
   where plan.pedido_id = p_pedido_id
     and plan.origem_dados = 'sistema'
   order by plan.versao desc, plan.id desc
   limit 1;
  select coalesce(max(plan.versao), 0) + 1 into v_versao
    from public.fin_pedido_planos_pagamento plan
   where plan.pedido_id = p_pedido_id;

  insert into public.fin_pedido_planos_pagamento(
    pedido_id, versao, vigencia_inicio, review_status, origem_dados,
    data_base, valor_total_centavos, pmp_dias, created_by
  ) values (
    p_pedido_id, v_versao, v_data_pedido, 'approved', 'sistema',
    v_data_pedido, v_total_centavos, v_pmp_dias, v_actor
  ) returning id into v_plano_id;

  insert into public.fin_pedido_parcelas(
    plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto,
    review_status, origem_dados, created_by, forma_pagamento, valor_centavos, dias_prazo
  )
  select
    v_plano_id,
    (item.value->>'numero_parcela')::integer,
    (item.value->>'data_vencimento')::date,
    ((item.value->>'valor_centavos')::bigint / 100.0),
    'approved', 'sistema', v_actor,
    item.value->>'forma_pagamento',
    (item.value->>'valor_centavos')::bigint,
    (item.value->>'dias_prazo')::integer
  from jsonb_array_elements(v_parcelas_normalizadas) item
  order by (item.value->>'numero_parcela')::integer;

  insert into public.fin_pedido_condicao_requisicoes(
    idempotency_key, pedido_id, plano_pagamento_id, actor_id, payload_hash
  ) values (
    p_idempotency_key, p_pedido_id, v_plano_id, v_actor, v_payload_hash
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'fin_pedido_planos_pagamento', v_plano_id::text,
    'pedidos.condicao_financeira_definida', 'pedidos.payment_terms.manage', v_context,
    jsonb_build_object('plano_anterior_id', v_plano_anterior_id),
    jsonb_build_object('pedido_id', p_pedido_id, 'versao', v_versao, 'data_base', v_data_pedido,
      'valor_total_centavos', v_total_centavos, 'pmp_dias', v_pmp_dias,
      'formas_pagamento', (select jsonb_agg(distinct item.value->>'forma_pagamento') from jsonb_array_elements(v_parcelas_normalizadas) item)),
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return v_plano_id;
end;
$$;

revoke all on function public.replace_com_pedido_condicao_financeira_idempotente(uuid, bigint, jsonb, text)
  from public, anon;
grant execute on function public.replace_com_pedido_condicao_financeira_idempotente(uuid, bigint, jsonb, text)
  to authenticated;

comment on function public.replace_com_pedido_condicao_financeira_idempotente(uuid, bigint, jsonb, text) is
  'ORD-01 1B: cria versao append-only da condicao financeira do pedido e calcula PMP ponderado desde com_pedidos.data_pedido.';
comment on column public.fin_pedido_planos_pagamento.pmp_dias is
  'PMP: soma(valor_centavos x dias_prazo) / soma(valor_centavos), arredondada deterministamente em seis casas decimais.';
