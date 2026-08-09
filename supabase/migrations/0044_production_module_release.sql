insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values
  ('pcp.guarantee.product.register', 'pcp', 'Registrar nova versao de garantia MAPA do produto', true, 310, 'pcp', 'write'),
  ('pcp.guarantee.mp_lot.register', 'pcp', 'Registrar nova versao de garantia de lote de materia-prima', true, 311, 'pcp', 'write'),
  ('pcp.guarantee.calculate', 'pcp', 'Calcular e congelar garantias de produto gerado por OP', true, 312, 'pcp', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

update public.sys_modules
   set display_name = 'Producao',
       description = 'Cadastros tecnicos, formulas, garantias, OP, CQ, lotes e transformacoes'
 where module_key = 'pcp';

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values ('/producao', 'pcp', true)
on conflict (route_prefix) do update set
  module_key = excluded.module_key,
  match_children = excluded.match_children;

alter table public.cad_garantias_produto_mapa
  add column if not exists valor_maximo numeric,
  add column if not exists documento_referencia text,
  add column if not exists justificativa text,
  add column if not exists supersedes_id bigint;

alter table public.cad_garantias_produto_mapa
  drop constraint if exists cad_garantias_produto_supersedes_fk;
alter table public.cad_garantias_produto_mapa
  add constraint cad_garantias_produto_supersedes_fk
  foreign key (supersedes_id) references public.cad_garantias_produto_mapa(id) not valid;
alter table public.cad_garantias_produto_mapa
  validate constraint cad_garantias_produto_supersedes_fk;

alter table public.cad_garantias_produto_mapa
  drop constraint if exists cad_garantias_produto_range_check;
alter table public.cad_garantias_produto_mapa
  add constraint cad_garantias_produto_range_check check (
    (
      tipo_limite = 'faixa'
      and valor_maximo is not null
      and valor_maximo >= valor
    )
    or (
      tipo_limite <> 'faixa'
      and valor_maximo is null
    )
  ) not valid;
alter table public.cad_garantias_produto_mapa
  validate constraint cad_garantias_produto_range_check;

alter table public.cad_garantias_produto_mapa
  drop constraint if exists cad_garantias_produto_dates_check;
alter table public.cad_garantias_produto_mapa
  add constraint cad_garantias_produto_dates_check check (
    vigencia_inicio is null
    or vigencia_fim is null
    or vigencia_fim >= vigencia_inicio
  ) not valid;
alter table public.cad_garantias_produto_mapa
  validate constraint cad_garantias_produto_dates_check;

alter table public.cad_garantias_produto_mapa
  drop constraint if exists cad_garantias_produto_text_check;
alter table public.cad_garantias_produto_mapa
  add constraint cad_garantias_produto_text_check check (
    nullif(btrim(nutriente), '') is not null
    and nullif(btrim(unidade), '') is not null
    and char_length(nutriente) <= 120
    and char_length(unidade) <= 30
  ) not valid;
alter table public.cad_garantias_produto_mapa
  validate constraint cad_garantias_produto_text_check;

alter table public.cad_garantias_lote_mp
  add column if not exists data_referencia date,
  add column if not exists justificativa text,
  add column if not exists supersedes_id bigint;

alter table public.cad_garantias_lote_mp
  drop constraint if exists cad_garantias_lote_supersedes_fk;
alter table public.cad_garantias_lote_mp
  add constraint cad_garantias_lote_supersedes_fk
  foreign key (supersedes_id) references public.cad_garantias_lote_mp(id) not valid;
alter table public.cad_garantias_lote_mp
  validate constraint cad_garantias_lote_supersedes_fk;

alter table public.cad_garantias_lote_mp
  drop constraint if exists cad_garantias_lote_text_check;
alter table public.cad_garantias_lote_mp
  add constraint cad_garantias_lote_text_check check (
    nullif(btrim(nutriente), '') is not null
    and nullif(btrim(unidade), '') is not null
    and char_length(nutriente) <= 120
    and char_length(unidade) <= 30
  ) not valid;
alter table public.cad_garantias_lote_mp
  validate constraint cad_garantias_lote_text_check;

create index if not exists idx_cad_garantias_produto_current
  on public.cad_garantias_produto_mapa(produto_id, lower(btrim(nutriente)), upper(btrim(unidade)), id desc);
create index if not exists idx_cad_garantias_produto_supersedes
  on public.cad_garantias_produto_mapa(supersedes_id)
  where supersedes_id is not null;
create index if not exists idx_cad_garantias_lote_current
  on public.cad_garantias_lote_mp(lote_mp_id, lower(btrim(nutriente)), upper(btrim(unidade)), data_referencia desc, id desc);
create index if not exists idx_cad_garantias_lote_supersedes
  on public.cad_garantias_lote_mp(supersedes_id)
  where supersedes_id is not null;

create or replace view public.cad_garantias_produto_mapa_atuais
with (security_invoker = true)
as
select current_guarantee.*
from (
  select
    guarantee.*,
    row_number() over (
      partition by guarantee.produto_id, lower(btrim(guarantee.nutriente)), upper(btrim(guarantee.unidade))
      order by guarantee.id desc
    ) as guarantee_rank
  from public.cad_garantias_produto_mapa guarantee
  where (guarantee.vigencia_inicio is null or guarantee.vigencia_inicio <= current_date)
    and (guarantee.vigencia_fim is null or guarantee.vigencia_fim >= current_date)
) current_guarantee
where current_guarantee.guarantee_rank = 1;

create or replace view public.cad_garantias_lote_mp_atuais
with (security_invoker = true)
as
select current_guarantee.*
from (
  select
    guarantee.*,
    row_number() over (
      partition by guarantee.lote_mp_id, lower(btrim(guarantee.nutriente)), upper(btrim(guarantee.unidade))
      order by guarantee.data_referencia desc nulls last, guarantee.id desc
    ) as guarantee_rank
  from public.cad_garantias_lote_mp guarantee
  where guarantee.lote_mp_id is not null
) current_guarantee
where current_guarantee.guarantee_rank = 1;

grant select on public.cad_garantias_produto_mapa_atuais to authenticated;
grant select on public.cad_garantias_lote_mp_atuais to authenticated;

create table if not exists public.pcp_op_garantia_resultados (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id),
  produto_gerado_id bigint not null references public.pcp_op_produtos_gerados(id),
  produto_id bigint not null references public.cad_produtos_base(id),
  calculo_versao integer not null,
  nutriente text not null,
  unidade text not null,
  valor_calculado numeric,
  garantia_produto_id bigint references public.cad_garantias_produto_mapa(id),
  tipo_limite text,
  valor_referencia numeric,
  valor_maximo_referencia numeric,
  status_resultado text not null,
  atende boolean,
  base_calculo_json jsonb not null default '[]'::jsonb,
  justificativa text not null,
  correlation_id text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_garantia_versao_check check (calculo_versao > 0),
  constraint pcp_op_garantia_valores_check check (
    (valor_calculado is null or valor_calculado >= 0)
    and (valor_referencia is null or valor_referencia >= 0)
    and (valor_maximo_referencia is null or valor_maximo_referencia >= valor_referencia)
  ),
  constraint pcp_op_garantia_status_check check (
    status_resultado in (
      'atende',
      'nao_atende',
      'informativo',
      'sem_referencia_mapa',
      'sem_dados_lote',
      'unidade_incompativel'
    )
  ),
  constraint pcp_op_garantia_atende_check check (
    (status_resultado in ('atende', 'nao_atende') and atende is not null)
    or (status_resultado not in ('atende', 'nao_atende') and atende is null)
  ),
  constraint pcp_op_garantia_text_check check (
    nullif(btrim(nutriente), '') is not null
    and nullif(btrim(unidade), '') is not null
    and nullif(btrim(justificativa), '') is not null
    and nullif(btrim(correlation_id), '') is not null
  ),
  constraint pcp_op_garantia_base_check check (jsonb_typeof(base_calculo_json) = 'object'),
  constraint pcp_op_garantia_result_key unique (
    produto_gerado_id,
    calculo_versao,
    nutriente,
    unidade
  )
);

