-- Organize the existing financial workbench without changing financial rules.
-- Read models are integral, receipt references are mandatory for new events,
-- and direct reads remain governed by atomic permissions.

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
  (
    'financeiro.dashboard.view',
    'financeiro',
    'Consultar a visao financeira consolidada',
    false,
    600,
    'financeiro',
    'read'
  ),
  (
    'financeiro.commissions.export',
    'financeiro',
    'Exportar o relatorio de comissoes a pagar',
    false,
    615,
    'financeiro',
    'read'
  )
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

alter table public.com_recebimentos
  add column if not exists referencia_documental text;

comment on column public.com_recebimentos.referencia_documental is
  'Referencia obrigatoria para novos recebimentos. Registros historicos podem permanecer sem valor.';

create index if not exists idx_com_recebimentos_referencia_documental
  on public.com_recebimentos(lower(referencia_documental))
  where referencia_documental is not null;

drop policy if exists "authenticated read com_recebimentos" on public.com_recebimentos;
create policy "governed read com_recebimentos"
on public.com_recebimentos
for select to authenticated
using (
  public.can_current_user('financeiro.receipts.view')
  or public.can_current_user('financeiro.receipts.register')
);

drop policy if exists "authenticated read fin_recebimento_alocacoes" on public.fin_recebimento_alocacoes;
create policy "governed read fin_recebimento_alocacoes"
on public.fin_recebimento_alocacoes
for select to authenticated
using (
  public.can_current_user('financeiro.receipts.view')
  or public.can_current_user('financeiro.receipts.register')
);

drop policy if exists "authenticated read com_comissao_liberacoes" on public.com_comissao_liberacoes;
create policy "governed read com_comissao_liberacoes"
on public.com_comissao_liberacoes
for select to authenticated
using (
  public.can_current_user('financeiro.commissions.view')
  or public.can_current_user('financeiro.commissions.pay')
  or public.can_current_user('financeiro.commissions.adjust')
);

drop policy if exists "authenticated read fin_comissao_movimentos" on public.fin_comissao_movimentos;
create policy "governed read fin_comissao_movimentos"
on public.fin_comissao_movimentos
for select to authenticated
using (
  public.can_current_user('financeiro.commissions.view')
  or public.can_current_user('financeiro.commissions.pay')
  or public.can_current_user('financeiro.commissions.adjust')
);

