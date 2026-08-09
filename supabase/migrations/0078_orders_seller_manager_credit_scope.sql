-- Seller workspace, manager approval queue and scoped order visibility.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.view.own', 'pedidos', 'Consultar pedidos da propria carteira comercial', true, 113, 'pedidos', 'read'),
  ('pedidos.view.team', 'pedidos', 'Consultar pedidos de vendedores subordinados', true, 114, 'pedidos', 'read'),
  ('pedidos.customer.credit.view', 'pedidos', 'Consultar credito dos clientes da carteira', true, 115, 'pedidos', 'read'),
  ('pedidos.credit.limit.adjust', 'pedidos', 'Alterar limite de credito com justificativa', true, 116, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table if not exists public.cad_limite_credito_eventos (
  id bigint generated always as identity primary key,
  limite_credito_id bigint not null references public.cad_limites_credito_cliente(id),
  cliente_id bigint not null references public.cad_clientes(id),
  tipo_evento text not null,
  limite_anterior numeric,
  limite_novo numeric not null,
  status_anterior text,
  status_novo text not null,
  justificativa text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_limite_credito_eventos_tipo_check
    check (tipo_evento in ('aumento', 'reducao', 'bloqueio', 'liberacao')),
  constraint cad_limite_credito_eventos_valor_check check (limite_novo >= 0),
  constraint cad_limite_credito_eventos_justificativa_check
    check (char_length(trim(justificativa)) >= 10)
);

create index if not exists idx_cad_limite_credito_eventos_cliente
  on public.cad_limite_credito_eventos(cliente_id, created_at desc);

alter table public.cad_limite_credito_eventos enable row level security;
revoke all on public.cad_limite_credito_eventos from public, anon;
revoke insert, update, delete, truncate on public.cad_limite_credito_eventos from authenticated;
grant select on public.cad_limite_credito_eventos to authenticated;

create or replace function public.current_commercial_person_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select person.id
    from public.cad_pessoas_comerciais person
   where person.user_profile_id = public.current_actor_id()
     and person.status = 'active'
   limit 1
$$;

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles profile
     where profile.id = public.current_actor_id()
       and profile.status = 'active'
       and profile.role = 'admin'
  )
$$;

