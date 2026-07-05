do $$
begin
  alter type public.audit_axis add value if not exists 'target_event';
exception
  when duplicate_object then null;
end;
$$;

create or replace function public.normalize_audit_axis(p_axis text)
returns public.audit_axis
language plpgsql
immutable
set search_path = public
as $$
declare
  v_axis text;
begin
  v_axis := lower(nullif(trim(p_axis), ''));

  if v_axis = 'event_movement' then
    v_axis := 'movement_event';
  end if;

  if v_axis in ('own_any', 'change_type', 'field_risk', 'movement_event', 'fiscal_event', 'financial_event', 'target_event', 'status_transition') then
    return v_axis::public.audit_axis;
  end if;

  raise exception 'invalid audit axis: %', p_axis;
end;
$$;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('metas.view', 'metas', 'Ver periodos, movimentos e saldos derivados de metas comerciais', true, 820),
  ('metas.periods.manage', 'metas', 'Criar ou ajustar periodos customizados de meta', true, 821),
  ('metas.sales.register', 'metas', 'Registrar venda aberta no ledger append-only de metas', true, 822),
  ('metas.cancellations.register', 'metas', 'Registrar abatimento de meta por cancelamento', true, 823),
  ('metas.returns.register', 'metas', 'Registrar abatimento de meta por devolucao quando aplicavel', true, 824),
  ('metas.adjust', 'metas', 'Registrar ajuste manual auditado de meta', true, 825)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create table if not exists public.com_meta_periodos (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null,
  data_inicio date not null,
  data_fim date not null,
  status text not null default 'active',
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_meta_periodos_codigo_check check (nullif(trim(codigo), '') is not null),
  constraint com_meta_periodos_nome_check check (nullif(trim(nome), '') is not null),
  constraint com_meta_periodos_datas_check check (data_fim >= data_inicio),
  constraint com_meta_periodos_status_check check (status in ('active', 'closed', 'cancelled'))
);

