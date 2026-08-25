-- ORD-01 tranche 1D: explicit order commercial context and immutable item price-reference snapshots.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pedidos.commercial_context.manage', 'pedidos', 'Definir contexto comercial e congelar referencias de preco do pedido', false, 134,
  'pedidos', 'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

alter table public.com_pedidos
  add column if not exists origem_comercial_id bigint references public.com_origens_comerciais(id) on delete restrict;

create table public.com_pedido_participantes_comerciais (
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  pessoa_papel_id bigint not null references public.cad_pessoa_papeis(id) on delete restrict,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  primary key (pedido_id, pessoa_papel_id)
);

create table public.com_pedido_item_referencias_comerciais (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  pedido_item_id bigint not null references public.com_pedido_itens(id) on delete restrict,
  origem_comercial_id bigint not null references public.com_origens_comerciais(id) on delete restrict,
  cliente_id bigint not null references public.cad_clientes(id) on delete restrict,
  area_comercial_id bigint references public.cad_areas_comerciais(id) on delete restrict,
  uf text,
  pessoa_papel_ids bigint[] not null default '{}'::bigint[],
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  data_comercial date not null,
  plano_pagamento_id bigint not null references public.fin_pedido_planos_pagamento(id) on delete restrict,
  pmp_dias numeric(18,6) not null check (pmp_dias >= 0),
  lista_id bigint not null references public.com_listas_preco(id) on delete restrict,
  lista_versao_id bigint not null references public.com_lista_preco_versoes(id) on delete restrict,
  publicacao_id bigint not null references public.com_lista_preco_publicacoes(id) on delete restrict,
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete restrict,
  prazo_faixa_dias integer not null check (prazo_faixa_dias >= 0),
  preco_referencia_centavos_por_litro bigint not null check (preco_referencia_centavos_por_litro > 0),
  resolved_by uuid not null references public.user_profiles(id) on delete restrict,
  resolved_at timestamptz not null default clock_timestamp(),
  lineage_json jsonb not null default '{}'::jsonb,
  constraint com_pedido_item_referencias_item_key unique (pedido_item_id),
  constraint com_pedido_item_referencias_pedido_item_key unique (pedido_id, pedido_item_id),
  constraint com_pedido_item_referencias_uf_check check (
    uf is null or uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
                          'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
  )
);

create index idx_com_pedido_participantes_comerciais_papel
  on public.com_pedido_participantes_comerciais(pessoa_papel_id, pedido_id);
create index idx_com_pedido_item_referencias_pedido
  on public.com_pedido_item_referencias_comerciais(pedido_id, pedido_item_id);
create index idx_com_pedido_item_referencias_lista
  on public.com_pedido_item_referencias_comerciais(lista_versao_id, produto_embalagem_id);

create table public.com_pedido_referencia_comercial_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default clock_timestamp()
);

create index idx_com_pedido_referencia_requisicoes_pedido
  on public.com_pedido_referencia_comercial_requisicoes(pedido_id, created_at desc);

create function public.prevent_fin_pedido_plan_change_after_commercial_snapshot()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
      from public.com_pedido_item_referencias_comerciais snapshot
     where snapshot.pedido_id = new.pedido_id
  ) then
    raise exception 'snapshot comercial ja foi congelado; nova condicao financeira exige revisao governada';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_fin_pedido_plan_change_after_commercial_snapshot()
  from public, anon, authenticated;

create trigger trg_fin_pedido_planos_snapshot_comercial_freeze
before insert on public.fin_pedido_planos_pagamento
for each row execute function public.prevent_fin_pedido_plan_change_after_commercial_snapshot();

do $$
begin
  if to_regprocedure('public.prevent_dec009_fact_changes()') is null then
    raise exception 'append-only guard is required for order commercial snapshots';
  end if;
end
$$;

create trigger trg_com_pedido_participantes_comerciais_append_only
before update or delete on public.com_pedido_participantes_comerciais
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_participantes_comerciais_no_truncate
before truncate on public.com_pedido_participantes_comerciais
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_item_referencias_comerciais_append_only
before update or delete on public.com_pedido_item_referencias_comerciais
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_item_referencias_comerciais_no_truncate
before truncate on public.com_pedido_item_referencias_comerciais
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_referencia_comercial_requisicoes_append_only
before update or delete on public.com_pedido_referencia_comercial_requisicoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_referencia_comercial_requisicoes_no_truncate
before truncate on public.com_pedido_referencia_comercial_requisicoes
for each statement execute function public.prevent_dec009_fact_changes();