create index if not exists idx_pcp_op_garantia_resultados_op
  on public.pcp_op_garantia_resultados(op_id, calculo_versao desc, id);
create index if not exists idx_pcp_op_garantia_resultados_produto
  on public.pcp_op_garantia_resultados(produto_gerado_id, calculo_versao desc, id);

create or replace view public.pcp_op_garantia_resultados_atuais
with (security_invoker = true)
as
select result.*
from public.pcp_op_garantia_resultados result
join (
  select op_id, max(calculo_versao) as calculo_versao
  from public.pcp_op_garantia_resultados
  group by op_id
) latest
  on latest.op_id = result.op_id
 and latest.calculo_versao = result.calculo_versao;

alter table public.pcp_op_garantia_resultados enable row level security;
drop policy if exists "active user read pcp guarantee results" on public.pcp_op_garantia_resultados;
create policy "active user read pcp guarantee results"
  on public.pcp_op_garantia_resultados
  for select to authenticated
  using (public.current_actor_id() is not null);

grant select on public.pcp_op_garantia_resultados to authenticated;
grant select on public.pcp_op_garantia_resultados_atuais to authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.pcp_op_garantia_resultados from authenticated;
revoke all on public.pcp_op_garantia_resultados from anon;

create or replace function public.prevent_production_guarantee_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; register a new version', tg_table_name;
end;
$$;

