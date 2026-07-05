do $$
begin
  alter type public.audit_axis add value if not exists 'financial_event';
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

  if v_axis in ('own_any', 'change_type', 'field_risk', 'movement_event', 'fiscal_event', 'financial_event', 'status_transition') then
    return v_axis::public.audit_axis;
  end if;

  raise exception 'invalid audit axis: %', p_axis;
end;
$$;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('financeiro.receipts.view', 'financeiro', 'Ver recebimentos, alocacoes e saldos financeiros', true, 601),
  ('financeiro.receipts.register', 'financeiro', 'Registrar recebimento e alocar por pedido/NF', true, 602),
  ('financeiro.receipts.reverse', 'financeiro', 'Estornar recebimento por evento financeiro auditado', true, 603),
  ('financeiro.commissions.view', 'financeiro', 'Ver liberacoes e conta corrente de comissoes', true, 611),
  ('financeiro.commissions.release', 'financeiro', 'Liberar comissao proporcional por recebimento', true, 612),
  ('financeiro.commissions.pay', 'financeiro', 'Registrar pagamento de comissao', true, 613),
  ('financeiro.commissions.adjust', 'financeiro', 'Registrar ajuste manual de conta corrente de comissao', true, 614)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

alter table public.com_recebimentos
  add column if not exists cliente_id bigint references public.cad_clientes(id),
  add column if not exists nota_fiscal_id bigint references public.fat_notas_fiscais(id),
  add column if not exists status text not null default 'active',
  add column if not exists correlation_id text;

alter table public.com_recebimentos
  alter column pedido_id drop not null;

do $$
begin
  alter table public.com_recebimentos
    add constraint com_recebimentos_status_check check (status in ('active', 'estornado', 'cancelled'));
exception
  when duplicate_object then null;
end;
$$;

update public.com_recebimentos recebimento
   set cliente_id = pedido.cliente_id
  from public.com_pedidos pedido
 where recebimento.pedido_id = pedido.id
   and recebimento.cliente_id is null;

alter table public.com_comissao_liberacoes
  add column if not exists alocacao_id bigint,
  add column if not exists memoria_calculo_json jsonb not null default '{}'::jsonb,
  add column if not exists correlation_id text;

create table if not exists public.fin_recebimento_alocacoes (
  id bigint generated always as identity primary key,
  recebimento_id bigint not null references public.com_recebimentos(id),
  pedido_id bigint not null references public.com_pedidos(id),
  nota_fiscal_id bigint references public.fat_notas_fiscais(id),
  valor_alocado numeric not null,
  tipo_alocacao text not null default 'recebimento',
  origem text not null default 'manual',
  memoria_calculo_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_recebimento_alocacoes_valor_check check (valor_alocado <> 0),
  constraint fin_recebimento_alocacoes_tipo_check check (tipo_alocacao in ('recebimento', 'estorno', 'ajuste')),
  constraint fin_recebimento_alocacoes_origem_check check (origem in ('pedido', 'nota_fiscal', 'manual', 'importacao', 'conciliacao'))
);

do $$
begin
  alter table public.com_comissao_liberacoes
    add constraint com_comissao_liberacoes_alocacao_fk
    foreign key (alocacao_id) references public.fin_recebimento_alocacoes(id);
exception
  when duplicate_object then null;
end;
$$;

create table if not exists public.fin_comissao_movimentos (
  id bigint generated always as identity primary key,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  pedido_id bigint references public.com_pedidos(id),
  recebimento_id bigint references public.com_recebimentos(id),
  alocacao_id bigint references public.fin_recebimento_alocacoes(id),
  liberacao_id bigint references public.com_comissao_liberacoes(id),
  tipo_movimento text not null,
  valor numeric not null,
  motivo text,
  memoria_calculo_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_comissao_movimentos_valor_check check (valor <> 0),
  constraint fin_comissao_movimentos_tipo_check check (
    tipo_movimento in (
      'credito_liberacao',
      'debito_pagamento',
      'debito_estorno',
      'compensacao_futura',
      'ajuste_manual'
    )
  ),
  constraint fin_comissao_movimentos_sinal_check check (
    (tipo_movimento = 'credito_liberacao' and valor > 0)
    or (tipo_movimento in ('debito_pagamento', 'debito_estorno', 'compensacao_futura') and valor < 0)
    or (tipo_movimento = 'ajuste_manual' and valor <> 0)
  ),
  constraint fin_comissao_movimentos_motivo_check check (
    tipo_movimento <> 'ajuste_manual' or nullif(trim(motivo), '') is not null
  )
);