create or replace function public.consultar_fin_dashboard(
  p_data_inicio date default (current_date - 30),
  p_data_fim date default current_date,
  p_data_corte date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_can_dashboard boolean;
  v_can_receipts boolean;
  v_can_commissions boolean;
  v_open_receivables numeric;
  v_received_period numeric;
  v_commission_balance numeric;
  v_orders_with_balance bigint;
begin
  if p_data_inicio is null or p_data_fim is null or p_data_corte is null then
    raise exception 'finance dates are required';
  end if;
  if p_data_fim < p_data_inicio then
    raise exception 'finance period is invalid';
  end if;

  v_can_dashboard := public.can_current_user('financeiro.dashboard.view');
  v_can_receipts :=
    public.can_current_user('financeiro.receipts.view')
    or public.can_current_user('financeiro.receipts.register');
  v_can_commissions :=
    public.can_current_user('financeiro.commissions.view')
    or public.can_current_user('financeiro.commissions.pay')
    or public.can_current_user('financeiro.commissions.adjust');

  if not (v_can_dashboard or v_can_receipts or v_can_commissions) then
    raise exception 'not allowed: financeiro.dashboard.view';
  end if;

  if v_can_dashboard or v_can_receipts then
    with order_balances as (
      select
        pedido.id,
        greatest(
          pedido.valor_total - coalesce(sum(
            case
              when recebimento.status = 'active'
               and recebimento.data_recebimento <= p_data_corte
              then alocacao.valor_alocado
              else 0
            end
          ), 0),
          0
        )::numeric as open_value
      from public.com_pedidos pedido
      left join public.fin_recebimento_alocacoes alocacao
        on alocacao.pedido_id = pedido.id
      left join public.com_recebimentos recebimento
        on recebimento.id = alocacao.recebimento_id
      where pedido.tipo_pedido = 'venda'
        and pedido.status in ('open', 'fulfilled')
        and pedido.data_pedido <= p_data_corte
      group by pedido.id, pedido.valor_total
    )
    select
      coalesce(sum(balance.open_value), 0),
      count(*) filter (where balance.open_value > 0)
      into v_open_receivables, v_orders_with_balance
      from order_balances balance;

    select coalesce(sum(recebimento.valor_recebido), 0)
      into v_received_period
      from public.com_recebimentos recebimento
     where recebimento.status = 'active'
       and recebimento.data_recebimento between p_data_inicio and p_data_fim;
  end if;

  if v_can_dashboard or v_can_commissions then
    select coalesce(sum(movimento.valor), 0)
      into v_commission_balance
      from public.fin_comissao_movimentos movimento
     where movimento.created_at::date <= p_data_corte;
  end if;

  return jsonb_build_object(
    'period_start', p_data_inicio,
    'period_end', p_data_fim,
    'cutoff_date', p_data_corte,
    'open_receivables', case when v_can_dashboard or v_can_receipts then v_open_receivables else null end,
    'received_period', case when v_can_dashboard or v_can_receipts then v_received_period else null end,
    'commission_balance', case when v_can_dashboard or v_can_commissions then v_commission_balance else null end,
    'orders_with_balance', case when v_can_dashboard or v_can_receipts then v_orders_with_balance else null end
  );
end;
$$;

create or replace function public.buscar_fin_pedidos_recebimento(
  p_query text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  pedido_id bigint,
  codigo_pedido text,
  cliente_id bigint,
  cliente_nome text,
  propriedade_nome text,
  valor_total numeric,
  valor_recebido numeric,
  saldo_aberto numeric,
  status text,
  referencias_fiscais jsonb,
  recebimentos_anteriores jsonb,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(nullif(btrim(p_query), ''));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not (
    public.can_current_user('financeiro.receipts.view')
    or public.can_current_user('financeiro.receipts.register')
  ) then
    raise exception 'not allowed: financeiro.receipts.view';
  end if;

  return query
  with receipt_totals as (
    select
      allocation.pedido_id,
      coalesce(sum(
        case when receipt.status = 'active' then allocation.valor_alocado else 0 end
      ), 0)::numeric as received_value
    from public.fin_recebimento_alocacoes allocation
    join public.com_recebimentos receipt on receipt.id = allocation.recebimento_id
    group by allocation.pedido_id
  ),
  candidates as (
    select
      orders.id,
      orders.codigo_pedido,
      orders.cliente_id,
      clients.nome as client_name,
      properties.nome as property_name,
      orders.valor_total,
      coalesce(receipt_totals.received_value, 0)::numeric as received_value,
      greatest(orders.valor_total - coalesce(receipt_totals.received_value, 0), 0)::numeric as open_value,
      orders.status
    from public.com_pedidos orders
    join public.cad_clientes clients on clients.id = orders.cliente_id
    left join public.cad_cliente_propriedades properties on properties.id = orders.propriedade_id
    left join receipt_totals on receipt_totals.pedido_id = orders.id
    where orders.tipo_pedido = 'venda'
      and orders.status in ('open', 'fulfilled')
      and greatest(orders.valor_total - coalesce(receipt_totals.received_value, 0), 0) > 0
      and (
        v_query is null
        or lower(orders.codigo_pedido) like '%' || v_query || '%'
        or lower(clients.nome) like '%' || v_query || '%'
        or lower(coalesce(properties.nome, '')) like '%' || v_query || '%'
        or exists (
          select 1
          from public.cad_cliente_identificacoes identification
          where identification.cliente_id = clients.id
            and (
              lower(coalesce(identification.razao_social, '')) like '%' || v_query || '%'
              or lower(coalesce(identification.nome_fantasia, '')) like '%' || v_query || '%'
            )
        )
        or exists (
          select 1
          from public.cad_cliente_estabelecimentos establishment
          where establishment.cliente_id = clients.id
            and lower(establishment.nome) like '%' || v_query || '%'
        )
        or exists (
          select 1
          from public.cad_cliente_enderecos address
          where address.cliente_id = clients.id
            and lower(concat_ws(' ', address.logradouro, address.bairro, address.cidade, address.uf)) like '%' || v_query || '%'
        )
        or exists (
          select 1
          from public.cad_cliente_documentos document
          where document.cliente_id = clients.id
            and nullif(regexp_replace(v_query, '[^a-z0-9]', '', 'g'), '') is not null
            and lower(document.numero_norm) like '%' || regexp_replace(v_query, '[^a-z0-9]', '', 'g') || '%'
        )
        or exists (
          select 1
          from public.fat_notas_fiscais invoice
          where invoice.pedido_id = orders.id
            and lower(coalesce(invoice.numero, '')) like '%' || v_query || '%'
        )
      )
  ),
  counted as (
    select candidates.*, count(*) over() as row_count
    from candidates
  )
  select
    counted.id,
    counted.codigo_pedido,
    counted.cliente_id,
    counted.client_name,
    counted.property_name,
    counted.valor_total,
    counted.received_value,
    counted.open_value,
    counted.status,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'numero', invoice.numero,
        'tipo', invoice.tipo,
        'status', invoice.status_atual
      ) order by invoice.id desc)
      from public.fat_notas_fiscais invoice
      where invoice.pedido_id = counted.id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', receipt.id,
        'valor', allocation.valor_alocado,
        'data', receipt.data_recebimento,
        'forma', receipt.forma_recebimento,
        'referencia_documental', receipt.referencia_documental,
        'status', receipt.status
      ) order by receipt.data_recebimento desc, receipt.id desc)
      from public.fin_recebimento_alocacoes allocation
      join public.com_recebimentos receipt on receipt.id = allocation.recebimento_id
      where allocation.pedido_id = counted.id
    ), '[]'::jsonb),
    counted.row_count
  from counted
  order by counted.codigo_pedido desc
  limit v_limit offset v_offset;
