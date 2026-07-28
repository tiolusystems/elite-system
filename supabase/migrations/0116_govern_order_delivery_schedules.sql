-- Govern customer portfolio search and relational delivery schedules for seller orders.

create table public.com_pedido_entregas (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  cliente_id bigint not null references public.cad_clientes(id) on delete restrict,
  sequencia integer not null,
  data_prevista date not null,
  propriedade_id bigint,
  estabelecimento_id bigint,
  endereco_id bigint,
  status text not null default 'planned',
  observacao text,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  updated_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_pedido_entregas_sequencia_check check (sequencia > 0),
  constraint com_pedido_entregas_local_check
    check (num_nonnulls(propriedade_id, estabelecimento_id, endereco_id) = 1),
  constraint com_pedido_entregas_status_check
    check (status in ('planned', 'partially_fulfilled', 'fulfilled', 'cancelled')),
  constraint com_pedido_entregas_observacao_check
    check (observacao is null or char_length(btrim(observacao)) <= 500),
  constraint com_pedido_entregas_pedido_sequencia_key unique (pedido_id, sequencia)
);

create unique index idx_cad_cliente_estabelecimentos_identity
  on public.cad_cliente_estabelecimentos(id, cliente_id);
create unique index idx_cad_cliente_enderecos_identity
  on public.cad_cliente_enderecos(id, cliente_id);
create unique index idx_com_pedido_entregas_identity
  on public.com_pedido_entregas(id, pedido_id);
create unique index idx_com_pedido_itens_order_identity
  on public.com_pedido_itens(id, pedido_id);
create index idx_com_pedido_entregas_order_status
  on public.com_pedido_entregas(pedido_id, status, data_prevista);

alter table public.com_pedido_entregas
  add constraint com_pedido_entregas_propriedade_cliente_fk
    foreign key (propriedade_id, cliente_id)
    references public.cad_cliente_propriedades(id, cliente_id) on delete restrict,
  add constraint com_pedido_entregas_estabelecimento_cliente_fk
    foreign key (estabelecimento_id, cliente_id)
    references public.cad_cliente_estabelecimentos(id, cliente_id) on delete restrict,
  add constraint com_pedido_entregas_endereco_cliente_fk
    foreign key (endereco_id, cliente_id)
    references public.cad_cliente_enderecos(id, cliente_id) on delete restrict;

create table public.com_pedido_entrega_itens (
  id bigint generated always as identity primary key,
  entrega_id bigint not null,
  pedido_id bigint not null,
  pedido_item_id bigint not null,
  quantidade_prevista numeric not null,
  quantidade_atendida numeric not null default 0,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint com_pedido_entrega_itens_quantidade_check
    check (quantidade_prevista > 0 and quantidade_atendida >= 0 and quantidade_atendida <= quantidade_prevista),
  constraint com_pedido_entrega_itens_key unique (entrega_id, pedido_item_id),
  constraint com_pedido_entrega_itens_entrega_fk
    foreign key (entrega_id, pedido_id)
    references public.com_pedido_entregas(id, pedido_id) on delete restrict,
  constraint com_pedido_entrega_itens_pedido_item_fk
    foreign key (pedido_item_id, pedido_id)
    references public.com_pedido_itens(id, pedido_id) on delete restrict
);

create index idx_com_pedido_entrega_itens_order
  on public.com_pedido_entrega_itens(pedido_id, pedido_item_id);

alter table public.exp_romaneios
  add column entrega_programada_id bigint references public.com_pedido_entregas(id) on delete restrict;

create index idx_exp_romaneios_entrega_programada
  on public.exp_romaneios(entrega_programada_id)
  where entrega_programada_id is not null;

create trigger trg_com_pedido_entregas_updated_at
before update on public.com_pedido_entregas
for each row execute function public.touch_updated_at();

alter table public.com_pedido_entregas enable row level security;
alter table public.com_pedido_entrega_itens enable row level security;

create policy "scoped authenticated read com_pedido_entregas"
  on public.com_pedido_entregas for select to authenticated
  using (public.can_current_user_view_order(pedido_id));