insert into public.fin_recebimento_alocacoes(
  recebimento_id,
  pedido_id,
  nota_fiscal_id,
  valor_alocado,
  tipo_alocacao,
  origem,
  memoria_calculo_json,
  created_by,
  created_at
)
select
  recebimento.id,
  recebimento.pedido_id,
  recebimento.nota_fiscal_id,
  recebimento.valor_recebido,
  'recebimento',
  case when recebimento.nota_fiscal_id is null then 'pedido' else 'nota_fiscal' end,
  jsonb_build_object('source', 'backfill_0026_from_com_recebimentos'),
  recebimento.created_by,
  recebimento.created_at
from public.com_recebimentos recebimento
where recebimento.pedido_id is not null
  and not exists (
    select 1
      from public.fin_recebimento_alocacoes alocacao
     where alocacao.recebimento_id = recebimento.id
  );

create index if not exists idx_fin_recebimento_alocacoes_recebimento on public.fin_recebimento_alocacoes(recebimento_id);
create index if not exists idx_fin_recebimento_alocacoes_pedido on public.fin_recebimento_alocacoes(pedido_id, created_at desc);
create index if not exists idx_fin_recebimento_alocacoes_nf on public.fin_recebimento_alocacoes(nota_fiscal_id) where nota_fiscal_id is not null;
create index if not exists idx_fin_comissao_movimentos_pessoa on public.fin_comissao_movimentos(pessoa_id, created_at desc);
create index if not exists idx_fin_comissao_movimentos_recebimento on public.fin_comissao_movimentos(recebimento_id) where recebimento_id is not null;

create or replace function public.prevent_financial_event_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'financial event ledgers are append-only';
end;
$$;

drop trigger if exists trg_fin_recebimento_alocacoes_no_update on public.fin_recebimento_alocacoes;
create trigger trg_fin_recebimento_alocacoes_no_update
before update or delete on public.fin_recebimento_alocacoes
for each row execute function public.prevent_financial_event_changes();

drop trigger if exists trg_fin_comissao_movimentos_no_update on public.fin_comissao_movimentos;
create trigger trg_fin_comissao_movimentos_no_update
before update or delete on public.fin_comissao_movimentos
for each row execute function public.prevent_financial_event_changes();

comment on table public.fin_recebimento_alocacoes is
  'Eventos de alocacao financeira. Um recebimento pode cobrir varios pedidos/NFs; reversao futura deve ser novo evento, nao edicao da alocacao original.';
comment on table public.fin_comissao_movimentos is
  'Conta corrente append-only de comissoes. Creditos, pagamentos, estornos, compensacoes e ajustes sao movimentos historicos auditados.';
comment on column public.com_recebimentos.pedido_id is
  'Compatibilidade com lancamento por pedido. Para pagamentos multi-pedido, a fonte de alocacao e fin_recebimento_alocacoes.';
comment on column public.com_comissao_liberacoes.memoria_calculo_json is
  'Snapshot proporcional usado para liberar comissao por recebimento; nao recalcular retroativamente.';

alter table public.fin_recebimento_alocacoes enable row level security;
alter table public.fin_comissao_movimentos enable row level security;

drop policy if exists "authenticated full receipt access" on public.com_recebimentos;
drop policy if exists "authenticated full commission release access" on public.com_comissao_liberacoes;
drop policy if exists "authenticated read com_recebimentos" on public.com_recebimentos;
drop policy if exists "authenticated read com_comissao_liberacoes" on public.com_comissao_liberacoes;
drop policy if exists "authenticated read fin_recebimento_alocacoes" on public.fin_recebimento_alocacoes;
drop policy if exists "authenticated read fin_comissao_movimentos" on public.fin_comissao_movimentos;

