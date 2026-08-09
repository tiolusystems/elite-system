-- Historical formula guarantees remain analytical evidence until explicitly reconciled.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pcp.guarantee.historical.review', 'pcp',
  'Revisar classificacao de garantia calculada do historico',
  false, 314, 'pcp', 'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.pcp_garantia_fontes_historicas (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id) on delete restrict,
  formula_versao_id bigint references public.pcp_formula_versoes(id) on delete restrict,
  descricao_origem text not null,
  valor_pp_percentual_l numeric,
  valor_pv_kg_l numeric,
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id) on delete restrict,
  source_row_id bigint not null references public.source_rows(id) on delete restrict,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint pcp_garantia_fonte_descricao_check check (nullif(btrim(descricao_origem), '') is not null),
  constraint pcp_garantia_fonte_valor_check check (
    valor_pp_percentual_l is not null or valor_pv_kg_l is not null
  ),
  constraint pcp_garantia_fonte_nonnegative_check check (
    coalesce(valor_pp_percentual_l, 0) >= 0 and coalesce(valor_pv_kg_l, 0) >= 0
  ),
  constraint pcp_garantia_fonte_origem_check check (origem_dados = 'excel_legado'),
  constraint pcp_garantia_fonte_source_unique unique (source_batch_id, source_row_id, produto_id)
);

create table public.pcp_garantia_reconciliacao_eventos (
  id bigint generated always as identity primary key,
  fonte_historica_id bigint not null references public.pcp_garantia_fontes_historicas(id) on delete restrict,
  decisao text not null,
  nutriente_id bigint references public.cad_nutrientes(id) on delete restrict,
  unidade_pp_id bigint references public.cad_unidades_medida(id) on delete restrict,
  unidade_pv_id bigint references public.cad_unidades_medida(id) on delete restrict,
  justificativa text not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint pcp_garantia_reconciliacao_decisao_check check (
    decisao in ('classificada', 'manter_pendente', 'descartada')
  ),
  constraint pcp_garantia_reconciliacao_justificativa_check check (
    char_length(btrim(justificativa)) >= 10
  ),
  constraint pcp_garantia_reconciliacao_catalogos_check check (
    (decisao = 'classificada' and nutriente_id is not null and unidade_pp_id is not null and unidade_pv_id is not null)
    or (decisao <> 'classificada' and nutriente_id is null and unidade_pp_id is null and unidade_pv_id is null)
  )
);

create index idx_pcp_garantia_fonte_produto
  on public.pcp_garantia_fontes_historicas(produto_id, created_at desc);
create index idx_pcp_garantia_reconciliacao_latest
  on public.pcp_garantia_reconciliacao_eventos(fonte_historica_id, created_at desc, id desc);

create trigger trg_pcp_garantia_fontes_append_only
before update or delete on public.pcp_garantia_fontes_historicas
for each row execute function public.prevent_production_guarantee_changes();
create trigger trg_pcp_garantia_fontes_no_truncate
before truncate on public.pcp_garantia_fontes_historicas
for each statement execute function public.prevent_production_guarantee_changes();
create trigger trg_pcp_garantia_reconciliacao_append_only
before update or delete on public.pcp_garantia_reconciliacao_eventos
for each row execute function public.prevent_production_guarantee_changes();
create trigger trg_pcp_garantia_reconciliacao_no_truncate
before truncate on public.pcp_garantia_reconciliacao_eventos
for each statement execute function public.prevent_production_guarantee_changes();

alter table public.pcp_garantia_fontes_historicas enable row level security;
alter table public.pcp_garantia_reconciliacao_eventos enable row level security;

create policy "active user read pcp_garantia_fontes_historicas"
  on public.pcp_garantia_fontes_historicas for select to authenticated
  using (public.current_actor_id() is not null);
create policy "active user read pcp_garantia_reconciliacao_eventos"
  on public.pcp_garantia_reconciliacao_eventos for select to authenticated
  using (public.current_actor_id() is not null);

grant select on public.pcp_garantia_fontes_historicas, public.pcp_garantia_reconciliacao_eventos to authenticated;
revoke insert, update, delete, truncate on public.pcp_garantia_fontes_historicas, public.pcp_garantia_reconciliacao_eventos from public, anon, authenticated;
revoke all on public.pcp_garantia_fontes_historicas, public.pcp_garantia_reconciliacao_eventos from anon;

create view public.pcp_garantias_historicas_conciliacao_atual
with (security_invoker = true)
as
select
  source.id,
  source.produto_id,
  product.codigo_produto,
  product.nome as produto_nome,
  source.formula_versao_id,
  source.descricao_origem,
  source.valor_pp_percentual_l,
  source.valor_pv_kg_l,
  source.source_batch_id,
  source.source_row_id,
  source_row.excel_row_number as linha_excel,
  source.created_at as importado_em,
  coalesce(review.decisao, 'nao_revisada') as decisao,
  review.nutriente_id,
  nutrient.nome as nutriente_nome,
  nutrient.simbolo as nutriente_simbolo,
  review.unidade_pp_id,
  unit_pp.codigo as unidade_pp_codigo,
  review.unidade_pv_id,
  unit_pv.codigo as unidade_pv_codigo,
  review.justificativa,
  review.created_at as revisado_em