create policy "scoped authenticated read com_pedido_entrega_itens"
  on public.com_pedido_entrega_itens for select to authenticated
  using (public.can_current_user_view_order(pedido_id));

revoke all on public.com_pedido_entregas, public.com_pedido_entrega_itens from public, anon;
revoke insert, update, delete, truncate on public.com_pedido_entregas, public.com_pedido_entrega_itens from authenticated;
grant select on public.com_pedido_entregas, public.com_pedido_entrega_itens to authenticated;

create or replace function public.consultar_com_carteira_clientes_paginada(
  p_busca text default null,
  p_limite integer default 20,
  p_offset integer default 0
)
returns table (
  vinculo_id bigint,
  cliente_id bigint,
  cliente_nome text,
  razao_social text,
  nome_fantasia text,
  documento_principal text,
  municipio text,
  uf text,
  situacao text,
  vendedor_id bigint,
  vendedor_nome text,
  limite_disponivel numeric,
  status_credito text
)
language sql
stable
security definer
set search_path = public
as $$
  select relation.id,
         client.id,
         client.nome,
         identification.razao_social,
         identification.nome_fantasia,
         document.numero,
         coalesce(address.cidade, property.cidade, client.cidade),
         coalesce(address.uf, property.uf, client.uf),
         coalesce(identification.situacao_cadastral, client.status),
         seller.id,
         seller.nome,
         credit.limite_disponivel,
         coalesce(credit.status_credito, 'pendente_aprovacao')
    from public.cad_cliente_vendedores relation
    join public.cad_cliente_vinculo_papeis role_catalog
      on role_catalog.id = relation.papel_vinculo_id
     and role_catalog.concede_visibilidade = true
    join public.cad_clientes client
      on client.id = relation.cliente_id
     and client.status = 'active'
    join public.cad_pessoas_comerciais seller
      on seller.id = relation.pessoa_id
     and seller.status = 'active'
    left join public.cad_cliente_identificacoes identification
      on identification.cliente_id = client.id
    left join public.cad_cliente_propriedades property
      on property.id = relation.propriedade_id
     and property.status = 'active'
    left join lateral (
      select customer_document.numero, customer_document.numero_norm
        from public.cad_cliente_documentos customer_document
       where customer_document.cliente_id = client.id
       order by case customer_document.tipo when 'cnpj' then 1 when 'cpf' then 2 when 'ie' then 3 else 4 end,
                customer_document.id
       limit 1
    ) document on true
    left join lateral (
      select customer_address.cidade, customer_address.uf
        from public.cad_cliente_enderecos customer_address
       where customer_address.cliente_id = client.id
         and customer_address.status = 'active'
         and customer_address.tipo = 'entrega'
       order by customer_address.id
       limit 1
    ) address on true
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
     and (
       relation.pessoa_id = public.current_commercial_person_id()
       or public.current_user_manages_seller(relation.pessoa_id)
     )
     and (
       nullif(btrim(p_busca), '') is null
       or client.nome ilike '%' || btrim(p_busca) || '%'
       or identification.razao_social ilike '%' || btrim(p_busca) || '%'
       or identification.nome_fantasia ilike '%' || btrim(p_busca) || '%'
       or document.numero_norm ilike '%' || public.normalize_customer_document(p_busca) || '%'
       or client.cidade ilike '%' || btrim(p_busca) || '%'
       or property.nome ilike '%' || btrim(p_busca) || '%'
       or exists (
         select 1
           from public.cad_cliente_estabelecimentos establishment
          where establishment.cliente_id = client.id
            and establishment.status = 'active'
            and establishment.nome ilike '%' || btrim(p_busca) || '%'
       )
       or exists (
         select 1
           from public.cad_cliente_documentos customer_document
          where customer_document.cliente_id = client.id
            and customer_document.numero_norm ilike '%' || public.normalize_customer_document(p_busca) || '%'
       )
     )
   order by client.nome, seller.nome, relation.id
   limit greatest(1, least(coalesce(p_limite, 20), 50))
  offset greatest(coalesce(p_offset, 0), 0)
$$;