create policy "authenticated read com_recebimentos"
on public.com_recebimentos
for select to authenticated
using (public.current_actor_id() is not null);

create policy "authenticated read com_comissao_liberacoes"
on public.com_comissao_liberacoes
for select to authenticated
using (public.current_actor_id() is not null);

create policy "authenticated read fin_recebimento_alocacoes"
on public.fin_recebimento_alocacoes
for select to authenticated
using (public.current_actor_id() is not null);

create policy "authenticated read fin_comissao_movimentos"
on public.fin_comissao_movimentos
for select to authenticated
using (public.current_actor_id() is not null);

grant select on public.com_recebimentos, public.com_comissao_liberacoes, public.fin_recebimento_alocacoes, public.fin_comissao_movimentos to authenticated;
revoke insert, update, delete on public.com_recebimentos, public.com_comissao_liberacoes, public.fin_recebimento_alocacoes, public.fin_comissao_movimentos from authenticated;

create or replace view public.fin_recebimento_saldos_pedido
with (security_invoker = true) as
select
  pedido.id as pedido_id,
  pedido.cliente_id,
  pedido.valor_total,
  coalesce(sum(alocacao.valor_alocado), 0)::numeric as valor_recebido_alocado,
  (pedido.valor_total - coalesce(sum(alocacao.valor_alocado), 0))::numeric as saldo_aberto
from public.com_pedidos pedido
left join public.fin_recebimento_alocacoes alocacao on alocacao.pedido_id = pedido.id
group by pedido.id, pedido.cliente_id, pedido.valor_total;

create or replace view public.fin_comissao_saldos
with (security_invoker = true) as
select
  pessoa.id as pessoa_id,
  pessoa.nome as pessoa_nome,
  coalesce(sum(movimento.valor), 0)::numeric as saldo_comissao
from public.cad_pessoas_comerciais pessoa
left join public.fin_comissao_movimentos movimento on movimento.pessoa_id = pessoa.id
group by pessoa.id, pessoa.nome;

grant select on public.fin_recebimento_saldos_pedido, public.fin_comissao_saldos to authenticated;

create or replace function public.fin_recebimento_snapshot(p_recebimento_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'recebimento',
    to_jsonb(recebimento),
    'alocacoes',
    coalesce((
      select jsonb_agg(to_jsonb(alocacao) order by alocacao.id)
      from public.fin_recebimento_alocacoes alocacao
      where alocacao.recebimento_id = recebimento.id
    ), '[]'::jsonb),
    'comissoes_liberadas',
    coalesce((
      select jsonb_agg(to_jsonb(liberacao) order by liberacao.id)
      from public.com_comissao_liberacoes liberacao
      where liberacao.recebimento_id = recebimento.id
    ), '[]'::jsonb),
    'movimentos_comissao',
    coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
      from public.fin_comissao_movimentos movimento
      where movimento.recebimento_id = recebimento.id
    ), '[]'::jsonb)
  )
  from public.com_recebimentos recebimento
  where recebimento.id = p_recebimento_id;
$$;

create or replace function public.fin_comissao_saldo_snapshot(p_pessoa_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pessoa_id', saldo.pessoa_id,
    'pessoa_nome', saldo.pessoa_nome,
    'saldo_comissao', saldo.saldo_comissao,
    'movimentos',
    coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
      from public.fin_comissao_movimentos movimento
      where movimento.pessoa_id = saldo.pessoa_id
    ), '[]'::jsonb)
  )
  from public.fin_comissao_saldos saldo
  where saldo.pessoa_id = p_pessoa_id;
$$;