create table if not exists public.com_meta_pessoa_periodo_locks (
  periodo_id bigint not null references public.com_meta_periodos(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  created_at timestamptz not null default now(),
  primary key (periodo_id, pessoa_id)
);

create table if not exists public.com_meta_movimentos (
  id bigint generated always as identity primary key,
  periodo_id bigint not null references public.com_meta_periodos(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  comissionado_id bigint references public.com_pedido_comissionados(id),
  pedido_id bigint references public.com_pedidos(id),
  pedido_item_id bigint references public.com_pedido_itens(id),
  nota_fiscal_id bigint references public.fat_notas_fiscais(id),
  nota_fiscal_item_id bigint references public.fat_nota_fiscal_itens(id),
  tipo_movimento text not null,
  papel_meta text not null default 'vendedor',
  valor_meta numeric not null,
  quantidade_meta numeric,
  data_evento date not null default current_date,
  data_competencia date not null,
  origem_modulo text not null,
  origem_tabela text,
  origem_id text,
  motivo_codigo text,
  motivo_detalhe text,
  memoria_calculo_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_meta_movimentos_tipo_check check (
    tipo_movimento in ('venda_aberta', 'cancelamento', 'devolucao', 'ajuste_manual')
  ),
  constraint com_meta_movimentos_valor_check check (valor_meta <> 0),
  constraint com_meta_movimentos_sinal_check check (
    (tipo_movimento = 'venda_aberta' and valor_meta > 0)
    or (tipo_movimento in ('cancelamento', 'devolucao') and valor_meta < 0)
    or (tipo_movimento = 'ajuste_manual' and valor_meta <> 0)
  ),
  constraint com_meta_movimentos_origem_check check (nullif(trim(origem_modulo), '') is not null),
  constraint com_meta_movimentos_memoria_check check (jsonb_typeof(memoria_calculo_json) = 'object'),
  constraint com_meta_movimentos_motivo_codigo_check check (
    motivo_codigo is null
    or motivo_codigo in (
      'cancelamento_pedido',
      'credito_reprovado',
      'qualidade',
      'avaria_transporte',
      'erro_separacao',
      'erro_comercial',
      'acordo_comercial',
      'correcao_lancamento',
      'ajuste_meta',
      'campanha_excepcional',
      'outro'
    )
  ),
  constraint com_meta_movimentos_motivo_obrigatorio_check check (
    tipo_movimento = 'venda_aberta' or nullif(trim(coalesce(motivo_codigo, '')), '') is not null
  ),
  constraint com_meta_movimentos_outro_detalhe_check check (
    motivo_codigo <> 'outro' or nullif(trim(coalesce(motivo_detalhe, '')), '') is not null
  )
);

create index if not exists idx_com_meta_periodos_datas on public.com_meta_periodos(data_inicio, data_fim, status);
create index if not exists idx_com_meta_movimentos_periodo_pessoa on public.com_meta_movimentos(periodo_id, pessoa_id, created_at desc);
create index if not exists idx_com_meta_movimentos_pedido on public.com_meta_movimentos(pedido_id, tipo_movimento) where pedido_id is not null;
create index if not exists idx_com_meta_movimentos_nf on public.com_meta_movimentos(nota_fiscal_id, tipo_movimento) where nota_fiscal_id is not null;

create unique index if not exists idx_com_meta_venda_aberta_once
  on public.com_meta_movimentos(pedido_id, pessoa_id, coalesce(comissionado_id, 0))
  where tipo_movimento = 'venda_aberta' and pedido_id is not null;

create unique index if not exists idx_com_meta_cancelamento_once
  on public.com_meta_movimentos(pedido_id, pessoa_id, coalesce(comissionado_id, 0))
  where tipo_movimento = 'cancelamento' and pedido_id is not null;

create unique index if not exists idx_com_meta_devolucao_item_once
  on public.com_meta_movimentos(nota_fiscal_item_id, pessoa_id, coalesce(comissionado_id, 0))
  where tipo_movimento = 'devolucao' and nota_fiscal_item_id is not null;

drop trigger if exists trg_com_meta_periodos_updated_at on public.com_meta_periodos;
create trigger trg_com_meta_periodos_updated_at
before update on public.com_meta_periodos
for each row execute function public.touch_updated_at();

create or replace function public.prevent_target_event_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'target event ledgers are append-only';
end;
$$;

drop trigger if exists trg_com_meta_movimentos_no_update on public.com_meta_movimentos;
create trigger trg_com_meta_movimentos_no_update
before update or delete on public.com_meta_movimentos
for each row execute function public.prevent_target_event_changes();

comment on table public.com_meta_periodos is
  'Periodos customizados de meta comercial. O periodo e definido pela data do pedido para venda aberta e pela data do evento para cancelamento/devolucao.';
comment on table public.com_meta_pessoa_periodo_locks is
  'Linha tecnica de lock por pessoa + periodo. Nao armazena saldo; serve para serializar calculos futuros de faixa perto de fronteiras.';
comment on table public.com_meta_movimentos is
  'Ledger append-only de metas comerciais. Venda aberta soma; cancelamento/devolucao/ajuste geram novos eventos. Saldo e derivado por view.';
comment on column public.com_meta_movimentos.motivo_codigo is
  'Motivo padronizado. Devolucao por qualidade nao deve gerar abatimento de meta; demais motivos geram evento negativo.';

alter table public.com_meta_periodos enable row level security;
alter table public.com_meta_pessoa_periodo_locks enable row level security;
alter table public.com_meta_movimentos enable row level security;

drop policy if exists "authenticated read com_meta_periodos" on public.com_meta_periodos;
drop policy if exists "authenticated read com_meta_pessoa_periodo_locks" on public.com_meta_pessoa_periodo_locks;
drop policy if exists "authenticated read com_meta_movimentos" on public.com_meta_movimentos;

create policy "authenticated read com_meta_periodos"
on public.com_meta_periodos
for select to authenticated
using (public.current_actor_id() is not null);

create policy "authenticated read com_meta_pessoa_periodo_locks"
on public.com_meta_pessoa_periodo_locks
for select to authenticated
using (public.current_actor_id() is not null);

create policy "authenticated read com_meta_movimentos"
on public.com_meta_movimentos
for select to authenticated
using (public.current_actor_id() is not null);

grant select on public.com_meta_periodos, public.com_meta_pessoa_periodo_locks, public.com_meta_movimentos to authenticated;
revoke insert, update, delete on public.com_meta_periodos, public.com_meta_pessoa_periodo_locks, public.com_meta_movimentos from authenticated;

create or replace view public.com_meta_saldos_pessoa_periodo
with (security_invoker = true) as
select
  periodo.id as periodo_id,
  periodo.codigo as periodo_codigo,
  periodo.nome as periodo_nome,
  periodo.data_inicio,
  periodo.data_fim,
  movimento.pessoa_id,
  pessoa.nome as pessoa_nome,
  movimento.papel_meta,
  coalesce(sum(movimento.valor_meta), 0)::numeric as valor_meta_liquido,
  coalesce(sum(coalesce(movimento.quantidade_meta, 0)), 0)::numeric as quantidade_meta_liquida,
  count(*)::integer as movimentos_count,
  max(movimento.created_at) as ultimo_movimento_at
from public.com_meta_periodos periodo
join public.com_meta_movimentos movimento on movimento.periodo_id = periodo.id
join public.cad_pessoas_comerciais pessoa on pessoa.id = movimento.pessoa_id
group by
  periodo.id,
  periodo.codigo,
  periodo.nome,
  periodo.data_inicio,
  periodo.data_fim,
  movimento.pessoa_id,
  pessoa.nome,
  movimento.papel_meta;

grant select on public.com_meta_saldos_pessoa_periodo to authenticated;

create or replace function public.resolve_com_meta_periodo(p_data date)
returns bigint
language plpgsql
stable
set search_path = public
as $$
declare
  v_periodo_id bigint;
begin
  if p_data is null then
    raise exception 'meta date is required';
  end if;

  select periodo.id
    into v_periodo_id
    from public.com_meta_periodos periodo
   where periodo.status = 'active'
     and p_data between periodo.data_inicio and periodo.data_fim
   order by periodo.data_inicio desc, periodo.data_fim asc, periodo.id desc
   limit 1;

  if v_periodo_id is null then
    raise exception 'meta period not found for date';
  end if;

  return v_periodo_id;
end;
$$;

create or replace function public.lock_com_meta_pessoa_periodo(
  p_periodo_id bigint,
  p_pessoa_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_periodo_id is null or p_periodo_id <= 0 then
    raise exception 'periodo_id is required';
  end if;
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;

  insert into public.com_meta_pessoa_periodo_locks(periodo_id, pessoa_id)
  values (p_periodo_id, p_pessoa_id)
  on conflict (periodo_id, pessoa_id) do nothing;

  perform 1
    from public.com_meta_pessoa_periodo_locks lock_row
   where lock_row.periodo_id = p_periodo_id
     and lock_row.pessoa_id = p_pessoa_id
   for update;
end;
$$;

create or replace function public.upsert_com_meta_periodo(
  p_codigo text,
  p_nome text,
  p_data_inicio date,
  p_data_fim date,
  p_status text default 'active',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_codigo text;
  v_status text;
  v_periodo_id bigint;
  v_before jsonb;
  v_after jsonb;
begin
  v_codigo := upper(nullif(trim(p_codigo), ''));
  v_status := lower(coalesce(nullif(trim(p_status), ''), 'active'));

  if v_codigo is null then
    raise exception 'codigo is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if p_data_inicio is null or p_data_fim is null then
    raise exception 'period dates are required';
  end if;
  if p_data_fim < p_data_inicio then
    raise exception 'data_fim must be greater than or equal to data_inicio';
  end if;
  if v_status not in ('active', 'closed', 'cancelled') then
    raise exception 'invalid meta period status';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.periods.manage',
    'metas',
    'com_meta_periodos',
    'target_event',
    jsonb_build_object('event', 'period_upsert')
  );

  select periodo.id, to_jsonb(periodo)
    into v_periodo_id, v_before
    from public.com_meta_periodos periodo
   where periodo.codigo = v_codigo
   for update;

  v_actor := public.current_actor_id();

  if v_periodo_id is null then
    insert into public.com_meta_periodos(
      codigo,
      nome,
      data_inicio,
      data_fim,
      status,
      observacao,
      created_by,
      updated_by
    )
    values (
      v_codigo,
      trim(p_nome),
      p_data_inicio,
      p_data_fim,
      v_status,
      nullif(trim(p_observacao), ''),
      v_actor,
      v_actor
    )
    returning id into v_periodo_id;
  else
    update public.com_meta_periodos
       set nome = trim(p_nome),
           data_inicio = p_data_inicio,
           data_fim = p_data_fim,
           status = v_status,
           observacao = nullif(trim(p_observacao), ''),
           updated_by = v_actor
     where id = v_periodo_id;
  end if;

  select to_jsonb(periodo)
    into v_after
    from public.com_meta_periodos periodo
   where periodo.id = v_periodo_id;

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_periodos',
    v_periodo_id::text,
    'metas.periodo_salvo',
    'metas.periods.manage',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'upsert_com_meta_periodo',
      'codigo', v_codigo,
      'status', v_status
    )
  );

  return v_periodo_id;
end;
$$;

create or replace function public.registrar_com_meta_venda_aberta(
  p_pedido_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_periodo_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_target record;
  v_movimento_id bigint;
  v_movimentos jsonb := '[]'::jsonb;
  v_pessoa_ids bigint[] := array[]::bigint[];
  v_count integer := 0;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.sales.register',
    'metas',
    'com_meta_movimentos',
    'target_event',
    jsonb_build_object('event', 'sale_opened', 'pedido_id', p_pedido_id)
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status <> 'open' then
    raise exception 'pedido must be open to enter target ledger';
  end if;
  if v_pedido.tipo_pedido <> 'venda' then
    raise exception 'only venda pedido enters target ledger';
  end if;
  if v_pedido.valor_total <= 0 then
    raise exception 'pedido valor_total must be greater than zero for target ledger';
  end if;
  if exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'venda_aberta'
  ) then
    raise exception 'meta sale already registered for pedido';
  end if;

  v_periodo_id := public.resolve_com_meta_periodo(v_pedido.data_pedido);
  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'periodo_id', v_periodo_id,
    'movimentos_pedido_before', '[]'::jsonb
  );

  for v_target in
    with comissionados as (
      select
        comissionado.id as comissionado_id,
        comissionado.pessoa_id,
        comissionado.pedido_item_id,
        comissionado.papel_comissao as papel_meta,
        coalesce(nullif(comissionado.valor_base, 0), item.valor_total, v_pedido.valor_total) as valor_meta,
        item.quantidade as quantidade_meta,
        'com_pedido_comissionados'::text as origem_tabela,
        comissionado.id::text as origem_id
      from public.com_pedido_comissionados comissionado
      left join public.com_pedido_itens item on item.id = comissionado.pedido_item_id
      where comissionado.pedido_id = p_pedido_id
        and comissionado.status in ('prevista', 'liberada', 'paga', 'bloqueada')
        and coalesce(comissionado.valor_base, item.valor_total, v_pedido.valor_total) > 0
    ),
    fallback as (
      select
        null::bigint as comissionado_id,
        v_pedido.vendedor_gerador_id as pessoa_id,
        item.id as pedido_item_id,
        'vendedor'::text as papel_meta,
        item.valor_total as valor_meta,
        item.quantidade as quantidade_meta,
        'com_pedido_itens'::text as origem_tabela,
        item.id::text as origem_id
      from public.com_pedido_itens item
      where item.pedido_id = p_pedido_id
        and item.status = 'active'
        and item.valor_total > 0
        and v_pedido.vendedor_gerador_id is not null
    )
    select * from comissionados
    union all
    select * from fallback
    where not exists (select 1 from comissionados)
  loop
    if v_target.pessoa_id is null then
      continue;
    end if;

    perform public.lock_com_meta_pessoa_periodo(v_periodo_id, v_target.pessoa_id);

    insert into public.com_meta_movimentos(
      periodo_id,
      pessoa_id,
      comissionado_id,
      pedido_id,
      pedido_item_id,
      tipo_movimento,
      papel_meta,
      valor_meta,
      quantidade_meta,
      data_evento,
      data_competencia,
      origem_modulo,
      origem_tabela,
      origem_id,
      memoria_calculo_json,
      created_by
    )
    values (
      v_periodo_id,
      v_target.pessoa_id,
      v_target.comissionado_id,
      p_pedido_id,
      v_target.pedido_item_id,
      'venda_aberta',
      coalesce(nullif(trim(v_target.papel_meta), ''), 'vendedor'),
      v_target.valor_meta,
      v_target.quantidade_meta,
      v_pedido.data_pedido,
      v_pedido.data_pedido,
      'pedido',
      v_target.origem_tabela,
      v_target.origem_id,
      jsonb_build_object(
        'source', 'registrar_com_meta_venda_aberta',
        'pedido_id', p_pedido_id,
        'pedido_data', v_pedido.data_pedido,
        'pedido_status', v_pedido.status,
        'period_rule', 'data_pedido',
        'base', 'vendido_ativo'
      ),
      v_actor
    )
    returning id into v_movimento_id;

    v_count := v_count + 1;
    v_pessoa_ids := array_append(v_pessoa_ids, v_target.pessoa_id);
    v_movimentos := v_movimentos || jsonb_build_array(jsonb_build_object(
      'movimento_id', v_movimento_id,
      'pessoa_id', v_target.pessoa_id,
      'comissionado_id', v_target.comissionado_id,
      'pedido_item_id', v_target.pedido_item_id,
      'valor_meta', v_target.valor_meta
    ));
  end loop;

  if v_count = 0 then
    raise exception 'pedido has no target person to register';
  end if;

  v_after := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'periodo_id', v_periodo_id,
    'movimentos', v_movimentos,
    'saldos_after', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.pessoa_id, saldo.papel_meta)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = v_periodo_id
         and saldo.pessoa_id = any(v_pessoa_ids)
    ), '[]'::jsonb)
  );

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_movimentos',
    p_pedido_id::text,
    'metas.venda_aberta_registrada',
    'metas.sales.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_meta_venda_aberta',
      'pedido_id', p_pedido_id,
      'periodo_id', v_periodo_id,
      'movimentos_count', v_count,
      'correlation_id', concat('pedido:', p_pedido_id::text, ':target_sale')
    )
  );

  return v_count;