revoke all on function public.prevent_production_guarantee_changes() from public, anon, authenticated;

drop trigger if exists trg_cad_garantias_produto_append_only on public.cad_garantias_produto_mapa;
create trigger trg_cad_garantias_produto_append_only
before update or delete on public.cad_garantias_produto_mapa
for each row execute function public.prevent_production_guarantee_changes();

drop trigger if exists trg_cad_garantias_produto_no_truncate on public.cad_garantias_produto_mapa;
create trigger trg_cad_garantias_produto_no_truncate
before truncate on public.cad_garantias_produto_mapa
for each statement execute function public.prevent_production_guarantee_changes();

drop trigger if exists trg_cad_garantias_lote_append_only on public.cad_garantias_lote_mp;
create trigger trg_cad_garantias_lote_append_only
before update or delete on public.cad_garantias_lote_mp
for each row execute function public.prevent_production_guarantee_changes();

drop trigger if exists trg_cad_garantias_lote_no_truncate on public.cad_garantias_lote_mp;
create trigger trg_cad_garantias_lote_no_truncate
before truncate on public.cad_garantias_lote_mp
for each statement execute function public.prevent_production_guarantee_changes();

drop trigger if exists trg_pcp_op_garantia_resultados_append_only on public.pcp_op_garantia_resultados;
create trigger trg_pcp_op_garantia_resultados_append_only
before update or delete on public.pcp_op_garantia_resultados
for each row execute function public.prevent_production_guarantee_changes();

drop trigger if exists trg_pcp_op_garantia_resultados_no_truncate on public.pcp_op_garantia_resultados;
create trigger trg_pcp_op_garantia_resultados_no_truncate
before truncate on public.pcp_op_garantia_resultados
for each statement execute function public.prevent_production_guarantee_changes();

