-- ORD-01 F2A: immutable practiced-price facts and commercial comparison for blocked sale orders.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.practiced_price.record', 'pedidos', 'Registrar preco praticado dos itens do pedido', false, 135, 'pedidos', 'write'),
  ('pedidos.commercial_comparison.view', 'pedidos', 'Consultar comparacao comercial do pedido', false, 136, 'pedidos', 'read')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_pedido_item_precos_praticados (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  pedido_item_id bigint not null references public.com_pedido_itens(id) on delete restrict,
  referencia_comercial_id bigint not null references public.com_pedido_item_referencias_comerciais(id) on delete restrict,
  unidade_precificacao_id bigint not null references public.cad_unidades_medida(id) on delete restrict,
  quantidade_apresentacoes numeric not null check (quantidade_apresentacoes > 0),
  quantidade_unidade_precificacao_por_apresentacao numeric not null
    check (quantidade_unidade_precificacao_por_apresentacao > 0),
  quantidade_unidade_precificacao numeric not null check (quantidade_unidade_precificacao > 0),
  preco_referencia_centavos_por_unidade_precificacao bigint not null
    check (preco_referencia_centavos_por_unidade_precificacao > 0),
  preco_praticado_centavos_por_unidade_precificacao bigint not null
    check (preco_praticado_centavos_por_unidade_precificacao > 0),
  diferenca_centavos_por_unidade_precificacao bigint not null,
  percentual_diferenca numeric(18,6) not null,
  valor_referencia_centavos bigint not null check (valor_referencia_centavos > 0),
  valor_praticado_centavos bigint not null check (valor_praticado_centavos > 0),
  impacto_financeiro_centavos bigint not null,
  classificacao text not null check (classificacao in ('BELOW_REFERENCE', 'AT_REFERENCE', 'ABOVE_REFERENCE')),
  motivo text not null check (length(btrim(motivo)) >= 10),
  recorded_by uuid not null references public.user_profiles(id) on delete restrict,
  recorded_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_item_precos_praticados_item_key unique (pedido_item_id),
  constraint com_pedido_item_precos_praticados_referencia_key unique (referencia_comercial_id),
  constraint com_pedido_item_precos_praticados_pedido_item_key unique (pedido_id, pedido_item_id),
  constraint com_pedido_item_precos_praticados_quantidade_check check (
    quantidade_unidade_precificacao = quantidade_apresentacoes * quantidade_unidade_precificacao_por_apresentacao
  ),
  constraint com_pedido_item_precos_praticados_diferenca_check check (
    diferenca_centavos_por_unidade_precificacao =
      preco_praticado_centavos_por_unidade_precificacao - preco_referencia_centavos_por_unidade_precificacao
  ),
  constraint com_pedido_item_precos_praticados_percentual_check check (
    percentual_diferenca = round(
      diferenca_centavos_por_unidade_precificacao::numeric * 100
      / preco_referencia_centavos_por_unidade_precificacao::numeric,
      6
    )
  ),
  constraint com_pedido_item_precos_praticados_referencia_valor_check check (
    valor_referencia_centavos = round(
      quantidade_unidade_precificacao * preco_referencia_centavos_por_unidade_precificacao::numeric,
      0
    )::bigint
  ),
  constraint com_pedido_item_precos_praticados_praticado_valor_check check (
    valor_praticado_centavos = round(
      quantidade_unidade_precificacao * preco_praticado_centavos_por_unidade_precificacao::numeric,
      0
    )::bigint
  ),
  constraint com_pedido_item_precos_praticados_impacto_check check (
    impacto_financeiro_centavos = valor_praticado_centavos - valor_referencia_centavos
  ),
  constraint com_pedido_item_precos_praticados_classificacao_derivada_check check (
    classificacao = case
      when preco_praticado_centavos_por_unidade_precificacao < preco_referencia_centavos_por_unidade_precificacao then 'BELOW_REFERENCE'
      when preco_praticado_centavos_por_unidade_precificacao = preco_referencia_centavos_por_unidade_precificacao then 'AT_REFERENCE'
      else 'ABOVE_REFERENCE'
    end
  )
);