end;
$$;

create or replace function public.buscar_fin_pedidos_comissionamento(
  p_query text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  pedido_id bigint,
  codigo_pedido text,
  cliente_nome text,
  valor_total numeric,
  status text,
  comissionados jsonb,
  total_percentual numeric,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(nullif(btrim(p_query), ''));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform public.require_current_user_permission('pedidos.commissions.assign');

  return query
  with candidates as (
    select
      orders.id,
      orders.codigo_pedido,
      clients.nome as client_name,
      orders.valor_total,
      orders.status
    from public.com_pedidos orders
    join public.cad_clientes clients on clients.id = orders.cliente_id
    where orders.tipo_pedido = 'venda'
      and orders.status in ('open', 'fulfilled')
      and not exists (
        select 1
        from public.fin_recebimento_alocacoes allocation
        where allocation.pedido_id = orders.id
      )
      and (
        v_query is null
        or lower(orders.codigo_pedido) like '%' || v_query || '%'
        or lower(clients.nome) like '%' || v_query || '%'
      )
  ),
  counted as (
    select candidates.*, count(*) over() as row_count
    from candidates
  )
  select
    counted.id,
    counted.codigo_pedido,
    counted.client_name,
    counted.valor_total,
    counted.status,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'pessoa_id', assignment.pessoa_id,
        'pessoa_nome', person.nome,
        'papel', assignment.papel_comissao,
        'percentual', assignment.percentual_comissao,
        'valor_previsto', assignment.valor_previsto,
        'status', assignment.status
      ) order by assignment.id)
      from public.com_pedido_comissionados assignment
      join public.cad_pessoas_comerciais person on person.id = assignment.pessoa_id
      where assignment.pedido_id = counted.id
        and assignment.status not in ('estornada')
    ), '[]'::jsonb),
    coalesce((
      select sum(assignment.percentual_comissao)
      from public.com_pedido_comissionados assignment
      where assignment.pedido_id = counted.id
        and assignment.status not in ('estornada')
    ), 0)::numeric,
    counted.row_count
  from counted
  order by counted.codigo_pedido desc
  limit v_limit offset v_offset;
end;
$$;