create or replace function public.registrar_pcp_garantia_produto(
  p_produto_id bigint,
  p_nutriente text,
  p_tipo_limite text,
  p_valor numeric,
  p_valor_maximo numeric,
  p_unidade text,
  p_fonte text default 'mapa',
  p_vigencia_inicio date default null,
  p_vigencia_fim date default null,
  p_documento_referencia text default null,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_status text;
  v_nutriente text;
  v_tipo_limite text;
  v_unidade text;
  v_fonte text;
  v_previous_id bigint;
  v_garantia_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.product.register',
    'pcp',
    'cad_garantias_produto_mapa',
    'field_risk',
    jsonb_build_object('produto_id', p_produto_id, 'event', 'register_product_guarantee')
  );

  v_nutriente := nullif(btrim(p_nutriente), '');
  v_tipo_limite := lower(nullif(btrim(p_tipo_limite), ''));
  v_unidade := upper(nullif(btrim(p_unidade), ''));
  v_fonte := lower(nullif(btrim(p_fonte), ''));

  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if v_nutriente is null or char_length(v_nutriente) > 120 then
    raise exception 'nutriente is required and must have at most 120 characters';
  end if;
  if v_unidade is null or char_length(v_unidade) > 30 then
    raise exception 'unidade is required and must have at most 30 characters';
  end if;
  if v_tipo_limite not in ('minimo', 'maximo', 'faixa', 'declarado') then
    raise exception 'invalid tipo_limite';
  end if;
  if v_fonte not in ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado') then
    raise exception 'invalid garantia source';
  end if;
  if p_valor is null or p_valor < 0 then
    raise exception 'valor must be greater than or equal to zero';
  end if;
  if v_tipo_limite = 'faixa' then
    if p_valor_maximo is null or p_valor_maximo < p_valor then
      raise exception 'faixa requires valor_maximo greater than or equal to valor';
    end if;
  elsif p_valor_maximo is not null then
    raise exception 'valor_maximo is allowed only for faixa';
  end if;
  if p_vigencia_inicio is not null and p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then
    raise exception 'vigencia_fim must be greater than or equal to vigencia_inicio';
  end if;
  if v_fonte in ('laboratorio', 'fornecedor') and nullif(btrim(p_documento_referencia), '') is null then
    raise exception 'documento_referencia is required for laboratorio or fornecedor';
  end if;
  if nullif(btrim(p_justificativa), '') is null then
    raise exception 'justificativa is required';
  end if;

  select produto.status
    into v_status
    from public.cad_produtos_base produto
   where produto.id = p_produto_id
   for update;
  if v_status is null then
    raise exception 'produto not found';
  end if;
  if v_status <> 'active' then
    raise exception 'produto status does not allow guarantee registration';
  end if;

  select guarantee.id, to_jsonb(guarantee)
    into v_previous_id, v_before
    from public.cad_garantias_produto_mapa guarantee
   where guarantee.produto_id = p_produto_id
     and lower(btrim(guarantee.nutriente)) = lower(v_nutriente)
     and upper(btrim(guarantee.unidade)) = v_unidade
   order by guarantee.id desc
   limit 1;

  v_actor := public.current_actor_id();
  insert into public.cad_garantias_produto_mapa(
    produto_id,
    nutriente,
    tipo_limite,
    valor,
    valor_maximo,
    unidade,
    fonte,
    vigencia_inicio,
    vigencia_fim,
    documento_referencia,
    justificativa,
    supersedes_id,
    created_by
  ) values (
    p_produto_id,
    v_nutriente,
    v_tipo_limite,
    p_valor,
    p_valor_maximo,
    v_unidade,
    v_fonte,
    p_vigencia_inicio,
    p_vigencia_fim,
    nullif(btrim(p_documento_referencia), ''),
    btrim(p_justificativa),
    v_previous_id,
    v_actor
  ) returning id into v_garantia_id;

  select to_jsonb(guarantee)
    into v_after
    from public.cad_garantias_produto_mapa guarantee
   where guarantee.id = v_garantia_id;

  perform public.log_audited_rpc_change(
    'pcp',
    'cad_garantias_produto_mapa',
    v_garantia_id::text,
    'pcp.garantia_produto_registrada',
    'pcp.guarantee.product.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_pcp_garantia_produto',
      'produto_id', p_produto_id,
      'supersedes_id', v_previous_id,
      'correlation_id', concat('produto:', p_produto_id, ':garantia:', v_garantia_id)
    )
  );

  return v_garantia_id;
end;
$$;