create index idx_com_pedido_item_precos_praticados_pedido
  on public.com_pedido_item_precos_praticados(pedido_id, pedido_item_id);

create table public.com_pedido_preco_praticado_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default clock_timestamp()
);

create index idx_com_pedido_preco_praticado_requisicoes_pedido
  on public.com_pedido_preco_praticado_requisicoes(pedido_id, created_at desc);

create or replace function public.validate_com_pedido_item_preco_praticado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_snapshot public.com_pedido_item_referencias_comerciais%rowtype;
  v_item public.com_pedido_itens%rowtype;
  v_pedido public.com_pedidos%rowtype;
  v_classificacao text;
begin
  select * into v_snapshot
    from public.com_pedido_item_referencias_comerciais snapshot
   where snapshot.id = new.referencia_comercial_id;
  if not found then raise exception 'referencia comercial congelada nao encontrada'; end if;
  select * into v_item from public.com_pedido_itens item where item.id = new.pedido_item_id;
  if not found then raise exception 'item do pedido nao encontrado'; end if;
  select * into v_pedido from public.com_pedidos pedido where pedido.id = new.pedido_id;
  if not found then raise exception 'pedido nao encontrado'; end if;

  if v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'preco praticado exige pedido de venda bloqueado';
  end if;
  if v_item.pedido_id <> new.pedido_id or v_item.status <> 'active' or v_item.tipo_item <> 'venda' then
    raise exception 'preco praticado exige item de venda ativo do pedido';
  end if;
  if v_snapshot.pedido_id is distinct from v_pedido.id
     or v_snapshot.pedido_item_id is distinct from v_item.id
     or v_snapshot.produto_embalagem_id is distinct from v_item.produto_embalagem_id
     or v_snapshot.cliente_id is distinct from v_pedido.cliente_id
     or v_snapshot.data_comercial is distinct from v_pedido.data_pedido
     or v_snapshot.origem_comercial_id is distinct from v_pedido.origem_comercial_id then
    raise exception 'referencia comercial congelada diverge da identidade material do pedido';
  end if;
  if v_snapshot.unidade_precificacao_id is null
     or v_snapshot.quantidade_unidade_precificacao_por_apresentacao is null
     or v_snapshot.quantidade_unidade_precificacao_por_apresentacao <= 0
     or v_snapshot.preco_referencia_centavos_por_unidade_precificacao is null
     or v_snapshot.preco_referencia_centavos_por_unidade_precificacao <= 0 then
    raise exception 'referencia comercial nao possui unidade, fator e preco genericos congelados';
  end if;
  if new.unidade_precificacao_id is distinct from v_snapshot.unidade_precificacao_id
     or new.quantidade_apresentacoes is distinct from v_item.quantidade
     or new.quantidade_unidade_precificacao_por_apresentacao is distinct from v_snapshot.quantidade_unidade_precificacao_por_apresentacao
     or new.preco_referencia_centavos_por_unidade_precificacao is distinct from v_snapshot.preco_referencia_centavos_por_unidade_precificacao then
    raise exception 'fato de preco praticado diverge do item ou da referencia comercial congelada';
  end if;
  if new.preco_praticado_centavos_por_unidade_precificacao <= 0 then
    raise exception 'preco praticado de venda deve ser maior que zero';
  end if;
  if new.quantidade_unidade_precificacao is distinct from new.quantidade_apresentacoes * new.quantidade_unidade_precificacao_por_apresentacao
     or new.diferenca_centavos_por_unidade_precificacao is distinct from new.preco_praticado_centavos_por_unidade_precificacao - new.preco_referencia_centavos_por_unidade_precificacao
     or new.percentual_diferenca is distinct from round(new.diferenca_centavos_por_unidade_precificacao::numeric * 100 / new.preco_referencia_centavos_por_unidade_precificacao::numeric, 6)
     or new.valor_referencia_centavos is distinct from round(new.quantidade_unidade_precificacao * new.preco_referencia_centavos_por_unidade_precificacao::numeric, 0)::bigint
     or new.valor_praticado_centavos is distinct from round(new.quantidade_unidade_precificacao * new.preco_praticado_centavos_por_unidade_precificacao::numeric, 0)::bigint
     or new.impacto_financeiro_centavos is distinct from new.valor_praticado_centavos - new.valor_referencia_centavos then
    raise exception 'fato de preco praticado possui calculo inconsistente';
  end if;
  v_classificacao := case
    when new.preco_praticado_centavos_por_unidade_precificacao < new.preco_referencia_centavos_por_unidade_precificacao then 'BELOW_REFERENCE'
    when new.preco_praticado_centavos_por_unidade_precificacao = new.preco_referencia_centavos_por_unidade_precificacao then 'AT_REFERENCE'
    else 'ABOVE_REFERENCE'
  end;
  if new.classificacao is distinct from v_classificacao then raise exception 'classificacao do preco praticado e inconsistente'; end if;
  return new;