create or replace function public.buscar_fin_pessoas_comissionaveis(
  p_query text default null,
  p_limit integer default 100
)
returns table (
  pessoa_id bigint,
  pessoa_nome text,
  papeis jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(nullif(btrim(p_query), ''));
begin
  perform public.require_current_user_permission('pedidos.commissions.assign');

  return query
  select
    person.id,
    person.nome,
    person.papeis_json
  from public.cad_pessoas_comerciais person
  where person.status = 'active'
    and (
      v_query is null
      or lower(person.nome) like '%' || v_query || '%'
      or lower(person.papeis_json::text) like '%' || v_query || '%'
    )
  order by person.nome
  limit least(greatest(coalesce(p_limit, 100), 1), 200);
end;
$$;

create or replace function public.consultar_fin_comissoes(
  p_query text default null,
  p_role text default null,
  p_status text default 'positive',
  p_data_corte date default current_date,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  pessoa_id bigint,
  pessoa_nome text,
  papeis jsonb,
  situacao text,
  comissoes_previstas numeric,
  creditos_liberados numeric,
  pagamentos numeric,
  estornos numeric,
  ajustes numeric,
  saldo numeric,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(nullif(btrim(p_query), ''));
  v_role text := lower(nullif(btrim(p_role), ''));
  v_status text := coalesce(nullif(lower(btrim(p_status)), ''), 'positive');
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not (
    public.can_current_user('financeiro.commissions.view')
    or public.can_current_user('financeiro.commissions.pay')
    or public.can_current_user('financeiro.commissions.adjust')
  ) then
    raise exception 'not allowed: financeiro.commissions.view';
  end if;
  if v_status not in ('positive', 'all', 'zero', 'negative') then
    raise exception 'invalid commission balance filter';
  end if;

  return query
  with balances as (
    select
      person.id,
      person.nome,
      person.papeis_json,
      person.status,
      coalesce((
        select sum(assignment.valor_previsto)
        from public.com_pedido_comissionados assignment
        where assignment.pessoa_id = person.id
          and assignment.status not in ('estornada')
          and assignment.created_at::date <= p_data_corte
      ), 0)::numeric as predicted,
      coalesce(sum(movement.valor) filter (where movement.tipo_movimento = 'credito_liberacao'), 0)::numeric as released,
      coalesce(sum(-movement.valor) filter (where movement.tipo_movimento = 'debito_pagamento'), 0)::numeric as paid,
      coalesce(sum(-movement.valor) filter (where movement.tipo_movimento in ('debito_estorno', 'compensacao_futura')), 0)::numeric as reversed,
      coalesce(sum(movement.valor) filter (where movement.tipo_movimento = 'ajuste_manual'), 0)::numeric as adjusted,
      coalesce(sum(movement.valor), 0)::numeric as current_balance
    from public.cad_pessoas_comerciais person
    left join public.fin_comissao_movimentos movement
      on movement.pessoa_id = person.id
     and movement.created_at::date <= p_data_corte
    where v_query is null
       or lower(person.nome) like '%' || v_query || '%'
       or lower(person.papeis_json::text) like '%' || v_query || '%'
    group by person.id, person.nome, person.papeis_json, person.status
  ),
  role_filtered as (
    select balances.*
    from balances
    where v_role is null
       or lower(balances.papeis_json::text) like '%"' || v_role || '"%'
  ),
  filtered as (
    select role_filtered.*
    from role_filtered
    where v_status = 'all'
       or (v_status = 'positive' and role_filtered.current_balance > 0)
       or (v_status = 'zero' and role_filtered.current_balance = 0)
       or (v_status = 'negative' and role_filtered.current_balance < 0)
  ),
  counted as (
    select filtered.*, count(*) over() as row_count
    from filtered
  )
  select
    counted.id,
    counted.nome,
    counted.papeis_json,
    counted.status,
    counted.predicted,
    counted.released,
    counted.paid,
    counted.reversed,
    counted.adjusted,
    counted.current_balance,
    counted.row_count
  from counted
  order by counted.nome
  limit v_limit offset v_offset;
end;
$$;

create or replace function public.consultar_fin_comissao_movimentos(
  p_pessoa_id bigint,
  p_data_inicio date default null,
  p_data_fim date default null,
  p_limit integer default 100
)
returns table (
  movimento_id bigint,
  tipo_movimento text,
  valor numeric,
  motivo text,
  pedido_codigo text,
  referencia text,
  criado_em timestamptz,
  criado_por text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.can_current_user('financeiro.commissions.view')
    or public.can_current_user('financeiro.commissions.pay')
    or public.can_current_user('financeiro.commissions.adjust')
  ) then
    raise exception 'not allowed: financeiro.commissions.view';
  end if;
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'commission person is required';
  end if;

  return query
  select
    movement.id,
    movement.tipo_movimento,
    movement.valor,
    movement.motivo,
    orders.codigo_pedido,
    coalesce(
      movement.memoria_calculo_json->>'referencia_pagamento',
      movement.memoria_calculo_json->>'motivo_detalhe',
      receipt.referencia_documental
    ),
    movement.created_at,
    profile.display_name
  from public.fin_comissao_movimentos movement
  left join public.com_pedidos orders on orders.id = movement.pedido_id
  left join public.com_recebimentos receipt on receipt.id = movement.recebimento_id
  left join public.user_profiles profile on profile.id = movement.created_by
  where movement.pessoa_id = p_pessoa_id
    and (p_data_inicio is null or movement.created_at::date >= p_data_inicio)
    and (p_data_fim is null or movement.created_at::date <= p_data_fim)
  order by movement.created_at desc, movement.id desc
  limit least(greatest(coalesce(p_limit, 100), 1), 300);
end;
$$;

create or replace function public.registrar_com_recebimento_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date,
  p_forma_recebimento text,
  p_observacao text,
  p_referencia_documental text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.fin_recebimento_requisicoes%rowtype;
  v_recebimento_id bigint;
  v_reference text := nullif(btrim(p_referencia_documental), '');
  v_context jsonb;
  v_after jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;
  if v_reference is null or length(v_reference) < 3 then
    raise exception 'receipt document reference is required';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id,
    'valor_recebido', p_valor_recebido,
    'data_recebimento', p_data_recebimento,
    'forma_recebimento', nullif(btrim(p_forma_recebimento), ''),
    'observacao', nullif(btrim(p_observacao), ''),
    'referencia_documental', v_reference
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select *
    into v_existing
    from public.fin_recebimento_requisicoes request
   where request.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different receipt request';
    end if;
    return v_existing.recebimento_id;
  end if;

  v_context := public.begin_audited_rpc(
    'financeiro.receipts.register',
    'financeiro',
    'com_recebimentos',
    'financial_event',
    jsonb_build_object(
      'event', 'receipt_document_reference',
      'idempotency_key', p_idempotency_key
    )
  );

  v_recebimento_id := public.registrar_com_recebimento(
    p_pedido_id,
    p_valor_recebido,
    p_data_recebimento,
    p_forma_recebimento,
    p_observacao
  );

  update public.com_recebimentos
     set referencia_documental = v_reference
   where id = v_recebimento_id;

  insert into public.fin_recebimento_requisicoes(
    idempotency_key,
    recebimento_id,
    actor_id,
    payload_hash
  ) values (
    p_idempotency_key,
    v_recebimento_id,
    v_actor,
    v_payload_hash
  );

  v_after := public.fin_recebimento_snapshot(v_recebimento_id);
  perform public.log_audited_rpc_change(
    'financeiro',
    'com_recebimentos',
    v_recebimento_id::text,
    'financeiro.referencia_documental_registrada',
    'financeiro.receipts.register',
    v_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_recebimento_idempotente',
      'referencia_documental', v_reference
    )
  );

  return v_recebimento_id;
end;
$$;

revoke all on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text)
  from public, anon, authenticated;