create or replace function public.registrar_pcp_garantia_lote_mp(
  p_lote_mp_id bigint,
  p_nutriente text,
  p_valor numeric,
  p_unidade text,
  p_fonte text,
  p_data_referencia date,
  p_documento_referencia text default null,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote record;
  v_nutriente text;
  v_unidade text;
  v_fonte text;
  v_previous_id bigint;
  v_garantia_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.mp_lot.register',
    'pcp',
    'cad_garantias_lote_mp',
    'field_risk',
    jsonb_build_object('lote_mp_id', p_lote_mp_id, 'event', 'register_mp_lot_guarantee')
  );

  v_nutriente := nullif(btrim(p_nutriente), '');
  v_unidade := upper(nullif(btrim(p_unidade), ''));
  v_fonte := lower(nullif(btrim(p_fonte), ''));

  if p_lote_mp_id is null or p_lote_mp_id <= 0 then
    raise exception 'lote_mp_id is required';
  end if;
  if v_nutriente is null or char_length(v_nutriente) > 120 then
    raise exception 'nutriente is required and must have at most 120 characters';
  end if;
  if v_unidade is null or char_length(v_unidade) > 30 then
    raise exception 'unidade is required and must have at most 30 characters';
  end if;
  if v_fonte not in ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado') then
    raise exception 'invalid garantia source';
  end if;
  if p_valor is null or p_valor < 0 then
    raise exception 'valor must be greater than or equal to zero';
  end if;
  if p_data_referencia is null then
    raise exception 'data_referencia is required';
  end if;
  if v_fonte in ('laboratorio', 'fornecedor') and nullif(btrim(p_documento_referencia), '') is null then
    raise exception 'documento_referencia is required for laboratorio or fornecedor';
  end if;
  if nullif(btrim(p_justificativa), '') is null then
    raise exception 'justificativa is required';
  end if;

  select lote.id, lote.materia_prima_id, lote.codigo_lote, lote.status
    into v_lote
    from public.est_lotes_mp lote
   where lote.id = p_lote_mp_id
   for update;
  if not found then
    raise exception 'MP lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled MP lot does not allow guarantee registration';
  end if;

  select guarantee.id, to_jsonb(guarantee)
    into v_previous_id, v_before
    from public.cad_garantias_lote_mp guarantee
   where guarantee.lote_mp_id = p_lote_mp_id
     and lower(btrim(guarantee.nutriente)) = lower(v_nutriente)
     and upper(btrim(guarantee.unidade)) = v_unidade
   order by guarantee.data_referencia desc nulls last, guarantee.id desc
   limit 1;

  v_actor := public.current_actor_id();
  insert into public.cad_garantias_lote_mp(
    materia_prima_id,
    lote_mp_ref_legado,
    lote_mp_id,
    nutriente,
    valor,
    unidade,
    fonte,
    data_referencia,
    documento_referencia,
    justificativa,
    supersedes_id,
    created_by
  ) values (
    v_lote.materia_prima_id,
    v_lote.codigo_lote,
    p_lote_mp_id,
    v_nutriente,
    p_valor,
    v_unidade,
    v_fonte,
    p_data_referencia,
    nullif(btrim(p_documento_referencia), ''),
    btrim(p_justificativa),
    v_previous_id,
    v_actor
  ) returning id into v_garantia_id;

  select to_jsonb(guarantee)
    into v_after
    from public.cad_garantias_lote_mp guarantee
   where guarantee.id = v_garantia_id;

  perform public.log_audited_rpc_change(
    'pcp',
    'cad_garantias_lote_mp',
    v_garantia_id::text,
    'pcp.garantia_lote_mp_registrada',
    'pcp.guarantee.mp_lot.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_pcp_garantia_lote_mp',
      'lote_mp_id', p_lote_mp_id,
      'materia_prima_id', v_lote.materia_prima_id,
      'supersedes_id', v_previous_id,
      'correlation_id', concat('lote_mp:', p_lote_mp_id, ':garantia:', v_garantia_id)
    )
  );

  return v_garantia_id;
end;
$$;

