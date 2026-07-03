create table if not exists public.com_pedidos (
  id bigint generated always as identity primary key,
  codigo_pedido text not null unique,
  cliente_id bigint not null references public.cad_clientes(id),
  tipo_pedido text not null,
  status text not null default 'draft',
  data_pedido date not null default current_date,
  previsao_entrega date,
  condicao_pagamento text,
  origem_canal text not null default 'interno',
  valor_total numeric not null default 0,
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_pedidos_tipo_check check (tipo_pedido in ('venda', 'bonificacao', 'devolucao')),
  constraint com_pedidos_status_check check (status in ('draft', 'open', 'blocked', 'cancelled', 'fulfilled')),
  constraint com_pedidos_origem_check check (origem_canal in ('interno', 'vendedor', 'importacao'))
);

create table if not exists public.com_pedido_itens (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  tipo_item text not null,
  quantidade numeric not null,
  valor_unitario numeric not null default 0,
  percentual_desconto numeric not null default 0,
  valor_total numeric not null default 0,
  status text not null default 'active',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_pedido_itens_tipo_check check (tipo_item in ('venda', 'bonificacao', 'devolucao')),
  constraint com_pedido_itens_status_check check (status in ('active', 'cancelled')),
  constraint com_pedido_itens_qtd_check check (quantidade > 0),
  constraint com_pedido_itens_valor_unitario_check check (valor_unitario >= 0),
  constraint com_pedido_itens_desconto_check check (percentual_desconto >= 0 and percentual_desconto <= 100)
);

create table if not exists public.com_pedido_comissionados (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  pedido_item_id bigint references public.com_pedido_itens(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  papel_comissao text not null,
  percentual_comissao numeric not null default 0,
  valor_base numeric not null default 0,
  valor_previsto numeric not null default 0,
  status text not null default 'prevista',
  campanha_ref text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_pedido_comissionados_papel_check check (
    papel_comissao in ('vendedor', 'gerente', 'tecnico_campo', 'campanha', 'outro')
  ),
  constraint com_pedido_comissionados_status_check check (
    status in ('prevista', 'liberada', 'paga', 'estornada', 'bloqueada')
  ),
  constraint com_pedido_comissionados_percentual_check check (percentual_comissao >= 0)
);

create index if not exists idx_com_pedidos_cliente_status on public.com_pedidos(cliente_id, status);
create index if not exists idx_com_pedidos_data on public.com_pedidos(data_pedido desc, id desc);
create index if not exists idx_com_pedido_itens_pedido on public.com_pedido_itens(pedido_id);
create index if not exists idx_com_pedido_comissionados_pedido on public.com_pedido_comissionados(pedido_id);
create index if not exists idx_com_pedido_comissionados_pessoa on public.com_pedido_comissionados(pessoa_id, status);

drop trigger if exists trg_com_pedidos_updated_at on public.com_pedidos;
create trigger trg_com_pedidos_updated_at before update on public.com_pedidos
for each row execute function public.touch_updated_at();

drop trigger if exists trg_com_pedido_itens_updated_at on public.com_pedido_itens;
create trigger trg_com_pedido_itens_updated_at before update on public.com_pedido_itens
for each row execute function public.touch_updated_at();

drop trigger if exists trg_com_pedido_comissionados_updated_at on public.com_pedido_comissionados;
create trigger trg_com_pedido_comissionados_updated_at before update on public.com_pedido_comissionados
for each row execute function public.touch_updated_at();

alter table public.com_pedidos enable row level security;
alter table public.com_pedido_itens enable row level security;
alter table public.com_pedido_comissionados enable row level security;

create policy "authenticated full order access" on public.com_pedidos
for all to authenticated using (true) with check (true);
create policy "authenticated full order item access" on public.com_pedido_itens
for all to authenticated using (true) with check (true);
create policy "authenticated full order commission access" on public.com_pedido_comissionados
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.view', 'pedidos', 'Ver pedidos, itens e comissoes previstas', true, 100),
  ('pedidos.create', 'pedidos', 'Criar pedido em rascunho ou aberto', true, 101),
  ('pedidos.manage', 'pedidos', 'Editar status, bloqueios e cancelamentos de pedidos', true, 102)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

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
declare
  v_actor uuid;
  v_codigo_pedido text;
  v_pedido_id bigint;
  v_item_id bigint;
  v_item_valor_total numeric;
  v_valor_base_comissao numeric;
  v_valor_previsto_comissao numeric;
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

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  if p_tipo_pedido = 'bonificacao' then
    v_item_valor_total := 0;
  elsif p_tipo_pedido = 'devolucao' then
    v_item_valor_total := -1 * p_quantidade * p_valor_unitario;
  else
    v_item_valor_total := p_quantidade * p_valor_unitario;
  end if;

  v_codigo_pedido := concat(
    'PED-',
    to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'),
    '-',
    upper(substr(md5(random()::text), 1, 4))
  );

  insert into public.com_pedidos(
    codigo_pedido,
    cliente_id,
    tipo_pedido,
    status,
    data_pedido,
    valor_total,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_pedido,
    p_cliente_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
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

  perform public.log_action(
    'comercial.pedido_rascunho_created',
    'com_pedidos',
    v_pedido_id::text,
    'success',
    null,
    jsonb_build_object(
      'codigo_pedido', v_codigo_pedido,
      'cliente_id', p_cliente_id,
      'produto_embalagem_id', p_produto_embalagem_id,
      'tipo_pedido', p_tipo_pedido,
      'status', p_status,
      'quantidade', p_quantidade,
      'valor_unitario', p_valor_unitario,
      'valor_total', v_item_valor_total,
      'vendedor_id', p_vendedor_id,
      'percentual_comissao', p_percentual_comissao
    ),
    jsonb_build_object('source', 'create_com_pedido_rascunho')
  );

  return v_pedido_id;
end;
$$;

revoke all on function public.create_com_pedido_rascunho(bigint, bigint, numeric, numeric, text, text, date, bigint, numeric, text) from public;
grant execute on function public.create_com_pedido_rascunho(bigint, bigint, numeric, numeric, text, text, date, bigint, numeric, text) to authenticated;