end;
$$;

create or replace function public.registrar_com_meta_cancelamento_pedido(
  p_pedido_id bigint,
  p_motivo_codigo text default 'cancelamento_pedido',
  p_motivo_detalhe text default null,
  p_data_evento date default current_date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_periodo_id bigint;
  v_motivo_codigo text;
  v_motivo_detalhe text;
  v_before jsonb;
  v_after jsonb;
  v_venda record;
  v_movimento_id bigint;
  v_movimentos jsonb := '[]'::jsonb;
  v_pessoa_ids bigint[] := array[]::bigint[];
  v_count integer := 0;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_data_evento is null then
    raise exception 'data_evento is required';
  end if;

  v_motivo_codigo := lower(coalesce(nullif(trim(p_motivo_codigo), ''), 'cancelamento_pedido'));
  v_motivo_detalhe := nullif(trim(p_motivo_detalhe), '');
  if v_motivo_codigo not in ('cancelamento_pedido', 'credito_reprovado', 'erro_comercial', 'acordo_comercial', 'outro') then
    raise exception 'invalid motivo_codigo';
  end if;
  if v_motivo_codigo = 'outro' and v_motivo_detalhe is null then
    raise exception 'motivo_detalhe is required when motivo_codigo is outro';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.cancellations.register',
    'metas',
    'com_meta_movimentos',
    'target_event',
    jsonb_build_object('event', 'order_cancellation', 'pedido_id', p_pedido_id, 'motivo_codigo', v_motivo_codigo)
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status <> 'cancelled' then
    raise exception 'pedido must be cancelled before target cancellation event';
  end if;
  if exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'cancelamento'
  ) then
    raise exception 'meta cancellation already registered for pedido';
  end if;
  if not exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'venda_aberta'
  ) then
    raise exception 'meta sale event not found for pedido';
  end if;

  v_periodo_id := public.resolve_com_meta_periodo(p_data_evento);
  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'movimentos_venda', coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
        from public.com_meta_movimentos movimento
       where movimento.pedido_id = p_pedido_id
         and movimento.tipo_movimento = 'venda_aberta'
    ), '[]'::jsonb)
  );

  for v_venda in
    select *
      from public.com_meta_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'venda_aberta'
     order by movimento.id
  loop
    perform public.lock_com_meta_pessoa_periodo(v_periodo_id, v_venda.pessoa_id);

    insert into public.com_meta_movimentos(
      periodo_id,
      pessoa_id,
      comissionado_id,
      pedido_id,
      pedido_item_id,
      tipo_movimento,
      papel_meta,
      valor_meta,
      quantidade_meta,
      data_evento,
      data_competencia,
      origem_modulo,
      origem_tabela,
      origem_id,
      motivo_codigo,
      motivo_detalhe,
      memoria_calculo_json,
      created_by
    )
    values (
      v_periodo_id,
      v_venda.pessoa_id,
      v_venda.comissionado_id,
      p_pedido_id,
      v_venda.pedido_item_id,
      'cancelamento',
      v_venda.papel_meta,
      -1 * abs(v_venda.valor_meta),
      case when v_venda.quantidade_meta is null then null else -1 * abs(v_venda.quantidade_meta) end,
      p_data_evento,
      p_data_evento,
      'pedido_cancelamento',
      'com_pedidos',
      p_pedido_id::text,
      v_motivo_codigo,
      v_motivo_detalhe,
      jsonb_build_object(
        'source', 'registrar_com_meta_cancelamento_pedido',
        'pedido_id', p_pedido_id,
        'venda_movimento_id', v_venda.id,
        'periodo_original_id', v_venda.periodo_id,
        'period_rule', 'data_evento',
        'cancelamento_abate_periodo_vigente', true
      ),
      v_actor
    )
    returning id into v_movimento_id;

    v_count := v_count + 1;
    v_pessoa_ids := array_append(v_pessoa_ids, v_venda.pessoa_id);
    v_movimentos := v_movimentos || jsonb_build_array(jsonb_build_object(
      'movimento_id', v_movimento_id,
      'venda_movimento_id', v_venda.id,
      'pessoa_id', v_venda.pessoa_id,
      'valor_meta', -1 * abs(v_venda.valor_meta)
    ));
  end loop;

  v_after := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'periodo_id', v_periodo_id,
    'movimentos', v_movimentos,
    'saldos_after', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.pessoa_id, saldo.papel_meta)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = v_periodo_id
         and saldo.pessoa_id = any(v_pessoa_ids)
    ), '[]'::jsonb)
  );

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_movimentos',
    p_pedido_id::text,
    'metas.cancelamento_registrado',
    'metas.cancellations.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_meta_cancelamento_pedido',
      'pedido_id', p_pedido_id,
      'periodo_id', v_periodo_id,
      'movimentos_count', v_count,
      'motivo_codigo', v_motivo_codigo,
      'correlation_id', concat('pedido:', p_pedido_id::text, ':target_cancel')
    )
  );

  return v_count;