create or replace function public.calcular_pcp_garantias_op(
  p_op_id bigint,
  p_justificativa text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
  v_output record;
  v_result record;
  v_calculo_versao integer;
  v_completed_date date;
  v_status_resultado text;
  v_atende boolean;
  v_output_count integer := 0;
  v_output_result_count integer;
  v_result_count integer := 0;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
  v_correlation_id text;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.calculate',
    'pcp',
    'pcp_ordens_producao',
    'target_event',
    jsonb_build_object('op_id', p_op_id, 'event', 'calculate_guarantees')
  );

  if p_op_id is null or p_op_id <= 0 then
    raise exception 'op_id is required';
  end if;
  if nullif(btrim(p_justificativa), '') is null then
    raise exception 'justificativa is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(concat('elite:pcp:guarantee:', p_op_id), 0));

  select op.*
    into v_op
    from public.pcp_ordens_producao op
   where op.id = p_op_id
   for update;
  if not found then
    raise exception 'OP not found';
  end if;
  if v_op.status <> 'completed' then
    raise exception 'OP must be completed before guarantee calculation';
  end if;
  if v_op.tipo_op = 'mapa_documental' then
    raise exception 'MAPA documental OP has no generated lot guarantee calculation';
  end if;

  v_completed_date := coalesce(v_op.completed_at::date, current_date);
  select coalesce(max(result.calculo_versao), 0) + 1
    into v_calculo_versao
    from public.pcp_op_garantia_resultados result
   where result.op_id = p_op_id;

  select coalesce(jsonb_agg(to_jsonb(result) order by result.produto_gerado_id, result.id), '[]'::jsonb)
    into v_before
    from public.pcp_op_garantia_resultados result
   where result.op_id = p_op_id
     and result.calculo_versao = v_calculo_versao - 1;

  v_actor := public.current_actor_id();
  v_correlation_id := concat('pcp_op:', p_op_id, ':guarantee_calculation:', v_calculo_versao);

  for v_output in
    select
      output.*,
      case
        when output.tipo_produto = 'PA' then item.produto_id
        else output.produto_id
      end as produto_base_id
    from public.pcp_op_produtos_gerados output
    left join public.cad_produto_embalagens item
      on item.id = output.produto_embalagem_id
   where output.op_id = p_op_id
   order by output.id
  loop
    v_output_count := v_output_count + 1;
    v_output_result_count := 0;

    for v_result in
      with referencias as (
        select distinct on (
          lower(btrim(guarantee.nutriente)),
          upper(btrim(guarantee.unidade))
        )
          guarantee.id,
          lower(btrim(guarantee.nutriente)) as nutriente_key,
          guarantee.nutriente,
          upper(btrim(guarantee.unidade)) as unidade,
          guarantee.tipo_limite,
          guarantee.valor,
          guarantee.valor_maximo
        from public.cad_garantias_produto_mapa guarantee
       where guarantee.produto_id = v_output.produto_base_id
         and (guarantee.vigencia_inicio is null or guarantee.vigencia_inicio <= v_completed_date)
         and (guarantee.vigencia_fim is null or guarantee.vigencia_fim >= v_completed_date)
       order by
         lower(btrim(guarantee.nutriente)),
         upper(btrim(guarantee.unidade)),
         coalesce(guarantee.vigencia_inicio, '-infinity'::date) desc,
         guarantee.id desc
      ),
      garantias_lote as (
        select distinct on (
          guarantee.lote_mp_id,
          lower(btrim(guarantee.nutriente)),
          upper(btrim(guarantee.unidade))
        )
          guarantee.id,
          guarantee.lote_mp_id,
          guarantee.materia_prima_id,
          lower(btrim(guarantee.nutriente)) as nutriente_key,
          guarantee.nutriente,
          upper(btrim(guarantee.unidade)) as unidade,
          guarantee.valor,
          guarantee.data_referencia
        from public.cad_garantias_lote_mp guarantee
        join (
          select distinct consumption.lote_mp_id
          from public.pcp_op_consumos_componentes consumption
          where consumption.op_id = p_op_id
            and consumption.tipo_componente = 'MP'
            and consumption.lote_mp_id is not null
        ) consumed_lot on consumed_lot.lote_mp_id = guarantee.lote_mp_id
       where guarantee.data_referencia is not null
         and guarantee.data_referencia <= v_completed_date
       order by
         guarantee.lote_mp_id,
         lower(btrim(guarantee.nutriente)),
         upper(btrim(guarantee.unidade)),
         guarantee.data_referencia desc,
         guarantee.id desc
      ),
      calculadas as (
        select
          guarantee.nutriente_key,
          min(guarantee.nutriente) as nutriente,
          guarantee.unidade,
          sum(guarantee.valor * consumption.quantidade_consumida)
            / nullif(sum(consumption.quantidade_consumida), 0) as valor_calculado,
          jsonb_agg(
            jsonb_build_object(
              'garantia_lote_id', guarantee.id,
              'lote_mp_id', guarantee.lote_mp_id,
              'materia_prima_id', guarantee.materia_prima_id,
              'quantidade_consumida', consumption.quantidade_consumida,
              'valor_garantia', guarantee.valor,
              'unidade', guarantee.unidade,
              'data_referencia', guarantee.data_referencia
            ) order by consumption.id, guarantee.id
          ) as base_calculo
        from public.pcp_op_consumos_componentes consumption
        join garantias_lote guarantee on guarantee.lote_mp_id = consumption.lote_mp_id
       where consumption.op_id = p_op_id
         and consumption.tipo_componente = 'MP'
       group by guarantee.nutriente_key, guarantee.unidade
      ),
      chaves as (
        select reference.nutriente_key, reference.unidade from referencias reference
        union
        select calculated.nutriente_key, calculated.unidade from calculadas calculated
      )
      select
        coalesce(reference.nutriente, calculated.nutriente) as nutriente,
        key_row.unidade,
        calculated.valor_calculado,
        calculated.base_calculo,
        reference.id as garantia_produto_id,
        reference.tipo_limite,
        reference.valor as valor_referencia,
        reference.valor_maximo as valor_maximo_referencia,
        exists (
          select 1 from referencias another_reference
          where another_reference.nutriente_key = key_row.nutriente_key
        ) as tem_referencia_nutriente,
        exists (
          select 1 from calculadas another_calculation
          where another_calculation.nutriente_key = key_row.nutriente_key
        ) as tem_calculo_nutriente
      from chaves key_row
      left join referencias reference
        on reference.nutriente_key = key_row.nutriente_key
       and reference.unidade = key_row.unidade
      left join calculadas calculated
        on calculated.nutriente_key = key_row.nutriente_key
       and calculated.unidade = key_row.unidade
      order by key_row.nutriente_key, key_row.unidade
    loop
      v_atende := null;
      if (
        v_result.garantia_produto_id is not null
        and v_result.valor_calculado is null
        and v_result.tem_calculo_nutriente
      ) or (
        v_result.garantia_produto_id is null
        and v_result.valor_calculado is not null
        and v_result.tem_referencia_nutriente
      ) then
        v_status_resultado := 'unidade_incompativel';
      elsif v_result.valor_calculado is null then
        v_status_resultado := 'sem_dados_lote';
      elsif v_result.garantia_produto_id is null then
        v_status_resultado := 'sem_referencia_mapa';
      elsif v_result.tipo_limite = 'minimo' then
        v_atende := v_result.valor_calculado >= v_result.valor_referencia;
        v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
      elsif v_result.tipo_limite = 'maximo' then
        v_atende := v_result.valor_calculado <= v_result.valor_referencia;
        v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
      elsif v_result.tipo_limite = 'faixa' then
        v_atende := v_result.valor_calculado between v_result.valor_referencia and v_result.valor_maximo_referencia;
        v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
      else
        v_status_resultado := 'informativo';
      end if;

      insert into public.pcp_op_garantia_resultados(
        op_id,
        produto_gerado_id,
        produto_id,
        calculo_versao,
        nutriente,
        unidade,
        valor_calculado,
        garantia_produto_id,
        tipo_limite,
        valor_referencia,
        valor_maximo_referencia,
        status_resultado,
        atende,
        base_calculo_json,
        justificativa,
        correlation_id,
        created_by
      ) values (
        p_op_id,
        v_output.id,
        v_output.produto_base_id,
        v_calculo_versao,
        v_result.nutriente,
        v_result.unidade,
        v_result.valor_calculado,
        v_result.garantia_produto_id,
        v_result.tipo_limite,
        v_result.valor_referencia,
        v_result.valor_maximo_referencia,
        v_status_resultado,
        v_atende,
        jsonb_build_object(
          'inputs', coalesce(v_result.base_calculo, '[]'::jsonb),
          'op_completed_date', v_completed_date,
          'calculation_version', v_calculo_versao
        ),
        btrim(p_justificativa),
        v_correlation_id,
        v_actor
      );
      v_output_result_count := v_output_result_count + 1;
      v_result_count := v_result_count + 1;
    end loop;

    if v_output_result_count = 0 then
      insert into public.pcp_op_garantia_resultados(
        op_id,
        produto_gerado_id,
        produto_id,
        calculo_versao,
        nutriente,
        unidade,
        status_resultado,
        atende,
        base_calculo_json,
        justificativa,
        correlation_id,
        created_by
      ) values (
        p_op_id,
        v_output.id,
        v_output.produto_base_id,
        v_calculo_versao,
        '(sem garantia cadastrada)',
        '-',
        'sem_dados_lote',
        null,
        jsonb_build_object(
          'inputs', '[]'::jsonb,
          'op_completed_date', v_completed_date,
          'calculation_version', v_calculo_versao
        ),
        btrim(p_justificativa),
        v_correlation_id,
        v_actor
      );
      v_result_count := v_result_count + 1;
    end if;
  end loop;

  if v_output_count = 0 then
    raise exception 'completed OP has no generated products';
  end if;

  select coalesce(jsonb_agg(to_jsonb(result) order by result.produto_gerado_id, result.id), '[]'::jsonb)
    into v_after
    from public.pcp_op_garantia_resultados result
   where result.op_id = p_op_id
     and result.calculo_versao = v_calculo_versao;

  perform public.log_audited_rpc_change(
    'pcp',
    'pcp_ordens_producao',
    p_op_id::text,
    'pcp.garantias_op_calculadas',
    'pcp.guarantee.calculate',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'calcular_pcp_garantias_op',
      'op_id', p_op_id,
      'calculo_versao', v_calculo_versao,
      'result_count', v_result_count,
      'correlation_id', v_correlation_id
    )
  );

  return v_calculo_versao;