create or replace function public.current_user_manages_seller(p_seller_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with actor as (
    select public.current_commercial_person_id() as person_id
  )
  select public.current_user_is_admin()
    or exists (
      select 1
        from public.cad_pessoas_comerciais seller, actor
       where seller.id = p_seller_id
         and seller.status = 'active'
         and seller.vendedor_responsavel_id = actor.person_id
    )
    or exists (
      select 1
        from public.cad_pessoa_areas_comerciais seller_area
        join public.cad_areas_comerciais area
          on area.id = seller_area.area_id and area.status = 'active'
        cross join actor
       where seller_area.pessoa_id = p_seller_id
         and seller_area.status = 'active'
         and (seller_area.vigencia_inicio is null or seller_area.vigencia_inicio <= current_date)
         and (seller_area.vigencia_fim is null or seller_area.vigencia_fim >= current_date)
         and (area.gerente_id = actor.person_id or exists (
           select 1 from public.cad_pessoa_areas_comerciais manager_area
            where manager_area.area_id = area.id
              and manager_area.pessoa_id = actor.person_id
              and manager_area.papel_area in ('gerente', 'supervisor')
              and manager_area.status = 'active'
              and (manager_area.vigencia_inicio is null or manager_area.vigencia_inicio <= current_date)
              and (manager_area.vigencia_fim is null or manager_area.vigencia_fim >= current_date)
         ))
    )
$$;

create or replace function public.can_current_user_view_order(p_order_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.com_pedidos orders
     where orders.id = p_order_id
       and (
         public.current_user_is_admin()
         or orders.vendedor_gerador_id = public.current_commercial_person_id()
         or public.current_user_manages_seller(orders.vendedor_gerador_id)
       )
  )
$$;

create or replace function public.can_current_user_view_client(p_client_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_is_admin() or exists (
    select 1
      from public.cad_cliente_vendedores relation
      join public.cad_cliente_vinculo_papeis role_catalog
        on role_catalog.id = relation.papel_vinculo_id
     where relation.cliente_id = p_client_id
       and relation.status = 'active'
       and role_catalog.concede_visibilidade = true
       and (relation.vigencia_inicio is null or relation.vigencia_inicio <= current_date)
       and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
       and (
         relation.pessoa_id = public.current_commercial_person_id()
         or public.current_user_manages_seller(relation.pessoa_id)
       )
  )
$$;

revoke all on function public.current_commercial_person_id() from public, anon;
revoke all on function public.current_user_is_admin() from public, anon;
revoke all on function public.current_user_manages_seller(bigint) from public, anon;
revoke all on function public.can_current_user_view_order(bigint) from public, anon;
revoke all on function public.can_current_user_view_client(bigint) from public, anon;
grant execute on function public.current_commercial_person_id() to authenticated;
grant execute on function public.current_user_is_admin() to authenticated;
grant execute on function public.current_user_manages_seller(bigint) to authenticated;
grant execute on function public.can_current_user_view_order(bigint) to authenticated;
grant execute on function public.can_current_user_view_client(bigint) to authenticated;

drop policy if exists "authenticated read com_pedidos" on public.com_pedidos;
create policy "scoped authenticated read com_pedidos" on public.com_pedidos
  for select to authenticated using (public.can_current_user_view_order(id));

drop policy if exists "authenticated read com_pedido_itens" on public.com_pedido_itens;
create policy "scoped authenticated read com_pedido_itens" on public.com_pedido_itens
  for select to authenticated using (public.can_current_user_view_order(pedido_id));

drop policy if exists "authenticated read com_pedido_comissionados" on public.com_pedido_comissionados;
create policy "scoped authenticated read com_pedido_comissionados" on public.com_pedido_comissionados
  for select to authenticated using (public.can_current_user_view_order(pedido_id));

drop policy if exists "authenticated read com_pedido_credito_decisoes" on public.com_pedido_credito_decisoes;
create policy "scoped authenticated read com_pedido_credito_decisoes" on public.com_pedido_credito_decisoes
  for select to authenticated using (public.can_current_user_view_order(pedido_id));

drop policy if exists "authenticated read cad_limites_credito_cliente" on public.cad_limites_credito_cliente;
create policy "scoped authenticated read cad_limites_credito_cliente" on public.cad_limites_credito_cliente
  for select to authenticated using (public.can_current_user_view_client(cliente_id));

create policy "scoped authenticated read cad_limite_credito_eventos"
  on public.cad_limite_credito_eventos for select to authenticated
  using (public.can_current_user_view_client(cliente_id));

create or replace function public.consultar_com_carteira_clientes(p_busca text default null)
returns table (
  vinculo_id bigint, cliente_id bigint, cliente_nome text, propriedade_id bigint,
  propriedade_nome text, vendedor_id bigint, vendedor_nome text,
  limite_disponivel numeric, status_credito text
)
language sql
stable
security definer
set search_path = public
as $$
  select relation.id,
         client.id,
         client.nome,
         property.id,
         property.nome,
         seller.id,
         seller.nome,
         credit.limite_disponivel,
         coalesce(credit.status_credito, 'pendente_aprovacao')
    from public.cad_cliente_vendedores relation
    join public.cad_cliente_vinculo_papeis role_catalog
      on role_catalog.id = relation.papel_vinculo_id and role_catalog.concede_visibilidade = true
    join public.cad_clientes client on client.id = relation.cliente_id and client.status = 'active'
    join public.cad_pessoas_comerciais seller on seller.id = relation.pessoa_id
    left join public.cad_cliente_propriedades property
      on property.id = relation.propriedade_id and property.status = 'active'
    left join lateral (
      select limits.limite_disponivel, limits.status_credito
        from public.cad_limites_credito_cliente limits
       where limits.cliente_id = client.id
       order by limits.updated_at desc, limits.id desc
       limit 1
    ) credit on true
   where relation.status = 'active'
     and (relation.vigencia_inicio is null or relation.vigencia_inicio <= current_date)
     and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
     and relation.pessoa_id = public.current_commercial_person_id()
     and (nullif(trim(p_busca), '') is null or client.nome ilike '%' || trim(p_busca) || '%')
   order by client.nome, property.nome nulls first
   limit 80
$$;

create or replace function public.consultar_com_pedidos_escopo(p_limite integer default 100)
returns table (
  pedido_id bigint, codigo_pedido text, cliente_id bigint, cliente_nome text,
  propriedade_nome text, vendedor_id bigint, vendedor_nome text, status text,
  tipo_pedido text, data_pedido date, valor_total numeric, criado_em timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select orders.id, orders.codigo_pedido, orders.cliente_id, client.nome,
         property.nome, seller.id, seller.nome, orders.status, orders.tipo_pedido,
         orders.data_pedido, orders.valor_total, orders.created_at
    from public.com_pedidos orders
    join public.cad_clientes client on client.id = orders.cliente_id
    left join public.cad_cliente_propriedades property on property.id = orders.propriedade_id
    left join public.cad_pessoas_comerciais seller on seller.id = orders.vendedor_gerador_id
   where public.can_current_user_view_order(orders.id)
   order by orders.created_at desc
   limit greatest(1, least(coalesce(p_limite, 100), 300))
$$;

create or replace function public.consultar_com_pedidos_aprovacao()
returns table (
  pedido_id bigint, codigo_pedido text, cliente_id bigint, cliente_nome text,
  vendedor_id bigint, vendedor_nome text, data_pedido date, valor_total numeric,
  limite_disponivel numeric, status_credito text
)
language sql
stable
security definer
set search_path = public
as $$
  select orders.id, orders.codigo_pedido, client.id, client.nome,
         seller.id, seller.nome, orders.data_pedido, orders.valor_total,
         credit.limite_disponivel, coalesce(credit.status_credito, 'pendente_aprovacao')
    from public.com_pedidos orders
    join public.cad_clientes client on client.id = orders.cliente_id
    join public.cad_pessoas_comerciais seller on seller.id = orders.vendedor_gerador_id
    left join lateral (
      select limits.limite_disponivel, limits.status_credito
        from public.cad_limites_credito_cliente limits
       where limits.cliente_id = client.id
       order by limits.updated_at desc, limits.id desc limit 1
    ) credit on true
   where orders.status = 'blocked'
     and public.current_user_manages_seller(orders.vendedor_gerador_id)
     and exists (
       select 1 from public.com_pedido_credito_decisoes decision
        where decision.pedido_id = orders.id
          and decision.decisao = 'pendente_aprovacao'
          and not exists (
            select 1 from public.com_pedido_credito_decisoes newer
             where newer.pedido_id = orders.id
               and (newer.created_at, newer.id) > (decision.created_at, decision.id)
          )
     )
   order by orders.created_at
$$;

revoke all on function public.consultar_com_carteira_clientes(text) from public, anon;
revoke all on function public.consultar_com_pedidos_escopo(integer) from public, anon;
revoke all on function public.consultar_com_pedidos_aprovacao() from public, anon;
grant execute on function public.consultar_com_carteira_clientes(text) to authenticated;
grant execute on function public.consultar_com_pedidos_escopo(integer) to authenticated;
grant execute on function public.consultar_com_pedidos_aprovacao() to authenticated;

create or replace function public.create_com_pedido_vendedor(
  p_cliente_vendedor_vinculo_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_data_pedido date default current_date,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_seller_id bigint;
  v_link public.cad_cliente_vendedores%rowtype;
  v_order_id bigint;
  v_limit numeric;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.create.own');
  v_actor := public.current_actor_id();
  v_seller_id := public.current_commercial_person_id();
  if v_seller_id is null then raise exception 'commercial identity not linked to current user'; end if;

  select * into v_link from public.cad_cliente_vendedores
   where id = p_cliente_vendedor_vinculo_id for share;
  if not found or v_link.pessoa_id <> v_seller_id or v_link.status <> 'active' then
    raise exception 'client is outside seller portfolio';
  end if;
  if (v_link.vigencia_inicio is not null and v_link.vigencia_inicio > p_data_pedido)
     or (v_link.vigencia_fim is not null and v_link.vigencia_fim < p_data_pedido) then
    raise exception 'client seller link is outside effective period';
  end if;

  v_context := public.begin_audited_rpc(
    'pedidos.create.own', 'pedidos', 'com_pedidos', 'own_any',
    jsonb_build_object('event', 'seller_order_pending_approval')
  );

  v_order_id := public.create_com_pedido_operacional(
    v_link.cliente_id, p_produto_embalagem_id, p_quantidade, p_valor_unitario,
    v_link.propriedade_id, 'venda', 'blocked', p_data_pedido,
    v_seller_id, null, p_observacao
  );

  update public.com_pedidos set cliente_vendedor_vinculo_id = v_link.id
   where id = v_order_id;

  select limits.limite_disponivel into v_limit
    from public.cad_limites_credito_cliente limits
   where limits.cliente_id = v_link.cliente_id
   order by limits.updated_at desc, limits.id desc limit 1;

  insert into public.com_pedido_credito_decisoes(
    pedido_id, decisao, status_anterior, status_resultante, motivo,
    limite_disponivel_snapshot, observacao, created_by
  ) values (
    v_order_id, 'pendente_aprovacao', 'blocked', 'blocked',
    'Aguardando liberacao gerencial', v_limit,
    'Pedido criado pelo vendedor e encaminhado automaticamente para aprovacao.', v_actor
  );

  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_order_id::text,
    'pedidos.pedido_enviado_aprovacao', 'pedidos.create.own', v_context,
    null, public.com_pedido_audit_snapshot(v_order_id),
    jsonb_build_object('source', 'create_com_pedido_vendedor', 'cliente_vendedor_vinculo_id', v_link.id)
  );
  return v_order_id;
end;
$$;

create or replace function public.registrar_com_pedido_decisao_gerencial(
  p_pedido_id bigint,
  p_decisao text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.com_pedidos%rowtype;
  v_limit numeric;
begin
  perform public.require_current_user_permission('pedidos.credit.review');
  if p_decisao not in ('liberado', 'bloqueado') then raise exception 'invalid manager decision'; end if;
  if char_length(trim(coalesce(p_justificativa, ''))) < 10 then raise exception 'justification must have at least 10 characters'; end if;
  select * into v_order from public.com_pedidos where id = p_pedido_id for update;
  if not found then raise exception 'pedido not found'; end if;
  if not public.current_user_manages_seller(v_order.vendedor_gerador_id) then raise exception 'order is outside manager team'; end if;
  select limits.limite_disponivel into v_limit from public.cad_limites_credito_cliente limits
   where limits.cliente_id = v_order.cliente_id order by limits.updated_at desc, limits.id desc limit 1;
  return public.registrar_com_pedido_decisao_credito(
    p_pedido_id, p_decisao, trim(p_justificativa), v_limit, null,
    'Decisao registrada pela alçada gerencial.'
  );
end;
$$;

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
  v_event_id bigint;
  v_event_type text;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.credit.limit.adjust');
  if p_limite_novo is null or p_limite_novo < 0 then raise exception 'new credit limit must be non-negative'; end if;
  if char_length(trim(coalesce(p_justificativa, ''))) < 10 then raise exception 'justification must have at least 10 characters'; end if;
  if not public.current_user_is_admin() and not exists (
    select 1 from public.cad_cliente_vendedores relation
     where relation.cliente_id = p_cliente_id and relation.status = 'active'
       and public.current_user_manages_seller(relation.pessoa_id)
  ) then raise exception 'client is outside manager team'; end if;

  perform pg_advisory_xact_lock(hashtextextended('credit_limit:' || p_cliente_id::text, 0));
  select * into v_current from public.cad_limites_credito_cliente
   where cliente_id = p_cliente_id order by updated_at desc, id desc limit 1 for update;
  v_actor := public.current_actor_id();
  v_context := public.begin_audited_rpc(
    'pedidos.credit.limit.adjust', 'pedidos', 'cad_limite_credito_eventos',
    'change_type', jsonb_build_object('event', 'credit_limit_adjustment')
  );

  if not found then
    insert into public.cad_limites_credito_cliente(
      cliente_id, limite_manual, limite_disponivel, status_credito, motivo, updated_by
    ) values (p_cliente_id, p_limite_novo, p_limite_novo, 'liberado', trim(p_justificativa), v_actor)
    returning * into v_current;
    v_event_type := 'liberacao';
  else
    v_event_type := case when p_limite_novo > v_current.limite_disponivel then 'aumento'
                         when p_limite_novo < v_current.limite_disponivel then 'reducao'
                         else 'liberacao' end;
    update public.cad_limites_credito_cliente
       set limite_manual = p_limite_novo, limite_disponivel = p_limite_novo,
           status_credito = 'liberado', motivo = trim(p_justificativa), updated_by = v_actor
     where id = v_current.id;
  end if;

  insert into public.cad_limite_credito_eventos(
    limite_credito_id, cliente_id, tipo_evento, limite_anterior, limite_novo,
    status_anterior, status_novo, justificativa, created_by
  ) values (
    v_current.id, p_cliente_id, v_event_type,
    case when v_event_type = 'liberacao' and v_current.created_at = v_current.updated_at then null else v_current.limite_disponivel end,
    p_limite_novo, v_current.status_credito, 'liberado', trim(p_justificativa), v_actor
  ) returning id into v_event_id;

  perform public.log_audited_rpc_change(
    'pedidos', 'cad_limite_credito_eventos', v_event_id::text,
    'pedidos.limite_credito_ajustado', 'pedidos.credit.limit.adjust', v_context,
    to_jsonb(v_current),
    (select to_jsonb(limits) from public.cad_limites_credito_cliente limits where limits.id = v_current.id),
    jsonb_build_object('source', 'ajustar_com_limite_credito_cliente', 'cliente_id', p_cliente_id, 'justificativa', trim(p_justificativa))
  );
  return v_event_id;
end;
$$;

revoke all on function public.create_com_pedido_vendedor(bigint, bigint, numeric, numeric, date, text) from public, anon;
revoke all on function public.registrar_com_pedido_decisao_gerencial(bigint, text, text) from public, anon;
revoke all on function public.ajustar_com_limite_credito_cliente(bigint, numeric, text) from public, anon;
grant execute on function public.create_com_pedido_vendedor(bigint, bigint, numeric, numeric, date, text) to authenticated;
grant execute on function public.registrar_com_pedido_decisao_gerencial(bigint, text, text) to authenticated;
grant execute on function public.ajustar_com_limite_credito_cliente(bigint, numeric, text) to authenticated;

comment on table public.cad_limite_credito_eventos is
  'Historico append-only de alteracoes gerenciais no limite de credito do cliente.';
comment on function public.create_com_pedido_vendedor(bigint, bigint, numeric, numeric, date, text) is
  'Cria venda para a carteira do usuario autenticado e sempre encaminha o pedido para liberacao gerencial.';