create or replace function public.registrar_fin_recebimento_alocado(
  p_cliente_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date default current_date,
  p_forma_recebimento text default null,
  p_observacao text default null,
  p_alocacoes_json jsonb default '[]'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_recebimento_id bigint;
  v_alocacao_id bigint;
  v_liberacao_id bigint;
  v_movimento_id bigint;
  v_cliente_id bigint;
  v_primeiro_pedido_id bigint;
  v_primeira_nf_id bigint;
  v_total_alocado numeric := 0;
  v_total_recebido_anterior numeric;
  v_total_recebido_atual numeric;
  v_percentual_recebido numeric;
  v_valor_ja_liberado numeric;
  v_valor_alvo_liberado numeric;
  v_valor_liberar numeric;
  v_allocation jsonb;
  v_pedido_id bigint;
  v_nota_fiscal_id bigint;
  v_valor_alocado numeric;
  v_pedido record;
  v_nota record;
  v_comissionado record;
  v_after jsonb;
  v_release_context jsonb;
  v_release_after jsonb;
  v_correlation_id text;
begin
  if p_valor_recebido is null or p_valor_recebido <= 0 then
    raise exception 'valor_recebido must be greater than zero';
  end if;
  if p_data_recebimento is null then
    raise exception 'data_recebimento is required';
  end if;
  if p_alocacoes_json is null or jsonb_typeof(p_alocacoes_json) <> 'array' or jsonb_array_length(p_alocacoes_json) = 0 then
    raise exception 'alocacoes_json must be a non-empty array';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.receipts.register',
    'financeiro',
    'com_recebimentos',
    'financial_event',
    jsonb_build_object('event', 'receipt_register')
  );

  v_actor := public.current_actor_id();
  v_cliente_id := p_cliente_id;

  for v_allocation in
    select value from jsonb_array_elements(p_alocacoes_json)
  loop
    if jsonb_typeof(v_allocation) <> 'object' then
      raise exception 'each allocation must be a json object';
    end if;

    v_pedido_id := nullif(trim(v_allocation->>'pedido_id'), '')::bigint;
    v_nota_fiscal_id := nullif(trim(v_allocation->>'nota_fiscal_id'), '')::bigint;
    v_valor_alocado := nullif(trim(v_allocation->>'valor_alocado'), '')::numeric;

    if v_pedido_id is null or v_pedido_id <= 0 then
      raise exception 'allocation pedido_id is required';
    end if;
    if v_valor_alocado is null or v_valor_alocado <= 0 then
      raise exception 'allocation valor_alocado must be greater than zero';
    end if;

    select id, cliente_id, tipo_pedido, status, valor_total
      into v_pedido
      from public.com_pedidos
     where id = v_pedido_id
     for update;

    if v_pedido.id is null then
      raise exception 'pedido not found';
    end if;
    if v_pedido.status in ('draft', 'blocked', 'cancelled') then
      raise exception 'pedido status does not allow receipt';
    end if;
    if v_pedido.tipo_pedido <> 'venda' or v_pedido.valor_total <= 0 then
      raise exception 'pedido does not allow receipt';
    end if;

    if v_cliente_id is null then
      v_cliente_id := v_pedido.cliente_id;
    elsif v_cliente_id <> v_pedido.cliente_id then
      raise exception 'all receipt allocations must belong to the same cliente';
    end if;

    if v_nota_fiscal_id is not null then
      select id, pedido_id, tipo, status_atual
        into v_nota
        from public.fat_notas_fiscais
       where id = v_nota_fiscal_id
       for update;

      if v_nota.id is null then
        raise exception 'nota fiscal not found';
      end if;
      if v_nota.pedido_id <> v_pedido_id then
        raise exception 'nota fiscal does not belong to allocation pedido';
      end if;
      if v_nota.status_atual <> 'emitida' then
        raise exception 'nota fiscal status does not allow receipt allocation';
      end if;
      if v_nota.tipo = 'remessa_vinculada' then
        raise exception 'linked remittance invoice cannot be commission payment base';
      end if;
    end if;

    select coalesce(sum(valor_alocado), 0)
      into v_total_recebido_anterior
      from public.fin_recebimento_alocacoes
     where pedido_id = v_pedido_id;

    if v_total_recebido_anterior + v_valor_alocado > v_pedido.valor_total then
      raise exception 'receipt exceeds order balance';
    end if;

    if v_primeiro_pedido_id is null then
      v_primeiro_pedido_id := v_pedido_id;
    end if;
    if v_primeira_nf_id is null then
      v_primeira_nf_id := v_nota_fiscal_id;
    end if;

    v_total_alocado := v_total_alocado + v_valor_alocado;
  end loop;

  if abs(v_total_alocado - p_valor_recebido) > 0.0001 then
    raise exception 'sum of allocations must match valor_recebido';
  end if;

  v_correlation_id := 'fin_recebimento:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || ':' || upper(substr(md5(random()::text), 1, 6));

  insert into public.com_recebimentos(
    pedido_id,
    cliente_id,
    nota_fiscal_id,
    valor_recebido,
    data_recebimento,
    forma_recebimento,
    observacao,
    status,
    correlation_id,
    created_by
  )
  values (
    case when jsonb_array_length(p_alocacoes_json) = 1 then v_primeiro_pedido_id else null end,
    v_cliente_id,
    case when jsonb_array_length(p_alocacoes_json) = 1 then v_primeira_nf_id else null end,
    p_valor_recebido,
    p_data_recebimento,
    nullif(trim(p_forma_recebimento), ''),
    nullif(trim(p_observacao), ''),
    'active',
    v_correlation_id,
    v_actor
  )
  returning id into v_recebimento_id;

  for v_allocation in
    select value from jsonb_array_elements(p_alocacoes_json)
  loop
    v_pedido_id := nullif(trim(v_allocation->>'pedido_id'), '')::bigint;
    v_nota_fiscal_id := nullif(trim(v_allocation->>'nota_fiscal_id'), '')::bigint;
    v_valor_alocado := nullif(trim(v_allocation->>'valor_alocado'), '')::numeric;

    select id, cliente_id, tipo_pedido, status, valor_total
      into v_pedido
      from public.com_pedidos
     where id = v_pedido_id
     for update;

    insert into public.fin_recebimento_alocacoes(
      recebimento_id,
      pedido_id,
      nota_fiscal_id,
      valor_alocado,
      tipo_alocacao,
      origem,
      memoria_calculo_json,
      created_by
    )
    values (
      v_recebimento_id,
      v_pedido_id,
      v_nota_fiscal_id,
      v_valor_alocado,
      'recebimento',
      case when v_nota_fiscal_id is null then 'pedido' else 'nota_fiscal' end,
      jsonb_build_object(
        'valor_recebido_total', p_valor_recebido,
        'valor_alocado', v_valor_alocado,
        'correlation_id', v_correlation_id
      ),
      v_actor
    )
    returning id into v_alocacao_id;

    select coalesce(sum(valor_alocado), 0)
      into v_total_recebido_atual
      from public.fin_recebimento_alocacoes
     where pedido_id = v_pedido_id;

    v_percentual_recebido := least(v_total_recebido_atual / v_pedido.valor_total, 1);

    for v_comissionado in
      select id, pessoa_id, valor_previsto
        from public.com_pedido_comissionados
       where pedido_id = v_pedido_id
         and status in ('prevista', 'liberada')
         and valor_previsto > 0
    loop
      select coalesce(sum(valor_liberado), 0)
        into v_valor_ja_liberado
        from public.com_comissao_liberacoes
       where comissionado_id = v_comissionado.id
         and status = 'liberada';

      v_valor_alvo_liberado := v_comissionado.valor_previsto * v_percentual_recebido;
      v_valor_liberar := v_valor_alvo_liberado - v_valor_ja_liberado;

      if v_valor_liberar > 0 then
        v_release_context := public.begin_audited_rpc(
          'financeiro.commissions.release',
          'financeiro',
          'com_comissao_liberacoes',
          'financial_event',
          jsonb_build_object(
            'event', 'commission_release',
            'correlation_id', v_correlation_id,
            'receipt_action_key', 'financeiro.receipts.register'
          )
        );

        insert into public.com_comissao_liberacoes(
          recebimento_id,
          alocacao_id,
          pedido_id,
          comissionado_id,
          pessoa_id,
          valor_liberado,
          percentual_recebido_snapshot,
          status,
          memoria_calculo_json,
          correlation_id,
          created_by
        )
        values (
          v_recebimento_id,
          v_alocacao_id,
          v_pedido_id,
          v_comissionado.id,
          v_comissionado.pessoa_id,
          v_valor_liberar,
          v_percentual_recebido,
          'liberada',
          jsonb_build_object(
            'valor_previsto_total', v_comissionado.valor_previsto,
            'valor_ja_liberado', v_valor_ja_liberado,
            'valor_alvo_liberado', v_valor_alvo_liberado,
            'valor_liberado_neste_recebimento', v_valor_liberar,
            'percentual_recebido_snapshot', v_percentual_recebido,
            'correlation_id', v_correlation_id
          ),
          v_correlation_id,
          v_actor
        )
        returning id into v_liberacao_id;

        insert into public.fin_comissao_movimentos(
          pessoa_id,
          pedido_id,
          recebimento_id,
          alocacao_id,
          liberacao_id,
          tipo_movimento,
          valor,
          memoria_calculo_json,
          created_by
        )
        values (
          v_comissionado.pessoa_id,
          v_pedido_id,
          v_recebimento_id,
          v_alocacao_id,
          v_liberacao_id,
          'credito_liberacao',
          v_valor_liberar,
          jsonb_build_object(
            'source', 'registrar_fin_recebimento_alocado',
            'correlation_id', v_correlation_id,
            'comissionado_id', v_comissionado.id,
            'percentual_recebido_snapshot', v_percentual_recebido
          ),
          v_actor
        )
        returning id into v_movimento_id;

        update public.com_pedido_comissionados
           set status = 'liberada',
               updated_by = v_actor
         where id = v_comissionado.id;

        select jsonb_build_object(
          'liberacao', to_jsonb(liberacao),
          'movimento', to_jsonb(movimento)
        )
          into v_release_after
          from public.com_comissao_liberacoes liberacao
          join public.fin_comissao_movimentos movimento on movimento.id = v_movimento_id
         where liberacao.id = v_liberacao_id;

        perform public.log_audited_rpc_change(
          'financeiro',
          'com_comissao_liberacoes',
          v_liberacao_id::text,
          'financeiro.comissao_liberada',
          'financeiro.commissions.release',
          v_release_context,
          null,
          v_release_after,
          jsonb_build_object(
            'source', 'registrar_fin_recebimento_alocado',
            'correlation_id', v_correlation_id,
            'recebimento_id', v_recebimento_id,
            'alocacao_id', v_alocacao_id,
            'pedido_id', v_pedido_id,
            'pessoa_id', v_comissionado.pessoa_id,
            'valor_liberado', v_valor_liberar
          )
        );
      end if;
    end loop;
  end loop;

  v_after := public.fin_recebimento_snapshot(v_recebimento_id);

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_recebimentos',
    v_recebimento_id::text,
    'financeiro.recebimento_registrado',
    'financeiro.receipts.register',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fin_recebimento_alocado',
      'correlation_id', v_correlation_id,
      'cliente_id', v_cliente_id,
      'total_alocado', v_total_alocado,
      'alocacoes_count', jsonb_array_length(p_alocacoes_json),
      'commission_action_key', 'financeiro.commissions.release'
    )
  );

  return v_recebimento_id;