end;
$$;

revoke all on function public.validate_com_pedido_item_preco_praticado() from public, anon, authenticated;

create trigger trg_com_pedido_item_precos_praticados_validate
before insert on public.com_pedido_item_precos_praticados
for each row execute function public.validate_com_pedido_item_preco_praticado();

create trigger trg_com_pedido_item_precos_praticados_append_only
before update or delete on public.com_pedido_item_precos_praticados
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_item_precos_praticados_no_truncate
before truncate on public.com_pedido_item_precos_praticados
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_preco_praticado_requisicoes_append_only
before update or delete on public.com_pedido_preco_praticado_requisicoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_preco_praticado_requisicoes_no_truncate
before truncate on public.com_pedido_preco_praticado_requisicoes
for each statement execute function public.prevent_dec009_fact_changes();

alter table public.com_pedido_item_precos_praticados enable row level security;
alter table public.com_pedido_preco_praticado_requisicoes enable row level security;

create policy "governed read practiced order prices"
  on public.com_pedido_item_precos_praticados for select to authenticated
  using (
    public.can_current_user('pedidos.commercial_comparison.view')
    and public.can_current_user_view_order(pedido_id)
  );
revoke all on table public.com_pedido_item_precos_praticados from public, anon, authenticated;
revoke all on table public.com_pedido_preco_praticado_requisicoes from public, anon, authenticated;
grant select on public.com_pedido_item_precos_praticados to authenticated;

create or replace function public.com_pedido_comparacao_comercial_documento(p_pedido_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with itens as (
    select
      fact.*,
      unidade.codigo as unidade_precificacao_codigo,
      unidade.simbolo as unidade_precificacao_simbolo
    from public.com_pedido_item_precos_praticados fact
    join public.cad_unidades_medida unidade on unidade.id = fact.unidade_precificacao_id
    where fact.pedido_id = p_pedido_id
  ), totais as (
    select
      coalesce(sum(valor_referencia_centavos), 0)::bigint as total_referencia_centavos,
      coalesce(sum(valor_praticado_centavos), 0)::bigint as total_praticado_centavos,
      coalesce(sum(abs(impacto_financeiro_centavos)) filter (where impacto_financeiro_centavos < 0), 0)::bigint as descontos_brutos_centavos,
      coalesce(sum(impacto_financeiro_centavos) filter (where impacto_financeiro_centavos > 0), 0)::bigint as overprice_bruto_centavos,
      coalesce(sum(impacto_financeiro_centavos), 0)::bigint as resultado_liquido_centavos
    from itens
  )
  select jsonb_build_object(
    'pedido_id', p_pedido_id,
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_item_id', item.pedido_item_id,
        'referencia_comercial_id', item.referencia_comercial_id,
        'unidade_precificacao_id', item.unidade_precificacao_id,
        'unidade_precificacao_codigo', item.unidade_precificacao_codigo,
        'unidade_precificacao_simbolo', item.unidade_precificacao_simbolo,
        'quantidade_apresentacoes', item.quantidade_apresentacoes,
        'quantidade_unidade_precificacao_por_apresentacao', item.quantidade_unidade_precificacao_por_apresentacao,
        'quantidade_unidade_precificacao', item.quantidade_unidade_precificacao,
        'preco_referencia_centavos_por_unidade_precificacao', item.preco_referencia_centavos_por_unidade_precificacao,
        'preco_praticado_centavos_por_unidade_precificacao', item.preco_praticado_centavos_por_unidade_precificacao,
        'diferenca_centavos_por_unidade_precificacao', item.diferenca_centavos_por_unidade_precificacao,
        'percentual_diferenca', item.percentual_diferenca,
        'valor_referencia_centavos', item.valor_referencia_centavos,
        'valor_praticado_centavos', item.valor_praticado_centavos,
        'impacto_financeiro_centavos', item.impacto_financeiro_centavos,
        'classificacao', item.classificacao
      ) order by item.pedido_item_id)
      from itens item
    ), '[]'::jsonb),
    'totais', jsonb_build_object(
      'total_referencia_centavos', totais.total_referencia_centavos,
      'total_praticado_centavos', totais.total_praticado_centavos,
      'descontos_brutos_centavos', totais.descontos_brutos_centavos,
      'overprice_bruto_centavos', totais.overprice_bruto_centavos,
      'resultado_liquido_centavos', totais.resultado_liquido_centavos,
      'percentual_resultado_liquido', case
        when totais.total_referencia_centavos > 0 then round(
          totais.resultado_liquido_centavos::numeric * 100 / totais.total_referencia_centavos::numeric,
          6
        )
        else null
      end
    )
  )
  from totais;
