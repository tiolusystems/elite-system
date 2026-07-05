insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.create', 'pedidos', 'Criar pedido; action legada para contrato de falha da aplicacao', true, 101),
  ('pedidos.create.own', 'pedidos', 'Criar pedido para o proprio escopo comercial', true, 105),
  ('pedidos.create.any', 'pedidos', 'Criar pedido fora do proprio escopo comercial', true, 106),
  ('pedidos.credit.review', 'pedidos', 'Liberar, bloquear ou enviar pedido para aprovacao de credito', true, 107),
  ('pedidos.status.transition', 'pedidos', 'Alterar status de pedido por transicao governada', true, 108),
  ('pedidos.cancel', 'pedidos', 'Cancelar pedido sem efeito fisico, fiscal ou financeiro ativo', true, 109)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create table if not exists public.com_pedido_status_transicoes (
  status_from text not null,
  status_to text not null,
  evento text not null,
  descricao text not null,
  created_at timestamptz not null default now(),
  primary key (status_from, status_to, evento),
  constraint com_pedido_status_transicoes_status_from_check check (
    status_from in ('draft', 'open', 'blocked', 'cancelled', 'fulfilled')
  ),
  constraint com_pedido_status_transicoes_status_to_check check (
    status_to in ('draft', 'open', 'blocked', 'cancelled', 'fulfilled')
  ),
  constraint com_pedido_status_transicoes_evento_check check (nullif(trim(evento), '') is not null)
);

insert into public.com_pedido_status_transicoes(status_from, status_to, evento, descricao)
values
  ('draft', 'open', 'credit_liberado', 'Credito liberado para pedido em rascunho'),
  ('open', 'open', 'credit_liberado', 'Credito revisado sem mudanca de status aberto'),
  ('blocked', 'open', 'credit_liberado', 'Credito liberado para pedido bloqueado'),
  ('draft', 'blocked', 'credit_bloqueado', 'Credito bloqueado para pedido em rascunho'),
  ('open', 'blocked', 'credit_bloqueado', 'Credito bloqueado para pedido aberto'),
  ('blocked', 'blocked', 'credit_bloqueado', 'Credito revisado mantendo bloqueio'),
  ('draft', 'blocked', 'credit_pendente', 'Pedido enviado para aprovacao de credito'),
  ('open', 'blocked', 'credit_pendente', 'Pedido aberto enviado para aprovacao de credito'),
  ('blocked', 'blocked', 'credit_pendente', 'Pedido bloqueado continua pendente de aprovacao'),
  ('draft', 'cancelled', 'cancel', 'Cancelamento de pedido em rascunho'),
  ('open', 'cancelled', 'cancel', 'Cancelamento de pedido aberto sem efeito ativo'),
  ('blocked', 'cancelled', 'cancel', 'Cancelamento de pedido bloqueado sem efeito ativo'),
  ('open', 'fulfilled', 'romaneio_fulfilled', 'Pedido atendido por confirmacao de romaneio')
on conflict (status_from, status_to, evento) do update set
  descricao = excluded.descricao;

alter table public.com_pedido_status_transicoes enable row level security;

drop policy if exists "authenticated read com_pedido_status_transicoes" on public.com_pedido_status_transicoes;
create policy "authenticated read com_pedido_status_transicoes" on public.com_pedido_status_transicoes
for select to authenticated using (public.current_actor_id() is not null);

grant select on public.com_pedido_status_transicoes to authenticated;
revoke insert, update, delete on public.com_pedido_status_transicoes from authenticated;

drop policy if exists "authenticated full order access" on public.com_pedidos;
drop policy if exists "authenticated full order item access" on public.com_pedido_itens;
drop policy if exists "authenticated full order commission access" on public.com_pedido_comissionados;
drop policy if exists "authenticated full order credit access" on public.com_pedido_credito_decisoes;
drop policy if exists "authenticated full order sequence access" on public.com_pedido_sequencias_propriedade;

drop policy if exists "authenticated read com_pedidos" on public.com_pedidos;
drop policy if exists "authenticated read com_pedido_itens" on public.com_pedido_itens;
drop policy if exists "authenticated read com_pedido_comissionados" on public.com_pedido_comissionados;
drop policy if exists "authenticated read com_pedido_credito_decisoes" on public.com_pedido_credito_decisoes;
drop policy if exists "authenticated read com_pedido_sequencias_propriedade" on public.com_pedido_sequencias_propriedade;

create policy "authenticated read com_pedidos" on public.com_pedidos
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read com_pedido_itens" on public.com_pedido_itens
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read com_pedido_comissionados" on public.com_pedido_comissionados
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read com_pedido_credito_decisoes" on public.com_pedido_credito_decisoes
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read com_pedido_sequencias_propriedade" on public.com_pedido_sequencias_propriedade
for select to authenticated using (public.current_actor_id() is not null);