alter table public.com_pedido_participantes_comerciais enable row level security;
alter table public.com_pedido_item_referencias_comerciais enable row level security;
alter table public.com_pedido_referencia_comercial_requisicoes enable row level security;

create policy "governed read order commercial participants"
  on public.com_pedido_participantes_comerciais for select to authenticated
  using (public.can_current_user('pedidos.price_reference.resolve'));
create policy "governed read order commercial references"
  on public.com_pedido_item_referencias_comerciais for select to authenticated
  using (public.can_current_user('pedidos.price_reference.resolve'));
create policy "governed read order commercial reference requests"
  on public.com_pedido_referencia_comercial_requisicoes for select to authenticated
  using (public.can_current_user('pedidos.commercial_context.manage'));

revoke all on table public.com_pedido_participantes_comerciais from public, anon, authenticated;
revoke all on table public.com_pedido_item_referencias_comerciais from public, anon, authenticated;
revoke all on table public.com_pedido_referencia_comercial_requisicoes from public, anon, authenticated;
grant select on table public.com_pedido_participantes_comerciais to authenticated;
grant select on table public.com_pedido_item_referencias_comerciais to authenticated;
grant select on table public.com_pedido_referencia_comercial_requisicoes to authenticated;

create function public.resolver_com_referencias_comerciais_pedido_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_origem_comercial_id bigint,
  p_area_comercial_id bigint,
  p_uf text,
  p_pessoa_papel_ids bigint[],
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
  v_existing public.com_pedido_referencia_comercial_requisicoes%rowtype;
  v_pedido public.com_pedidos%rowtype;
  v_plano public.fin_pedido_planos_pagamento%rowtype;
  v_participantes bigint[] := '{}'::bigint[];
  v_uf_normalizada text;
  v_item record;
  v_referencia record;
  v_snapshot_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.commercial_context.manage', 'pedidos', 'com_pedido_item_referencias_comerciais',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido e obrigatorio'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  if p_pessoa_papel_ids is not null and array_position(p_pessoa_papel_ids, null) is not null then
    raise exception 'participantes comerciais nao podem conter valor nulo';
  end if;

  select coalesce(array_agg(distinct participant.id order by participant.id), '{}'::bigint[])
    into v_participantes
    from unnest(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) participant(id);
  if cardinality(v_participantes) <> cardinality(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) then
    raise exception 'participante comercial informado mais de uma vez';
  end if;
  v_uf_normalizada := case when p_uf is null then null else upper(btrim(p_uf)) end;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'order_commercial_reference', 'pedido_id', p_pedido_id,
    'origem_comercial_id', p_origem_comercial_id, 'area_comercial_id', p_area_comercial_id,
    'uf', v_uf_normalizada, 'pessoa_papel_ids', v_participantes, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('order_commercial_reference:' || p_pedido_id::text, 0));

  select * into v_existing
    from public.com_pedido_referencia_comercial_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.pedido_id <> p_pedido_id
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.pedido_id;
  end if;

  select * into v_pedido from public.com_pedidos order_header where order_header.id = p_pedido_id for update;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_pedido.status <> 'blocked' then raise exception 'referencia comercial exige pedido bloqueado'; end if;
  if exists (select 1 from public.com_pedido_item_referencias_comerciais snapshot where snapshot.pedido_id = p_pedido_id) then
    raise exception 'pedido ja possui referencia comercial imutavel';
  end if;
  if v_pedido.origem_comercial_id is not null and v_pedido.origem_comercial_id <> p_origem_comercial_id then
    raise exception 'origem comercial do pedido ja foi definida';
  end if;
  if exists (select 1 from public.com_pedido_participantes_comerciais participant where participant.pedido_id = p_pedido_id) then
    raise exception 'participantes comerciais do pedido ja foram definidos';
  end if;

  select * into v_plano
   from public.fin_pedido_planos_pagamento plan
   where plan.pedido_id = p_pedido_id
     and plan.origem_dados = 'sistema'
     and plan.review_status = 'approved'
     and plan.vigencia_inicio <= current_date
     and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date)
     and plan.pmp_dias is not null
   order by plan.versao desc, plan.id desc
   limit 1
   for share;
  if not found then raise exception 'pedido nao possui condicao financeira governada com PMP'; end if;

  for v_item in
    select item.id, item.produto_embalagem_id
      from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id and item.status = 'active'
     order by item.id
     for update
  loop
    select * into v_referencia
      from public.resolver_com_referencia_comercial(
        v_pedido.data_pedido, v_plano.pmp_dias, p_origem_comercial_id, p_area_comercial_id,
        v_uf_normalizada, v_pedido.cliente_id, v_participantes, v_item.produto_embalagem_id
      );
    insert into public.com_pedido_item_referencias_comerciais(
      pedido_id, pedido_item_id, origem_comercial_id, cliente_id, area_comercial_id, uf,
      pessoa_papel_ids, produto_embalagem_id, data_comercial, plano_pagamento_id, pmp_dias,
      lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
      preco_referencia_centavos_por_litro, resolved_by, lineage_json
    ) values (
      p_pedido_id, v_item.id, p_origem_comercial_id, v_pedido.cliente_id, p_area_comercial_id, v_uf_normalizada,
      v_participantes, v_item.produto_embalagem_id, v_pedido.data_pedido, v_plano.id, v_plano.pmp_dias,
      v_referencia.lista_id, v_referencia.versao_id, v_referencia.publicacao_id, v_referencia.regra_id,
      v_referencia.prazo_faixa_dias, v_referencia.preco_referencia_centavos_por_litro, v_actor,
      jsonb_build_object('resolver', '0127', 'especificidade', v_referencia.especificidade,
        'prioridade', v_referencia.prioridade, 'plano_pagamento_versao', v_plano.versao)
    ) returning id into v_snapshot_id;
    perform public.log_audited_rpc_change(
      'pedidos', 'com_pedido_item_referencias_comerciais', v_snapshot_id::text,
      'pedidos.referencia_comercial_congelada', 'pedidos.commercial_context.manage', v_context,
      null, jsonb_build_object('pedido_id', p_pedido_id, 'pedido_item_id', v_item.id,
        'lista_versao_id', v_referencia.versao_id, 'preco_centavos_por_litro', v_referencia.preco_referencia_centavos_por_litro),
      jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
    );
  end loop;
  if v_snapshot_id is null then raise exception 'pedido nao possui itens ativos para resolver'; end if;

  update public.com_pedidos
     set origem_comercial_id = p_origem_comercial_id,
         updated_by = v_actor
   where id = p_pedido_id;
  insert into public.com_pedido_participantes_comerciais(pedido_id, pessoa_papel_id, created_by)
  select p_pedido_id, participant.id, v_actor
    from unnest(v_participantes) participant(id);

  insert into public.com_pedido_referencia_comercial_requisicoes(idempotency_key, pedido_id, actor_id, payload_hash)
  values (p_idempotency_key, p_pedido_id, v_actor, v_payload_hash);
  return p_pedido_id;
end;
$$;

revoke all on function public.resolver_com_referencias_comerciais_pedido_idempotente(uuid, bigint, bigint, bigint, text, bigint[], text)
  from public, anon;
grant execute on function public.resolver_com_referencias_comerciais_pedido_idempotente(uuid, bigint, bigint, bigint, text, bigint[], text)
  to authenticated;

comment on table public.com_pedido_participantes_comerciais is
  'Participantes comerciais relacionais do pedido, definidos junto ao congelamento da referencia comercial.';
comment on table public.com_pedido_item_referencias_comerciais is
  'Snapshot append-only da referencia comercial resolvida por item, sem reinterpretacao por cadastros ou listas futuras.';
comment on function public.resolver_com_referencias_comerciais_pedido_idempotente(uuid, bigint, bigint, bigint, text, bigint[], text) is
  'ORD-01 1D: define origem e participantes explicitos e congela por item a referencia devolvida exclusivamente pelo resolvedor 0127.';
comment on function public.prevent_fin_pedido_plan_change_after_commercial_snapshot() is
  'Trava transitória da ORD-01 1D: apos snapshot comercial, nova condicao financeira exige revisao governada futura.';
