-- ORD-01: governed order revisions and contractual addenda.
-- This migration does not rewrite 0124..0135 and does not alter logistics.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.effectiveness.internal', 'pedidos', 'Registro interno da efetivacao governada do pedido', false, 144, 'pedidos', 'write'),
  ('pedidos.revision.request', 'pedidos', 'Solicitar revisao material ou aditivo contratual do pedido', false, 145, 'pedidos', 'write'),
  ('pedidos.revision.view', 'pedidos', 'Consultar historico de revisoes e aditivos do pedido', false, 146, 'pedidos', 'read'),
  ('pedidos.revision.effectuate', 'pedidos', 'Efetivar aditivo contratual com gates governados', false, 147, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_pedido_contrato_geneses (
  id bigint generated always as identity primary key,
  pedido_id bigint not null unique references public.com_pedidos(id) on delete restrict,
  sequence integer not null default 0 check (sequence = 0),
  effective_f2b_confirmation_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  effective_f2b_document_sha256 text not null check (effective_f2b_document_sha256 ~ '^[0-9a-f]{64}$'),
  f2a_fact_ids bigint[] not null,
  commercial_reference_ids bigint[] not null,
  financial_plan_id bigint references public.fin_pedido_planos_pagamento(id) on delete restrict,
  credit_decision_id bigint,
  signature_evidence_id bigint,
  signature_decision_id bigint,
  discount_decision_id bigint,
  effectiveness_audit_log_id bigint not null references public.action_logs(id) on delete restrict,
  effective_actor_id uuid not null references public.user_profiles(id) on delete restrict,
  pedido_efetivado_em timestamptz not null,
  contract_state_json jsonb not null,
  contract_state_sha256 text not null check (contract_state_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_contrato_geneses_json_check check (jsonb_typeof(contract_state_json) = 'object')
);

create table public.com_pedido_revisoes_governadas (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  tipo text not null check (tipo in ('pre_efetivacao', 'aditivo')),
  sequence integer not null check (sequence > 0),
  base_f2b_confirmation_id bigint references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  base_sequence integer not null check (base_sequence >= 0),
  base_contract_state_sha256 text not null check (base_contract_state_sha256 ~ '^[0-9a-f]{64}$'),
  delta_json jsonb not null,
  delta_sha256 text not null check (delta_sha256 ~ '^[0-9a-f]{64}$'),
  resulting_contract_state_json jsonb not null,
  resulting_contract_state_sha256 text not null check (resulting_contract_state_sha256 ~ '^[0-9a-f]{64}$'),
  impact_mask text[] not null,
  idempotency_key uuid not null,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_revisoes_tipo_base_check check (
    (tipo = 'pre_efetivacao' and base_sequence >= 0)
    or (tipo = 'aditivo' and base_sequence >= 0)
  ),
  constraint com_pedido_revisoes_json_check check (
    jsonb_typeof(delta_json) = 'object' and jsonb_typeof(resulting_contract_state_json) = 'object'
  ),
  constraint com_pedido_revisoes_impact_check check (
    impact_mask <@ array['pricing','discount','financial','buyer_signature','commercial_resolution']::text[]
  ),
  constraint com_pedido_revisoes_idempotency_key unique (idempotency_key),
  constraint com_pedido_revisoes_order_sequence unique (pedido_id, sequence)
);

create index idx_com_pedido_revisoes_pedido
  on public.com_pedido_revisoes_governadas(pedido_id, sequence desc);

create table public.com_pedido_revisao_eventos (
  id bigint generated always as identity primary key,
  revisao_id bigint not null references public.com_pedido_revisoes_governadas(id) on delete restrict,
  evento text not null check (evento in ('requested','pending','rejected','effective')),
  idempotency_key uuid unique,
  payload_hash text check (payload_hash is null or payload_hash ~ '^[0-9a-f]{64}$'),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_revisao_eventos_json_check check (jsonb_typeof(payload_json) = 'object')
);

-- The original order item remains immutable lineage.  A governed revision owns
-- its resulting commercial item state instead of reusing mutable/legacy fields.
create table public.com_pedido_revisao_itens (
  id bigint generated always as identity primary key,
  revisao_id bigint not null references public.com_pedido_revisoes_governadas(id) on delete restrict,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  pedido_item_origem_id bigint not null references public.com_pedido_itens(id) on delete restrict,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  quantidade_apresentacoes numeric not null check (quantidade_apresentacoes > 0),
  unidade_precificacao_id bigint not null references public.cad_unidades_medida(id) on delete restrict,
  quantidade_unidade_precificacao_por_apresentacao numeric not null
    check (quantidade_unidade_precificacao_por_apresentacao > 0),
  quantidade_unidade_precificacao numeric not null check (quantidade_unidade_precificacao > 0),
  estado_item_json jsonb not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_revisao_itens_quantidade_check check (
    quantidade_unidade_precificacao = quantidade_apresentacoes * quantidade_unidade_precificacao_por_apresentacao
  ),
  constraint com_pedido_revisao_itens_estado_check check (jsonb_typeof(estado_item_json) = 'object'),
  constraint com_pedido_revisao_itens_revision_origin_key unique (revisao_id, pedido_item_origem_id)
);

-- Internal index of the exact derived facts.  It is the only version-aware
-- source for pre-effectiveness materialization and genesis after that version opens.
create table public.com_pedido_revisao_materializacoes (
  revisao_id bigint primary key references public.com_pedido_revisoes_governadas(id) on delete restrict,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  plano_pagamento_id bigint not null references public.fin_pedido_planos_pagamento(id) on delete restrict,
  confirmacao_comercial_id bigint not null unique references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  revisao_item_ids bigint[] not null,
  referencia_comercial_ids bigint[] not null,
  preco_praticado_ids bigint[] not null,
  materialized_by uuid not null references public.user_profiles(id) on delete restrict,
  materialized_at timestamptz not null default clock_timestamp()
);

  create index idx_com_pedido_revisao_eventos_revisao
  on public.com_pedido_revisao_eventos(revisao_id, created_at, id);

alter table public.com_pedido_revisoes_governadas
  add column if not exists base_event_id bigint references public.com_pedido_revisao_eventos(id) on delete restrict;

alter table public.com_pedido_confirmacoes_comerciais
  add column if not exists revisao_id bigint references public.com_pedido_revisoes_governadas(id) on delete restrict;
alter table public.fin_pedido_planos_pagamento
  add column if not exists revisao_id bigint references public.com_pedido_revisoes_governadas(id) on delete restrict;
alter table public.com_pedido_item_referencias_comerciais
  add column if not exists revisao_id bigint references public.com_pedido_revisoes_governadas(id) on delete restrict;
alter table public.com_pedido_item_precos_praticados
  add column if not exists revisao_id bigint references public.com_pedido_revisoes_governadas(id) on delete restrict;
alter table public.com_pedido_item_referencias_comerciais
  add column if not exists revisao_item_id bigint references public.com_pedido_revisao_itens(id) on delete restrict;
alter table public.com_pedido_item_precos_praticados
  add column if not exists revisao_item_id bigint references public.com_pedido_revisao_itens(id) on delete restrict;

alter table public.com_pedido_item_referencias_comerciais
  add constraint com_pedido_item_referencias_revision_item_pair_check check (
    (revisao_id is null and revisao_item_id is null)
    or (revisao_id is not null and revisao_item_id is not null)
  );
alter table public.com_pedido_item_precos_praticados
  add constraint com_pedido_item_precos_revision_item_pair_check check (
    (revisao_id is null and revisao_item_id is null)
    or (revisao_id is not null and revisao_item_id is not null)
  );

alter table public.com_pedido_item_referencias_comerciais
  drop constraint if exists com_pedido_item_referencias_item_key,
  drop constraint if exists com_pedido_item_referencias_pedido_item_key;
alter table public.com_pedido_item_precos_praticados
  drop constraint if exists com_pedido_item_precos_praticados_item_key,
  drop constraint if exists com_pedido_item_precos_praticados_referencia_key,
  drop constraint if exists com_pedido_item_precos_praticados_pedido_item_key;

create unique index if not exists com_pedido_item_referencias_version_key
  on public.com_pedido_item_referencias_comerciais(pedido_item_id, coalesce(revisao_id, 0));
create unique index if not exists com_pedido_item_precos_version_key
  on public.com_pedido_item_precos_praticados(pedido_item_id, coalesce(revisao_id, 0));
create unique index if not exists com_pedido_item_precos_reference_version_key
  on public.com_pedido_item_precos_praticados(referencia_comercial_id, coalesce(revisao_id, 0));
create unique index if not exists com_pedido_item_referencias_revision_item_key
  on public.com_pedido_item_referencias_comerciais(revisao_item_id)
  where revisao_item_id is not null;
create unique index if not exists com_pedido_item_precos_revision_item_key
  on public.com_pedido_item_precos_praticados(revisao_item_id)
  where revisao_item_id is not null;

alter table public.com_pedido_contrato_geneses enable row level security;
alter table public.com_pedido_revisoes_governadas enable row level security;
alter table public.com_pedido_revisao_eventos enable row level security;
alter table public.com_pedido_revisao_itens enable row level security;
alter table public.com_pedido_revisao_materializacoes enable row level security;

revoke all on public.com_pedido_contrato_geneses from public, anon, authenticated;
revoke all on public.com_pedido_revisoes_governadas from public, anon, authenticated;
revoke all on public.com_pedido_revisao_eventos from public, anon, authenticated;
revoke all on public.com_pedido_revisao_itens from public, anon, authenticated;
revoke all on public.com_pedido_revisao_materializacoes from public, anon, authenticated;

create or replace function public.validate_com_pedido_revision_append_only()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'fato de revisao contratual e append-only';
end;
$$;

revoke all on function public.validate_com_pedido_revision_append_only() from public, anon, authenticated;

create trigger trg_com_pedido_contrato_geneses_append_only
before update or delete on public.com_pedido_contrato_geneses
for each row execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_contrato_geneses_no_truncate
before truncate on public.com_pedido_contrato_geneses
for each statement execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisoes_append_only
before update or delete on public.com_pedido_revisoes_governadas
for each row execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisoes_no_truncate
before truncate on public.com_pedido_revisoes_governadas
for each statement execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisao_eventos_append_only
before update or delete on public.com_pedido_revisao_eventos
for each row execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisao_eventos_no_truncate
before truncate on public.com_pedido_revisao_eventos
for each statement execute function public.validate_com_pedido_revision_append_only();

create or replace function public.ord01_revision_hash(p_document jsonb)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(convert_to(p_document::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function public.ord01_apply_com_pedido_contract_delta(p_base jsonb, p_delta jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_key text;
  v_result jsonb;
  v_allowed constant text[] := array[
    'f2b_document','f2a_comparison','financial_condition','condicao_financeira',
    'commercial_context','contexto_comercial','obrigacoes_contratuais',
    'itens','pricing','discount','financial','buyer_signature','commercial_resolution'
  ];
begin
  if jsonb_typeof(p_base) <> 'object' or jsonb_typeof(p_delta) <> 'object' then
    raise exception 'estado e delta contratuais devem ser objetos';
  end if;
  foreach v_key in array array['schema_version','pedido_id','f2b_document','f2a_comparison','financial_condition'] loop
    if not (p_base ? v_key) then
      raise exception 'estado contratual base incompleto: %', v_key;
    end if;
  end loop;
  if jsonb_typeof(p_base->'f2b_document') <> 'object'
     or jsonb_typeof(p_base->'f2a_comparison') <> 'object'
     or jsonb_typeof(p_base->'f2a_comparison'->'itens') <> 'array'
     or jsonb_typeof(p_base->'f2a_comparison'->'totais') <> 'object'
     or jsonb_typeof(p_base->'financial_condition') <> 'object'
     or jsonb_typeof(p_base->'financial_condition'->'parcelas') <> 'array'
     or p_base->>'pedido_id' is null then
    raise exception 'estado contratual base possui secoes obrigatorias invalidas';
  end if;
  for v_key in select key from jsonb_object_keys(p_delta) key
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'campo de delta contratual nao governado: %', v_key;
    end if;
    if p_delta->v_key is null or p_delta->v_key = 'null'::jsonb then
      raise exception 'campo de delta contratual nulo: %', v_key;
    end if;
  end loop;
  if (p_delta ? 'financial_condition') and (p_delta ? 'condicao_financeira') then
    raise exception 'delta possui aliases financeiros conflitantes';
  end if;
  if (p_delta ? 'commercial_context') and (p_delta ? 'contexto_comercial') then
    raise exception 'delta possui aliases comerciais conflitantes';
  end if;
  v_result := p_base || p_delta;
  if v_result = p_base then
    raise exception 'delta de revisao sem efeito material';
  end if;
  if (v_result ? 'financial_condition') and (v_result ? 'condicao_financeira') then
    raise exception 'resultado possui aliases financeiros conflitantes';
  end if;
  if (v_result ? 'commercial_context') and (v_result ? 'contexto_comercial') then
    raise exception 'resultado possui aliases comerciais conflitantes';
  end if;
  if jsonb_typeof(v_result->'f2b_document') <> 'object'
     or jsonb_typeof(v_result->'f2a_comparison') <> 'object'
     or jsonb_typeof(v_result->'f2a_comparison'->'itens') <> 'array'
     or jsonb_typeof(v_result->'f2a_comparison'->'totais') <> 'object'
     or jsonb_typeof(v_result->'financial_condition') <> 'object'
     or jsonb_typeof(v_result->'financial_condition'->'parcelas') <> 'array'
     or v_result->>'pedido_id' is null
     or v_result ? 'pending_revision_delta'
     or v_result ? 'pending_impact_mask' then
    raise exception 'resultado contratual incompleto ou nao materializavel';
  end if;
  if v_result->'f2b_document'->>'schema_version' !~ '^[1-9][0-9]*$'
     or v_result->'f2b_document'#>>'{pedido,pedido_id}' !~ '^[1-9][0-9]*$'
     or (v_result->'f2b_document'#>>'{pedido,pedido_id}')::bigint <> (v_result->>'pedido_id')::bigint
     or v_result->'f2b_document'#>>'{versao_comercial,numero}' !~ '^[1-9][0-9]*$'
     or jsonb_typeof(v_result->'f2b_document'->'itens') <> 'array'
     or jsonb_array_length(v_result->'f2b_document'->'itens') <> jsonb_array_length(v_result->'f2a_comparison'->'itens')
     or v_result->'f2b_document'->'comparacao_comercial' is distinct from v_result->'f2a_comparison'
     or exists (
       select 1
         from jsonb_array_elements(v_result->'f2a_comparison'->'itens') comparison_item
        where not exists (
          select 1
            from jsonb_array_elements(v_result->'f2b_document'->'itens') document_item
           where document_item->>'pedido_item_id' is not distinct from comparison_item->>'pedido_item_id'
             and document_item->>'produto_embalagem_id' is not distinct from comparison_item->>'produto_embalagem_id'
             and document_item->>'quantidade_apresentacoes' is not distinct from comparison_item->>'quantidade_apresentacoes'
             and document_item->>'unidade_precificacao_id' is not distinct from comparison_item->>'unidade_precificacao_id'
             and document_item->>'quantidade_unidade_precificacao_por_apresentacao' is not distinct from comparison_item->>'quantidade_unidade_precificacao_por_apresentacao'
             and document_item->>'quantidade_unidade_precificacao' is not distinct from comparison_item->>'quantidade_unidade_precificacao'
             and document_item->>'preco_referencia_centavos_por_unidade_precificacao' is not distinct from comparison_item->>'preco_referencia_centavos_por_unidade_precificacao'
             and document_item->>'preco_praticado_centavos_por_unidade_precificacao' is not distinct from comparison_item->>'preco_praticado_centavos_por_unidade_precificacao'
             and document_item->>'diferenca_centavos_por_unidade_precificacao' is not distinct from comparison_item->>'diferenca_centavos_por_unidade_precificacao'
             and document_item->>'percentual_diferenca' is not distinct from comparison_item->>'percentual_diferenca'
             and document_item->>'valor_referencia_centavos' is not distinct from comparison_item->>'valor_referencia_centavos'
             and document_item->>'valor_praticado_centavos' is not distinct from comparison_item->>'valor_praticado_centavos'
             and document_item->>'impacto_financeiro_centavos' is not distinct from comparison_item->>'impacto_financeiro_centavos'
             and document_item->>'classificacao' is not distinct from comparison_item->>'classificacao'
        )
     ) then
    raise exception 'documento F2B resultante diverge da comparacao comercial completa';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(v_result->'f2a_comparison'->'itens') item
     where jsonb_typeof(item) <> 'object'
        or item->>'pedido_item_id' is null
        or item->>'produto_embalagem_id' is null
        or item->>'unidade_precificacao_id' is null
        or item->>'quantidade_unidade_precificacao_por_apresentacao' is null
        or item->>'preco_referencia_centavos_por_unidade_precificacao' is null
        or item->>'preco_praticado_centavos_por_unidade_precificacao' is null
        or item->>'classificacao' not in ('BELOW_REFERENCE','AT_REFERENCE','ABOVE_REFERENCE')
        or item->>'pedido_item_id' !~ '^[1-9][0-9]*$'
        or item->>'produto_embalagem_id' !~ '^[1-9][0-9]*$'
        or item->>'unidade_precificacao_id' !~ '^[1-9][0-9]*$'
        or item->>'quantidade_unidade_precificacao_por_apresentacao' !~ '^[0-9]+(\\.[0-9]+)?$'
        or item->>'preco_referencia_centavos_por_unidade_precificacao' !~ '^[1-9][0-9]*$'
        or item->>'preco_praticado_centavos_por_unidade_precificacao' !~ '^[1-9][0-9]*$'
  ) then
    raise exception 'comparacao comercial resultante possui item incompleto';
  end if;
  return v_result;
end;
$$;


create or replace function public.ord01_revisao_comparacao_persistida(p_revisao_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with revision as (
    select id, pedido_id from public.com_pedido_revisoes_governadas where id = p_revisao_id
  ), facts as (
    select fact.*, snapshot.produto_embalagem_id, snapshot.origem_comercial_id,
           snapshot.cliente_id, snapshot.area_comercial_id, snapshot.uf,
           snapshot.pessoa_papel_ids, snapshot.data_comercial, snapshot.pmp_dias,
           snapshot.lista_id, snapshot.lista_versao_id, snapshot.publicacao_id,
           snapshot.regra_id, snapshot.prazo_faixa_dias, revision_item.id as revision_item_id
      from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_item_referencias_comerciais snapshot
        on snapshot.id = fact.referencia_comercial_id
      join public.com_pedido_revisao_itens revision_item
        on revision_item.id = fact.revisao_item_id
      join revision on revision.id = fact.revisao_id
     where fact.revisao_id = p_revisao_id
       and snapshot.revisao_id = p_revisao_id
       and snapshot.revisao_item_id = revision_item.id
       and revision_item.pedido_id = revision.pedido_id
  )
  select jsonb_build_object(
    'schema_version', 1,
    'pedido_id', (select pedido_id from revision),
    'itens', coalesce(jsonb_agg(jsonb_build_object(
      'pedido_item_id', pedido_item_id,
      'produto_embalagem_id', produto_embalagem_id,
      'origem_comercial_id', origem_comercial_id,
      'cliente_id', cliente_id,
      'area_comercial_id', area_comercial_id,
      'uf', uf,
      'pessoa_papel_ids', to_jsonb(pessoa_papel_ids),
      'data_comercial', data_comercial,
      'pmp_dias', pmp_dias,
      'lista_id', lista_id,
      'lista_versao_id', lista_versao_id,
      'publicacao_id', publicacao_id,
      'regra_id', regra_id,
      'prazo_faixa_dias', prazo_faixa_dias,
      'unidade_precificacao_id', unidade_precificacao_id,
      'quantidade_apresentacoes', quantidade_apresentacoes,
      'quantidade_unidade_precificacao_por_apresentacao', quantidade_unidade_precificacao_por_apresentacao,
      'quantidade_unidade_precificacao', quantidade_unidade_precificacao,
      'preco_referencia_centavos_por_unidade_precificacao', preco_referencia_centavos_por_unidade_precificacao,
      'preco_praticado_centavos_por_unidade_precificacao', preco_praticado_centavos_por_unidade_precificacao,
      'diferenca_centavos_por_unidade_precificacao', diferenca_centavos_por_unidade_precificacao,
      'percentual_diferenca', percentual_diferenca,
      'valor_referencia_centavos', valor_referencia_centavos,
      'valor_praticado_centavos', valor_praticado_centavos,
      'impacto_financeiro_centavos', impacto_financeiro_centavos,
      'classificacao', classificacao
    ) order by revision_item_id), '[]'::jsonb),
    'totais', jsonb_build_object(
      'total_referencia_centavos', coalesce(sum(valor_referencia_centavos), 0),
      'total_praticado_centavos', coalesce(sum(valor_praticado_centavos), 0),
      'descontos_brutos_centavos', coalesce(sum(case when impacto_financeiro_centavos < 0 then -impacto_financeiro_centavos else 0 end), 0),
      'overprice_bruto_centavos', coalesce(sum(case when impacto_financeiro_centavos > 0 then impacto_financeiro_centavos else 0 end), 0),
      'resultado_liquido_centavos', coalesce(sum(impacto_financeiro_centavos), 0),
      'percentual_resultado_liquido', case when coalesce(sum(valor_referencia_centavos), 0) = 0 then 0
        else round(coalesce(sum(impacto_financeiro_centavos), 0)::numeric * 100 / sum(valor_referencia_centavos)::numeric, 6) end
    )
  ) from facts;
$$;

create or replace function public.ord01_comparacao_original_persistida(p_pedido_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with facts as (
    select fact.*, snapshot.produto_embalagem_id, snapshot.origem_comercial_id,
           snapshot.cliente_id, snapshot.area_comercial_id, snapshot.uf,
           snapshot.pessoa_papel_ids, snapshot.data_comercial, snapshot.pmp_dias,
           snapshot.lista_id, snapshot.lista_versao_id, snapshot.publicacao_id,
           snapshot.regra_id, snapshot.prazo_faixa_dias
      from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_item_referencias_comerciais snapshot
        on snapshot.id = fact.referencia_comercial_id
     where fact.pedido_id = p_pedido_id
       and fact.revisao_id is null
       and snapshot.revisao_id is null
  )
  select jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'itens', coalesce(jsonb_agg(jsonb_build_object(
      'pedido_item_id', pedido_item_id,
      'produto_embalagem_id', produto_embalagem_id,
      'origem_comercial_id', origem_comercial_id,
      'cliente_id', cliente_id,
      'area_comercial_id', area_comercial_id,
      'uf', uf,
      'pessoa_papel_ids', to_jsonb(pessoa_papel_ids),
      'data_comercial', data_comercial,
      'pmp_dias', pmp_dias,
      'lista_id', lista_id,
      'lista_versao_id', lista_versao_id,
      'publicacao_id', publicacao_id,
      'regra_id', regra_id,
      'prazo_faixa_dias', prazo_faixa_dias,
      'unidade_precificacao_id', unidade_precificacao_id,
      'quantidade_apresentacoes', quantidade_apresentacoes,
      'quantidade_unidade_precificacao_por_apresentacao', quantidade_unidade_precificacao_por_apresentacao,
      'quantidade_unidade_precificacao', quantidade_unidade_precificacao,
      'preco_referencia_centavos_por_unidade_precificacao', preco_referencia_centavos_por_unidade_precificacao,
      'preco_praticado_centavos_por_unidade_precificacao', preco_praticado_centavos_por_unidade_precificacao,
      'diferenca_centavos_por_unidade_precificacao', diferenca_centavos_por_unidade_precificacao,
      'percentual_diferenca', percentual_diferenca,
      'valor_referencia_centavos', valor_referencia_centavos,
      'valor_praticado_centavos', valor_praticado_centavos,
      'impacto_financeiro_centavos', impacto_financeiro_centavos,
      'classificacao', classificacao
    ) order by pedido_item_id), '[]'::jsonb),
    'totais', jsonb_build_object(
      'total_referencia_centavos', coalesce(sum(valor_referencia_centavos), 0),
      'total_praticado_centavos', coalesce(sum(valor_praticado_centavos), 0),
      'descontos_brutos_centavos', coalesce(sum(case when impacto_financeiro_centavos < 0 then -impacto_financeiro_centavos else 0 end), 0),
      'overprice_bruto_centavos', coalesce(sum(case when impacto_financeiro_centavos > 0 then impacto_financeiro_centavos else 0 end), 0),
      'resultado_liquido_centavos', coalesce(sum(impacto_financeiro_centavos), 0),
      'percentual_resultado_liquido', case when coalesce(sum(valor_referencia_centavos), 0) = 0 then 0
        else round(coalesce(sum(impacto_financeiro_centavos), 0)::numeric * 100 / sum(valor_referencia_centavos)::numeric, 6) end
    )
  ) from facts;
$$;

create or replace function public.ord01_revisao_estado_materializado(p_revisao_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_materialization public.com_pedido_revisao_materializacoes%rowtype;
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_plan public.fin_pedido_planos_pagamento%rowtype;
  v_financial jsonb;
begin
  select * into v_materialization from public.com_pedido_revisao_materializacoes where revisao_id = p_revisao_id;
  if not found then raise exception 'revisao ainda nao possui fatos materializados'; end if;
  select * into v_confirmation from public.com_pedido_confirmacoes_comerciais
   where id = v_materialization.confirmacao_comercial_id and revisao_id = p_revisao_id;
  select * into v_plan from public.fin_pedido_planos_pagamento
   where id = v_materialization.plano_pagamento_id and revisao_id = p_revisao_id;
  if not found then raise exception 'revisao possui plano financeiro materializado inconsistente'; end if;
  select jsonb_build_object(
    'plano_pagamento_id', v_plan.id,
    'versao', v_plan.versao,
    'pmp_dias', v_plan.pmp_dias,
    'valor_total_centavos', v_plan.valor_total_centavos,
    'parcelas', coalesce(jsonb_agg(jsonb_build_object(
      'numero_parcela', installment.numero_parcela,
      'forma_pagamento', installment.forma_pagamento,
      'valor_centavos', installment.valor_centavos,
      'data_vencimento', installment.data_vencimento,
      'dias_prazo', installment.dias_prazo
    ) order by installment.numero_parcela), '[]'::jsonb)
  ) into v_financial
  from public.fin_pedido_parcelas installment
  where installment.plano_pagamento_id = v_plan.id;
  return jsonb_build_object(
    'schema_version', 1,
    'pedido_id', v_materialization.pedido_id,
    'f2b_confirmation_id', v_confirmation.id,
    'f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'f2b_document', v_confirmation.documento_canonico_json,
    'f2a_comparison', public.ord01_revisao_comparacao_persistida(p_revisao_id),
    'financial_condition', v_financial,
    'gate_facts', public.ord01_revision_current_pre_effective_state(v_materialization.pedido_id)->'gate_facts'
  );
end;
$$;

create or replace function public.ord01_contract_state_materialization_equivalent(p_expected jsonb, p_actual jsonb)
returns boolean
language sql
immutable
as $$
  select
    ((p_expected - 'f2b_confirmation_id' - 'f2b_document_sha256')
      || jsonb_build_object('financial_condition', (p_expected->'financial_condition') - 'plano_pagamento_id' - 'versao'))
    is not distinct from
    ((p_actual - 'f2b_confirmation_id' - 'f2b_document_sha256')
      || jsonb_build_object('financial_condition', (p_actual->'financial_condition') - 'plano_pagamento_id' - 'versao'));
$$;

create or replace function public.ord01_revision_current_pre_effective_state_versioned_0136(p_pedido_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_financial jsonb;
  v_f2a_fact_ids bigint[];
  v_reference_ids bigint[];
begin
  -- This is the initial H0 candidate only.  Chain traversal is handled by
  -- ord01_revision_current_contract_state and never guesses a global latest fact.
  select * into v_confirmation from public.com_pedido_confirmacoes_comerciais
   where pedido_id = p_pedido_id and revisao_id is null
   order by numero_versao desc, id desc limit 1;
  if not found then raise exception 'pedido nao possui estado F2B original governado'; end if;
  select jsonb_build_object(
    'plano_pagamento_id', plan.id,
    'versao', plan.versao,
    'pmp_dias', plan.pmp_dias,
    'valor_total_centavos', plan.valor_total_centavos,
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object(
      'numero_parcela', installment.numero_parcela,
      'forma_pagamento', installment.forma_pagamento,
      'valor_centavos', installment.valor_centavos,
      'data_vencimento', installment.data_vencimento,
      'dias_prazo', installment.dias_prazo
    ) order by installment.numero_parcela)
      from public.fin_pedido_parcelas installment where installment.plano_pagamento_id = plan.id), '[]'::jsonb)
  ) into v_financial
  from public.fin_pedido_planos_pagamento plan
  where plan.pedido_id = p_pedido_id and plan.revisao_id is null
    and plan.origem_dados = 'sistema' and plan.review_status = 'approved'
    and plan.vigencia_inicio <= current_date
    and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date)
    and plan.pmp_dias is not null
  order by plan.versao desc, plan.id desc limit 1;
  if v_financial is null then raise exception 'pedido nao possui condicao financeira original governada vigente'; end if;
  select coalesce(array_agg(fact.id order by fact.id), '{}'::bigint[]),
         coalesce(array_agg(distinct reference.id order by reference.id), '{}'::bigint[])
    into v_f2a_fact_ids, v_reference_ids
    from public.com_pedido_item_precos_praticados fact
    join public.com_pedido_item_referencias_comerciais reference
      on reference.id = fact.referencia_comercial_id
   where fact.pedido_id = p_pedido_id
     and fact.revisao_id is null
     and reference.revisao_id is null;
  if cardinality(v_f2a_fact_ids) = 0 or cardinality(v_reference_ids) = 0 then
    raise exception 'pedido nao possui fatos comerciais originais congelados';
  end if;
  return jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'f2b_confirmation_id', v_confirmation.id,
    'f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'f2b_document', v_confirmation.documento_canonico_json,
    'f2a_comparison', public.ord01_comparacao_original_persistida(p_pedido_id),
    'financial_condition', v_financial,
    'gate_facts', jsonb_build_object(
      'f2a_fact_ids', to_jsonb(v_f2a_fact_ids),
      'commercial_reference_ids', to_jsonb(v_reference_ids),
      'financial_plan_id', v_financial->>'plano_pagamento_id'
    )
  );
end;
$$;

create or replace function public.materializar_com_pedido_revisao_pre_efetiva(p_revisao_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_order public.com_pedidos%rowtype;
  v_state jsonb;
  v_financial jsonb;
  v_item jsonb;
  v_origin_item public.com_pedido_itens%rowtype;
  v_revision_item_id bigint;
  v_plan_id bigint;
  v_reference_id bigint;
  v_fact_id bigint;
  v_confirmation_id bigint;
  v_version integer;
  v_actor uuid := public.current_actor_id();
  v_document jsonb;
  v_has_discount boolean;
  v_unit_code text;
  v_legacy_liter_price bigint;
  v_revision_item_ids bigint[] := '{}'::bigint[];
  v_reference_ids bigint[] := '{}'::bigint[];
  v_fact_ids bigint[] := '{}'::bigint[];
  v_previous_context text := current_setting('elite.revision_materialization', true);
  v_audit_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.revision.request');
  v_audit_context := public.begin_audited_rpc(
    'pedidos.revision.request', 'pedidos', 'com_pedido_revisao_materializacoes',
    'change_type', jsonb_build_object('revisao_id', p_revisao_id)
  );
  select * into v_revision from public.com_pedido_revisoes_governadas where id = p_revisao_id for update;
  if not found or v_revision.tipo <> 'pre_efetivacao' then
    raise exception 'materializacao exige revisao pre-efetivacao';
  end if;
  if not public.can_current_user_view_order(v_revision.pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  select * into v_order from public.com_pedidos where id = v_revision.pedido_id for update;
  if not found or v_order.status <> 'blocked' or v_order.pedido_efetivado_em is not null then
    raise exception 'materializacao pre-efetiva exige pedido bloqueado ainda nao efetivado';
  end if;
  if exists (select 1 from public.com_pedido_revisao_materializacoes where revisao_id = p_revisao_id) then
    return;
  end if;
  v_state := v_revision.resulting_contract_state_json;
  v_financial := v_state->'financial_condition';
  if jsonb_array_length(v_state->'f2a_comparison'->'itens') <> (
    select count(*) from public.com_pedido_itens where pedido_id = v_order.id and status = 'active' and tipo_item = 'venda'
  ) then
    raise exception 'revisao nao possui comparacao completa dos itens de venda ativos';
  end if;
  if (v_state->'f2b_document'#>>'{versao_comercial,numero}') !~ '^[1-9][0-9]*$' then
    raise exception 'estado revisado nao informa a versao F2B materializavel';
  end if;
  v_version := (v_state->'f2b_document'#>>'{versao_comercial,numero}')::integer;
  if exists (select 1 from public.com_pedido_confirmacoes_comerciais where pedido_id = v_order.id and numero_versao = v_version) then
    raise exception 'versao F2B revisada ja existe';
  end if;

  perform set_config('elite.revision_materialization', '1', true);
  insert into public.fin_pedido_planos_pagamento(
    pedido_id, versao, vigencia_inicio, vigencia_fim, review_status, origem_dados,
    data_base, valor_total_centavos, pmp_dias, created_by, revisao_id
  ) values (
    v_order.id,
    coalesce((select max(versao) from public.fin_pedido_planos_pagamento where pedido_id = v_order.id), 0) + 1,
    v_order.data_pedido, null, 'approved', 'sistema', v_order.data_pedido,
    (v_financial->>'valor_total_centavos')::bigint,
    (v_financial->>'pmp_dias')::numeric, v_actor, p_revisao_id
  ) returning id into v_plan_id;
  insert into public.fin_pedido_parcelas(
    plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto,
    review_status, origem_dados, forma_pagamento, valor_centavos, dias_prazo, created_by
  )
  select v_plan_id, (part->>'numero_parcela')::integer, (part->>'data_vencimento')::date,
    (part->>'valor_centavos')::numeric, 'approved', 'sistema', part->>'forma_pagamento',
    (part->>'valor_centavos')::bigint, (part->>'dias_prazo')::integer, v_actor
    from jsonb_array_elements(v_financial->'parcelas') part;

  for v_item in select value from jsonb_array_elements(v_state->'f2a_comparison'->'itens') loop
    select * into v_origin_item from public.com_pedido_itens
     where id = (v_item->>'pedido_item_id')::bigint and pedido_id = v_order.id for update;
    if not found or v_origin_item.status <> 'active' or v_origin_item.tipo_item <> 'venda' then
      raise exception 'item de origem da revisao nao pertence ao pedido de venda ativo';
    end if;
    if not exists (select 1 from public.cad_produto_embalagens where id = (v_item->>'produto_embalagem_id')::bigint)
       or not exists (select 1 from public.cad_unidades_medida where id = (v_item->>'unidade_precificacao_id')::bigint) then
      raise exception 'item comercial resultante referencia cadastro inexistente';
    end if;
    insert into public.com_pedido_revisao_itens(
      revisao_id, pedido_id, pedido_item_origem_id, produto_embalagem_id,
      quantidade_apresentacoes, unidade_precificacao_id,
      quantidade_unidade_precificacao_por_apresentacao,
      quantidade_unidade_precificacao, estado_item_json, created_by
    ) values (
      p_revisao_id, v_order.id, v_origin_item.id, (v_item->>'produto_embalagem_id')::bigint,
      (v_item->>'quantidade_apresentacoes')::numeric, (v_item->>'unidade_precificacao_id')::bigint,
      (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric,
      (v_item->>'quantidade_unidade_precificacao')::numeric, v_item, v_actor
    ) returning id into v_revision_item_id;
    v_revision_item_ids := array_append(v_revision_item_ids, v_revision_item_id);
    select lower(unidade.codigo) into v_unit_code from public.cad_unidades_medida unidade
     where unidade.id = (v_item->>'unidade_precificacao_id')::bigint;
    v_legacy_liter_price := case when v_unit_code = 'l'
      then (v_item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint else null end;
    insert into public.com_pedido_item_referencias_comerciais(
      pedido_id, pedido_item_id, origem_comercial_id, cliente_id, area_comercial_id, uf,
      pessoa_papel_ids, produto_embalagem_id, data_comercial, plano_pagamento_id, pmp_dias,
      lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
      preco_referencia_centavos_por_litro, unidade_precificacao_id,
      quantidade_unidade_precificacao_por_apresentacao,
      preco_referencia_centavos_por_unidade_precificacao, resolved_by, lineage_json,
      revisao_id, revisao_item_id
    ) values (
      v_order.id, v_origin_item.id, (v_item->>'origem_comercial_id')::bigint,
      (v_item->>'cliente_id')::bigint, nullif(v_item->>'area_comercial_id','')::bigint, nullif(v_item->>'uf',''),
      coalesce((select array_agg(value::bigint) from jsonb_array_elements_text(coalesce(v_item->'pessoa_papel_ids', '[]'::jsonb)) value), '{}'::bigint[]),
      (v_item->>'produto_embalagem_id')::bigint, (v_item->>'data_comercial')::date, v_plan_id,
      (v_item->>'pmp_dias')::numeric, (v_item->>'lista_id')::bigint, (v_item->>'lista_versao_id')::bigint,
      (v_item->>'publicacao_id')::bigint, (v_item->>'regra_id')::bigint, (v_item->>'prazo_faixa_dias')::integer,
      v_legacy_liter_price, (v_item->>'unidade_precificacao_id')::bigint,
      (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric,
      (v_item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint, v_actor,
      jsonb_build_object('revision_id', p_revisao_id, 'revision_item_id', v_revision_item_id, 'source', '0136'),
      p_revisao_id, v_revision_item_id
    ) returning id into v_reference_id;
    v_reference_ids := array_append(v_reference_ids, v_reference_id);
    insert into public.com_pedido_item_precos_praticados(
      pedido_id, pedido_item_id, referencia_comercial_id, unidade_precificacao_id,
      quantidade_apresentacoes, quantidade_unidade_precificacao_por_apresentacao,
      quantidade_unidade_precificacao, preco_referencia_centavos_por_unidade_precificacao,
      preco_praticado_centavos_por_unidade_precificacao, diferenca_centavos_por_unidade_precificacao,
      percentual_diferenca, valor_referencia_centavos, valor_praticado_centavos,
      impacto_financeiro_centavos, classificacao, motivo, recorded_by, revisao_id, revisao_item_id
    ) values (
      v_order.id, v_origin_item.id, v_reference_id, (v_item->>'unidade_precificacao_id')::bigint,
      (v_item->>'quantidade_apresentacoes')::numeric,
      (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric,
      (v_item->>'quantidade_unidade_precificacao')::numeric,
      (v_item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'diferenca_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'percentual_diferenca')::numeric, (v_item->>'valor_referencia_centavos')::bigint,
      (v_item->>'valor_praticado_centavos')::bigint, (v_item->>'impacto_financeiro_centavos')::bigint,
      v_item->>'classificacao', coalesce(nullif(v_item->>'motivo',''), 'revisao contratual governada'),
      v_actor, p_revisao_id, v_revision_item_id
    ) returning id into v_fact_id;
    v_fact_ids := array_append(v_fact_ids, v_fact_id);
  end loop;
  if cardinality(v_reference_ids) <> cardinality(v_revision_item_ids)
     or cardinality(v_fact_ids) <> cardinality(v_revision_item_ids) then
    raise exception 'materializacao da revisao nao produziu todos os fatos versionados';
  end if;
  v_has_discount := exists (
    select 1 from jsonb_array_elements(v_state->'f2a_comparison'->'itens') item
     where item->>'classificacao' = 'BELOW_REFERENCE'
  );
  v_document := v_state->'f2b_document';
  insert into public.com_pedido_confirmacoes_comerciais(
    pedido_id, numero_versao, versao_anterior_id, possui_desconto, justificativa_comercial,
    descontos_confirmados, comparacao_sha256, preview_hash, documento_canonico_json,
    documento_canonico_sha256, confirmed_by, confirmed_at, revisao_id
  ) values (
    v_order.id, v_version,
    (select id from public.com_pedido_confirmacoes_comerciais where pedido_id = v_order.id order by numero_versao desc, id desc limit 1),
    v_has_discount, nullif(v_document#>>'{comercial,justificativa}', ''), v_has_discount,
    public.ord01_revision_hash(v_state->'f2a_comparison'), public.ord01_revision_hash(v_state),
    v_document, public.ord01_revision_hash(v_document), v_actor, clock_timestamp(), p_revisao_id
  ) returning id into v_confirmation_id;
  insert into public.com_pedido_revisao_materializacoes(
    revisao_id, pedido_id, plano_pagamento_id, confirmacao_comercial_id,
    revisao_item_ids, referencia_comercial_ids, preco_praticado_ids, materialized_by
  ) values (
    p_revisao_id, v_order.id, v_plan_id, v_confirmation_id,
    v_revision_item_ids, v_reference_ids, v_fact_ids, v_actor
  );
  if not public.ord01_contract_state_materialization_equivalent(
    v_state, public.ord01_revisao_estado_materializado(p_revisao_id)
  ) then
    raise exception 'fatos materializados divergem do estado contratual revisado';
  end if;
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_revisao_materializacoes', p_revisao_id::text,
    'pedidos.revisao.materializada', 'pedidos.revision.request',
    v_audit_context, null,
    jsonb_build_object(
      'revisao_id', p_revisao_id, 'plano_pagamento_id', v_plan_id,
      'confirmacao_comercial_id', v_confirmation_id,
      'revisao_item_ids', to_jsonb(v_revision_item_ids),
      'referencia_comercial_ids', to_jsonb(v_reference_ids),
      'preco_praticado_ids', to_jsonb(v_fact_ids)
    ), jsonb_build_object('source', 'resulting_contract_state_json'), 'database_rpc'
  );
  perform set_config('elite.revision_materialization', coalesce(v_previous_context, ''), true);
exception when others then
  perform set_config('elite.revision_materialization', coalesce(v_previous_context, ''), true);
  raise;
end;
$$;

create or replace function public.ord01_revision_impact_mask_versioned_0136(p_base jsonb, p_result jsonb)
returns text[]
language plpgsql
immutable
as $$
declare
  v_mask text[] := '{}'::text[];
  v_base_document jsonb := (p_base->'f2b_document') #- array['versao_comercial','numero'];
  v_result_document jsonb := (p_result->'f2b_document') #- array['versao_comercial','numero'];
begin
  if p_base->'f2a_comparison' is distinct from p_result->'f2a_comparison'
     or p_base->'itens' is distinct from p_result->'itens'
     or p_base->'pricing' is distinct from p_result->'pricing' then
    v_mask := array_append(v_mask, 'pricing');
  end if;
  if p_base->'f2a_comparison' is distinct from p_result->'f2a_comparison'
     or p_base->'discount' is distinct from p_result->'discount' then
    v_mask := array_append(v_mask, 'discount');
  end if;
  if p_base->'financial_condition' is distinct from p_result->'financial_condition'
     or p_base->'financial' is distinct from p_result->'financial' then
    v_mask := array_append(v_mask, 'financial');
  end if;
  if p_base->'obrigacoes_contratuais' is distinct from p_result->'obrigacoes_contratuais'
     or p_base->'buyer_signature' is distinct from p_result->'buyer_signature'
     or v_base_document is distinct from v_result_document then
    v_mask := array_append(v_mask, 'buyer_signature');
  end if;
  if p_base->'commercial_context' is distinct from p_result->'commercial_context'
     or p_base->'commercial_resolution' is distinct from p_result->'commercial_resolution' then
    v_mask := array_append(v_mask, 'commercial_resolution');
  end if;
  if cardinality(v_mask) = 0 then
    raise exception 'delta de revisao nao possui dimensao material governada';
  end if;
  return v_mask;
end;
$$;

create or replace function public.ord01_revision_current_contract_state(p_pedido_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_genesis public.com_pedido_contrato_geneses%rowtype;
  v_state jsonb;
  v_source jsonb;
  v_revision record;
  v_expected_hash text;
  v_expected_sequence integer := 0;
  v_tip_revision_id bigint;
  v_tip_event_id bigint;
  v_baseline_confirmation bigint;
  v_baseline_plan bigint;
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_order.pedido_efetivado_em is null then
    v_state := public.ord01_revision_current_pre_effective_state(p_pedido_id);
    v_expected_hash := public.ord01_revision_hash(v_state);
    for v_revision in
      select revision.*
        from public.com_pedido_revisoes_governadas revision
       where revision.pedido_id = p_pedido_id and revision.tipo = 'pre_efetivacao'
         and exists (select 1 from public.com_pedido_revisao_eventos event where event.revisao_id = revision.id and event.evento = 'effective')
       order by revision.sequence, revision.id
    loop
      select event.id into v_tip_event_id from public.com_pedido_revisao_eventos event
       where event.revisao_id = v_revision.id and event.evento = 'effective'
       order by event.id desc limit 1;
      if v_revision.base_sequence <> v_expected_sequence
         or v_revision.base_contract_state_sha256 <> v_expected_hash
         or v_revision.sequence <> v_expected_sequence + 1
         or public.ord01_revision_hash(v_revision.delta_json) <> v_revision.delta_sha256
         or public.ord01_apply_com_pedido_contract_delta(v_state, v_revision.delta_json) <> v_revision.resulting_contract_state_json
         or public.ord01_revision_hash(v_revision.resulting_contract_state_json) <> v_revision.resulting_contract_state_sha256
         or (v_expected_sequence = 0 and v_revision.base_event_id is not null)
         or (v_expected_sequence > 0 and v_revision.base_event_id is distinct from v_tip_revision_id) then
        raise exception 'cadeia contratual inconsistente';
      end if;
      v_state := v_revision.resulting_contract_state_json;
      v_expected_hash := v_revision.resulting_contract_state_sha256;
      v_expected_sequence := v_revision.sequence;
      v_tip_revision_id := v_tip_event_id;
      v_tip_event_id := null;
    end loop;
    if v_expected_sequence = 0 then
      v_baseline_confirmation := (v_state->>'f2b_confirmation_id')::bigint;
      v_baseline_plan := (v_state->'financial_condition'->>'plano_pagamento_id')::bigint;
      v_source := jsonb_build_object(
        'revisao_id', null,
        'confirmacao_comercial_id', v_baseline_confirmation,
        'plano_pagamento_id', v_baseline_plan
      );
    else
      select jsonb_build_object(
        'revisao_id', materialization.revisao_id,
        'confirmacao_comercial_id', materialization.confirmacao_comercial_id,
        'plano_pagamento_id', materialization.plano_pagamento_id,
        'revisao_item_ids', to_jsonb(materialization.revisao_item_ids),
        'referencia_comercial_ids', to_jsonb(materialization.referencia_comercial_ids),
        'preco_praticado_ids', to_jsonb(materialization.preco_praticado_ids)
      ) into v_source
      from public.com_pedido_revisao_materializacoes materialization
      join public.com_pedido_revisoes_governadas revision on revision.id = materialization.revisao_id
      where revision.pedido_id = p_pedido_id and revision.sequence = v_expected_sequence;
      if v_source is null then raise exception 'cadeia contratual sem materializacao versionada'; end if;
    end if;
    return jsonb_build_object(
      'sequence', v_expected_sequence,
      'contract_state_sha256', v_expected_hash,
      'contract_state', v_state,
      'source_facts', v_source,
      'source', 'pre_effective_contract_chain'
    );
  end if;

  select * into v_genesis from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id;
  if not found then raise exception 'UNRESOLVABLE: contrato genese nao materializado'; end if;
  v_state := v_genesis.contract_state_json;
  v_expected_hash := v_genesis.contract_state_sha256;
  v_source := jsonb_build_object(
    'revisao_id', null,
    'confirmacao_comercial_id', v_genesis.effective_f2b_confirmation_id,
    'plano_pagamento_id', v_genesis.financial_plan_id,
    'referencia_comercial_ids', to_jsonb(v_genesis.commercial_reference_ids),
    'preco_praticado_ids', to_jsonb(v_genesis.f2a_fact_ids)
  );
  for v_revision in
    select revision.*
      from public.com_pedido_revisoes_governadas revision
     where revision.pedido_id = p_pedido_id
       and revision.tipo in ('pre_efetivacao', 'aditivo')
       and exists (select 1 from public.com_pedido_revisao_eventos event where event.revisao_id = revision.id and event.evento = 'effective')
     order by revision.sequence, revision.id
  loop
    select event.id into v_tip_event_id from public.com_pedido_revisao_eventos event
     where event.revisao_id = v_revision.id and event.evento = 'effective'
     order by event.id desc limit 1;
    if v_revision.base_sequence <> v_expected_sequence
       or v_revision.base_contract_state_sha256 <> v_expected_hash
       or v_revision.sequence <> v_expected_sequence + 1
       or public.ord01_revision_hash(v_revision.delta_json) <> v_revision.delta_sha256
       or public.ord01_apply_com_pedido_contract_delta(v_state, v_revision.delta_json) <> v_revision.resulting_contract_state_json
       or public.ord01_revision_hash(v_revision.resulting_contract_state_json) <> v_revision.resulting_contract_state_sha256
       or (v_expected_sequence = 0 and v_revision.base_event_id is not null)
       or (v_expected_sequence > 0 and v_revision.base_event_id is distinct from v_tip_revision_id) then
      raise exception 'cadeia contratual inconsistente';
    end if;
    v_state := v_revision.resulting_contract_state_json;
    v_expected_hash := v_revision.resulting_contract_state_sha256;
    v_expected_sequence := v_revision.sequence;
    v_tip_revision_id := v_tip_event_id;
    v_tip_event_id := null;
    if v_revision.tipo = 'pre_efetivacao' then
      select jsonb_build_object(
        'revisao_id', materialization.revisao_id,
        'confirmacao_comercial_id', materialization.confirmacao_comercial_id,
        'plano_pagamento_id', materialization.plano_pagamento_id,
        'revisao_item_ids', to_jsonb(materialization.revisao_item_ids),
        'referencia_comercial_ids', to_jsonb(materialization.referencia_comercial_ids),
        'preco_praticado_ids', to_jsonb(materialization.preco_praticado_ids)
      ) into v_source
      from public.com_pedido_revisao_materializacoes materialization
      where materialization.revisao_id = v_revision.id;
      if v_source is null then
        raise exception 'cadeia contratual sem materializacao versionada';
      end if;
    end if;
  end loop;
  return jsonb_build_object(
    'sequence', v_expected_sequence,
    'contract_state_sha256', v_expected_hash,
    'contract_state', v_state,
    'source_facts', v_source,
    'source', 'contract_chain'
  );
end;
$$;

create or replace function public.solicitar_com_pedido_revisao_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_delta_json jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_actor_id();
  v_order public.com_pedidos%rowtype;
  v_existing public.com_pedido_revisoes_governadas%rowtype;
  v_state jsonb;
  v_mask text[];
  v_tipo text;
  v_sequence integer;
  v_base_sequence integer;
  v_base_hash text;
  v_base_f2b bigint;
  v_base_event_id bigint;
  v_result jsonb;
  v_stored_delta jsonb;
  v_delta_hash text;
  v_result_hash text;
  v_payload_hash text;
  v_id bigint;
  v_next_f2b_version integer;
  v_audit_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.revision.request');
  v_audit_context := public.begin_audited_rpc(
    'pedidos.revision.request', 'pedidos', 'com_pedido_revisoes_governadas',
    'change_type', jsonb_build_object('pedido_id', p_pedido_id, 'correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null or p_pedido_id is null or jsonb_typeof(p_delta_json) <> 'object' then
    raise exception 'revisao exige chave, pedido e delta objeto';
  end if;
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  v_payload_hash := public.ord01_revision_hash(jsonb_build_object('pedido_id', p_pedido_id, 'delta', p_delta_json));
  perform pg_advisory_xact_lock(hashtextextended(concat('ord01-revision:', p_pedido_id), 0));
  select * into v_existing from public.com_pedido_revisoes_governadas where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.created_by is distinct from v_actor or v_existing.payload_hash <> v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.id;
  end if;
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found or v_order.tipo_pedido <> 'venda' then raise exception 'revisao exige pedido de venda'; end if;
  if exists (
    select 1 from public.com_pedido_revisoes_governadas revision
     where revision.pedido_id = p_pedido_id
       and not exists (select 1 from public.com_pedido_revisao_eventos event where event.revisao_id = revision.id and event.evento in ('rejected','effective'))
  ) then raise exception 'pedido ja possui revisao material ativa'; end if;
  if v_order.pedido_efetivado_em is not null
     and not exists (select 1 from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id) then
    perform public.materializar_com_pedido_contrato_genese(p_pedido_id);
  end if;
  v_state := public.ord01_revision_current_contract_state(p_pedido_id);
  v_tipo := case when v_order.pedido_efetivado_em is null then 'pre_efetivacao' else 'aditivo' end;
  v_base_sequence := (v_state->>'sequence')::integer;
  v_base_hash := v_state->>'contract_state_sha256';
  v_base_f2b := (v_state->'source_facts'->>'confirmacao_comercial_id')::bigint;
  if v_base_sequence > 0 then
    select event.id into v_base_event_id
      from public.com_pedido_revisoes_governadas previous_revision
      join public.com_pedido_revisao_eventos event on event.revisao_id = previous_revision.id
     where previous_revision.pedido_id = p_pedido_id
       and previous_revision.sequence = v_base_sequence
       and event.evento = 'effective'
     order by event.id desc limit 1;
    if v_base_event_id is null then raise exception 'cadeia contratual sem evento efetivo no topo'; end if;
  end if;
  select coalesce(max(sequence), 0) + 1 into v_sequence
    from public.com_pedido_revisoes_governadas where pedido_id = p_pedido_id;
  v_result := public.ord01_apply_com_pedido_contract_delta(v_state->'contract_state', p_delta_json);
  if v_tipo = 'pre_efetivacao' then
    select coalesce(max(numero_versao), 0) + 1 into v_next_f2b_version
      from public.com_pedido_confirmacoes_comerciais where pedido_id = p_pedido_id;
    v_result := jsonb_set(v_result, '{f2b_document,versao_comercial,numero}', to_jsonb(v_next_f2b_version), true);
    v_result := jsonb_set(v_result, '{f2b_document,pedido,pedido_id}', to_jsonb(p_pedido_id), true);
    v_stored_delta := p_delta_json || jsonb_build_object('f2b_document', v_result->'f2b_document');
    v_result := public.ord01_apply_com_pedido_contract_delta(v_state->'contract_state', v_stored_delta);
  else
    v_stored_delta := p_delta_json;
  end if;
  v_delta_hash := public.ord01_revision_hash(v_stored_delta);
  v_mask := public.ord01_revision_impact_mask(v_state->'contract_state', v_result);
  v_result_hash := public.ord01_revision_hash(v_result);
  insert into public.com_pedido_revisoes_governadas(
    pedido_id, tipo, sequence, base_f2b_confirmation_id, base_sequence,
    base_contract_state_sha256, base_event_id, delta_json, delta_sha256,
    resulting_contract_state_json, resulting_contract_state_sha256,
    impact_mask, idempotency_key, payload_hash, created_by
  ) values (
    p_pedido_id, v_tipo, v_sequence, v_base_f2b, v_base_sequence,
    v_base_hash, v_base_event_id, v_stored_delta, v_delta_hash, v_result, v_result_hash,
    v_mask, p_idempotency_key, v_payload_hash, v_actor
  ) returning id into v_id;
  insert into public.com_pedido_revisao_eventos(revisao_id, evento, idempotency_key, payload_hash, actor_id, payload_json)
  values (v_id, 'requested', p_idempotency_key, v_payload_hash, v_actor,
    jsonb_build_object('impact_mask', to_jsonb(v_mask), 'base_sequence', v_base_sequence, 'base_f2b_confirmation_id', v_base_f2b));
  insert into public.com_pedido_revisao_eventos(revisao_id, evento, actor_id, payload_json)
  values (v_id, 'pending', v_actor, jsonb_build_object(
    'reason', case when v_tipo = 'pre_efetivacao' then 'nova versao comercial aguarda os gates vinculados a revisao' else 'capacidade downstream deve ser comprovada antes do aditivo' end,
    'impact_mask', to_jsonb(v_mask)
  ));
  if v_tipo = 'pre_efetivacao' then
    perform public.materializar_com_pedido_revisao_pre_efetiva(v_id);
  end if;
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_revisoes_governadas', v_id::text,
    'pedidos.revisao.solicitada', 'pedidos.revision.request',
    v_audit_context, null,
    jsonb_build_object('pedido_id', p_pedido_id, 'tipo', v_tipo, 'sequence', v_sequence, 'impact_mask', to_jsonb(v_mask)),
    jsonb_build_object('base_hash', v_base_hash, 'delta_hash', v_delta_hash, 'result_hash', v_result_hash), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.ord01_revisao_pre_efetiva_gates(p_revisao_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_materialization public.com_pedido_revisao_materializacoes%rowtype;
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_comparison jsonb;
  v_credit_id bigint;
  v_evidence_id bigint;
  v_signature_id bigint;
  v_discount_id bigint;
  v_pending text[] := '{}'::text[];
  v_has_below boolean;
  v_f2a_ok boolean;
begin
  select * into v_materialization from public.com_pedido_revisao_materializacoes where revisao_id = p_revisao_id;
  if not found then raise exception 'revisao ainda nao possui materializacao governada'; end if;
  select * into v_confirmation from public.com_pedido_confirmacoes_comerciais
   where id = v_materialization.confirmacao_comercial_id and revisao_id = p_revisao_id;
  if not found then raise exception 'materializacao sem confirmacao F2B da revisao'; end if;
  v_comparison := public.ord01_revisao_comparacao_persistida(p_revisao_id);
  -- The persisted fact comparison is numeric(18,6)-normalized by PostgreSQL;
  -- compare its JSON meaning to the frozen F2B document, not its incidental
  -- textual numeric scale (for example 0 versus 0.000000).
  v_f2a_ok := jsonb_array_length(v_comparison->'itens') = cardinality(v_materialization.revisao_item_ids)
    and v_comparison = v_confirmation.documento_canonico_json->'comparacao_comercial';
  if not v_f2a_ok then v_pending := array_append(v_pending, 'F2A'); end if;
  select decision.id into v_credit_id from public.com_pedido_credito_decisoes decision
   where decision.pedido_id = v_materialization.pedido_id
     and decision.confirmacao_comercial_id = v_confirmation.id
     and decision.documento_comercial_sha256 = v_confirmation.documento_canonico_sha256
     and decision.decisao = 'liberado'
   order by decision.created_at desc, decision.id desc limit 1;
  if v_credit_id is null then v_pending := array_append(v_pending, 'CREDITO'); end if;
  select evidence.id, decision.id into v_evidence_id, v_signature_id
    from public.com_pedido_assinatura_evidencias evidence
    join public.com_pedido_assinatura_decisoes decision on decision.evidencia_id = evidence.id
   where evidence.pedido_id = v_materialization.pedido_id
     and evidence.confirmacao_comercial_id = v_confirmation.id
     and evidence.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256
     and decision.pedido_id = v_materialization.pedido_id
     and decision.confirmacao_comercial_id = v_confirmation.id
     and decision.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256
     and decision.decisao = 'ACCEPTED'
   order by decision.decided_at desc, decision.id desc limit 1;
  if v_signature_id is null then v_pending := array_append(v_pending, 'ASSINATURA_COMPRADOR'); end if;
  v_has_below := exists (
    select 1 from public.com_pedido_item_precos_praticados fact
     where fact.revisao_id = p_revisao_id and fact.classificacao = 'BELOW_REFERENCE'
  );
  if v_has_below then
    select decision.id into v_discount_id from public.com_pedido_decisoes_desconto decision
     where decision.pedido_id = v_materialization.pedido_id
       and decision.confirmacao_comercial_id = v_confirmation.id
       and decision.comparacao_sha256 = v_confirmation.comparacao_sha256
       and decision.decisao = 'APPROVED'
     order by decision.decided_at desc, decision.id desc limit 1;
    if v_discount_id is null then v_pending := array_append(v_pending, 'APROVACAO_DESCONTO'); end if;
  end if;
  return jsonb_build_object(
    'pedido_id', v_materialization.pedido_id,
    'revisao_id', p_revisao_id,
    'current_f2b_confirmation_id', v_confirmation.id,
    'current_f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'credit_decision_id', v_credit_id,
    'signature_evidence_id', v_evidence_id,
    'signature_decision_id', v_signature_id,
    'discount_decision_id', v_discount_id,
    'f2a_valid', v_f2a_ok,
    'discount_required', v_has_below,
    'complete', cardinality(v_pending) = 0,
    'pending_conditions', to_jsonb(v_pending)
  );
end;
$$;

alter function public.avaliar_com_pedido_efetividade(bigint)
  rename to avaliar_com_pedido_efetividade_impl_0135;

create or replace function public.avaliar_com_pedido_efetividade(p_pedido_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_revision_id bigint;
begin
  select confirmation.revisao_id into v_revision_id
    from public.com_pedido_confirmacoes_comerciais confirmation
   where confirmation.pedido_id = p_pedido_id
   order by confirmation.numero_versao desc, confirmation.id desc limit 1;
  if v_revision_id is not null then
    -- Existing source-fact RPCs may record their independently governed fact in
    -- any order, but only the revision effectuation RPC may open the sale.
    return public.ord01_revisao_pre_efetiva_gates(v_revision_id)
      || jsonb_build_object('effective', false, 'revision_effectuation_required', true);
  end if;
  return public.avaliar_com_pedido_efetividade_impl_0135(p_pedido_id);
end;
$$;

create or replace function public.efetivar_com_pedido_revisao_idempotente(
  p_idempotency_key uuid,
  p_revisao_id bigint,
  p_gate_facts jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_actor_id();
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_order public.com_pedidos%rowtype;
  v_existing public.com_pedido_revisao_eventos%rowtype;
  v_payload_hash text;
  v_state jsonb;
  v_gates jsonb;
  v_event_id bigint;
  v_effective_at timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_previous_context text := current_setting('elite.effectiveness_context', true);
  v_audit_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.revision.effectuate');
  v_audit_context := public.begin_audited_rpc(
    'pedidos.revision.effectuate', 'pedidos', 'com_pedidos',
    'status_transition', jsonb_build_object('revisao_id', p_revisao_id, 'correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null or p_revisao_id is null or jsonb_typeof(p_gate_facts) <> 'object' then
    raise exception 'efetivacao exige chave, revisao e fatos de gate objeto';
  end if;
  v_payload_hash := public.ord01_revision_hash(jsonb_build_object('revisao_id', p_revisao_id, 'gate_facts', p_gate_facts));
  perform pg_advisory_xact_lock(hashtextextended(concat('ord01-revision:', p_revisao_id), 0));
  select * into v_existing from public.com_pedido_revisao_eventos where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.revisao_id is distinct from p_revisao_id
       or v_existing.payload_hash is distinct from v_payload_hash
       or v_existing.evento <> 'effective' then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return p_revisao_id;
  end if;
  select * into v_revision from public.com_pedido_revisoes_governadas where id = p_revisao_id for update;
  if not found then raise exception 'revisao nao encontrada'; end if;
  if not public.can_current_user_view_order(v_revision.pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  select * into v_order from public.com_pedidos where id = v_revision.pedido_id for update;
  if v_revision.tipo <> 'pre_efetivacao' then
    raise exception 'dimensao impactada sem consumidor downstream suportado';
  end if;
  if v_order.pedido_efetivado_em is not null then
    raise exception 'pedido ja foi efetivado; revisao posterior exige aditivo governado';
  end if;
  if exists (select 1 from public.com_pedido_revisao_eventos where revisao_id = p_revisao_id and evento in ('rejected','effective')) then
    raise exception 'revisao ja encerrada';
  end if;
  if not exists (select 1 from public.com_pedido_revisao_materializacoes where revisao_id = p_revisao_id) then
    perform public.materializar_com_pedido_revisao_pre_efetiva(p_revisao_id);
  end if;
  v_state := public.ord01_revision_current_contract_state(v_revision.pedido_id);
  if (v_state->>'sequence')::integer <> v_revision.base_sequence
     or v_state->>'contract_state_sha256' <> v_revision.base_contract_state_sha256 then
    raise exception 'base contratual obsoleta; revisao recusada';
  end if;
  v_gates := public.ord01_revisao_pre_efetiva_gates(p_revisao_id);
  if coalesce((v_gates->>'complete')::boolean, false) is not true then
    raise exception 'revisao permanece bloqueada: %', coalesce(v_gates->'pending_conditions', '[]'::jsonb);
  end if;
  insert into public.com_pedido_revisao_eventos(revisao_id, evento, idempotency_key, payload_hash, actor_id, payload_json)
  values (p_revisao_id, 'effective', p_idempotency_key, v_payload_hash, v_actor,
    jsonb_build_object('gate_facts', v_gates, 'base_sequence', v_revision.base_sequence))
  returning id into v_event_id;
  perform public.validate_com_pedido_status_transition(v_order.status, 'open', 'effectiveness_recognized');
  v_effective_at := clock_timestamp();
  v_before := public.com_pedido_audit_snapshot(v_order.id);
  perform set_config('elite.effectiveness_context', '1', true);
  begin
    update public.com_pedidos
       set status = 'open', pedido_efetivado_em = v_effective_at, updated_by = v_actor
     where id = v_order.id and status = 'blocked' and pedido_efetivado_em is null;
  exception when others then
    perform set_config('elite.effectiveness_context', coalesce(v_previous_context, ''), true);
    raise;
  end;
  perform set_config('elite.effectiveness_context', coalesce(v_previous_context, ''), true);
  v_after := public.com_pedido_audit_snapshot(v_order.id);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_order.id::text, 'pedidos.pedido_efetivado', 'pedidos.revision.effectuate',
    v_audit_context, v_before, v_after,
    jsonb_build_object(
      'pedido_id', v_order.id, 'revisao_id', p_revisao_id, 'evento_efetivo_id', v_event_id,
      'pedido_efetivado_em', v_effective_at,
      'current_f2b_confirmation_id', v_gates->'current_f2b_confirmation_id',
      'f2b_document_sha256', v_gates->'current_f2b_document_sha256',
      'credit_decision_id', v_gates->'credit_decision_id',
      'signature_evidence_id', v_gates->'signature_evidence_id',
      'signature_decision_id', v_gates->'signature_decision_id',
      'discount_decision_id', v_gates->'discount_decision_id'
    ), 'database_rpc'
  );
  return p_revisao_id;
end;
$$;

create or replace function public.ord01_contract_genesis_state_draft_0136(p_pedido_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_audit_count integer;
  v_audit_id bigint;
  v_f2b_id bigint;
  v_credit_id bigint;
  v_signature_evidence_id bigint;
  v_signature_decision_id bigint;
  v_base_state jsonb;
  v_fact_ids bigint[];
  v_reference_ids bigint[];
  v_plan_id bigint;
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id;
  if not found or v_order.pedido_efetivado_em is null then raise exception 'pedido ainda nao foi efetivado'; end if;
  select count(*), max(id) into v_audit_count, v_audit_id
    from public.action_logs
   where entity_type = 'com_pedidos' and entity_id = p_pedido_id::text and action = 'pedidos.pedido_efetivado';
  if v_audit_count <> 1 then raise exception 'UNRESOLVABLE: efetividade sem auditoria unica'; end if;
  select (metadata_json->>'current_f2b_confirmation_id')::bigint,
         (metadata_json->>'credit_decision_id')::bigint,
         (metadata_json->>'signature_evidence_id')::bigint,
         (metadata_json->>'signature_decision_id')::bigint
    into v_f2b_id, v_credit_id, v_signature_evidence_id, v_signature_decision_id
    from public.action_logs where id = v_audit_id;
  select * into v_confirmation from public.com_pedido_confirmacoes_comerciais
   where id = v_f2b_id and pedido_id = p_pedido_id;
  if not found then raise exception 'UNRESOLVABLE: confirmacao F2B efetiva ausente'; end if;
  if v_credit_id is null or v_signature_evidence_id is null or v_signature_decision_id is null then
    raise exception 'UNRESOLVABLE: fatos de gate efetivos incompletos';
  end if;
  if v_confirmation.revisao_id is not null then
    -- H0 is the immutable original commercial baseline, even when H1 was the
    -- first version to satisfy the effectiveness gates.  H1 remains the next
    -- hash-chain link; it must never be collapsed into genesis.
    v_base_state := public.ord01_revision_current_pre_effective_state(p_pedido_id);
    select coalesce(array_agg(fact.id order by fact.id), '{}'::bigint[]),
           coalesce(array_agg(reference.id order by reference.id), '{}'::bigint[]),
           min(reference.plano_pagamento_id)
      into v_fact_ids, v_reference_ids, v_plan_id
      from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_item_referencias_comerciais reference
        on reference.id = fact.referencia_comercial_id
     where fact.pedido_id = p_pedido_id
       and fact.revisao_id is null
       and reference.revisao_id is null;
  else
    v_base_state := public.ord01_revision_current_pre_effective_state(p_pedido_id);
    select coalesce(array_agg(fact.id order by fact.id), '{}'::bigint[]),
           coalesce(array_agg(snapshot.id order by snapshot.id), '{}'::bigint[]),
           min(snapshot.plano_pagamento_id)
      into v_fact_ids, v_reference_ids, v_plan_id
      from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_item_referencias_comerciais snapshot on snapshot.id = fact.referencia_comercial_id
     where fact.pedido_id = p_pedido_id and fact.revisao_id is null and snapshot.revisao_id is null;
  end if;
  if cardinality(v_fact_ids) = 0 or cardinality(v_reference_ids) = 0 or v_plan_id is null then
    raise exception 'UNRESOLVABLE: fatos efetivos F2A/F1D incompletos';
  end if;
  if cardinality(v_fact_ids) = 0 or cardinality(v_reference_ids) = 0 or v_plan_id is null then
    raise exception 'UNRESOLVABLE: fatos originais da genese incompletos';
  end if;
  -- The hashable H0 state is exactly the base consumed by a pre-effectiveness
  -- revision. Effectiveness evidence remains in the append-only audit and
  -- genesis columns, rather than mutating H0 after H1 has been requested.
  return v_base_state;
end;
$$;

create or replace function public.materializar_com_pedido_contrato_genese(p_pedido_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.com_pedido_contrato_geneses%rowtype;
  v_order public.com_pedidos%rowtype;
  v_state jsonb;
  v_actor uuid;
  v_audit_id bigint;
  v_credit_id bigint;
  v_signature_evidence_id bigint;
  v_signature_decision_id bigint;
  v_discount_id bigint;
  v_id bigint;
begin
  select * into v_existing from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id;
  if found then return v_existing.id; end if;
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found or v_order.pedido_efetivado_em is null then raise exception 'genese exige pedido efetivado'; end if;
  v_state := public.ord01_contract_genesis_state(p_pedido_id);
  select id,
         actor_user_id,
         nullif(metadata_json->>'credit_decision_id', '')::bigint,
         nullif(metadata_json->>'signature_evidence_id', '')::bigint,
         nullif(metadata_json->>'signature_decision_id', '')::bigint,
         nullif(metadata_json->>'discount_decision_id', '')::bigint
    into v_audit_id, v_actor, v_credit_id, v_signature_evidence_id,
         v_signature_decision_id, v_discount_id
   from public.action_logs
   where entity_type = 'com_pedidos'
     and entity_id = p_pedido_id::text
     and action = 'pedidos.pedido_efetivado'
   order by id desc limit 1;
  if v_audit_id is null or v_actor is null then
    raise exception 'UNRESOLVABLE: efetividade sem auditoria governada';
  end if;
  insert into public.com_pedido_contrato_geneses(
    pedido_id, effective_f2b_confirmation_id, effective_f2b_document_sha256,
    f2a_fact_ids, commercial_reference_ids, financial_plan_id,
    credit_decision_id, signature_evidence_id, signature_decision_id, discount_decision_id,
    effectiveness_audit_log_id, effective_actor_id, pedido_efetivado_em,
    contract_state_json, contract_state_sha256, created_by
  ) values (
    p_pedido_id, (v_state->>'f2b_confirmation_id')::bigint, v_state->>'f2b_document_sha256',
    array(select jsonb_array_elements_text(v_state->'gate_facts'->'f2a_fact_ids')::bigint),
    array(select jsonb_array_elements_text(v_state->'gate_facts'->'commercial_reference_ids')::bigint),
    (v_state->'gate_facts'->>'financial_plan_id')::bigint,
    v_credit_id,
    v_signature_evidence_id,
    v_signature_decision_id,
    v_discount_id,
    v_audit_id,
    v_actor, v_order.pedido_efetivado_em, v_state, public.ord01_revision_hash(v_state), v_actor
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.validate_com_pedido_confirmacao_comercial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_comparacao jsonb;
  v_possui_desconto boolean;
begin
  select * into v_pedido from public.com_pedidos where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'confirmacao comercial exige pedido de venda bloqueado';
  end if;
  if new.revisao_id is not null then
    if current_setting('elite.revision_materialization', true) <> '1' then
      raise exception 'confirmacao comercial versionada exige materializacao governada';
    end if;
    select * into v_revision from public.com_pedido_revisoes_governadas
     where id = new.revisao_id and pedido_id = new.pedido_id and tipo = 'pre_efetivacao';
    if not found or new.numero_versao <= 1 or new.versao_anterior_id is null then
      raise exception 'confirmacao comercial versionada nao possui linhagem F2B valida';
    end if;
    if new.documento_canonico_json is distinct from v_revision.resulting_contract_state_json->'f2b_document'
       or new.comparacao_sha256 is distinct from public.ord01_revision_hash(v_revision.resulting_contract_state_json->'f2a_comparison')
       or new.documento_canonico_sha256 is distinct from public.ord01_revision_hash(new.documento_canonico_json) then
      raise exception 'confirmacao comercial versionada diverge do estado contratual resultante';
    end if;
    return new;
  end if;
  if new.numero_versao = 1 and new.versao_anterior_id is not null then raise exception 'primeira versao comercial nao possui antecessora'; end if;
  if new.numero_versao > 1 then raise exception 'nova versao comercial exige revisao governada futura'; end if;
  v_comparacao := public.com_pedido_comparacao_comercial_documento(new.pedido_id);
  if jsonb_array_length(v_comparacao->'itens') = 0 then raise exception 'confirmacao comercial exige comparacao F2A completa'; end if;
  if exists (
    select 1 from public.com_pedido_itens item
     where item.pedido_id = new.pedido_id and item.status = 'active'
       and not exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_item_id = item.id and fact.revisao_id is null)
  ) then raise exception 'confirmacao comercial exige comparacao F2A de todos os itens ativos'; end if;
  v_possui_desconto := exists (select 1 from jsonb_array_elements(v_comparacao->'itens') item where item->>'classificacao' = 'BELOW_REFERENCE');
  if new.possui_desconto is distinct from v_possui_desconto
     or new.comparacao_sha256 is distinct from public.ord01_revision_hash(v_comparacao)
     or new.documento_canonico_sha256 is distinct from public.ord01_revision_hash(new.documento_canonico_json) then
    raise exception 'confirmacao comercial original diverge da comparacao F2A';
  end if;
  return new;
end;
$$;

create or replace function public.ord01_revision_impact_mask(p_base jsonb, p_result jsonb)
returns text[]
language plpgsql
immutable
as $$
declare
  v_mask text[] := '{}'::text[];
begin
  if p_base->'f2b_document' is distinct from p_result->'f2b_document'
     or p_base->'f2a_comparison' is distinct from p_result->'f2a_comparison'
     or p_base->'itens' is distinct from p_result->'itens'
     or p_base->'pricing' is distinct from p_result->'pricing' then
    v_mask := array_append(v_mask, 'pricing');
  end if;
  if p_base->'f2a_comparison' is distinct from p_result->'f2a_comparison'
     or p_base->'discount' is distinct from p_result->'discount' then
    v_mask := array_append(v_mask, 'discount');
  end if;
  if p_base->'financial_condition' is distinct from p_result->'financial_condition'
     or p_base->'condicao_financeira' is distinct from p_result->'condicao_financeira'
     or p_base->'financial' is distinct from p_result->'financial' then
    v_mask := array_append(v_mask, 'financial');
  end if;
  if p_base->'obrigacoes_contratuais' is distinct from p_result->'obrigacoes_contratuais'
     or p_base->'buyer_signature' is distinct from p_result->'buyer_signature' then
    v_mask := array_append(v_mask, 'buyer_signature');
  end if;
  if p_base->'commercial_context' is distinct from p_result->'commercial_context'
     or p_base->'contexto_comercial' is distinct from p_result->'contexto_comercial'
     or p_base->'commercial_resolution' is distinct from p_result->'commercial_resolution' then
    v_mask := array_append(v_mask, 'commercial_resolution');
  end if;
  if cardinality(v_mask) = 0 then
    raise exception 'delta de revisao nao possui dimensao material governada';
  end if;
  return v_mask;
end;
$$;

create or replace function public.ord01_revision_current_pre_effective_state(p_pedido_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_comparison jsonb;
  v_financial jsonb;
  v_state jsonb;
begin
  select * into v_confirmation
    from public.com_pedido_confirmacoes_comerciais
   where pedido_id = p_pedido_id
   order by numero_versao desc, id desc limit 1;
  if not found then raise exception 'pedido nao possui estado F2B governado'; end if;
  v_comparison := public.com_revisao_comercial_venda_comparacao_persistida(p_pedido_id);
  select jsonb_build_object(
    'plano_pagamento_id', plan.id,
    'versao', plan.versao,
    'pmp_dias', plan.pmp_dias,
    'valor_total_centavos', plan.valor_total_centavos,
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object(
      'numero_parcela', installment.numero_parcela,
      'forma_pagamento', installment.forma_pagamento,
      'valor_centavos', installment.valor_centavos,
      'data_vencimento', installment.data_vencimento,
      'dias_prazo', installment.dias_prazo
    ) order by installment.numero_parcela)
    from public.fin_pedido_parcelas installment where installment.plano_pagamento_id = plan.id), '[]'::jsonb)
  ) into v_financial
  from public.fin_pedido_planos_pagamento plan
  where plan.pedido_id = p_pedido_id
    and plan.origem_dados = 'sistema'
    and plan.review_status = 'approved'
    and plan.vigencia_inicio <= current_date
    and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date)
    and plan.pmp_dias is not null
  order by plan.versao desc, plan.id desc limit 1;
  if v_financial is null then raise exception 'pedido nao possui condicao financeira governada vigente'; end if;
  v_state := jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'f2b_confirmation_id', v_confirmation.id,
    'f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'f2b_document', v_confirmation.documento_canonico_json,
    'f2a_comparison', v_comparison,
    'financial_condition', v_financial
  );
  return v_state;
end;
$$;

create or replace function public.ord01_contract_genesis_state(p_pedido_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
  v_comparison jsonb;
  v_order public.com_pedidos%rowtype;
  v_audit_count integer;
  v_audit_id bigint;
  v_f2b_id bigint;
  v_effective_actor uuid;
  v_f2a_fact_ids bigint[];
  v_reference_ids bigint[];
  v_plan_ids bigint[];
  v_plan_id bigint;
  v_credit_id bigint;
  v_signature_evidence_id bigint;
  v_signature_decision_id bigint;
  v_discount_id bigint;
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id;
  if not found or v_order.pedido_efetivado_em is null then raise exception 'pedido ainda nao foi efetivado'; end if;
  select count(*), max(id)
    into v_audit_count, v_audit_id
    from public.action_logs
   where entity_type = 'com_pedidos'
     and entity_id = p_pedido_id::text
     and action = 'pedidos.pedido_efetivado';
  if v_audit_count <> 1 then raise exception 'UNRESOLVABLE: efetividade sem auditoria unica'; end if;
  select
    (metadata_json->>'current_f2b_confirmation_id')::bigint,
    (metadata_json->>'credit_decision_id')::bigint,
    (metadata_json->>'signature_evidence_id')::bigint,
    (metadata_json->>'signature_decision_id')::bigint,
    (metadata_json->>'discount_decision_id')::bigint
    into v_f2b_id, v_credit_id, v_signature_evidence_id,
         v_signature_decision_id, v_discount_id
    from public.action_logs
   where id = v_audit_id;
  select actor_user_id into v_effective_actor from public.action_logs where id = v_audit_id;
  select * into v_confirmation
    from public.com_pedido_confirmacoes_comerciais
   where id = v_f2b_id and pedido_id = p_pedido_id;
  if not found then raise exception 'UNRESOLVABLE: confirmacao F2B efetiva ausente'; end if;
  if v_credit_id is null or v_signature_evidence_id is null or v_signature_decision_id is null then
    raise exception 'UNRESOLVABLE: fatos de gate efetivos incompletos';
  end if;
  select coalesce(array_agg(fact.id order by fact.id), '{}'::bigint[]),
         coalesce(array_agg(distinct snapshot.id order by snapshot.id), '{}'::bigint[]),
         coalesce(array_agg(distinct snapshot.plano_pagamento_id order by snapshot.plano_pagamento_id), '{}'::bigint[])
    into v_f2a_fact_ids, v_reference_ids, v_plan_ids
    from public.com_pedido_item_precos_praticados fact
    join public.com_pedido_item_referencias_comerciais snapshot
      on snapshot.id = fact.referencia_comercial_id
   where fact.pedido_id = p_pedido_id
     and fact.revisao_id is null
     and snapshot.revisao_id is null;
  if cardinality(v_f2a_fact_ids) = 0 or cardinality(v_reference_ids) = 0 or cardinality(v_plan_ids) <> 1 then
    raise exception 'UNRESOLVABLE: fatos F2A ou condicao financeira nao deterministica';
  end if;
  v_plan_id := v_plan_ids[1];
  if v_discount_id is null and exists (
    select 1 from public.com_pedido_item_precos_praticados fact
     where fact.pedido_id = p_pedido_id and fact.revisao_id is null and fact.classificacao = 'BELOW_REFERENCE'
  ) then
    raise exception 'UNRESOLVABLE: aprovacao F2C efetiva ausente';
  end if;
  v_comparison := public.com_revisao_comercial_venda_comparacao_persistida(p_pedido_id);
  if jsonb_array_length(coalesce(v_comparison->'itens', '[]'::jsonb)) = 0 then
    raise exception 'efetividade sem fatos F2A congelados';
  end if;
  return jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'f2b_confirmation_id', v_confirmation.id,
    'f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'f2b_document', v_confirmation.documento_canonico_json,
    'f2a_comparison', v_comparison,
    'pedido_efetivado_em', v_order.pedido_efetivado_em,
    'gate_facts', jsonb_build_object(
      'f2a_fact_ids', to_jsonb(v_f2a_fact_ids),
      'commercial_reference_ids', to_jsonb(v_reference_ids),
      'financial_plan_id', v_plan_id,
      'credit_decision_id', v_credit_id,
      'signature_evidence_id', v_signature_evidence_id,
      'signature_decision_id', v_signature_decision_id,
      'discount_decision_id', v_discount_id,
      'effectiveness_audit_log_id', v_audit_id,
      'effective_actor_id', v_effective_actor
    )
  );
end;
$$;

create or replace function public.materializar_com_pedido_contrato_genese_draft_0136(p_pedido_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.com_pedido_contrato_geneses%rowtype;
  v_order public.com_pedidos%rowtype;
  v_state jsonb;
  v_actor uuid;
  v_id bigint;
begin
  select * into v_existing from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id;
  if found then return v_existing.id; end if;
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found or v_order.pedido_efetivado_em is null then raise exception 'contrato genese exige pedido efetivado'; end if;
  v_state := public.ord01_contract_genesis_state_draft_0136(p_pedido_id);
  v_actor := public.current_actor_id();
  insert into public.com_pedido_contrato_geneses(
    pedido_id, effective_f2b_confirmation_id, effective_f2b_document_sha256,
    f2a_fact_ids, commercial_reference_ids, financial_plan_id,
    credit_decision_id, signature_evidence_id, signature_decision_id,
    discount_decision_id, effectiveness_audit_log_id, effective_actor_id,
    pedido_efetivado_em, contract_state_json, contract_state_sha256, created_by
  ) values (
    p_pedido_id,
    (v_state->>'f2b_confirmation_id')::bigint,
    v_state->>'f2b_document_sha256',
    (select array_agg(value::bigint) from jsonb_array_elements_text(v_state->'gate_facts'->'f2a_fact_ids') value),
    (select array_agg(value::bigint) from jsonb_array_elements_text(v_state->'gate_facts'->'commercial_reference_ids') value),
    (v_state->'gate_facts'->>'financial_plan_id')::bigint,
    (v_state->'gate_facts'->>'credit_decision_id')::bigint,
    (v_state->'gate_facts'->>'signature_evidence_id')::bigint,
    (v_state->'gate_facts'->>'signature_decision_id')::bigint,
    nullif(v_state->'gate_facts'->>'discount_decision_id', '')::bigint,
    (v_state->'gate_facts'->>'effectiveness_audit_log_id')::bigint,
    (v_state->'gate_facts'->>'effective_actor_id')::uuid,
    v_order.pedido_efetivado_em,
    v_state,
    public.ord01_revision_hash(v_state),
    v_actor
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.validate_com_pedido_confirmacao_comercial_draft_0136()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_comparacao jsonb;
  v_possui_desconto boolean;
begin
  if current_setting('elite.revision_materialization', true) = '1' then
    select * into v_pedido from public.com_pedidos where id = new.pedido_id;
    if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
      raise exception 'confirmacao comercial exige pedido de venda bloqueado';
    end if;
    if new.numero_versao <= 1 or new.versao_anterior_id is null then
      raise exception 'materializacao de revisao exige sucessora F2B';
    end if;
    if new.documento_canonico_sha256 is distinct from public.ord01_revision_hash(new.documento_canonico_json) then
      raise exception 'hash do documento comercial divergente';
    end if;
    if (new.documento_canonico_json#>>'{pedido,pedido_id}')::bigint is distinct from new.pedido_id
       or (new.documento_canonico_json#>>'{versao_comercial,numero}')::integer is distinct from new.numero_versao then
      raise exception 'documento comercial diverge da identidade da versao';
    end if;
    return new;
  end if;
  if new.numero_versao = 1 and new.versao_anterior_id is not null then raise exception 'primeira versao comercial nao possui antecessora'; end if;
  if new.numero_versao > 1 then raise exception 'nova versao comercial exige revisao governada futura'; end if;
  v_comparacao := public.com_pedido_comparacao_comercial_documento(new.pedido_id);
  if jsonb_array_length(v_comparacao->'itens') = 0 then raise exception 'confirmacao comercial exige comparacao F2A completa'; end if;
  if exists (
    select 1 from public.com_pedido_itens item
     where item.pedido_id = new.pedido_id and item.status = 'active'
       and not exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_item_id = item.id)
  ) then raise exception 'confirmacao comercial exige comparacao F2A de todos os itens ativos'; end if;
  v_possui_desconto := exists (select 1 from jsonb_array_elements(v_comparacao->'itens') item where item->>'classificacao' = 'BELOW_REFERENCE');
  if new.possui_desconto is distinct from v_possui_desconto then raise exception 'classificacao de desconto diverge da comparacao F2A'; end if;
  if new.comparacao_sha256 is distinct from public.ord01_revision_hash(v_comparacao) then raise exception 'fingerprint da comparacao F2A divergente'; end if;
  if new.documento_canonico_sha256 is distinct from public.ord01_revision_hash(new.documento_canonico_json) then raise exception 'hash do documento comercial divergente'; end if;
  if (new.documento_canonico_json#>>'{pedido,pedido_id}')::bigint is distinct from new.pedido_id
     or (new.documento_canonico_json#>>'{versao_comercial,numero}')::integer is distinct from new.numero_versao then
    raise exception 'documento comercial diverge da identidade da versao';
  end if;
  return new;
end;
$$;

create or replace function public.materializar_com_pedido_revisao_pre_efetiva_draft_0136(p_revisao_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_order public.com_pedidos%rowtype;
  v_state jsonb;
  v_financial jsonb;
  v_item jsonb;
  v_old_snapshot public.com_pedido_item_referencias_comerciais%rowtype;
  v_item_row public.com_pedido_itens%rowtype;
  v_plan_id bigint;
  v_reference_id bigint;
  v_version integer;
  v_confirmation_id bigint;
  v_actor uuid := public.current_actor_id();
  v_document jsonb;
  v_has_discount boolean;
begin
  select * into v_revision from public.com_pedido_revisoes_governadas where id = p_revisao_id for update;
  if not found or v_revision.tipo <> 'pre_efetivacao' then
    raise exception 'materializacao exige revisao pre-efetivacao';
  end if;
  select * into v_order from public.com_pedidos where id = v_revision.pedido_id for update;
  if not found or v_order.status <> 'blocked' or v_order.pedido_efetivado_em is not null then
    raise exception 'materializacao pre-efetiva exige pedido bloqueado ainda nao efetivado';
  end if;
  v_state := v_revision.resulting_contract_state_json;
  v_financial := v_state->'financial_condition';
  if jsonb_array_length(v_state->'f2a_comparison'->'itens') <> (
    select count(*) from public.com_pedido_itens where pedido_id = v_order.id and status = 'active'
  ) then
    raise exception 'revisao nao possui comparacao completa de todos os itens ativos';
  end if;
  if exists (
    select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_id = v_order.id and fact.revisao_id = p_revisao_id
  ) then
    return;
  end if;
  perform set_config('elite.revision_materialization', '1', true);

  insert into public.fin_pedido_planos_pagamento(
    pedido_id, versao, vigencia_inicio, vigencia_fim, review_status, origem_dados,
    data_base, valor_total_centavos, pmp_dias, created_by, revisao_id
  ) values (
    v_order.id,
    coalesce((select max(versao) from public.fin_pedido_planos_pagamento where pedido_id = v_order.id), 0) + 1,
    v_order.data_pedido, null, 'approved', 'sistema', v_order.data_pedido,
    (v_financial->>'valor_total_centavos')::bigint,
    (v_financial->>'pmp_dias')::numeric, v_actor, p_revisao_id
  ) returning id into v_plan_id;
  insert into public.fin_pedido_parcelas(
    plano_pagamento_id, numero_parcela, data_vencimento, valor_previsto,
    review_status, origem_dados, forma_pagamento, valor_centavos, dias_prazo, created_by
  )
  select v_plan_id, (part->>'numero_parcela')::integer, (part->>'data_vencimento')::date,
    (part->>'valor_centavos')::numeric, 'approved', 'sistema', part->>'forma_pagamento',
    (part->>'valor_centavos')::bigint, (part->>'dias_prazo')::integer, v_actor
    from jsonb_array_elements(v_financial->'parcelas') part;

  for v_item in select value from jsonb_array_elements(v_state->'f2a_comparison'->'itens') loop
    select * into v_item_row from public.com_pedido_itens where id = (v_item->>'pedido_item_id')::bigint and pedido_id = v_order.id for update;
    if not found or v_item_row.status <> 'active' then raise exception 'item da revisao nao pertence ao pedido ativo'; end if;
    select * into v_old_snapshot from public.com_pedido_item_referencias_comerciais
     where pedido_item_id = v_item_row.id and revisao_id is null;
    if not found then raise exception 'item da revisao nao possui referencia comercial base'; end if;
    insert into public.com_pedido_item_referencias_comerciais(
      pedido_id, pedido_item_id, origem_comercial_id, cliente_id, area_comercial_id, uf,
      pessoa_papel_ids, produto_embalagem_id, data_comercial, plano_pagamento_id, pmp_dias,
      lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
      preco_referencia_centavos_por_litro, unidade_precificacao_id,
      quantidade_unidade_precificacao_por_apresentacao,
      preco_referencia_centavos_por_unidade_precificacao, resolved_by, lineage_json, revisao_id
    ) values (
      v_order.id, v_item_row.id, (v_item->>'origem_comercial_id')::bigint,
      v_order.cliente_id, nullif(v_item->>'area_comercial_id','')::bigint, nullif(v_item->>'uf',''),
      coalesce((select array_agg(value::bigint) from jsonb_array_elements_text(v_item->'pessoa_papel_ids') value), '{}'::bigint[]),
      v_item_row.produto_embalagem_id, v_order.data_pedido, v_plan_id,
      (v_item->>'pmp_dias')::numeric, (v_item->>'lista_id')::bigint, (v_item->>'lista_versao_id')::bigint,
      (v_item->>'publicacao_id')::bigint, (v_item->>'regra_id')::bigint, (v_item->>'prazo_faixa_dias')::integer,
      v_old_snapshot.preco_referencia_centavos_por_litro,
      (v_item->>'unidade_precificacao_id')::bigint,
      (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric,
      (v_item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint,
      v_actor, jsonb_build_object('revision_id', p_revisao_id, 'source', '0136'), p_revisao_id
    ) returning id into v_reference_id;
    insert into public.com_pedido_item_precos_praticados(
      pedido_id, pedido_item_id, referencia_comercial_id, unidade_precificacao_id,
      quantidade_apresentacoes, quantidade_unidade_precificacao_por_apresentacao,
      quantidade_unidade_precificacao, preco_referencia_centavos_por_unidade_precificacao,
      preco_praticado_centavos_por_unidade_precificacao, diferenca_centavos_por_unidade_precificacao,
      percentual_diferenca, valor_referencia_centavos, valor_praticado_centavos,
      impacto_financeiro_centavos, classificacao, motivo, recorded_by, revisao_id
    ) values (
      v_order.id, v_item_row.id, v_reference_id, (v_item->>'unidade_precificacao_id')::bigint,
      v_item_row.quantidade, (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric,
      (v_item->>'quantidade_unidade_precificacao')::numeric,
      (v_item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'diferenca_centavos_por_unidade_precificacao')::bigint,
      (v_item->>'percentual_diferenca')::numeric, (v_item->>'valor_referencia_centavos')::bigint,
      (v_item->>'valor_praticado_centavos')::bigint, (v_item->>'impacto_financeiro_centavos')::bigint,
      v_item->>'classificacao', coalesce(nullif(v_item->>'motivo',''), 'revisao contratual governada'), v_actor, p_revisao_id
    );
  end loop;
  v_has_discount := exists (select 1 from jsonb_array_elements(v_state->'f2a_comparison'->'itens') item where item->>'classificacao' = 'BELOW_REFERENCE');
  select coalesce(max(numero_versao), 0) + 1 into v_version from public.com_pedido_confirmacoes_comerciais where pedido_id = v_order.id;
  v_document := jsonb_set(v_state->'f2b_document', '{versao_comercial,numero}', to_jsonb(v_version), true);
  v_document := jsonb_set(v_document, '{pedido,pedido_id}', to_jsonb(v_order.id), true);
  insert into public.com_pedido_confirmacoes_comerciais(
    pedido_id, numero_versao, versao_anterior_id, possui_desconto, justificativa_comercial,
    descontos_confirmados, comparacao_sha256, preview_hash, documento_canonico_json,
    documento_canonico_sha256, confirmed_by, confirmed_at, revisao_id
  ) values (
    v_order.id, v_version,
    (select id from public.com_pedido_confirmacoes_comerciais where pedido_id = v_order.id and revisao_id is null order by numero_versao desc limit 1),
    v_has_discount, nullif(v_document#>>'{comercial,justificativa}', ''), v_has_discount,
    public.ord01_revision_hash(v_state->'f2a_comparison'), public.ord01_revision_hash(v_state),
    v_document, public.ord01_revision_hash(v_document), v_actor, clock_timestamp(), p_revisao_id
  ) returning id into v_confirmation_id;
  if v_confirmation_id is null or v_plan_id is null then raise exception 'materializacao da revisao nao produziu fatos completos'; end if;
  perform set_config('elite.revision_materialization', '', true);
exception when others then
  perform set_config('elite.revision_materialization', '', true);
  raise;
end;
$$;

create or replace function public.materializar_com_pedido_contrato_genese_apos_efetividade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.pedido_efetivado_em is null and new.pedido_efetivado_em is not null then
    perform public.materializar_com_pedido_contrato_genese(new.id);
  end if;
  return new;
end;
$$;

revoke all on function public.materializar_com_pedido_contrato_genese_apos_efetividade() from public, anon, authenticated;
drop trigger if exists trg_com_pedido_contrato_genese_apos_efetividade on public.com_pedidos;
create constraint trigger trg_com_pedido_contrato_genese_apos_efetividade
after update of pedido_efetivado_em on public.com_pedidos
deferrable initially deferred
for each row when (old.pedido_efetivado_em is null and new.pedido_efetivado_em is not null)
execute function public.materializar_com_pedido_contrato_genese_apos_efetividade();

create or replace function public.ord01_revision_current_contract_state_draft_0136(p_pedido_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_genesis public.com_pedido_contrato_geneses%rowtype;
  v_state jsonb;
  v_revision record;
  v_expected_hash text;
  v_expected_sequence integer := 0;
begin
  select * into v_order from public.com_pedidos where id = p_pedido_id;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_order.pedido_efetivado_em is null then
    return jsonb_build_object(
      'sequence', 0,
      'contract_state_sha256', public.ord01_revision_hash(public.ord01_revision_current_pre_effective_state(p_pedido_id)),
      'contract_state', public.ord01_revision_current_pre_effective_state(p_pedido_id),
      'source', 'current_f2b_state'
    );
  end if;
  select * into v_genesis from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id;
  if not found then
    raise exception 'UNRESOLVABLE: contrato genese nao materializado';
  end if;
  v_state := v_genesis.contract_state_json;
  v_expected_hash := v_genesis.contract_state_sha256;
  for v_revision in
    select revision.*
      from public.com_pedido_revisoes_governadas revision
     where revision.pedido_id = p_pedido_id and revision.tipo = 'aditivo'
       and exists (select 1 from public.com_pedido_revisao_eventos event where event.revisao_id = revision.id and event.evento = 'effective')
     order by revision.sequence, revision.id
  loop
    if v_revision.base_sequence <> v_expected_sequence
       or v_revision.base_contract_state_sha256 <> v_expected_hash
      or v_revision.sequence <> v_expected_sequence + 1
       or (v_revision.base_event_id is not null and not exists (
         select 1
           from public.com_pedido_revisao_eventos event
           join public.com_pedido_revisoes_governadas base_revision on base_revision.id = event.revisao_id
          where event.id = v_revision.base_event_id
            and base_revision.pedido_id = p_pedido_id
            and base_revision.sequence = v_revision.base_sequence
            and event.evento = 'effective'
       ))
       or public.ord01_revision_hash(v_revision.delta_json) <> v_revision.delta_sha256
       or public.ord01_apply_com_pedido_contract_delta(v_state, v_revision.delta_json) <> v_revision.resulting_contract_state_json
       or v_revision.resulting_contract_state_sha256 <> public.ord01_revision_hash(v_revision.resulting_contract_state_json)
       or v_revision.base_sequence <> v_revision.sequence - 1 then
      raise exception 'cadeia contratual inconsistente';
    end if;
    v_state := v_revision.resulting_contract_state_json;
    v_expected_hash := v_revision.resulting_contract_state_sha256;
    v_expected_sequence := v_revision.sequence;
  end loop;
  return jsonb_build_object(
    'sequence', v_expected_sequence,
    'contract_state_sha256', v_expected_hash,
    'contract_state', v_state,
    'source', 'contract_chain'
  );
end;
$$;

create or replace function public.resolver_com_pedido_contrato_vigente(p_pedido_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.ord01_revision_current_contract_state(p_pedido_id);
$$;

create or replace function public.consultar_com_pedido_contrato_vigente(p_pedido_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not public.can_current_user_view_order(p_pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  perform public.require_current_user_permission('pedidos.revision.view');
  return public.resolver_com_pedido_contrato_vigente(p_pedido_id);
end;
$$;

create or replace function public.solicitar_com_pedido_revisao_idempotente_draft_0136(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_delta_json jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_actor_id();
  v_order public.com_pedidos%rowtype;
  v_existing public.com_pedido_revisoes_governadas%rowtype;
  v_state jsonb;
  v_mask text[];
  v_tipo text;
  v_sequence integer;
  v_base_sequence integer;
  v_base_hash text;
  v_base_f2b bigint;
  v_base_event_id bigint;
  v_result jsonb;
  v_delta_hash text;
  v_result_hash text;
  v_payload_hash text;
  v_id bigint;
begin
  perform public.require_current_user_permission('pedidos.revision.request');
  if p_idempotency_key is null or p_pedido_id is null or jsonb_typeof(p_delta_json) <> 'object' then
    raise exception 'revisao exige chave, pedido e delta objeto';
  end if;
  if not public.can_current_user_view_order(p_pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  v_payload_hash := public.ord01_revision_hash(jsonb_build_object('pedido_id', p_pedido_id, 'delta', p_delta_json));
  perform pg_advisory_xact_lock(hashtextextended(concat('ord01-revision:', p_pedido_id), 0));
  select * into v_existing from public.com_pedido_revisoes_governadas where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.created_by is distinct from v_actor or v_existing.payload_hash <> v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.id;
  end if;
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found or v_order.tipo_pedido <> 'venda' then raise exception 'revisao exige pedido de venda'; end if;
  if exists (
    select 1 from public.com_pedido_revisoes_governadas revision
     where revision.pedido_id = p_pedido_id
       and not exists (select 1 from public.com_pedido_revisao_eventos event where event.revisao_id = revision.id and event.evento in ('rejected','effective'))
  ) then raise exception 'pedido ja possui revisao material ativa'; end if;
  if v_order.pedido_efetivado_em is not null
     and not exists (select 1 from public.com_pedido_contrato_geneses where pedido_id = p_pedido_id) then
    perform public.materializar_com_pedido_contrato_genese(p_pedido_id);
  end if;
  v_state := public.ord01_revision_current_contract_state(p_pedido_id);
  v_tipo := case when v_order.pedido_efetivado_em is null then 'pre_efetivacao' else 'aditivo' end;
  v_base_sequence := coalesce((v_state->>'sequence')::integer, 0);
  v_base_hash := v_state->>'contract_state_sha256';
  v_base_f2b := nullif(v_state->'contract_state'->>'f2b_confirmation_id', '')::bigint;
  select event.id into v_base_event_id
    from public.com_pedido_revisoes_governadas previous_revision
    join public.com_pedido_revisao_eventos event on event.revisao_id = previous_revision.id
   where previous_revision.pedido_id = p_pedido_id
     and previous_revision.sequence = v_base_sequence
     and event.evento = 'effective'
   order by event.id desc
   limit 1;
  select coalesce(max(sequence), 0) + 1 into v_sequence
    from public.com_pedido_revisoes_governadas where pedido_id = p_pedido_id;
  v_delta_hash := public.ord01_revision_hash(p_delta_json);
  v_result := public.ord01_apply_com_pedido_contract_delta(v_state->'contract_state', p_delta_json);
  v_mask := public.ord01_revision_impact_mask(v_state->'contract_state', v_result);
  v_result_hash := public.ord01_revision_hash(v_result);
  insert into public.com_pedido_revisoes_governadas(
    pedido_id, tipo, sequence, base_f2b_confirmation_id, base_sequence,
    base_contract_state_sha256, base_event_id, delta_json, delta_sha256,
    resulting_contract_state_json, resulting_contract_state_sha256,
    impact_mask, idempotency_key, payload_hash, created_by
  ) values (
    p_pedido_id, v_tipo, v_sequence, v_base_f2b, v_base_sequence,
    v_base_hash, v_base_event_id, p_delta_json, v_delta_hash, v_result, v_result_hash,
    v_mask, p_idempotency_key, v_payload_hash, v_actor
  ) returning id into v_id;
  insert into public.com_pedido_revisao_eventos(revisao_id, evento, idempotency_key, payload_hash, actor_id, payload_json)
  values (v_id, 'requested', p_idempotency_key, v_payload_hash, v_actor,
    jsonb_build_object('impact_mask', to_jsonb(v_mask), 'base_sequence', v_base_sequence));
  insert into public.com_pedido_revisao_eventos(revisao_id, evento, actor_id, payload_json)
  values (v_id, 'pending', v_actor, jsonb_build_object(
    'reason', case when v_tipo = 'pre_efetivacao' then 'nova versao F2B exige materializacao governada dos fatos derivados' else 'capacidade downstream deve ser comprovada antes do aditivo' end,
    'unsupported_dimensions', to_jsonb(v_mask)
  ));
  if v_tipo = 'pre_efetivacao' then
    perform public.materializar_com_pedido_revisao_pre_efetiva(v_id);
  end if;
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_revisoes_governadas', v_id::text,
    'pedidos.revisao.solicitada', 'pedidos.revision.request',
    jsonb_build_object('actor_id', v_actor, 'pedido_id', p_pedido_id), null,
    jsonb_build_object('pedido_id', p_pedido_id, 'tipo', v_tipo, 'sequence', v_sequence, 'impact_mask', to_jsonb(v_mask)),
    jsonb_build_object('base_hash', v_base_hash, 'delta_hash', v_delta_hash), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.efetivar_com_pedido_revisao_idempotente_draft_0136(
  p_idempotency_key uuid,
  p_revisao_id bigint,
  p_gate_facts jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_order public.com_pedidos%rowtype;
begin
  perform public.require_current_user_permission('pedidos.revision.effectuate');
  select * into v_revision from public.com_pedido_revisoes_governadas where id = p_revisao_id for update;
  if not found then raise exception 'revisao nao encontrada'; end if;
  select * into v_order from public.com_pedidos where id = v_revision.pedido_id for update;
  if v_revision.tipo = 'pre_efetivacao' then
    if not exists (select 1 from public.com_pedido_item_precos_praticados where revisao_id = v_revision.id) then
      perform public.materializar_com_pedido_revisao_pre_efetiva(v_revision.id);
    end if;
    raise exception 'nova versao F2B materializada; gates da versao atual ainda nao estao completos';
  end if;
  if not exists (select 1 from public.com_pedido_contrato_geneses where pedido_id = v_revision.pedido_id) then
    perform public.materializar_com_pedido_contrato_genese(v_revision.pedido_id);
  end if;
  if (public.resolver_com_pedido_contrato_vigente(v_revision.pedido_id)->>'sequence')::integer <> v_revision.base_sequence
     or public.resolver_com_pedido_contrato_vigente(v_revision.pedido_id)->>'contract_state_sha256' <> v_revision.base_contract_state_sha256 then
    raise exception 'base contratual obsoleta; aditivo recusado';
  end if;
  raise exception 'dimensao impactada sem consumidor downstream suportado';
end;
$$;

create or replace function public.encerrar_com_pedido_revisao_idempotente(
  p_idempotency_key uuid,
  p_revisao_id bigint,
  p_justificativa text,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_actor_id();
  v_revision public.com_pedido_revisoes_governadas%rowtype;
  v_payload_hash text;
  v_existing public.com_pedido_revisao_eventos%rowtype;
  v_event_id bigint;
  v_audit_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.revision.request');
  v_audit_context := public.begin_audited_rpc(
    'pedidos.revision.request', 'pedidos', 'com_pedido_revisoes_governadas',
    'status_transition', jsonb_build_object('revisao_id', p_revisao_id, 'correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null or p_revisao_id is null then
    raise exception 'encerramento exige chave e revisao';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'justificativa de rejeicao deve ter ao menos 10 caracteres';
  end if;
  v_payload_hash := public.ord01_revision_hash(jsonb_build_object(
    'revisao_id', p_revisao_id,
    'justificativa', btrim(p_justificativa),
    'motivo', btrim(coalesce(p_motivo, ''))
  ));
  perform pg_advisory_xact_lock(hashtextextended(concat('ord01-revision:', p_revisao_id), 0));
  select * into v_existing
    from public.com_pedido_revisao_eventos
   where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.revisao_id is distinct from p_revisao_id
       or v_existing.payload_hash is distinct from v_payload_hash
       or v_existing.evento <> 'rejected' then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return p_revisao_id;
  end if;
  select * into v_revision
    from public.com_pedido_revisoes_governadas
   where id = p_revisao_id for update;
  if not found then raise exception 'revisao nao encontrada'; end if;
  perform 1 from public.com_pedidos where id = v_revision.pedido_id for update;
  if not found or not public.can_current_user_view_order(v_revision.pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  if exists (select 1 from public.com_pedido_revisao_eventos where revisao_id = p_revisao_id and evento in ('rejected','effective')) then
    raise exception 'revisao ja encerrada';
  end if;
  insert into public.com_pedido_revisao_eventos(
    revisao_id, evento, idempotency_key, payload_hash, actor_id, payload_json
  ) values (
    p_revisao_id, 'rejected', p_idempotency_key, v_payload_hash, v_actor,
    jsonb_build_object('justificativa', btrim(p_justificativa), 'motivo', btrim(coalesce(p_motivo, '')))
  ) returning id into v_event_id;
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_revisoes_governadas', p_revisao_id::text,
    'pedidos.revisao.rejeitada', 'pedidos.revision.request',
    v_audit_context, null,
    jsonb_build_object('revisao_id', p_revisao_id, 'evento_id', v_event_id),
    jsonb_build_object('justificativa', btrim(p_justificativa)), 'database_rpc'
  );
  return p_revisao_id;
end;
$$;

-- SIG01 functions invoked by the 0136 effectiveness/revision smoke must use the
-- current ten-argument audited-RPC contract.  This is an additive repair of the
-- deployed definition; migration 0133 remains immutable.
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
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_assinatura_evidencias', v_id::text,
    'pedidos.buyer_signature.submitted', 'pedidos.buyer_signature.submit', v_context,
    null, jsonb_build_object('pedido_id', p_pedido_id, 'status', 'PENDING', 'accepted', false),
    jsonb_build_object('source', '0136_audit_contract_repair'), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.decidir_com_pedido_assinatura_idempotente_impl_0135(
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
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_assinatura_decisoes', v_decision_id::text,
    case when p_decisao = 'ACCEPTED' then 'pedidos.buyer_signature.accepted' else 'pedidos.buyer_signature.rejected' end,
    'pedidos.buyer_signature.review', v_context, null,
    jsonb_build_object('pedido_id', v_evidence.pedido_id, 'status', p_decisao, 'pedido_permanece_bloqueado', true),
    jsonb_build_object('source', '0136_audit_contract_repair'), 'database_rpc'
  );
  return v_decision_id;
end;
$$;

-- Preserve the existing effectiveness semantics while repairing the SIG01
-- decision timestamp column through this additive migration.
create or replace function public.com_pedido_efetividade_estado(p_pedido_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
  select max(confirmation.numero_versao) into v_current_version
    from public.com_pedido_confirmacoes_comerciais confirmation where confirmation.pedido_id = p_pedido_id;
  if v_current_version is not null then
    select * into v_confirmation from public.com_pedido_confirmacoes_comerciais confirmation
     where confirmation.pedido_id = p_pedido_id and confirmation.numero_versao = v_current_version;
  end if;
  if v_confirmation.id is not null then
    v_comparison := public.com_pedido_comparacao_comercial_documento(p_pedido_id);
    v_comparison_sha256 := encode(extensions.digest(convert_to(v_comparison::text, 'UTF8'), 'sha256'), 'hex');
    select count(*) into v_active_items from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id and item.status = 'active' and item.tipo_item = 'venda';
    select count(*) into v_priced_items from public.com_pedido_item_precos_praticados fact
      join public.com_pedido_itens item on item.id = fact.pedido_item_id
     where fact.pedido_id = p_pedido_id and item.pedido_id = p_pedido_id and item.status = 'active' and item.tipo_item = 'venda';
    v_f2a_ok := v_active_items > 0 and v_active_items = v_priced_items and v_comparison_sha256 = v_confirmation.comparacao_sha256;
    select * into v_credit from public.com_pedido_credito_decisoes decision
     where decision.pedido_id = p_pedido_id order by decision.created_at desc, decision.id desc limit 1;
    v_credit_decision_id := v_credit.id;
    v_credit_ok := v_credit.id is not null and v_credit.decisao = 'liberado'
      and v_credit.confirmacao_comercial_id = v_confirmation.id
      and v_credit.documento_comercial_sha256 = v_confirmation.documento_canonico_sha256;
    select evidence.id, decision.id into v_signature_evidence_id, v_signature_decision_id
      from public.com_pedido_assinatura_evidencias evidence join public.com_pedido_assinatura_decisoes decision on decision.evidencia_id = evidence.id
     where evidence.pedido_id = p_pedido_id and evidence.confirmacao_comercial_id = v_confirmation.id
       and evidence.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256
       and decision.pedido_id = p_pedido_id and decision.confirmacao_comercial_id = v_confirmation.id
       and decision.documento_canonico_sha256 = v_confirmation.documento_canonico_sha256 and decision.decisao = 'ACCEPTED'
     order by decision.decided_at desc, decision.id desc limit 1;
    v_signature_ok := found;
    select exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_id = p_pedido_id and fact.classificacao = 'BELOW_REFERENCE') into v_has_below;
    if v_has_below then
      select decision.id into v_discount_decision_id from public.com_pedido_decisoes_desconto decision
       where decision.pedido_id = p_pedido_id and decision.confirmacao_comercial_id = v_confirmation.id
         and decision.comparacao_sha256 = v_confirmation.comparacao_sha256 and decision.decisao = 'APPROVED'
       order by decision.decided_at desc, decision.id desc limit 1;
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
    'pedido_id', p_pedido_id, 'tipo_pedido', v_order.tipo_pedido, 'status', v_order.status,
    'pedido_efetivado_em', v_order.pedido_efetivado_em, 'current_f2b_version', v_current_version,
    'current_f2b_confirmation_id', nullif(v_confirmation.id, 0), 'current_f2b_document_sha256', v_confirmation.documento_canonico_sha256,
    'credit_decision_id', v_credit_decision_id, 'signature_evidence_id', v_signature_evidence_id,
    'signature_decision_id', v_signature_decision_id, 'discount_decision_id', v_discount_decision_id,
    'f2a_valid', v_f2a_ok, 'credit_valid', v_credit_ok, 'signature_valid', v_signature_ok,
    'discount_required', v_has_below, 'discount_valid', v_discount_ok,
    'complete', v_confirmation.id is not null and v_f2a_ok and v_credit_ok and v_signature_ok and v_discount_ok,
    'pending_conditions', to_jsonb(v_pending)
  );
end;
$$;

revoke all on function public.com_pedido_efetividade_estado(bigint) from public, anon, authenticated;

revoke all on function public.ord01_revision_hash(jsonb) from public, anon, authenticated;
revoke all on function public.ord01_apply_com_pedido_contract_delta(jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.ord01_revision_impact_mask(jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.ord01_revision_current_pre_effective_state(bigint) from public, anon, authenticated;
revoke all on function public.ord01_contract_genesis_state(bigint) from public, anon, authenticated;
revoke all on function public.materializar_com_pedido_contrato_genese(bigint) from public, anon, authenticated;
revoke all on function public.ord01_revision_current_contract_state(bigint) from public, anon, authenticated;
revoke all on function public.resolver_com_pedido_contrato_vigente(bigint) from public, anon, authenticated;
revoke all on function public.consultar_com_pedido_contrato_vigente(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_contrato_vigente(bigint) to authenticated;
revoke all on function public.solicitar_com_pedido_revisao_idempotente(uuid,bigint,jsonb) from public, anon;
grant execute on function public.solicitar_com_pedido_revisao_idempotente(uuid,bigint,jsonb) to authenticated;
revoke all on function public.efetivar_com_pedido_revisao_idempotente(uuid,bigint,jsonb) from public, anon;
grant execute on function public.efetivar_com_pedido_revisao_idempotente(uuid,bigint,jsonb) to authenticated;
revoke all on function public.encerrar_com_pedido_revisao_idempotente(uuid,bigint,text,text) from public, anon;
grant execute on function public.encerrar_com_pedido_revisao_idempotente(uuid,bigint,text,text) to authenticated;

-- The idempotent manager-decision RPC remains the only application entrypoint.
-- Internal SECURITY DEFINER composition continues to call the credit function
-- as its owner, without exposing the non-idempotent function to app roles.
revoke all on function public.registrar_com_pedido_decisao_credito(bigint,text,text,numeric,numeric,text)
  from public, anon, authenticated;

comment on table public.com_pedido_contrato_geneses is
  'ORD-01: H0 imutavel do contrato comercial efetivo. Nao e republicacao nem substitui pedido_efetivado_em.';
comment on table public.com_pedido_revisoes_governadas is
  'ORD-01: revisao pre-efetivacao ou aditivo pos-efetivacao com delta e cadeia SHA-256 append-only.';
comment on table public.com_pedido_revisao_eventos is
  'ORD-01: eventos append-only do ciclo de revisao; revisao pendente nao altera o contrato vigente.';
comment on function public.resolver_com_pedido_contrato_vigente(bigint) is
  'ORD-01: projecao canonica do contrato vigente; falha fechado quando a cadeia H0..Hn e inconsistente.';
comment on function public.efetivar_com_pedido_revisao_idempotente(uuid,bigint,jsonb) is
  'ORD-01: efetivacao bloqueada enquanto a dimensao impactada nao possuir consumidor downstream suportado.';

-- ORD-01 0136 final integrity pass: versioned derived facts are private and
-- cannot be confused with the immutable legacy item/fact set.
create trigger trg_com_pedido_revisao_itens_append_only
before update or delete on public.com_pedido_revisao_itens
for each row execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisao_itens_no_truncate
before truncate on public.com_pedido_revisao_itens
for each statement execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisao_materializacoes_append_only
before update or delete on public.com_pedido_revisao_materializacoes
for each row execute function public.validate_com_pedido_revision_append_only();
create trigger trg_com_pedido_revisao_materializacoes_no_truncate
before truncate on public.com_pedido_revisao_materializacoes
for each statement execute function public.validate_com_pedido_revision_append_only();

create or replace function public.prevent_fin_pedido_plan_change_after_commercial_snapshot()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.revisao_id is not null then
    if current_setting('elite.revision_materialization', true) <> '1' then
      raise exception 'plano financeiro versionado exige materializacao governada';
    end if;
    if not exists (
      select 1 from public.com_pedido_revisoes_governadas revision
       where revision.id = new.revisao_id
         and revision.pedido_id = new.pedido_id
         and revision.tipo = 'pre_efetivacao'
    ) then
      raise exception 'plano financeiro versionado nao pertence a revisao pre-efetiva do pedido';
    end if;
    return new;
  end if;
  if exists (
    select 1 from public.com_pedido_item_referencias_comerciais snapshot
     where snapshot.pedido_id = new.pedido_id
       and snapshot.revisao_id is null
  ) then
    raise exception 'snapshot comercial ja foi congelado; nova condicao financeira exige revisao governada';
  end if;
  return new;
end;
$$;

create or replace function public.validate_com_pedido_item_referencia_revisionada()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_item public.com_pedido_revisao_itens%rowtype;
begin
  if new.revisao_id is null then
    if new.revisao_item_id is not null then
      raise exception 'referencia comercial original nao pode apontar item de revisao';
    end if;
    return new;
  end if;
  if current_setting('elite.revision_materialization', true) <> '1' then
    raise exception 'referencia comercial versionada exige materializacao governada';
  end if;
  select * into v_item from public.com_pedido_revisao_itens where id = new.revisao_item_id;
  if not found
     or v_item.revisao_id is distinct from new.revisao_id
     or v_item.pedido_id is distinct from new.pedido_id
     or v_item.pedido_item_origem_id is distinct from new.pedido_item_id
     or v_item.produto_embalagem_id is distinct from new.produto_embalagem_id
     or v_item.unidade_precificacao_id is distinct from new.unidade_precificacao_id
     or v_item.quantidade_unidade_precificacao_por_apresentacao is distinct from new.quantidade_unidade_precificacao_por_apresentacao then
    raise exception 'referencia comercial versionada diverge do item comercial resultante';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_com_pedido_item_referencias_revision_validate on public.com_pedido_item_referencias_comerciais;
create trigger trg_com_pedido_item_referencias_revision_validate
before insert on public.com_pedido_item_referencias_comerciais
for each row execute function public.validate_com_pedido_item_referencia_revisionada();

create or replace function public.validate_com_pedido_item_preco_praticado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_snapshot public.com_pedido_item_referencias_comerciais%rowtype;
  v_item public.com_pedido_itens%rowtype;
  v_revision_item public.com_pedido_revisao_itens%rowtype;
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
  if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'preco praticado exige pedido de venda bloqueado';
  end if;
  if v_item.pedido_id <> new.pedido_id or v_item.status <> 'active' or v_item.tipo_item <> 'venda' then
    raise exception 'preco praticado exige item de venda ativo do pedido';
  end if;

  if new.revisao_id is null then
    if new.revisao_item_id is not null or v_snapshot.revisao_id is not null or v_snapshot.revisao_item_id is not null then
      raise exception 'fato original nao pode usar referencia comercial versionada';
    end if;
    if v_snapshot.pedido_id is distinct from v_pedido.id
       or v_snapshot.pedido_item_id is distinct from v_item.id
       or v_snapshot.produto_embalagem_id is distinct from v_item.produto_embalagem_id
       or v_snapshot.cliente_id is distinct from v_pedido.cliente_id
       or v_snapshot.data_comercial is distinct from v_pedido.data_pedido
       or v_snapshot.origem_comercial_id is distinct from v_pedido.origem_comercial_id then
      raise exception 'referencia comercial congelada diverge da identidade material do pedido';
    end if;
    if new.quantidade_apresentacoes is distinct from v_item.quantidade then
      raise exception 'fato de preco praticado diverge do item original';
    end if;
  else
    if current_setting('elite.revision_materialization', true) <> '1' then
      raise exception 'fato de preco praticado versionado exige materializacao governada';
    end if;
    select * into v_revision_item from public.com_pedido_revisao_itens where id = new.revisao_item_id;
    if not found
       or v_revision_item.revisao_id is distinct from new.revisao_id
       or v_revision_item.pedido_id is distinct from new.pedido_id
       or v_revision_item.pedido_item_origem_id is distinct from new.pedido_item_id
       or v_snapshot.revisao_id is distinct from new.revisao_id
       or v_snapshot.revisao_item_id is distinct from new.revisao_item_id
       or v_snapshot.produto_embalagem_id is distinct from v_revision_item.produto_embalagem_id
       or new.quantidade_apresentacoes is distinct from v_revision_item.quantidade_apresentacoes then
      raise exception 'fato de preco praticado diverge do item comercial resultante';
    end if;
  end if;

  if v_snapshot.unidade_precificacao_id is null
     or v_snapshot.quantidade_unidade_precificacao_por_apresentacao is null
     or v_snapshot.quantidade_unidade_precificacao_por_apresentacao <= 0
     or v_snapshot.preco_referencia_centavos_por_unidade_precificacao is null
     or v_snapshot.preco_referencia_centavos_por_unidade_precificacao <= 0
     or new.unidade_precificacao_id is distinct from v_snapshot.unidade_precificacao_id
     or new.quantidade_unidade_precificacao_por_apresentacao is distinct from v_snapshot.quantidade_unidade_precificacao_por_apresentacao
     or new.preco_referencia_centavos_por_unidade_precificacao is distinct from v_snapshot.preco_referencia_centavos_por_unidade_precificacao then
    raise exception 'fato de preco praticado diverge da referencia comercial congelada';
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

create or replace function public.ord01_apply_com_pedido_contract_delta(p_base jsonb, p_delta jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  v_key text;
  v_delta jsonb := p_delta;
  v_result jsonb;
  v_allowed constant text[] := array[
    'f2b_document','f2a_comparison','financial_condition','commercial_context',
    'obrigacoes_contratuais','itens','pricing','discount','financial',
    'buyer_signature','commercial_resolution','condicao_financeira','contexto_comercial'
  ];
begin
  if jsonb_typeof(p_base) <> 'object' or jsonb_typeof(p_delta) <> 'object' then
    raise exception 'estado e delta contratuais devem ser objetos';
  end if;
  if (p_delta ? 'financial_condition') and (p_delta ? 'condicao_financeira')
     and p_delta->'financial_condition' is distinct from p_delta->'condicao_financeira' then
    raise exception 'delta possui aliases financeiros conflitantes';
  end if;
  if (p_delta ? 'commercial_context') and (p_delta ? 'contexto_comercial')
     and p_delta->'commercial_context' is distinct from p_delta->'contexto_comercial' then
    raise exception 'delta possui aliases comerciais conflitantes';
  end if;
  -- Normalize aliases before any result-schema validation.  Aliases never
  -- become part of the canonical hashable state.
  if v_delta ? 'condicao_financeira' then
    v_delta := (v_delta - 'condicao_financeira') || jsonb_build_object('financial_condition', v_delta->'condicao_financeira');
  end if;
  if v_delta ? 'contexto_comercial' then
    v_delta := (v_delta - 'contexto_comercial') || jsonb_build_object('commercial_context', v_delta->'contexto_comercial');
  end if;
  for v_key in select key from jsonb_object_keys(v_delta) key loop
    if not (v_key = any(v_allowed)) then
      raise exception 'campo de delta contratual nao governado: %', v_key;
    end if;
    if v_delta->v_key is null or v_delta->v_key = 'null'::jsonb then
      raise exception 'campo de delta contratual nulo: %', v_key;
    end if;
  end loop;
  if jsonb_typeof(p_base->'f2b_document') <> 'object'
     or jsonb_typeof(p_base->'f2a_comparison') <> 'object'
     or jsonb_typeof(p_base->'f2a_comparison'->'itens') <> 'array'
     or jsonb_typeof(p_base->'f2a_comparison'->'totais') <> 'object'
     or jsonb_typeof(p_base->'financial_condition') <> 'object'
     or jsonb_typeof(p_base->'financial_condition'->'parcelas') <> 'array'
     or p_base->>'schema_version' !~ '^[1-9][0-9]*$'
     or p_base->>'pedido_id' !~ '^[1-9][0-9]*$' then
    raise exception 'estado contratual base possui secoes obrigatorias invalidas';
  end if;
  v_result := (p_base - 'condicao_financeira' - 'contexto_comercial') || v_delta;
  if v_result = (p_base - 'condicao_financeira' - 'contexto_comercial') then
    raise exception 'delta de revisao sem efeito material';
  end if;
  if jsonb_typeof(v_result->'f2b_document') <> 'object'
     or jsonb_typeof(v_result->'f2a_comparison') <> 'object'
     or jsonb_typeof(v_result->'f2a_comparison'->'itens') <> 'array'
     or jsonb_array_length(v_result->'f2a_comparison'->'itens') = 0
     or jsonb_typeof(v_result->'f2a_comparison'->'totais') <> 'object'
     or jsonb_typeof(v_result->'financial_condition') <> 'object'
     or jsonb_typeof(v_result->'financial_condition'->'parcelas') <> 'array'
     or jsonb_array_length(v_result->'financial_condition'->'parcelas') = 0
     or v_result->>'schema_version' !~ '^[1-9][0-9]*$'
     or v_result->>'pedido_id' !~ '^[1-9][0-9]*$'
     or v_result ? 'pending_revision_delta'
     or v_result ? 'pending_impact_mask' then
    raise exception 'resultado contratual incompleto ou nao materializavel';
  end if;
  if v_result->'financial_condition'->>'valor_total_centavos' !~ '^[1-9][0-9]*$'
     or v_result->'financial_condition'->>'pmp_dias' !~ '^[0-9]+(\.[0-9]+)?$'
     or exists (
       select 1 from jsonb_array_elements(v_result->'financial_condition'->'parcelas') part
        where jsonb_typeof(part) <> 'object'
          or part->>'numero_parcela' !~ '^[1-9][0-9]*$'
          or part->>'forma_pagamento' not in ('boleto','pix','ted','cessao_credito')
          or part->>'valor_centavos' !~ '^[1-9][0-9]*$'
          or part->>'data_vencimento' !~ '^\d{4}-\d{2}-\d{2}$'
          or part->>'dias_prazo' !~ '^\d+$'
     ) then
    raise exception 'condicao financeira resultante nao e materializavel';
  end if;
  if (
    select coalesce(sum((part->>'valor_centavos')::bigint), 0)
      from jsonb_array_elements(v_result->'financial_condition'->'parcelas') part
  ) <> (v_result->'financial_condition'->>'valor_total_centavos')::bigint then
    raise exception 'parcelas resultantes nao reconciliam o valor financeiro';
  end if;
  if (
    select round(
      sum((part->>'valor_centavos')::numeric * (part->>'dias_prazo')::numeric)
      / nullif(sum((part->>'valor_centavos')::numeric), 0),
      6
    ) from jsonb_array_elements(v_result->'financial_condition'->'parcelas') part
  ) is distinct from (v_result->'financial_condition'->>'pmp_dias')::numeric then
    raise exception 'parcelas resultantes divergem do PMP';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(v_result->'f2a_comparison'->'itens') item
     where jsonb_typeof(item) <> 'object'
        or item->>'pedido_item_id' !~ '^[1-9][0-9]*$'
        or item->>'produto_embalagem_id' !~ '^[1-9][0-9]*$'
        or item->>'origem_comercial_id' !~ '^[1-9][0-9]*$'
        or item->>'cliente_id' !~ '^[1-9][0-9]*$'
        or item->>'data_comercial' !~ '^\d{4}-\d{2}-\d{2}$'
        or item->>'pmp_dias' !~ '^[0-9]+(\.[0-9]+)?$'
        or item->>'lista_id' !~ '^[1-9][0-9]*$'
        or item->>'lista_versao_id' !~ '^[1-9][0-9]*$'
        or item->>'publicacao_id' !~ '^[1-9][0-9]*$'
        or item->>'regra_id' !~ '^[1-9][0-9]*$'
        or item->>'prazo_faixa_dias' !~ '^\d+$'
        or item->>'unidade_precificacao_id' !~ '^[1-9][0-9]*$'
        or item->>'quantidade_apresentacoes' !~ '^[0-9]+(\.[0-9]+)?$'
        or (item->>'quantidade_apresentacoes')::numeric <= 0
        or item->>'quantidade_unidade_precificacao_por_apresentacao' !~ '^[0-9]+(\.[0-9]+)?$'
        or (item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric <= 0
        or item->>'quantidade_unidade_precificacao' !~ '^[0-9]+(\.[0-9]+)?$'
        or (item->>'quantidade_unidade_precificacao')::numeric is distinct from
           (item->>'quantidade_apresentacoes')::numeric * (item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric
        or item->>'preco_referencia_centavos_por_unidade_precificacao' !~ '^[1-9][0-9]*$'
        or item->>'preco_praticado_centavos_por_unidade_precificacao' !~ '^[1-9][0-9]*$'
        or item->>'diferenca_centavos_por_unidade_precificacao' !~ '^-?[0-9]+$'
        or item->>'percentual_diferenca' !~ '^-?[0-9]+(\.[0-9]+)?$'
        or item->>'valor_referencia_centavos' !~ '^[1-9][0-9]*$'
        or item->>'valor_praticado_centavos' !~ '^[1-9][0-9]*$'
        or item->>'impacto_financeiro_centavos' !~ '^-?[0-9]+$'
        or (item->>'diferenca_centavos_por_unidade_precificacao')::bigint is distinct from
           (item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint - (item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint
        or (item->>'percentual_diferenca')::numeric is distinct from round(
           (item->>'diferenca_centavos_por_unidade_precificacao')::numeric * 100 /
           (item->>'preco_referencia_centavos_por_unidade_precificacao')::numeric, 6
        )
        or (item->>'valor_referencia_centavos')::bigint is distinct from round(
           (item->>'quantidade_unidade_precificacao')::numeric *
           (item->>'preco_referencia_centavos_por_unidade_precificacao')::numeric, 0
        )::bigint
        or (item->>'valor_praticado_centavos')::bigint is distinct from round(
           (item->>'quantidade_unidade_precificacao')::numeric *
           (item->>'preco_praticado_centavos_por_unidade_precificacao')::numeric, 0
        )::bigint
        or (item->>'impacto_financeiro_centavos')::bigint is distinct from
           (item->>'valor_praticado_centavos')::bigint - (item->>'valor_referencia_centavos')::bigint
        or (item->>'classificacao' = 'BELOW_REFERENCE' and
           (item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint >= (item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint)
        or (item->>'classificacao' = 'AT_REFERENCE' and
           (item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint <> (item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint)
        or (item->>'classificacao' = 'ABOVE_REFERENCE' and
           (item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint <= (item->>'preco_referencia_centavos_por_unidade_precificacao')::bigint)
        or item->>'classificacao' not in ('BELOW_REFERENCE','AT_REFERENCE','ABOVE_REFERENCE')
  ) then
    raise exception 'comparacao comercial resultante possui item incompleto ou invalido';
  end if;
  return v_result;
end;
$$;

-- Activate the version-aware overrides only after every compatibility
-- definition above has been installed. Temporary implementations are removed
-- below so they cannot remain as latent SECURITY DEFINER entrypoints.
alter function public.ord01_revision_current_pre_effective_state(bigint)
  rename to ord01_revision_current_pre_effective_state_draft_0136;
alter function public.ord01_revision_current_pre_effective_state_versioned_0136(bigint)
  rename to ord01_revision_current_pre_effective_state;
alter function public.ord01_revision_impact_mask(jsonb, jsonb)
  rename to ord01_revision_impact_mask_draft_0136;
alter function public.ord01_revision_impact_mask_versioned_0136(jsonb, jsonb)
  rename to ord01_revision_impact_mask;
alter function public.ord01_contract_genesis_state(bigint)
  rename to ord01_contract_genesis_state_draft_legacy_0136;
alter function public.ord01_contract_genesis_state_draft_0136(bigint)
  rename to ord01_contract_genesis_state;

drop function public.ord01_revision_current_pre_effective_state_draft_0136(bigint);
drop function public.ord01_revision_impact_mask_draft_0136(jsonb, jsonb);
drop function public.ord01_contract_genesis_state_draft_legacy_0136(bigint);
drop function public.materializar_com_pedido_contrato_genese_draft_0136(bigint);
drop function public.validate_com_pedido_confirmacao_comercial_draft_0136();
drop function public.materializar_com_pedido_revisao_pre_efetiva_draft_0136(bigint);
drop function public.ord01_revision_current_contract_state_draft_0136(bigint);
drop function public.solicitar_com_pedido_revisao_idempotente_draft_0136(uuid, bigint, jsonb);
drop function public.efetivar_com_pedido_revisao_idempotente_draft_0136(uuid, bigint, jsonb);

-- These governed reads execute permission checks (and, for the resolver,
-- governed resolution helpers). They are operationally volatile and must not
-- be planned as stable expressions across authorization or request changes.
alter function public.resolver_com_referencia_comercial_unidade(
  date, numeric, bigint, bigint, text, bigint, bigint[], bigint
) volatile;
alter function public.resolver_com_referencia_comercial(
  date, numeric, bigint, bigint, text, bigint, bigint[], bigint
) volatile;
alter function public.com_revisao_comercial_venda_calcular(jsonb) volatile;
alter function public.consultar_com_pedido_documento_assinavel(bigint) volatile;
alter function public.consultar_com_pedido_assinaturas(bigint) volatile;
alter function public.consultar_com_pedido_assinatura_artefato(bigint) volatile;
alter function public.autorizar_com_pedido_assinatura_evidencia(bigint, bigint, text) volatile;

revoke all on function public.ord01_revisao_comparacao_persistida(bigint) from public, anon, authenticated;
revoke all on function public.ord01_revisao_estado_materializado(bigint) from public, anon, authenticated;
revoke all on function public.ord01_contract_state_materialization_equivalent(jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.ord01_revisao_pre_efetiva_gates(bigint) from public, anon, authenticated;
revoke all on function public.materializar_com_pedido_revisao_pre_efetiva(bigint) from public, anon, authenticated;
revoke all on function public.materializar_com_pedido_contrato_genese(bigint) from public, anon, authenticated;
revoke all on function public.materializar_com_pedido_contrato_genese_apos_efetividade() from public, anon, authenticated;
revoke all on function public.validate_com_pedido_item_referencia_revisionada() from public, anon, authenticated;