from public.pcp_garantia_fontes_historicas source
join public.cad_produtos_base product on product.id = source.produto_id
join public.source_rows source_row on source_row.id = source.source_row_id
left join lateral (
  select event.*
  from public.pcp_garantia_reconciliacao_eventos event
  where event.fonte_historica_id = source.id
  order by event.created_at desc, event.id desc
  limit 1
) review on true
left join public.cad_nutrientes nutrient on nutrient.id = review.nutriente_id
left join public.cad_unidades_medida unit_pp on unit_pp.id = review.unidade_pp_id
left join public.cad_unidades_medida unit_pv on unit_pv.id = review.unidade_pv_id;

grant select on public.pcp_garantias_historicas_conciliacao_atual to authenticated;
revoke all on public.pcp_garantias_historicas_conciliacao_atual from public, anon;

create or replace function public.revisar_pcp_garantia_historica(
  p_fonte_historica_id bigint,
  p_decisao text,
  p_nutriente_id bigint default null,
  p_unidade_pp_id bigint default null,
  p_unidade_pv_id bigint default null,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source record;
  v_decisao text := lower(nullif(btrim(p_decisao), ''));
  v_event_id bigint;
  v_actor uuid;
  v_permission_context jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.historical.review', 'pcp',
    'pcp_garantia_reconciliacao_eventos', 'field_risk',
    jsonb_build_object('fonte_historica_id', p_fonte_historica_id, 'event', 'review_historical_guarantee')
  );

  select source.* into v_source
  from public.pcp_garantia_fontes_historicas source
  where source.id = p_fonte_historica_id
  for update;
  if not found then raise exception 'historical guarantee source not found'; end if;
  if v_decisao not in ('classificada', 'manter_pendente', 'descartada') then
    raise exception 'invalid historical guarantee review decision';
  end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'historical guarantee review justification must have at least 10 characters';
  end if;

  if v_decisao = 'classificada' then
    if p_nutriente_id is null or p_unidade_pp_id is null or p_unidade_pv_id is null then
      raise exception 'nutrient and both units are required for classification';
    end if;
    if not exists (select 1 from public.cad_nutrientes where id = p_nutriente_id and status = 'active') then
      raise exception 'active nutrient not found';
    end if;
    if not exists (select 1 from public.cad_unidades_medida where id = p_unidade_pp_id and status = 'active')
       or not exists (select 1 from public.cad_unidades_medida where id = p_unidade_pv_id and status = 'active') then
      raise exception 'active guarantee unit not found';
    end if;
  elsif p_nutriente_id is not null or p_unidade_pp_id is not null or p_unidade_pv_id is not null then
    raise exception 'catalog mapping is only accepted for classified decision';
  end if;

  v_actor := public.current_actor_id();
  insert into public.pcp_garantia_reconciliacao_eventos(
    fonte_historica_id, decisao, nutriente_id, unidade_pp_id, unidade_pv_id,
    justificativa, created_by
  ) values (
    p_fonte_historica_id, v_decisao, p_nutriente_id, p_unidade_pp_id, p_unidade_pv_id,
    btrim(p_justificativa), v_actor
  ) returning id into v_event_id;

  select to_jsonb(event) into v_after
  from public.pcp_garantia_reconciliacao_eventos event where event.id = v_event_id;

  perform public.log_audited_rpc_change(
    'pcp', 'pcp_garantia_reconciliacao_eventos', v_event_id::text,
    'pcp.garantia_historica_revisada', 'pcp.guarantee.historical.review',
    v_permission_context, null, v_after,
    jsonb_build_object(
      'fonte_historica_id', p_fonte_historica_id,
      'produto_id', v_source.produto_id,
      'source_batch_id', v_source.source_batch_id,
      'source_row_id', v_source.source_row_id,
      'promove_garantia_operacional', false,
      'correlation_id', concat('garantia_historica:', p_fonte_historica_id, ':review:', v_event_id)
    )
  );
  return v_event_id;
end;
$$;

revoke all on function public.revisar_pcp_garantia_historica(bigint, text, bigint, bigint, bigint, text) from public, anon;
grant execute on function public.revisar_pcp_garantia_historica(bigint, text, bigint, bigint, bigint, text) to authenticated;

comment on table public.pcp_garantia_fontes_historicas is
  'Valores calculados encontrados no Excel, preservados por linha e sem efeito operacional.';
comment on table public.pcp_garantia_reconciliacao_eventos is
  'Decisoes append-only de classificacao; nunca promovem automaticamente garantia MAPA, garantia de lote ou resultado de OP.';