grant select on
  public.com_pedidos,
  public.com_pedido_itens,
  public.com_pedido_comissionados,
  public.com_pedido_credito_decisoes,
  public.com_pedido_sequencias_propriedade
to authenticated;

revoke insert, update, delete on
  public.com_pedidos,
  public.com_pedido_itens,
  public.com_pedido_comissionados,
  public.com_pedido_credito_decisoes,
  public.com_pedido_sequencias_propriedade
from authenticated;

create or replace function public.com_pedido_audit_snapshot(p_pedido_id bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pedido', (
      select to_jsonb(pedido)
        from public.com_pedidos pedido
       where pedido.id = p_pedido_id
    ),
    'itens', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.id)
        from public.com_pedido_itens item
       where item.pedido_id = p_pedido_id
    ), '[]'::jsonb),
    'comissionados', coalesce((
      select jsonb_agg(to_jsonb(comissionado) order by comissionado.id)
        from public.com_pedido_comissionados comissionado
       where comissionado.pedido_id = p_pedido_id
    ), '[]'::jsonb),
    'credito_decisoes', coalesce((
      select jsonb_agg(to_jsonb(decisao) order by decisao.id)
        from public.com_pedido_credito_decisoes decisao
       where decisao.pedido_id = p_pedido_id
    ), '[]'::jsonb)
  );
$$;