$$;

revoke all on function public.com_pedido_comparacao_comercial_documento(bigint) from public, anon, authenticated;

create or replace function public.consultar_com_comparacao_comercial_pedido(p_pedido_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.commercial_comparison.view');
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido e obrigatorio'; end if;
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  if not exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_id = p_pedido_id) then
    raise exception 'pedido nao possui preco praticado congelado';
  end if;
  if exists (
    select 1
      from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id
       and item.status = 'active'
       and not exists (
         select 1 from public.com_pedido_item_precos_praticados fact
          where fact.pedido_item_id = item.id
       )
  ) then
    raise exception 'comparacao comercial exige revisao governada do pedido';
  end if;
  return public.com_pedido_comparacao_comercial_documento(p_pedido_id);
end;
$$;

revoke all on function public.consultar_com_comparacao_comercial_pedido(bigint) from public, anon;
grant execute on function public.consultar_com_comparacao_comercial_pedido(bigint) to authenticated;

create or replace function public.registrar_com_precos_praticados_pedido_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_itens jsonb,
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
  v_existing public.com_pedido_preco_praticado_requisicoes%rowtype;
  v_pedido public.com_pedidos%rowtype;
  v_item jsonb;
  v_item_id bigint;
  v_preco_praticado bigint;
  v_payload_ids bigint[] := '{}'::bigint[];
  v_pedido_item_ids bigint[] := '{}'::bigint[];
  v_itens_normalizados jsonb := '[]'::jsonb;
  v_item_order record;
  v_quantidade_comercial numeric;
  v_diferenca bigint;
  v_percentual numeric(18,6);
  v_valor_referencia bigint;
  v_valor_praticado bigint;
  v_impacto bigint;
  v_classificacao text;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.practiced_price.record', 'pedidos', 'com_pedido_item_precos_praticados',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido e obrigatorio'; end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 or jsonb_array_length(p_itens) > 100 then
    raise exception 'itens devem conter entre 1 e 100 registros';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'cada preco praticado deve ser um objeto'; end if;
    if coalesce(v_item->>'pedido_item_id', '') !~ '^[1-9][0-9]*$' then raise exception 'item do pedido invalido'; end if;
    if coalesce(v_item->>'preco_praticado_centavos_por_unidade_precificacao', '') !~ '^[1-9][0-9]*$' then
      raise exception 'preco praticado de venda deve ser maior que zero em centavos inteiros';
    end if;
    begin
      v_item_id := (v_item->>'pedido_item_id')::bigint;
      v_preco_praticado := (v_item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint;
    exception when others then
      raise exception 'item ou preco praticado fora da faixa permitida';
    end;
    if v_item_id = any(v_payload_ids) then raise exception 'item do pedido informado mais de uma vez'; end if;
    v_payload_ids := array_append(v_payload_ids, v_item_id);
    v_itens_normalizados := v_itens_normalizados || jsonb_build_array(jsonb_build_object(
      'pedido_item_id', v_item_id,
      'preco_praticado_centavos_por_unidade_precificacao', v_preco_praticado
    ));
  end loop;

  select coalesce(jsonb_agg(item.value order by (item.value->>'pedido_item_id')::bigint), '[]'::jsonb)
    into v_itens_normalizados
    from jsonb_array_elements(v_itens_normalizados) item;
  select coalesce(array_agg((item.value->>'pedido_item_id')::bigint order by (item.value->>'pedido_item_id')::bigint), '{}'::bigint[])
    into v_payload_ids
    from jsonb_array_elements(v_itens_normalizados) item;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'order_practiced_prices', 'pedido_id', p_pedido_id,
    'itens', v_itens_normalizados, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('order_practiced_prices:' || p_pedido_id::text, 0));

  select * into v_existing
    from public.com_pedido_preco_praticado_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.pedido_id <> p_pedido_id
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.pedido_id;
  end if;

  select * into v_pedido from public.com_pedidos pedido where pedido.id = p_pedido_id for update;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'preco praticado exige pedido de venda bloqueado';
  end if;
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  if exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_id = p_pedido_id) then
    raise exception 'pedido ja possui preco praticado imutavel';
  end if;

  perform 1
    from public.com_pedido_itens item
   where item.pedido_id = p_pedido_id and item.status = 'active'
   for update;
  select coalesce(array_agg(item.id order by item.id), '{}'::bigint[])
    into v_pedido_item_ids
    from public.com_pedido_itens item
   where item.pedido_id = p_pedido_id and item.status = 'active';
  if cardinality(v_pedido_item_ids) = 0 then raise exception 'pedido nao possui itens ativos'; end if;
  if v_payload_ids is distinct from v_pedido_item_ids then
    raise exception 'precos praticados devem informar exatamente todos os itens ativos do pedido';
  end if;
  if exists (
    select 1 from public.com_pedido_itens item
     where item.id = any(v_pedido_item_ids) and item.tipo_item <> 'venda'
  ) then raise exception 'preco praticado exige somente itens de venda'; end if;
  if exists (
    select 1
      from public.com_pedido_itens item
      left join public.com_pedido_item_referencias_comerciais snapshot on snapshot.pedido_item_id = item.id
     where item.id = any(v_pedido_item_ids)
       and (
         snapshot.id is null
         or snapshot.pedido_id is distinct from v_pedido.id
         or snapshot.pedido_item_id is distinct from item.id
         or snapshot.produto_embalagem_id is distinct from item.produto_embalagem_id
         or snapshot.cliente_id is distinct from v_pedido.cliente_id
         or snapshot.data_comercial is distinct from v_pedido.data_pedido
         or snapshot.origem_comercial_id is distinct from v_pedido.origem_comercial_id
         or snapshot.unidade_precificacao_id is null
         or snapshot.quantidade_unidade_precificacao_por_apresentacao is null
         or snapshot.quantidade_unidade_precificacao_por_apresentacao <= 0
         or snapshot.preco_referencia_centavos_por_unidade_precificacao is null
         or snapshot.preco_referencia_centavos_por_unidade_precificacao <= 0
       )
  ) then raise exception 'todos os itens de venda exigem referencia comercial generica congelada e materialmente coerente'; end if;

  for v_item_order in
    select
      item.id as pedido_item_id,
      item.quantidade,
      snapshot.id as referencia_comercial_id,
      snapshot.unidade_precificacao_id,
      snapshot.quantidade_unidade_precificacao_por_apresentacao,
      snapshot.preco_referencia_centavos_por_unidade_precificacao,
      payload.value as payload
    from public.com_pedido_itens item
    join public.com_pedido_item_referencias_comerciais snapshot on snapshot.pedido_item_id = item.id
    join lateral jsonb_array_elements(v_itens_normalizados) payload(value)
      on (payload.value->>'pedido_item_id')::bigint = item.id
    where item.id = any(v_pedido_item_ids)
    order by item.id
  loop
    v_preco_praticado := (v_item_order.payload->>'preco_praticado_centavos_por_unidade_precificacao')::bigint;
    v_quantidade_comercial := v_item_order.quantidade * v_item_order.quantidade_unidade_precificacao_por_apresentacao;
    v_diferenca := v_preco_praticado - v_item_order.preco_referencia_centavos_por_unidade_precificacao;
    v_percentual := round(v_diferenca::numeric * 100 / v_item_order.preco_referencia_centavos_por_unidade_precificacao::numeric, 6);
    v_valor_referencia := round(v_quantidade_comercial * v_item_order.preco_referencia_centavos_por_unidade_precificacao::numeric, 0)::bigint;
    v_valor_praticado := round(v_quantidade_comercial * v_preco_praticado::numeric, 0)::bigint;
    v_impacto := v_valor_praticado - v_valor_referencia;
    v_classificacao := case when v_diferenca < 0 then 'BELOW_REFERENCE' when v_diferenca = 0 then 'AT_REFERENCE' else 'ABOVE_REFERENCE' end;
    if v_valor_referencia <= 0 or v_valor_praticado <= 0 then
      raise exception 'quantidade comercial nao produz valor economico positivo em centavos';
    end if;
    insert into public.com_pedido_item_precos_praticados(
      pedido_id, pedido_item_id, referencia_comercial_id, unidade_precificacao_id,
      quantidade_apresentacoes, quantidade_unidade_precificacao_por_apresentacao, quantidade_unidade_precificacao,
      preco_referencia_centavos_por_unidade_precificacao, preco_praticado_centavos_por_unidade_precificacao,
      diferenca_centavos_por_unidade_precificacao, percentual_diferenca,
      valor_referencia_centavos, valor_praticado_centavos, impacto_financeiro_centavos, classificacao,
      motivo, recorded_by
    ) values (
      p_pedido_id, v_item_order.pedido_item_id, v_item_order.referencia_comercial_id, v_item_order.unidade_precificacao_id,
      v_item_order.quantidade, v_item_order.quantidade_unidade_precificacao_por_apresentacao, v_quantidade_comercial,
      v_item_order.preco_referencia_centavos_por_unidade_precificacao, v_preco_praticado,
      v_diferenca, v_percentual, v_valor_referencia, v_valor_praticado, v_impacto, v_classificacao,
      btrim(p_motivo), v_actor
    );
  end loop;

  insert into public.com_pedido_preco_praticado_requisicoes(idempotency_key, pedido_id, actor_id, payload_hash)
  values (p_idempotency_key, p_pedido_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_item_precos_praticados', p_pedido_id::text,
    'pedidos.preco_praticado_congelado', 'pedidos.practiced_price.record', v_context,
    null, public.com_pedido_comparacao_comercial_documento(p_pedido_id),
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_pedido_id;
end;
$$;

revoke all on function public.registrar_com_precos_praticados_pedido_idempotente(uuid, bigint, jsonb, text)
  from public, anon;
grant execute on function public.registrar_com_precos_praticados_pedido_idempotente(uuid, bigint, jsonb, text)
  to authenticated;

comment on table public.com_pedido_item_precos_praticados is
  'ORD-01 F2A: fatos append-only do preco praticado por item de venda, comparados a referencia comercial generica congelada.';
comment on function public.registrar_com_precos_praticados_pedido_idempotente(uuid, bigint, jsonb, text) is
  'ORD-01 F2A: registra atomicamente preco praticado positivo em centavos por unidade comercial para todos os itens ativos de pedido de venda bloqueado.';
comment on function public.consultar_com_comparacao_comercial_pedido(bigint) is
  'ORD-01 F2A: consulta comparacao por item e totais comerciais derivados de fatos append-only.';