end;
$$;

create or replace function public.registrar_com_recebimento(
  p_pedido_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date default current_date,
  p_forma_recebimento text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id bigint;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;

  select cliente_id
    into v_cliente_id
    from public.com_pedidos
   where id = p_pedido_id;

  if v_cliente_id is null then
    raise exception 'pedido not found';
  end if;

  return public.registrar_fin_recebimento_alocado(
    v_cliente_id,
    p_valor_recebido,
    p_data_recebimento,
    p_forma_recebimento,
    p_observacao,
    jsonb_build_array(jsonb_build_object(
      'pedido_id', p_pedido_id,
      'valor_alocado', p_valor_recebido
    ))
  );
end;
$$;

create or replace function public.registrar_fin_comissao_pagamento(
  p_pessoa_id bigint,
  p_valor_pago numeric,
  p_data_pagamento date default current_date,
  p_forma_pagamento text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
  v_saldo numeric;
begin
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_valor_pago is null or p_valor_pago <= 0 then
    raise exception 'valor_pago must be greater than zero';
  end if;
  if p_data_pagamento is null then
    raise exception 'data_pagamento is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.pay',
    'financeiro',
    'fin_comissao_movimentos',
    'financial_event',
    jsonb_build_object('event', 'commission_payment')
  );

  v_actor := public.current_actor_id();
  v_before := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  if v_before is null then
    raise exception 'pessoa not found';
  end if;

  v_saldo := coalesce((v_before->>'saldo_comissao')::numeric, 0);
  if v_saldo < p_valor_pago then
    raise exception 'commission payment exceeds available balance';
  end if;

  insert into public.fin_comissao_movimentos(
    pessoa_id,
    tipo_movimento,
    valor,
    motivo,
    memoria_calculo_json,
    created_by
  )
  values (
    p_pessoa_id,
    'debito_pagamento',
    -1 * p_valor_pago,
    nullif(trim(p_motivo), ''),
    jsonb_build_object(
      'data_pagamento', p_data_pagamento,
      'forma_pagamento', nullif(trim(p_forma_pagamento), ''),
      'saldo_anterior', v_saldo
    ),
    v_actor
  )
  returning id into v_movimento_id;

  v_after := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  perform public.log_audited_rpc_change(
    'financeiro',
    'fin_comissao_movimentos',
    v_movimento_id::text,
    'financeiro.comissao_paga',
    'financeiro.commissions.pay',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fin_comissao_pagamento',
      'pessoa_id', p_pessoa_id,
      'valor_pago', p_valor_pago,
      'data_pagamento', p_data_pagamento,
      'forma_pagamento', nullif(trim(p_forma_pagamento), '')
    )
  );

  return v_movimento_id;