end;
$$;

comment on function public.registrar_pcp_garantia_produto(bigint, text, text, numeric, numeric, text, text, date, date, text, text) is
  'Registra versao append-only de garantia MAPA do produto. Correcao cria novo registro com supersedes_id.';
comment on function public.registrar_pcp_garantia_lote_mp(bigint, text, numeric, text, text, date, text, text) is
  'Registra versao append-only de garantia vinculada ao lote relacional de MP.';
comment on function public.calcular_pcp_garantias_op(bigint, text) is
  'Cria snapshot versionado das garantias por produto gerado, ponderando lotes MP efetivamente consumidos.';

revoke all on function public.registrar_pcp_garantia_produto(bigint, text, text, numeric, numeric, text, text, date, date, text, text)
  from public, anon;
revoke all on function public.registrar_pcp_garantia_lote_mp(bigint, text, numeric, text, text, date, text, text)
  from public, anon;
revoke all on function public.calcular_pcp_garantias_op(bigint, text)
  from public, anon;

grant execute on function public.registrar_pcp_garantia_produto(bigint, text, text, numeric, numeric, text, text, date, date, text, text)
  to authenticated;
grant execute on function public.registrar_pcp_garantia_lote_mp(bigint, text, numeric, text, text, date, text, text)
  to authenticated;
grant execute on function public.calcular_pcp_garantias_op(bigint, text)
  to authenticated;