revoke all on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text, text)
  from public, anon;
grant execute on function public.registrar_com_recebimento_idempotente(uuid, bigint, numeric, date, text, text, text)
  to authenticated;

revoke all on function public.consultar_fin_dashboard(date, date, date)
  from public, anon;
revoke all on function public.buscar_fin_pedidos_recebimento(text, integer, integer)
  from public, anon;
revoke all on function public.buscar_fin_pedidos_comissionamento(text, integer, integer)
  from public, anon;
revoke all on function public.buscar_fin_pessoas_comissionaveis(text, integer)
  from public, anon;
revoke all on function public.consultar_fin_comissoes(text, text, text, date, integer, integer)
  from public, anon;
revoke all on function public.consultar_fin_comissao_movimentos(bigint, date, date, integer)
  from public, anon;

grant execute on function public.consultar_fin_dashboard(date, date, date)
  to authenticated;
grant execute on function public.buscar_fin_pedidos_recebimento(text, integer, integer)
  to authenticated;
grant execute on function public.buscar_fin_pedidos_comissionamento(text, integer, integer)
  to authenticated;
grant execute on function public.buscar_fin_pessoas_comissionaveis(text, integer)
  to authenticated;
grant execute on function public.consultar_fin_comissoes(text, text, text, date, integer, integer)
  to authenticated;
grant execute on function public.consultar_fin_comissao_movimentos(bigint, date, date, integer)
  to authenticated;

comment on function public.consultar_fin_dashboard(date, date, date) is
  'Integral financial totals. Detail pagination never changes the indicators.';
comment on function public.buscar_fin_pedidos_recebimento(text, integer, integer) is
  'Governed receipt search by order, customer, document, fiscal reference or delivery property.';
comment on function public.consultar_fin_comissoes(text, text, text, date, integer, integer) is
  'Governed commission account balances at a cutoff date.';