end;
$$;

create or replace function public.registrar_com_meta_devolucao_nf(
  p_nota_fiscal_devolucao_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_nota record;
  v_periodo_id bigint;
  v_motivo_devolucao text;
  v_before jsonb;
  v_after jsonb;
  v_item record;
  v_venda record;
  v_movimento_id bigint;
  v_valor_meta numeric;
  v_quantidade_meta numeric;
  v_movimentos jsonb := '[]'::jsonb;
  v_pessoa_ids bigint[] := array[]::bigint[];
  v_item_sales_count integer;
  v_count integer := 0;
begin
  if p_nota_fiscal_devolucao_id is null or p_nota_fiscal_devolucao_id <= 0 then
    raise exception 'nota_fiscal_devolucao_id is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.returns.register',
    'metas',
    'com_meta_movimentos',
    'target_event',
    jsonb_build_object('event', 'fiscal_return', 'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id)
  );

  select *
    into v_nota
    from public.fat_notas_fiscais
   where id = p_nota_fiscal_devolucao_id
   for update;

  if v_nota.id is null then
    raise exception 'nota fiscal devolucao not found';
  end if;
  if v_nota.tipo <> 'devolucao' then
    raise exception 'nota fiscal must be devolucao to register target return';
  end if;
  if v_nota.status_atual not in ('emitida') then
    raise exception 'nota fiscal devolucao status does not allow target return';
  end if;

  select lower(nullif(trim(evento.payload_json->>'motivo_devolucao'), ''))
    into v_motivo_devolucao
    from public.fat_nota_fiscal_eventos evento
   where evento.nota_fiscal_id = p_nota_fiscal_devolucao_id
     and evento.tipo_evento = 'emitida'
   order by evento.data_evento desc, evento.id desc
   limit 1;

  if v_motivo_devolucao is null then
    raise exception 'motivo_devolucao is required in fiscal return event payload';
  end if;
  if v_motivo_devolucao not in ('qualidade', 'avaria_transporte', 'erro_separacao', 'erro_comercial', 'acordo_comercial', 'outro') then
    raise exception 'invalid motivo_devolucao';
  end if;
  if exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.nota_fiscal_id = p_nota_fiscal_devolucao_id
       and movimento.tipo_movimento = 'devolucao'
  ) then
    raise exception 'meta return already registered for nota fiscal';
  end if;

  v_periodo_id := public.resolve_com_meta_periodo(v_nota.data_emissao);
  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'nota_devolucao', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_devolucao_id),
    'motivo_devolucao', v_motivo_devolucao,
    'periodo_id', v_periodo_id
  );

  if v_motivo_devolucao = 'qualidade' then
    v_after := v_before || jsonb_build_object(
      'qualidade_sem_penalizacao', true,
      'movimentos', '[]'::jsonb
    );

    perform public.log_audited_rpc_change(
      'metas',
      'com_meta_movimentos',
      p_nota_fiscal_devolucao_id::text,
      'metas.devolucao_qualidade_sem_abatimento',
      'metas.returns.register',
      v_permission_context,
      v_before,
      v_after,
      jsonb_build_object(
        'source', 'registrar_com_meta_devolucao_nf',
        'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
        'motivo_devolucao', v_motivo_devolucao,
        'movimentos_count', 0,
        'correlation_id', concat('nota_fiscal:', p_nota_fiscal_devolucao_id::text, ':target_return')
      )
    );

    return 0;
  end if;

  for v_item in
    select
      item_devolucao.id as nota_fiscal_item_id,
      item_devolucao.pedido_id,
      item_devolucao.pedido_item_id,
      item_devolucao.quantidade,
      item_devolucao.valor_item,
      item_origem.quantidade as quantidade_origem,
      item_origem.valor_item as valor_origem
    from public.fat_nota_fiscal_itens item_devolucao
    join public.fat_nota_fiscal_itens item_origem on item_origem.id = item_devolucao.nota_item_devolvido_id
   where item_devolucao.nota_fiscal_id = p_nota_fiscal_devolucao_id
   order by item_devolucao.id
  loop
    v_item_sales_count := 0;

    for v_venda in
      select *
        from public.com_meta_movimentos movimento
       where movimento.pedido_id = v_item.pedido_id
         and movimento.tipo_movimento = 'venda_aberta'
         and (
           movimento.pedido_item_id = v_item.pedido_item_id
           or movimento.pedido_item_id is null
         )
       order by movimento.id
    loop
      v_item_sales_count := v_item_sales_count + 1;
      perform public.lock_com_meta_pessoa_periodo(v_periodo_id, v_venda.pessoa_id);

      if coalesce(v_item.valor_origem, 0) > 0 then
        v_valor_meta := -1 * abs(v_venda.valor_meta) * least(v_item.valor_item / v_item.valor_origem, 1);
      elsif coalesce(v_item.quantidade_origem, 0) > 0 then
        v_valor_meta := -1 * abs(v_venda.valor_meta) * least(v_item.quantidade / v_item.quantidade_origem, 1);
      else
        raise exception 'returned item has no proportional base for target ledger';
      end if;
      v_quantidade_meta := case
        when v_venda.quantidade_meta is null or v_item.quantidade_origem is null or v_item.quantidade_origem = 0 then null
        else -1 * abs(v_venda.quantidade_meta) * least(v_item.quantidade / v_item.quantidade_origem, 1)
      end;

      if v_valor_meta = 0 then
        continue;
      end if;

      insert into public.com_meta_movimentos(
        periodo_id,
        pessoa_id,
        comissionado_id,
        pedido_id,
        pedido_item_id,
        nota_fiscal_id,
        nota_fiscal_item_id,
        tipo_movimento,
        papel_meta,
        valor_meta,
        quantidade_meta,
        data_evento,
        data_competencia,
        origem_modulo,
        origem_tabela,
        origem_id,
        motivo_codigo,
        motivo_detalhe,
        memoria_calculo_json,
        created_by
      )
      values (
        v_periodo_id,
        v_venda.pessoa_id,
        v_venda.comissionado_id,
        v_item.pedido_id,
        v_item.pedido_item_id,
        p_nota_fiscal_devolucao_id,
        v_item.nota_fiscal_item_id,
        'devolucao',
        v_venda.papel_meta,
        v_valor_meta,
        v_quantidade_meta,
        v_nota.data_emissao,
        v_nota.data_emissao,
        'devolucao_fiscal',
        'fat_nota_fiscal_itens',
        v_item.nota_fiscal_item_id::text,
        v_motivo_devolucao,
        null,
        jsonb_build_object(
          'source', 'registrar_com_meta_devolucao_nf',
          'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
          'nota_fiscal_item_devolucao_id', v_item.nota_fiscal_item_id,
          'venda_movimento_id', v_venda.id,
          'period_rule', 'data_evento',
          'devolucao_abate_periodo_vigente', true
        ),
        v_actor
      )
      returning id into v_movimento_id;

      v_count := v_count + 1;
      v_pessoa_ids := array_append(v_pessoa_ids, v_venda.pessoa_id);
      v_movimentos := v_movimentos || jsonb_build_array(jsonb_build_object(
        'movimento_id', v_movimento_id,
        'venda_movimento_id', v_venda.id,
        'nota_fiscal_item_id', v_item.nota_fiscal_item_id,
        'pessoa_id', v_venda.pessoa_id,
        'valor_meta', v_valor_meta
      ));
    end loop;

    if v_item_sales_count = 0 then
      raise exception 'meta sale event not found for returned item';
    end if;
  end loop;

  if v_count = 0 then
    raise exception 'no target return movements were generated';
  end if;

  v_after := jsonb_build_object(
    'nota_devolucao', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_devolucao_id),
    'periodo_id', v_periodo_id,
    'motivo_devolucao', v_motivo_devolucao,
    'movimentos', v_movimentos,
    'saldos_after', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.pessoa_id, saldo.papel_meta)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = v_periodo_id
         and saldo.pessoa_id = any(v_pessoa_ids)
    ), '[]'::jsonb)
  );

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_movimentos',
    p_nota_fiscal_devolucao_id::text,
    'metas.devolucao_registrada',
    'metas.returns.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_meta_devolucao_nf',
      'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
      'periodo_id', v_periodo_id,
      'motivo_devolucao', v_motivo_devolucao,
      'movimentos_count', v_count,
      'correlation_id', concat('nota_fiscal:', p_nota_fiscal_devolucao_id::text, ':target_return')
    )
  );

  return v_count;