end;
$$;

create or replace function public.registrar_fin_comissao_ajuste(
  p_pessoa_id bigint,
  p_valor_ajuste numeric,
  p_motivo text,
  p_referencia_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
begin
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_valor_ajuste is null or p_valor_ajuste = 0 then
    raise exception 'valor_ajuste must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;
  if p_referencia_json is not null and jsonb_typeof(p_referencia_json) <> 'object' then
    raise exception 'referencia_json must be a json object';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.adjust',
    'financeiro',
    'fin_comissao_movimentos',
    'financial_event',
    jsonb_build_object('event', 'commission_manual_adjustment')
  );

  v_actor := public.current_actor_id();
  v_before := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  if v_before is null then
    raise exception 'pessoa not found';
  end if;

  insert into public.fin_comissao_movimentos(
    pessoa_id,
    tipo_movimento,
    valor,
    motivo,
    memoria_calculo_json,
    created_by
  )
  values (
    p_pessoa_id,
    'ajuste_manual',
    p_valor_ajuste,
    nullif(trim(p_motivo), ''),
    coalesce(p_referencia_json, '{}'::jsonb),
    v_actor
  )
  returning id into v_movimento_id;

  v_after := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  perform public.log_audited_rpc_change(
    'financeiro',
    'fin_comissao_movimentos',
    v_movimento_id::text,
    'financeiro.comissao_ajustada',
    'financeiro.commissions.adjust',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fin_comissao_ajuste',
      'pessoa_id', p_pessoa_id,
      'valor_ajuste', p_valor_ajuste
    )
  );

  return v_movimento_id;
end;
$$;

revoke all on function public.fin_recebimento_snapshot(bigint) from public;
revoke all on function public.fin_comissao_saldo_snapshot(bigint) from public;
revoke all on function public.registrar_fin_recebimento_alocado(bigint, numeric, date, text, text, jsonb) from public;
revoke all on function public.registrar_com_recebimento(bigint, numeric, date, text, text) from public;
revoke all on function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text) from public;
revoke all on function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb) from public;

grant execute on function public.registrar_fin_recebimento_alocado(bigint, numeric, date, text, text, jsonb) to authenticated;
grant execute on function public.registrar_com_recebimento(bigint, numeric, date, text, text) to authenticated;
grant execute on function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text) to authenticated;
grant execute on function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb) to authenticated;