create or replace function public.consultar_com_locais_entrega_cliente(p_cliente_id bigint)
returns table (
  local_key text,
  tipo_local text,
  propriedade_id bigint,
  estabelecimento_id bigint,
  endereco_id bigint,
  nome text,
  endereco_resumo text,
  municipio text,
  uf text
)
language sql
stable
security definer
set search_path = public
as $$
  with allowed_client as (
    select p_cliente_id as cliente_id
     where public.can_current_user_view_client(p_cliente_id)
  ),
  locations as (
    select 'propriedade:' || property.id::text as local_key,
           'propriedade'::text as tipo_local,
           property.id as propriedade_id,
           null::bigint as estabelecimento_id,
           null::bigint as endereco_id,
           property.nome,
           concat_ws(', ', address.logradouro, address.numero, address.bairro) as endereco_resumo,
           coalesce(address.cidade, property.cidade) as municipio,
           coalesce(address.uf, property.uf) as uf,
           1 as sort_order
      from allowed_client
      join public.cad_cliente_propriedades property
        on property.cliente_id = allowed_client.cliente_id
       and property.status = 'active'
      left join lateral (
        select delivery_address.logradouro, delivery_address.numero, delivery_address.bairro,
               delivery_address.cidade, delivery_address.uf
          from public.cad_cliente_enderecos delivery_address
         where delivery_address.cliente_id = property.cliente_id
           and delivery_address.propriedade_id = property.id
           and delivery_address.status = 'active'
           and delivery_address.tipo = 'entrega'
         order by delivery_address.id
         limit 1
      ) address on true
    union all
    select 'estabelecimento:' || establishment.id::text,
           'estabelecimento',
           null::bigint,
           establishment.id,
           null::bigint,
           establishment.nome,
           concat_ws(', ', address.logradouro, address.numero, address.bairro),
           address.cidade,
           address.uf,
           2
      from allowed_client
      join public.cad_cliente_estabelecimentos establishment
        on establishment.cliente_id = allowed_client.cliente_id
       and establishment.status = 'active'
      join lateral (
        select delivery_address.logradouro, delivery_address.numero, delivery_address.bairro,
               delivery_address.cidade, delivery_address.uf
          from public.cad_cliente_enderecos delivery_address
         where delivery_address.cliente_id = establishment.cliente_id
           and delivery_address.estabelecimento_id = establishment.id
           and delivery_address.status = 'active'
           and delivery_address.tipo = 'entrega'
         order by delivery_address.id
         limit 1
      ) address on true
    union all
    select 'endereco:' || address.id::text,
           'cadastro_geral',
           null::bigint,
           null::bigint,
           address.id,
           'Cadastro geral do cliente',
           concat_ws(', ', address.logradouro, address.numero, address.bairro),
           address.cidade,
           address.uf,
           3
      from allowed_client
      join public.cad_cliente_enderecos address
        on address.cliente_id = allowed_client.cliente_id
       and address.propriedade_id is null
       and address.estabelecimento_id is null
       and address.status = 'active'
       and address.tipo = 'entrega'
  )
  select local_key, tipo_local, propriedade_id, estabelecimento_id, endereco_id,
         nome, nullif(endereco_resumo, ''), municipio, uf
    from locations
   order by sort_order, nome, local_key
$$;