end;
$$;

create or replace function public.registrar_com_meta_ajuste_manual(
  p_periodo_id bigint,
  p_pessoa_id bigint,
  p_valor_meta numeric,
  p_motivo_codigo text,
  p_motivo_detalhe text default null,
  p_memoria_calculo_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_motivo_codigo text;
  v_motivo_detalhe text;
  v_memoria jsonb;
  v_movimento_id bigint;
  v_before jsonb;
  v_after jsonb;
begin
  if p_periodo_id is null or p_periodo_id <= 0 then
    raise exception 'periodo_id is required';
  end if;
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_valor_meta is null or p_valor_meta = 0 then
    raise exception 'valor_meta must be different from zero';
  end if;

  v_motivo_codigo := lower(nullif(trim(p_motivo_codigo), ''));
  v_motivo_detalhe := nullif(trim(p_motivo_detalhe), '');
  v_memoria := coalesce(p_memoria_calculo_json, '{}'::jsonb);

  if jsonb_typeof(v_memoria) <> 'object' then
    raise exception 'memoria_calculo_json must be a json object';
  end if;
  if v_motivo_codigo not in ('correcao_lancamento', 'ajuste_meta', 'campanha_excepcional', 'outro') then
    raise exception 'invalid motivo_codigo';
  end if;
  if v_motivo_codigo = 'outro' and v_motivo_detalhe is null then
    raise exception 'motivo_detalhe is required when motivo_codigo is outro';
  end if;
  if not exists (
    select 1
      from public.com_meta_periodos periodo
     where periodo.id = p_periodo_id
       and periodo.status = 'active'
  ) then
    raise exception 'active meta period not found';
  end if;
  if not exists (
    select 1
      from public.cad_pessoas_comerciais pessoa
     where pessoa.id = p_pessoa_id
       and pessoa.status = 'active'
  ) then
    raise exception 'active pessoa not found';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.adjust',
    'metas',
    'com_meta_movimentos',
    'target_event',
    jsonb_build_object('event', 'target_manual_adjustment', 'motivo_codigo', v_motivo_codigo)
  );

  perform public.lock_com_meta_pessoa_periodo(p_periodo_id, p_pessoa_id);
  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'periodo_id', p_periodo_id,
    'pessoa_id', p_pessoa_id,
    'saldo_before', (
      select to_jsonb(saldo)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = p_periodo_id
         and saldo.pessoa_id = p_pessoa_id
       limit 1
    )
  );

  insert into public.com_meta_movimentos(
    periodo_id,
    pessoa_id,
    tipo_movimento,
    papel_meta,
    valor_meta,
    data_evento,
    data_competencia,
    origem_modulo,
    origem_tabela,
    origem_id,
    motivo_codigo,
    motivo_detalhe,
    memoria_calculo_json,
    created_by
  )
  values (
    p_periodo_id,
    p_pessoa_id,
    'ajuste_manual',
    'ajuste',
    p_valor_meta,
    current_date,
    current_date,
    'ajuste_manual',
    'com_meta_movimentos',
    null,
    v_motivo_codigo,
    v_motivo_detalhe,
    v_memoria || jsonb_build_object('motivo_codigo', v_motivo_codigo),
    v_actor
  )
  returning id into v_movimento_id;

  v_after := jsonb_build_object(
    'periodo_id', p_periodo_id,
    'pessoa_id', p_pessoa_id,
    'movimento_id', v_movimento_id,
    'saldo_after', (
      select to_jsonb(saldo)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = p_periodo_id
         and saldo.pessoa_id = p_pessoa_id
       limit 1
    )
  );

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_movimentos',
    v_movimento_id::text,
    'metas.ajuste_manual_registrado',
    'metas.adjust',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_meta_ajuste_manual',
      'periodo_id', p_periodo_id,
      'pessoa_id', p_pessoa_id,
      'motivo_codigo', v_motivo_codigo
    )
  );

  return v_movimento_id;
