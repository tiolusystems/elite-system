-- ORD-01 F2C: independent, version-bound discount review.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pedidos.commercial_discount.review', 'pedidos',
  'Revisar desconto comercial do pedido', false, 139, 'pedidos', 'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_pedido_decisoes_desconto (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  confirmacao_comercial_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  comparacao_sha256 text not null check (comparacao_sha256 ~ '^[0-9a-f]{64}$'),
  decisao text not null check (decisao in ('APPROVED', 'REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  decided_by uuid not null references public.user_profiles(id) on delete restrict,
  decided_at timestamptz not null default clock_timestamp(),
  constraint com_pedido_decisoes_desconto_version_key unique (confirmacao_comercial_id),
  constraint com_pedido_decisoes_desconto_pedido_version_key unique (pedido_id, confirmacao_comercial_id)
);

create index idx_com_pedido_decisoes_desconto_pedido
  on public.com_pedido_decisoes_desconto(pedido_id, decided_at desc);

create table public.com_pedido_decisao_desconto_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  confirmacao_comercial_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  decisao_id bigint not null unique references public.com_pedido_decisoes_desconto(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

create or replace function public.prevent_order_discount_review_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'decisao de desconto e somente leitura depois de registrada';
end;
$$;
revoke all on function public.prevent_order_discount_review_changes() from public, anon, authenticated;

create trigger trg_com_pedido_decisoes_desconto_append_only
before update or delete on public.com_pedido_decisoes_desconto
for each row execute function public.prevent_order_discount_review_changes();
create trigger trg_com_pedido_decisoes_desconto_no_truncate
before truncate on public.com_pedido_decisoes_desconto
for each statement execute function public.prevent_order_discount_review_changes();
create trigger trg_com_pedido_decisao_desconto_requisicoes_append_only
before update or delete on public.com_pedido_decisao_desconto_requisicoes
for each row execute function public.prevent_order_discount_review_changes();
create trigger trg_com_pedido_decisao_desconto_requisicoes_no_truncate
before truncate on public.com_pedido_decisao_desconto_requisicoes
for each statement execute function public.prevent_order_discount_review_changes();

alter table public.com_pedido_decisoes_desconto enable row level security;
alter table public.com_pedido_decisao_desconto_requisicoes enable row level security;
revoke all on table public.com_pedido_decisoes_desconto from public, anon, authenticated;
revoke all on table public.com_pedido_decisao_desconto_requisicoes from public, anon, authenticated;

create or replace function public.validate_com_pedido_decisao_desconto()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_confirmacao public.com_pedido_confirmacoes_comerciais%rowtype;
  v_comparacao jsonb;
  v_hash text;
begin
  select * into v_pedido from public.com_pedidos where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'revisao de desconto exige pedido de venda bloqueado';
  end if;
  select * into v_confirmacao
    from public.com_pedido_confirmacoes_comerciais
   where id = new.confirmacao_comercial_id and pedido_id = new.pedido_id;
  if not found then raise exception 'versao comercial F2B nao pertence ao pedido'; end if;
  if v_confirmacao.id <> (select id from public.com_pedido_confirmacoes_comerciais where pedido_id = new.pedido_id order by numero_versao desc limit 1) then
    raise exception 'decisao de desconto exige a versao comercial vigente';
  end if;
  v_comparacao := public.com_pedido_comparacao_comercial_documento(new.pedido_id);
  v_hash := encode(extensions.digest(convert_to(v_comparacao::text, 'UTF8'), 'sha256'), 'hex');
  if new.comparacao_sha256 is distinct from v_hash or new.comparacao_sha256 is distinct from v_confirmacao.comparacao_sha256 then
    raise exception 'fingerprint da comparacao comercial divergente';
  end if;
  if not exists (
    select 1 from public.com_pedido_item_precos_praticados fact
     where fact.pedido_id = new.pedido_id and fact.classificacao = 'BELOW_REFERENCE'
  ) then
    raise exception 'o pedido nao possui desconto comercial pendente';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_com_pedido_decisao_desconto() from public, anon, authenticated;
create trigger trg_com_pedido_decisoes_desconto_validate
before insert on public.com_pedido_decisoes_desconto
for each row execute function public.validate_com_pedido_decisao_desconto();

create or replace function public.validate_com_pedido_credito_desconto_gate()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_confirmacao_id bigint;
begin
  if new.decisao <> 'liberado' then return new; end if;
  select * into v_pedido from public.com_pedidos where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' then return new; end if;
  select confirmation.id into v_confirmacao_id
    from public.com_pedido_confirmacoes_comerciais confirmation
   where confirmation.pedido_id = new.pedido_id
   order by confirmation.numero_versao desc limit 1;
  if exists (
    select 1 from public.com_pedido_item_precos_praticados fact
     where fact.pedido_id = new.pedido_id and fact.classificacao = 'BELOW_REFERENCE'
  ) and not exists (
    select 1 from public.com_pedido_decisoes_desconto decision
     where decision.pedido_id = new.pedido_id
       and decision.confirmacao_comercial_id = v_confirmacao_id
       and decision.decisao = 'APPROVED'
  ) then
    raise exception 'desconto comercial exige aprovacao independente antes da decisao de credito';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_com_pedido_credito_desconto_gate() from public, anon, authenticated;
create trigger trg_com_pedido_credito_decisoes_discount_gate
before insert on public.com_pedido_credito_decisoes
for each row execute function public.validate_com_pedido_credito_desconto_gate();

create or replace function public.registrar_com_pedido_decisao_desconto_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_confirmacao_comercial_id bigint,
  p_comparacao_sha256 text,
  p_decisao text,
  p_justificativa text
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_decisao_desconto_requisicoes%rowtype;
  v_decisao_id bigint;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.commercial_discount.review');
  if p_idempotency_key is null then raise exception 'idempotency_key e obrigatoria'; end if;
  if p_decisao not in ('APPROVED', 'REJECTED') then raise exception 'decisao de desconto invalida'; end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 10 then raise exception 'justificativa deve possuir ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'pedido_id', p_pedido_id, 'confirmacao_comercial_id', p_confirmacao_comercial_id,
    'comparacao_sha256', p_comparacao_sha256, 'decisao', p_decisao,
    'justificativa', btrim(p_justificativa)
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_decisao_desconto_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com payload divergente';
    end if;
    return v_existing.decisao_id;
  end if;
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  v_context := public.begin_audited_rpc(
    'pedidos.commercial_discount.review', 'pedidos', 'com_pedido_decisoes_desconto',
    'change_type', jsonb_build_object('pedido_id', p_pedido_id, 'decision', p_decisao)
  );
  insert into public.com_pedido_decisoes_desconto(
    pedido_id, confirmacao_comercial_id, comparacao_sha256, decisao, justificativa, decided_by
  ) values (
    p_pedido_id, p_confirmacao_comercial_id, lower(p_comparacao_sha256), p_decisao, btrim(p_justificativa), v_actor
  ) returning id into v_decisao_id;
  insert into public.com_pedido_decisao_desconto_requisicoes(
    idempotency_key, pedido_id, confirmacao_comercial_id, decisao_id, actor_id, payload_hash
  ) values (p_idempotency_key, p_pedido_id, p_confirmacao_comercial_id, v_decisao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_decisoes_desconto', v_decisao_id::text,
    case when p_decisao = 'APPROVED' then 'pedidos.desconto_aprovado' else 'pedidos.desconto_rejeitado' end,
    'pedidos.commercial_discount.review', v_context, null,
    jsonb_build_object('pedido_id', p_pedido_id, 'confirmacao_comercial_id', p_confirmacao_comercial_id, 'decisao', p_decisao),
    jsonb_build_object('pedido_permanece_bloqueado', true), 'database_rpc'
  );
  return v_decisao_id;
end;
$$;
revoke all on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text) from public, anon;
grant execute on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text) to authenticated;