create or replace function public.create_com_pedido_vendedor_programado_idempotente(
  p_idempotency_key uuid,
  p_cliente_vendedor_vinculo_id bigint,
  p_itens_jsonb jsonb,
  p_entregas_jsonb jsonb,
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
  v_payload_hash text;
  v_existing public.com_pedido_requisicoes%rowtype;
  v_pedido_id bigint;
  v_cliente_id bigint;
  v_delivery record;
  v_allocation record;
  v_entrega_id bigint;
  v_item_id bigint;
  v_item_quantity numeric;
  v_item_index integer;
  v_property_id bigint;
  v_establishment_id bigint;
  v_address_id bigint;
  v_delivery_date date;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.create.own');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  if p_data_pedido is null then raise exception 'order date is required'; end if;
  if jsonb_typeof(p_entregas_jsonb) <> 'array' or jsonb_array_length(p_entregas_jsonb) < 1 then
    raise exception 'delivery schedule is required';
  end if;
  if jsonb_typeof(p_itens_jsonb) <> 'array' or jsonb_array_length(p_itens_jsonb) < 1 then
    raise exception 'sale items are required';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(p_itens_jsonb) entry(item)
     group by nullif(entry.item->>'produto_embalagem_id', '')
    having count(*) > 1
  ) then
    raise exception 'duplicate sale presentation is not allowed';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo_operacao', 'venda_programada',
    'cliente_vendedor_vinculo_id', p_cliente_vendedor_vinculo_id,
    'itens', p_itens_jsonb,
    'entregas', p_entregas_jsonb,
    'data_pedido', p_data_pedido,
    'observacao', nullif(btrim(p_observacao), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
    from public.com_pedido_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'venda'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different order request';
    end if;
    return v_existing.pedido_id;
  end if;

  v_pedido_id := public.create_com_pedido_vendedor_itens(
    p_cliente_vendedor_vinculo_id, p_itens_jsonb, p_data_pedido, p_observacao
  );
  select orders.cliente_id into v_cliente_id
    from public.com_pedidos orders
   where orders.id = v_pedido_id;

  for v_delivery in
    select entry.item, entry.ordinality
      from jsonb_array_elements(p_entregas_jsonb) with ordinality as entry(item, ordinality)
     order by entry.ordinality
  loop
    v_delivery_date := nullif(v_delivery.item->>'data_prevista', '')::date;
    v_property_id := nullif(v_delivery.item->>'propriedade_id', '')::bigint;
    v_establishment_id := nullif(v_delivery.item->>'estabelecimento_id', '')::bigint;
    v_address_id := nullif(v_delivery.item->>'endereco_id', '')::bigint;

    if v_delivery_date is null then raise exception 'delivery date is required'; end if;
    if v_delivery_date < p_data_pedido then raise exception 'delivery date cannot precede order date'; end if;
    if num_nonnulls(v_property_id, v_establishment_id, v_address_id) <> 1 then
      raise exception 'delivery location is required';
    end if;
    if v_property_id is not null and not exists (
      select 1 from public.cad_cliente_propriedades property
       where property.id = v_property_id and property.cliente_id = v_cliente_id and property.status = 'active'
    ) then raise exception 'delivery property is inactive or belongs to another client'; end if;
    if v_establishment_id is not null and not exists (
      select 1 from public.cad_cliente_estabelecimentos establishment
       where establishment.id = v_establishment_id and establishment.cliente_id = v_cliente_id and establishment.status = 'active'
    ) then raise exception 'delivery establishment is inactive or belongs to another client'; end if;
    if v_address_id is not null and not exists (
      select 1 from public.cad_cliente_enderecos address
       where address.id = v_address_id and address.cliente_id = v_cliente_id
         and address.status = 'active' and address.tipo = 'entrega'
    ) then raise exception 'delivery address is inactive or belongs to another client'; end if;
    if jsonb_typeof(v_delivery.item->'itens') <> 'array' or jsonb_array_length(v_delivery.item->'itens') < 1 then
      raise exception 'delivery items are required';
    end if;

    insert into public.com_pedido_entregas(
      pedido_id, cliente_id, sequencia, data_prevista, propriedade_id,
      estabelecimento_id, endereco_id, status, observacao, created_by, updated_by
    ) values (
      v_pedido_id, v_cliente_id, v_delivery.ordinality, v_delivery_date, v_property_id,
      v_establishment_id, v_address_id, 'planned',
      nullif(btrim(v_delivery.item->>'observacao'), ''), v_actor, v_actor
    ) returning id into v_entrega_id;

    for v_allocation in
      select allocation.item, allocation.ordinality
        from jsonb_array_elements(v_delivery.item->'itens') with ordinality as allocation(item, ordinality)
    loop
      v_item_id := null;
      v_item_quantity := null;
      v_item_index := nullif(v_allocation.item->>'item_index', '')::integer;
      if v_item_index is null or v_item_index < 1 then raise exception 'invalid delivery item position'; end if;
      select item.id, item.quantidade into v_item_id, v_item_quantity
        from public.com_pedido_itens item
       where item.pedido_id = v_pedido_id and item.status = 'active'
       order by item.id
      offset (v_item_index - 1) limit 1;
      if v_item_id is null then raise exception 'delivery item does not belong to order'; end if;
      if coalesce((v_allocation.item->>'quantidade')::numeric, 0) <= 0 then
        raise exception 'delivery item quantity must be positive';
      end if;
      insert into public.com_pedido_entrega_itens(
        entrega_id, pedido_id, pedido_item_id, quantidade_prevista, created_by
      ) values (
        v_entrega_id, v_pedido_id, v_item_id,
        (v_allocation.item->>'quantidade')::numeric, v_actor
      );
    end loop;
  end loop;

  if exists (
    select 1
      from public.com_pedido_itens item
      left join lateral (
        select sum(schedule_item.quantidade_prevista) as quantidade_programada
          from public.com_pedido_entrega_itens schedule_item
         where schedule_item.pedido_item_id = item.id
      ) schedule on true
     where item.pedido_id = v_pedido_id
       and item.status = 'active'
       and coalesce(schedule.quantidade_programada, 0) is distinct from item.quantidade
  ) then raise exception 'delivery schedule does not cover order quantities'; end if;

  update public.com_pedidos
     set previsao_entrega = (
       select min(delivery.data_prevista)
         from public.com_pedido_entregas delivery
        where delivery.pedido_id = v_pedido_id
          and delivery.status <> 'cancelled'
     ),
         updated_by = v_actor
   where id = v_pedido_id;

  insert into public.com_pedido_requisicoes(
    idempotency_key, tipo_operacao, pedido_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'venda', v_pedido_id, v_actor, v_payload_hash);

  v_context := public.begin_audited_rpc(
    'pedidos.create.own', 'pedidos', 'com_pedido_entregas', 'own_any',
    jsonb_build_object('pedido_id', v_pedido_id)
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedidos', v_pedido_id::text,
    'pedidos.programacao_entrega_criada', 'pedidos.create.own', v_context,
    null, public.com_pedido_audit_snapshot(v_pedido_id),
    jsonb_build_object(
      'source', 'create_com_pedido_vendedor_programado_idempotente',
      'entregas', jsonb_array_length(p_entregas_jsonb)
    )
  );
  return v_pedido_id;
end;
$$;

revoke all on function public.consultar_com_carteira_clientes_paginada(text, integer, integer)
  from public, anon;
revoke all on function public.consultar_com_locais_entrega_cliente(bigint)
  from public, anon;
revoke all on function public.create_com_pedido_vendedor_programado_idempotente(uuid, bigint, jsonb, jsonb, date, text)
  from public, anon;
grant execute on function public.consultar_com_carteira_clientes_paginada(text, integer, integer)
  to authenticated;
grant execute on function public.consultar_com_locais_entrega_cliente(bigint)
  to authenticated;
grant execute on function public.create_com_pedido_vendedor_programado_idempotente(uuid, bigint, jsonb, jsonb, date, text)
  to authenticated;

comment on table public.com_pedido_entregas is
  'Programacao relacional de entregas do pedido. Nao reserva nem movimenta estoque.';
comment on table public.com_pedido_entrega_itens is
  'Distribuicao planejada dos itens entre entregas, sem efeito fisico ou financeiro.';
comment on function public.consultar_com_carteira_clientes_paginada(text, integer, integer) is
  'Lista e pesquisa incrementalmente apenas clientes da carteira ou equipe governada da sessao.';
comment on function public.consultar_com_locais_entrega_cliente(bigint) is
  'Lista somente locais ativos pertencentes ao cliente dentro do escopo comercial da sessao.';
comment on function public.create_com_pedido_vendedor_programado_idempotente(uuid, bigint, jsonb, jsonb, date, text) is
  'Cria atomicamente pedido bloqueado, itens e programacao integral de entregas, com idempotencia e auditoria.';