end;
$$;

revoke all on function public.normalize_audit_axis(text) from public;
revoke all on function public.prevent_target_event_changes() from public;
revoke all on function public.resolve_com_meta_periodo(date) from public;
revoke all on function public.lock_com_meta_pessoa_periodo(bigint, bigint) from public;
revoke all on function public.upsert_com_meta_periodo(text, text, date, date, text, text) from public;
revoke all on function public.registrar_com_meta_venda_aberta(bigint) from public;
revoke all on function public.registrar_com_meta_cancelamento_pedido(bigint, text, text, date) from public;
revoke all on function public.registrar_com_meta_devolucao_nf(bigint) from public;
revoke all on function public.registrar_com_meta_ajuste_manual(bigint, bigint, numeric, text, text, jsonb) from public;

grant execute on function public.upsert_com_meta_periodo(text, text, date, date, text, text) to authenticated;
grant execute on function public.registrar_com_meta_venda_aberta(bigint) to authenticated;
grant execute on function public.registrar_com_meta_cancelamento_pedido(bigint, text, text, date) to authenticated;
grant execute on function public.registrar_com_meta_devolucao_nf(bigint) to authenticated;
grant execute on function public.registrar_com_meta_ajuste_manual(bigint, bigint, numeric, text, text, jsonb) to authenticated;