create or replace function public.consultar_com_pedidos_revisao_desconto()
returns table(
  pedido_id bigint, codigo_pedido text, cliente_id bigint, cliente_nome text,
  vendedor_id bigint, vendedor_nome text, valor_total numeric,
  confirmacao_comercial_id bigint, comparacao_sha256 text,
  justificativa_comercial text, comparacao jsonb, decisao text
)
language sql stable security definer set search_path = public as $$
  select orders.id, orders.codigo_pedido, client.id, client.nome,
         seller.id, seller.nome, orders.valor_total,
         confirmation.id, confirmation.comparacao_sha256,
         confirmation.justificativa_comercial,
         public.com_pedido_comparacao_comercial_documento(orders.id),
         decision.decisao
    from public.com_pedidos orders
    join public.cad_clientes client on client.id = orders.cliente_id
    join public.cad_pessoas_comerciais seller on seller.id = orders.vendedor_gerador_id
    join lateral (
      select current_confirmation.* from public.com_pedido_confirmacoes_comerciais current_confirmation
       where current_confirmation.pedido_id = orders.id
       order by current_confirmation.numero_versao desc limit 1
    ) confirmation on true
    left join public.com_pedido_decisoes_desconto decision on decision.confirmacao_comercial_id = confirmation.id
   where public.can_current_user('pedidos.commercial_discount.review')
     and orders.tipo_pedido = 'venda' and orders.status = 'blocked'
     and public.current_user_manages_seller(orders.vendedor_gerador_id)
     and exists (select 1 from public.com_pedido_item_precos_praticados fact where fact.pedido_id = orders.id and fact.classificacao = 'BELOW_REFERENCE')
    and decision.id is null
   order by orders.created_at;
$$;
revoke all on function public.consultar_com_pedidos_revisao_desconto() from public, anon;
grant execute on function public.consultar_com_pedidos_revisao_desconto() to authenticated;

comment on table public.com_pedido_decisoes_desconto is
  'ORD-01 F2C: decisao append-only independente, vinculada a uma versao exata da confirmacao F2B.';
comment on function public.registrar_com_pedido_decisao_desconto_idempotente(uuid,bigint,bigint,text,text,text) is
  'ORD-01 F2C: registra aprovacao/rejeicao de desconto sem abrir pedido, alterar credito, preco ou comissao.';