create or replace function public.validate_com_pedido_status_transition(
  p_status_from text,
  p_status_to text,
  p_evento text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status_from text;
  v_status_to text;
  v_evento text;
begin
  v_status_from := lower(nullif(trim(p_status_from), ''));
  v_status_to := lower(nullif(trim(p_status_to), ''));
  v_evento := lower(nullif(trim(p_evento), ''));

  if v_status_from is null or v_status_to is null or v_evento is null then
    raise exception 'pedido status transition requires status_from, status_to and evento';
  end if;

  if not exists (
    select 1
      from public.com_pedido_status_transicoes transicao
     where transicao.status_from = v_status_from
       and transicao.status_to = v_status_to
       and transicao.evento = v_evento
  ) then
    raise exception 'pedido status transition not allowed: % -> % via %', v_status_from, v_status_to, v_evento;
  end if;
end;
$$;

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_action_key text;
  v_scope text;
  v_permission_context jsonb;
  v_codigo_pedido text;
  v_pedido_id bigint;
  v_item_id bigint;
  v_item_valor_total numeric;
  v_valor_base_comissao numeric;
  v_valor_previsto_comissao numeric;
  v_sequencia integer;
  v_produto_embalagem_status text;
  v_after jsonb;
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'quantidade must be greater than zero';
  end if;
  if p_valor_unitario is null or p_valor_unitario < 0 then
    raise exception 'valor_unitario must be greater than or equal to zero';
  end if;
  if p_tipo_pedido not in ('venda', 'bonificacao', 'devolucao') then
    raise exception 'invalid tipo_pedido';
  end if;
  if p_status not in ('draft', 'open', 'blocked') then
    raise exception 'invalid initial status';
  end if;
  if p_percentual_comissao is not null and p_percentual_comissao < 0 then
    raise exception 'percentual_comissao must be greater than or equal to zero';
  end if;
  if p_data_pedido is null then
    raise exception 'data_pedido is required';
  end if;

  v_actor := public.current_actor_id();
  if p_vendedor_id is not null and exists (
    select 1
      from public.cad_pessoas_comerciais vendedor
     where vendedor.id = p_vendedor_id
       and vendedor.user_profile_id = v_actor
  ) then
    v_scope := 'own';
    v_action_key := 'pedidos.create.own';
  else
    v_scope := 'any';
    v_action_key := 'pedidos.create.any';
  end if;

  v_permission_context := public.begin_audited_rpc(
    v_action_key,
    'pedidos',
    'com_pedidos',
    'own_any',
    jsonb_build_object('scope', v_scope, 'event', 'order_create')
  );

  if not exists (select 1 from public.cad_clientes where id = p_cliente_id and status = 'active') then
    raise exception 'active cliente not found';
  end if;
  if p_propriedade_id is not null and not exists (
    select 1
    from public.cad_cliente_propriedades
    where id = p_propriedade_id
      and cliente_id = p_cliente_id
      and status = 'active'
  ) then
    raise exception 'active propriedade does not belong to cliente';
  end if;
  if p_vendedor_id is not null and not exists (
    select 1
    from public.cad_pessoas_comerciais
    where id = p_vendedor_id
      and status = 'active'
  ) then
    raise exception 'active vendedor not found';
  end if;

  select status
    into v_produto_embalagem_status
    from public.cad_produto_embalagens
    where id = p_produto_embalagem_id;

  if v_produto_embalagem_status is null then
    raise exception 'produto_embalagem not found';
  end if;
  if v_produto_embalagem_status <> 'active' then
    raise exception 'produto_embalagem status does not allow order creation';
  end if;

  v_sequencia := public.next_com_pedido_sequencia(p_cliente_id, p_propriedade_id);

  v_codigo_pedido := concat(
    'PED-',
    case
      when p_propriedade_id is null then concat('C', p_cliente_id::text)
      else concat('P', p_propriedade_id::text)
    end,
    '-',
    lpad(v_sequencia::text, 6, '0')
  );

  if p_tipo_pedido = 'bonificacao' then
    v_item_valor_total := 0;
  elsif p_tipo_pedido = 'devolucao' then
    v_item_valor_total := -1 * p_quantidade * p_valor_unitario;
  else
    v_item_valor_total := p_quantidade * p_valor_unitario;
  end if;

  insert into public.com_pedidos(
    codigo_pedido,
    cliente_id,
    propriedade_id,
    sequencia_propriedade,
    vendedor_gerador_id,
    tipo_pedido,
    status,
    data_pedido,
    origem_canal,
    valor_total,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_pedido,
    p_cliente_id,
    p_propriedade_id,
    v_sequencia,
    p_vendedor_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    case when p_vendedor_id is null then 'interno' else 'vendedor' end,
    v_item_valor_total,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_pedido_id;

  insert into public.com_pedido_itens(
    pedido_id,
    produto_embalagem_id,
    tipo_item,
    quantidade,
    valor_unitario,
    valor_total,
    created_by,
    updated_by
  )
  values (
    v_pedido_id,
    p_produto_embalagem_id,
    p_tipo_pedido,
    p_quantidade,
    p_valor_unitario,
    v_item_valor_total,
    v_actor,
    v_actor
  )
  returning id into v_item_id;

  if p_vendedor_id is not null and p_percentual_comissao is not null and p_percentual_comissao > 0 and p_tipo_pedido <> 'bonificacao' then
    v_valor_base_comissao := v_item_valor_total;
    v_valor_previsto_comissao := v_valor_base_comissao * p_percentual_comissao / 100;

    insert into public.com_pedido_comissionados(
      pedido_id,
      pedido_item_id,
      pessoa_id,
      papel_comissao,
      percentual_comissao,
      valor_base,
      valor_previsto,
      created_by,
      updated_by
    )
    values (
      v_pedido_id,
      v_item_id,
      p_vendedor_id,
      'vendedor',
      p_percentual_comissao,
      v_valor_base_comissao,
      v_valor_previsto_comissao,
      v_actor,
      v_actor
    );
  end if;

  v_after := public.com_pedido_audit_snapshot(v_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    v_pedido_id::text,
    'pedidos.pedido_criado',
    v_action_key,
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_com_pedido_operacional',
      'codigo_pedido', v_codigo_pedido,
      'cliente_id', p_cliente_id,
      'propriedade_id', p_propriedade_id,
      'sequencia_propriedade', v_sequencia,
      'produto_embalagem_id', p_produto_embalagem_id,
      'tipo_pedido', p_tipo_pedido,
      'initial_status', p_status,
      'quantidade', p_quantidade,
      'valor_unitario', p_valor_unitario,
      'valor_total', v_item_valor_total,
      'vendedor_id', p_vendedor_id,
      'percentual_comissao', p_percentual_comissao,
      'scope', v_scope
    )
  );

  return v_pedido_id;
end;
$$;

create or replace function public.create_com_pedido_rascunho(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.create_com_pedido_operacional(
    p_cliente_id,
    p_produto_embalagem_id,
    p_quantidade,
    p_valor_unitario,
    null,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    p_vendedor_id,
    p_percentual_comissao,
    p_observacao
  );
end;
$$;

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
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_status_resultante text;
  v_evento text;
  v_decisao_id bigint;
  v_before jsonb;
  v_after jsonb;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_decisao not in ('liberado', 'bloqueado', 'pendente_aprovacao') then
    raise exception 'invalid decisao';
  end if;
  if p_decisao <> 'liberado' and nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required when decisao is not liberado';
  end if;
  if p_limite_disponivel_snapshot is not null and p_limite_disponivel_snapshot < 0 then
    raise exception 'limite_disponivel_snapshot must be greater than or equal to zero';
  end if;
  if p_inadimplencia_snapshot is not null and p_inadimplencia_snapshot < 0 then
    raise exception 'inadimplencia_snapshot must be greater than or equal to zero';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'pedidos.credit.review',
    'pedidos',
    'com_pedido_credito_decisoes',
    'status_transition',
    jsonb_build_object('event', 'credit_review')
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status in ('cancelled', 'fulfilled') then
    raise exception 'pedido status does not allow credit decision';
  end if;

  v_before := public.com_pedido_audit_snapshot(p_pedido_id);

  if p_decisao = 'liberado' then
    v_status_resultante := 'open';
    v_evento := 'credit_liberado';
  elsif p_decisao = 'bloqueado' then
    v_status_resultante := 'blocked';
    v_evento := 'credit_bloqueado';
  else
    v_status_resultante := 'blocked';
    v_evento := 'credit_pendente';
  end if;

  perform public.validate_com_pedido_status_transition(v_pedido.status, v_status_resultante, v_evento);

  v_actor := public.current_actor_id();

  insert into public.com_pedido_credito_decisoes(
    pedido_id,
    decisao,
    status_anterior,
    status_resultante,
    motivo,
    limite_disponivel_snapshot,
    inadimplencia_snapshot,
    observacao,
    created_by
  )
  values (
    p_pedido_id,
    p_decisao,
    v_pedido.status,
    v_status_resultante,
    nullif(trim(p_motivo), ''),
    p_limite_disponivel_snapshot,
    p_inadimplencia_snapshot,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_decisao_id;

  update public.com_pedidos
     set status = v_status_resultante,
         updated_by = v_actor
   where id = p_pedido_id;

  v_after := public.com_pedido_audit_snapshot(p_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedido_credito_decisoes',
    v_decisao_id::text,
    'pedidos.credito_revisado',
    'pedidos.credit.review',
    v_permission_context || jsonb_build_object('transition_event', v_evento),
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_pedido_decisao_credito',
      'pedido_id', p_pedido_id,
      'decisao_id', v_decisao_id,
      'status_anterior', v_pedido.status,
      'status_resultante', v_status_resultante,
      'decisao', p_decisao,
      'transition_event', v_evento
    )
  );

  return v_decisao_id;
end;
$$;

create or replace function public.cancelar_com_pedido(
  p_pedido_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_before jsonb;
  v_after jsonb;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'pedidos.cancel',
    'pedidos',
    'com_pedidos',
    'status_transition',
    jsonb_build_object('event', 'cancel')
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status in ('cancelled', 'fulfilled') then
    raise exception 'pedido status does not allow cancellation';
  end if;
  if exists (
    select 1
      from public.exp_romaneios romaneio
     where romaneio.pedido_id = p_pedido_id
       and romaneio.status not in ('cancelado', 'estornado')
  ) then
    raise exception 'pedido has active romaneio; cancel romaneio first';
  end if;
  if exists (
    select 1
      from public.fat_notas_fiscais nota
     where nota.pedido_id = p_pedido_id
       and nota.status_atual not in ('cancelada', 'inutilizada')
  ) then
    raise exception 'pedido has active nota fiscal; cancel fiscal document first';
  end if;
  if exists (
    select 1
      from public.com_recebimentos recebimento
     where recebimento.pedido_id = p_pedido_id
       and coalesce(recebimento.status, 'active') = 'active'
  ) then
    raise exception 'pedido has active receipt; reverse receipt first';
  end if;

  perform public.validate_com_pedido_status_transition(v_pedido.status, 'cancelled', 'cancel');

  v_actor := public.current_actor_id();
  v_before := public.com_pedido_audit_snapshot(p_pedido_id);

  update public.com_pedidos
     set status = 'cancelled',
         updated_by = v_actor
   where id = p_pedido_id;

  update public.com_pedido_itens
     set status = 'cancelled',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status = 'active';

  update public.com_pedido_comissionados
     set status = 'bloqueada',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status = 'prevista';

  v_after := public.com_pedido_audit_snapshot(p_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    p_pedido_id::text,
    'pedidos.pedido_cancelado',
    'pedidos.cancel',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'cancelar_com_pedido',
      'pedido_id', p_pedido_id,
      'motivo', trim(p_motivo),
      'status_anterior', v_pedido.status,
      'status_resultante', 'cancelled'
    )
  );

  return p_pedido_id;
end;
$$;

revoke all on function public.com_pedido_audit_snapshot(bigint) from public;
revoke all on function public.validate_com_pedido_status_transition(text, text, text) from public;
revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from public;
revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from authenticated;
revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.create_com_pedido_rascunho(bigint, bigint, numeric, numeric, text, text, date, bigint, numeric, text) from public;
revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) from public;
revoke all on function public.cancelar_com_pedido(bigint, text) from public;

grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.create_com_pedido_rascunho(bigint, bigint, numeric, numeric, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) to authenticated;
grant execute on function public.cancelar_com_pedido(bigint, text) to authenticated;
