create table if not exists public.est_lotes_pa (
  id bigint generated always as identity primary key,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  codigo_lote text not null,
  codigo_lote_norm text generated always as (lower(btrim(codigo_lote))) stored,
  status text not null default 'disponivel',
  data_fabricacao date,
  data_validade date,
  origem_ref text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint est_lotes_pa_status_check check (status in ('disponivel', 'bloqueado', 'esgotado', 'cancelado')),
  constraint est_lotes_pa_codigo_check check (length(btrim(codigo_lote)) > 0),
  constraint est_lotes_pa_datas_check check (
    data_fabricacao is null
    or data_validade is null
    or data_validade >= data_fabricacao
  ),
  constraint est_lotes_pa_key unique (produto_embalagem_id, codigo_lote_norm)
);

create table if not exists public.est_movimentos_pa (
  id bigint generated always as identity primary key,
  lote_pa_id bigint not null references public.est_lotes_pa(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  tipo_movimento text not null,
  quantidade numeric not null,
  origem_modulo text not null,
  origem_tabela text,
  origem_id text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_movimentos_pa_tipo_check check (
    tipo_movimento in (
      'importacao_inicial',
      'entrada_producao',
      'ajuste_entrada',
      'estorno_saida',
      'transformacao_entrada',
      'saida_romaneio',
      'ajuste_saida',
      'transformacao_saida'
    )
  ),
  constraint est_movimentos_pa_quantidade_check check (
    (
      tipo_movimento in (
        'importacao_inicial',
        'entrada_producao',
        'ajuste_entrada',
        'estorno_saida',
        'transformacao_entrada'
      )
      and quantidade > 0
    )
    or (
      tipo_movimento in (
        'saida_romaneio',
        'ajuste_saida',
        'transformacao_saida'
      )
      and quantidade < 0
    )
  )
);

create table if not exists public.est_reservas_pa (
  id bigint generated always as identity primary key,
  lote_pa_id bigint not null references public.est_lotes_pa(id),
  romaneio_id bigint not null references public.exp_romaneios(id),
  romaneio_item_id bigint not null references public.exp_romaneio_itens(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  quantidade_reservada numeric not null,
  status text not null default 'ativa',
  motivo_liberacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint est_reservas_pa_status_check check (status in ('ativa', 'baixada', 'liberada', 'estornada')),
  constraint est_reservas_pa_qtd_check check (quantidade_reservada > 0)
);

alter table public.exp_romaneio_itens
  add column if not exists lote_pa_id bigint references public.est_lotes_pa(id);

alter table public.exp_romaneio_movimentos_pa
  add column if not exists lote_pa_id bigint references public.est_lotes_pa(id);

create index if not exists idx_est_lotes_pa_produto_status
  on public.est_lotes_pa(produto_embalagem_id, status);

create index if not exists idx_est_movimentos_pa_lote
  on public.est_movimentos_pa(lote_pa_id, created_at desc);

create index if not exists idx_est_movimentos_pa_produto
  on public.est_movimentos_pa(produto_embalagem_id, created_at desc);

create index if not exists idx_est_movimentos_pa_origem
  on public.est_movimentos_pa(origem_modulo, origem_tabela, origem_id);

create index if not exists idx_est_reservas_pa_lote_status
  on public.est_reservas_pa(lote_pa_id, status);

create index if not exists idx_est_reservas_pa_romaneio
  on public.est_reservas_pa(romaneio_id, status);

create unique index if not exists ux_est_reservas_pa_item_ativa
  on public.est_reservas_pa(romaneio_item_id)
  where status = 'ativa';

create index if not exists idx_exp_romaneio_itens_lote_pa_id
  on public.exp_romaneio_itens(lote_pa_id)
  where lote_pa_id is not null;

create index if not exists idx_exp_romaneio_mov_pa_lote_pa_id
  on public.exp_romaneio_movimentos_pa(lote_pa_id)
  where lote_pa_id is not null;

drop trigger if exists trg_est_lotes_pa_updated_at on public.est_lotes_pa;
create trigger trg_est_lotes_pa_updated_at before update on public.est_lotes_pa
for each row execute function public.touch_updated_at();

drop trigger if exists trg_est_reservas_pa_updated_at on public.est_reservas_pa;
create trigger trg_est_reservas_pa_updated_at before update on public.est_reservas_pa
for each row execute function public.touch_updated_at();

create or replace function public.prevent_est_movimentos_pa_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'est_movimentos_pa is append-only';
end;
$$;

drop trigger if exists trg_est_movimentos_pa_no_update on public.est_movimentos_pa;
create trigger trg_est_movimentos_pa_no_update
before update or delete on public.est_movimentos_pa
for each row execute function public.prevent_est_movimentos_pa_changes();

alter table public.est_lotes_pa enable row level security;
alter table public.est_movimentos_pa enable row level security;
alter table public.est_reservas_pa enable row level security;

create policy "authenticated full PA lot access" on public.est_lotes_pa
for all to authenticated using (true) with check (true);

create policy "authenticated full PA movement access" on public.est_movimentos_pa
for all to authenticated using (true) with check (true);

create policy "authenticated full PA reservation access" on public.est_reservas_pa
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.pa.view', 'estoque', 'Ver lotes, reservas, movimentos e saldos de produto acabado', true, 230),
  ('estoque.pa.lots.create', 'estoque', 'Criar lote de produto acabado com entrada auditada', true, 231),
  ('estoque.pa.reserve', 'estoque', 'Reservar lote de produto acabado para romaneio', true, 232),
  ('estoque.pa.adjust', 'estoque', 'Registrar ajuste manual auditado de produto acabado', true, 233)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace view public.est_lotes_pa_saldos as
with movimentos as (
  select
    lote_pa_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -1 * quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_pa
  group by lote_pa_id
),
reservas as (
  select
    lote_pa_id,
    sum(quantidade_reservada) as quantidade_reservada
  from public.est_reservas_pa
  where status = 'ativa'
  group by lote_pa_id
)
select
  lote.id as lote_pa_id,
  lote.produto_embalagem_id,
  lote.codigo_lote,
  lote.status,
  lote.data_fabricacao,
  lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref,
  lote.observacao,
  lote.created_at,
  lote.updated_at
from public.est_lotes_pa lote
left join movimentos on movimentos.lote_pa_id = lote.id
left join reservas on reservas.lote_pa_id = lote.id;

grant select on public.est_lotes_pa_saldos to authenticated;

create or replace function public.sync_est_lote_pa_status(p_lote_pa_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_saldo_fisico numeric;
begin
  select status
    into v_status
    from public.est_lotes_pa
    where id = p_lote_pa_id
    for update;

  if not found then
    raise exception 'PA lot not found';
  end if;

  select saldo_fisico
    into v_saldo_fisico
    from public.est_lotes_pa_saldos
    where lote_pa_id = p_lote_pa_id;

  if v_status in ('disponivel', 'esgotado') then
    update public.est_lotes_pa
       set status = case when coalesce(v_saldo_fisico, 0) <= 0 then 'esgotado' else 'disponivel' end
     where id = p_lote_pa_id;
  end if;
end;
$$;

create or replace function public.create_est_lote_pa(
  p_produto_embalagem_id bigint,
  p_codigo_lote text,
  p_quantidade_entrada numeric,
  p_tipo_entrada text default 'importacao_inicial',
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_origem_ref text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote_id bigint;
  v_produto_embalagem_status text;
begin
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if nullif(trim(p_codigo_lote), '') is null then
    raise exception 'codigo_lote is required';
  end if;
  if p_quantidade_entrada is null or p_quantidade_entrada <= 0 then
    raise exception 'quantidade_entrada must be greater than zero';
  end if;
  if p_tipo_entrada not in ('importacao_inicial', 'entrada_producao', 'ajuste_entrada', 'transformacao_entrada') then
    raise exception 'invalid tipo_entrada';
  end if;
  if p_data_fabricacao is not null and p_data_validade is not null and p_data_validade < p_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;

  select status
    into v_produto_embalagem_status
    from public.cad_produto_embalagens
    where id = p_produto_embalagem_id;

  if v_produto_embalagem_status is null then
    raise exception 'produto_embalagem not found';
  end if;
  if v_produto_embalagem_status <> 'active' then
    raise exception 'produto_embalagem status does not allow PA lot creation';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.est_lotes_pa(
    produto_embalagem_id,
    codigo_lote,
    data_fabricacao,
    data_validade,
    origem_ref,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_produto_embalagem_id,
    trim(p_codigo_lote),
    p_data_fabricacao,
    p_data_validade,
    nullif(trim(p_origem_ref), ''),
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_lote_id;

  insert into public.est_movimentos_pa(
    lote_pa_id,
    produto_embalagem_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    v_lote_id,
    p_produto_embalagem_id,
    p_tipo_entrada,
    p_quantidade_entrada,
    'estoque_pa',
    'est_lotes_pa',
    v_lote_id::text,
    nullif(trim(p_observacao), ''),
    v_actor
  );

  perform public.sync_est_lote_pa_status(v_lote_id);

  perform public.log_action(
    'estoque.pa_lote_created',
    'est_lotes_pa',
    v_lote_id::text,
    'success',
    null,
    jsonb_build_object(
      'produto_embalagem_id', p_produto_embalagem_id,
      'codigo_lote', trim(p_codigo_lote),
      'quantidade_entrada', p_quantidade_entrada,
      'tipo_entrada', p_tipo_entrada,
      'origem_ref', nullif(trim(p_origem_ref), '')
    ),
    jsonb_build_object('source', 'create_est_lote_pa')
  );

  return v_lote_id;
end;
$$;

create or replace function public.registrar_est_reserva_pa(
  p_romaneio_item_id bigint,
  p_lote_pa_id bigint,
  p_quantidade_reservada numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_romaneio_item record;
  v_lote record;
  v_reserva_existente record;
  v_quantidade_reservada numeric;
  v_saldo_disponivel numeric;
  v_reserva_id bigint;
  v_tem_reserva_existente boolean := false;
begin
  if p_romaneio_item_id is null or p_romaneio_item_id <= 0 then
    raise exception 'romaneio_item_id is required';
  end if;
  if p_lote_pa_id is null or p_lote_pa_id <= 0 then
    raise exception 'lote_pa_id is required';
  end if;

  select
      rom_item.id,
      rom_item.romaneio_id,
      rom_item.pedido_id,
      rom_item.pedido_item_id,
      rom_item.produto_embalagem_id,
      rom_item.quantidade_romaneada,
      rom_item.status as item_status,
      rom.status as romaneio_status,
      pedido.status as pedido_status
    into v_romaneio_item
    from public.exp_romaneio_itens rom_item
    join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
    join public.com_pedidos pedido on pedido.id = rom_item.pedido_id
    where rom_item.id = p_romaneio_item_id
    for update of rom_item, rom;

  if not found then
    raise exception 'romaneio item not found';
  end if;
  if v_romaneio_item.pedido_status <> 'open' then
    raise exception 'pedido status does not allow PA reservation';
  end if;
  if v_romaneio_item.romaneio_status not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow PA reservation';
  end if;
  if v_romaneio_item.item_status not in ('draft', 'reservado') then
    raise exception 'romaneio item status does not allow PA reservation';
  end if;

  v_quantidade_reservada := coalesce(p_quantidade_reservada, v_romaneio_item.quantidade_romaneada);
  if v_quantidade_reservada <= 0 then
    raise exception 'quantidade_reservada must be greater than zero';
  end if;
  if v_quantidade_reservada <> v_romaneio_item.quantidade_romaneada then
    raise exception 'reserved quantity must match romaneio item quantity';
  end if;

  select *
    into v_lote
    from public.est_lotes_pa
    where id = p_lote_pa_id
    for update;

  if not found then
    raise exception 'PA lot not found';
  end if;
  if v_lote.status <> 'disponivel' then
    raise exception 'PA lot status does not allow reservation';
  end if;
  if v_lote.produto_embalagem_id <> v_romaneio_item.produto_embalagem_id then
    raise exception 'PA lot product does not match romaneio item';
  end if;

  select *
    into v_reserva_existente
    from public.est_reservas_pa
    where romaneio_item_id = p_romaneio_item_id
      and status = 'ativa'
    for update;
  v_tem_reserva_existente := found;

  select saldo_disponivel
    into v_saldo_disponivel
    from public.est_lotes_pa_saldos
    where lote_pa_id = p_lote_pa_id;

  v_saldo_disponivel := coalesce(v_saldo_disponivel, 0);
  if v_tem_reserva_existente and v_reserva_existente.lote_pa_id = p_lote_pa_id then
    v_saldo_disponivel := v_saldo_disponivel + v_reserva_existente.quantidade_reservada;
  end if;

  if v_saldo_disponivel < v_quantidade_reservada then
    raise exception 'insufficient PA available balance for reservation';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  if v_tem_reserva_existente then
    update public.est_reservas_pa
       set status = 'liberada',
           motivo_liberacao = coalesce(nullif(trim(p_observacao), ''), 'substituida por nova reserva'),
           updated_by = v_actor
     where id = v_reserva_existente.id;
  end if;

  insert into public.est_reservas_pa(
    lote_pa_id,
    romaneio_id,
    romaneio_item_id,
    produto_embalagem_id,
    quantidade_reservada,
    status,
    created_by,
    updated_by
  )
  values (
    p_lote_pa_id,
    v_romaneio_item.romaneio_id,
    p_romaneio_item_id,
    v_romaneio_item.produto_embalagem_id,
    v_quantidade_reservada,
    'ativa',
    v_actor,
    v_actor
  )
  returning id into v_reserva_id;

  update public.exp_romaneio_itens
     set lote_pa_id = p_lote_pa_id,
         lote_pa_ref = v_lote.codigo_lote,
         quantidade_reservada = v_quantidade_reservada,
         status = 'reservado',
         updated_by = v_actor
   where id = p_romaneio_item_id;

  update public.exp_romaneios
     set status = 'separacao',
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = v_romaneio_item.romaneio_id
     and status = 'draft';

  perform public.log_action(
    'estoque.pa_reserva_registrada',
    'est_reservas_pa',
    v_reserva_id::text,
    'success',
    case when not v_tem_reserva_existente then null else jsonb_build_object(
      'reserva_anterior_id', v_reserva_existente.id,
      'lote_pa_id', v_reserva_existente.lote_pa_id,
      'quantidade_reservada', v_reserva_existente.quantidade_reservada,
      'status', v_reserva_existente.status
    ) end,
    jsonb_build_object(
      'romaneio_id', v_romaneio_item.romaneio_id,
      'romaneio_item_id', p_romaneio_item_id,
      'lote_pa_id', p_lote_pa_id,
      'codigo_lote', v_lote.codigo_lote,
      'quantidade_reservada', v_quantidade_reservada
    ),
    jsonb_build_object('source', 'registrar_est_reserva_pa')
  );

  return v_reserva_id;
end;
$$;

create or replace function public.registrar_est_ajuste_pa(
  p_lote_pa_id bigint,
  p_quantidade numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote record;
  v_saldo_disponivel numeric;
  v_movimento_id bigint;
  v_tipo_movimento text;
begin
  if p_lote_pa_id is null or p_lote_pa_id <= 0 then
    raise exception 'lote_pa_id is required';
  end if;
  if p_quantidade is null or p_quantidade = 0 then
    raise exception 'quantidade must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_lote
    from public.est_lotes_pa
    where id = p_lote_pa_id
    for update;

  if not found then
    raise exception 'PA lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled PA lot does not allow adjustment';
  end if;

  select saldo_disponivel
    into v_saldo_disponivel
    from public.est_lotes_pa_saldos
    where lote_pa_id = p_lote_pa_id;

  if p_quantidade < 0 and coalesce(v_saldo_disponivel, 0) < abs(p_quantidade) then
    raise exception 'adjustment exceeds available PA balance';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  v_tipo_movimento := case when p_quantidade > 0 then 'ajuste_entrada' else 'ajuste_saida' end;

  insert into public.est_movimentos_pa(
    lote_pa_id,
    produto_embalagem_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    p_lote_pa_id,
    v_lote.produto_embalagem_id,
    v_tipo_movimento,
    p_quantidade,
    'estoque_pa',
    'est_lotes_pa',
    p_lote_pa_id::text,
    trim(p_motivo),
    v_actor
  )
  returning id into v_movimento_id;

  perform public.sync_est_lote_pa_status(p_lote_pa_id);

  perform public.log_action(
    'estoque.pa_ajuste_registrado',
    'est_movimentos_pa',
    v_movimento_id::text,
    'success',
    null,
    jsonb_build_object(
      'lote_pa_id', p_lote_pa_id,
      'produto_embalagem_id', v_lote.produto_embalagem_id,
      'tipo_movimento', v_tipo_movimento,
      'quantidade', p_quantidade,
      'motivo', trim(p_motivo)
    ),
    jsonb_build_object('source', 'registrar_est_ajuste_pa')
  );

  return v_movimento_id;
end;
$$;

create or replace function public.confirmar_exp_romaneio(
  p_romaneio_id bigint,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_pedido_id bigint;
  v_status_anterior text;
  v_pedido_status text;
  v_item record;
  v_reserva record;
  v_saldo_fisico numeric;
  v_quantidade_confirmada_outros numeric;
begin
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;

  select pedido_id, status
    into v_pedido_id, v_status_anterior
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if v_pedido_id is null then
    raise exception 'romaneio not found';
  end if;
  if v_status_anterior not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow confirmation';
  end if;

  select status
    into v_pedido_status
    from public.com_pedidos
    where id = v_pedido_id
    for update;

  if v_pedido_status <> 'open' then
    raise exception 'pedido status does not allow romaneio confirmation';
  end if;

  if not exists (
    select 1 from public.exp_romaneio_itens
    where romaneio_id = p_romaneio_id
      and status in ('draft', 'reservado')
  ) then
    raise exception 'romaneio has no active items';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  for v_item in
    select
      rom_item.id,
      rom_item.pedido_id,
      rom_item.pedido_item_id,
      rom_item.produto_embalagem_id,
      rom_item.quantidade_romaneada,
      pedido_item.quantidade as quantidade_pedido,
      pedido_item.status as pedido_item_status
    from public.exp_romaneio_itens rom_item
    join public.com_pedido_itens pedido_item on pedido_item.id = rom_item.pedido_item_id
    where rom_item.romaneio_id = p_romaneio_id
      and rom_item.status in ('draft', 'reservado')
    for update of rom_item
  loop
    if v_item.pedido_item_status <> 'active' then
      raise exception 'pedido item status does not allow romaneio confirmation';
    end if;

    select
        reserva.id,
        reserva.lote_pa_id,
        reserva.quantidade_reservada,
        lote.codigo_lote,
        lote.produto_embalagem_id,
        lote.status as lote_status
      into v_reserva
      from public.est_reservas_pa reserva
      join public.est_lotes_pa lote on lote.id = reserva.lote_pa_id
      where reserva.romaneio_item_id = v_item.id
        and reserva.status = 'ativa'
      for update of reserva, lote;

    if not found then
      raise exception 'active PA reservation is required before confirmation';
    end if;
    if v_reserva.quantidade_reservada <> v_item.quantidade_romaneada then
      raise exception 'active PA reservation quantity does not match romaneio item';
    end if;
    if v_reserva.produto_embalagem_id <> v_item.produto_embalagem_id then
      raise exception 'PA reservation product does not match romaneio item';
    end if;
    if v_reserva.lote_status not in ('disponivel', 'esgotado') then
      raise exception 'PA lot status does not allow confirmation';
    end if;

    select saldo_fisico
      into v_saldo_fisico
      from public.est_lotes_pa_saldos
      where lote_pa_id = v_reserva.lote_pa_id;

    if coalesce(v_saldo_fisico, 0) < v_reserva.quantidade_reservada then
      raise exception 'PA physical balance is lower than reservation';
    end if;

    select coalesce(sum(outro_item.quantidade_romaneada), 0)
      into v_quantidade_confirmada_outros
      from public.exp_romaneio_itens outro_item
      join public.exp_romaneios outro_rom on outro_rom.id = outro_item.romaneio_id
      where outro_item.pedido_item_id = v_item.pedido_item_id
        and outro_rom.id <> p_romaneio_id
        and outro_rom.status = 'confirmado'
        and outro_item.status = 'confirmado';

    if v_quantidade_confirmada_outros + v_item.quantidade_romaneada > v_item.quantidade_pedido then
      raise exception 'romaneio confirmation exceeds pending order quantity';
    end if;

    insert into public.exp_romaneio_movimentos_pa(
      romaneio_id,
      romaneio_item_id,
      pedido_id,
      pedido_item_id,
      produto_embalagem_id,
      lote_pa_ref,
      lote_pa_id,
      tipo_movimento,
      quantidade,
      observacao,
      created_by
    )
    values (
      p_romaneio_id,
      v_item.id,
      v_item.pedido_id,
      v_item.pedido_item_id,
      v_item.produto_embalagem_id,
      v_reserva.codigo_lote,
      v_reserva.lote_pa_id,
      'baixa',
      v_item.quantidade_romaneada,
      nullif(trim(p_observacao), ''),
      v_actor
    );

    insert into public.est_movimentos_pa(
      lote_pa_id,
      produto_embalagem_id,
      tipo_movimento,
      quantidade,
      origem_modulo,
      origem_tabela,
      origem_id,
      observacao,
      created_by
    )
    values (
      v_reserva.lote_pa_id,
      v_item.produto_embalagem_id,
      'saida_romaneio',
      -1 * v_item.quantidade_romaneada,
      'romaneio',
      'exp_romaneios',
      p_romaneio_id::text,
      nullif(trim(p_observacao), ''),
      v_actor
    );

    update public.est_reservas_pa
       set status = 'baixada',
           updated_by = v_actor
     where id = v_reserva.id;

    perform public.sync_est_lote_pa_status(v_reserva.lote_pa_id);
  end loop;

  update public.exp_romaneio_itens
     set status = 'confirmado',
         quantidade_reservada = 0,
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status in ('draft', 'reservado');

  update public.exp_romaneios
     set status = 'confirmado',
         confirmado_at = now(),
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_romaneio_id;

  if not exists (
    select 1
      from public.com_pedido_itens pedido_item
      left join (
        select rom_item.pedido_item_id, sum(rom_item.quantidade_romaneada) as quantidade_confirmada
          from public.exp_romaneio_itens rom_item
          join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
          where rom.pedido_id = v_pedido_id
            and rom.status = 'confirmado'
            and rom_item.status = 'confirmado'
          group by rom_item.pedido_item_id
      ) confirmado on confirmado.pedido_item_id = pedido_item.id
      where pedido_item.pedido_id = v_pedido_id
        and pedido_item.status = 'active'
        and coalesce(confirmado.quantidade_confirmada, 0) < pedido_item.quantidade
  ) then
    update public.com_pedidos
       set status = 'fulfilled',
           updated_by = v_actor
     where id = v_pedido_id
       and status = 'open';
  end if;

  perform public.log_action(
    'expedicao.romaneio_confirmado',
    'exp_romaneios',
    p_romaneio_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', 'confirmado',
      'pedido_id', v_pedido_id,
      'observacao', nullif(trim(p_observacao), ''),
      'estoque_pa_integrado', true
    ),
    jsonb_build_object('source', 'confirmar_exp_romaneio')
  );

  return p_romaneio_id;
end;
$$;

create or replace function public.cancelar_exp_romaneio(
  p_romaneio_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_pedido_id bigint;
  v_status_anterior text;
begin
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select pedido_id, status
    into v_pedido_id, v_status_anterior
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if v_pedido_id is null then
    raise exception 'romaneio not found';
  end if;
  if v_status_anterior not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow cancellation';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  update public.est_reservas_pa
     set status = 'liberada',
         motivo_liberacao = trim(p_motivo),
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status = 'ativa';

  update public.exp_romaneio_itens
     set status = 'cancelado',
         quantidade_reservada = 0,
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status in ('draft', 'reservado');

  update public.exp_romaneios
     set status = 'cancelado',
         updated_by = v_actor,
         observacao = concat_ws(' | ', observacao, concat('cancelado: ', trim(p_motivo)))
   where id = p_romaneio_id;

  perform public.log_action(
    'expedicao.romaneio_cancelado',
    'exp_romaneios',
    p_romaneio_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', 'cancelado',
      'pedido_id', v_pedido_id,
      'motivo', trim(p_motivo),
      'estoque_pa_reserva_liberada', true
    ),
    jsonb_build_object('source', 'cancelar_exp_romaneio')
  );

  return p_romaneio_id;
end;
$$;

create or replace function public.estornar_exp_romaneio(
  p_romaneio_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_status_anterior text;
  v_pedido_id bigint;
  v_movimento record;
begin
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select pedido_id, status
    into v_pedido_id, v_status_anterior
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if v_pedido_id is null then
    raise exception 'romaneio not found';
  end if;
  if v_status_anterior <> 'confirmado' then
    raise exception 'romaneio status does not allow reversal';
  end if;
  if not exists (
    select 1
      from public.exp_romaneio_movimentos_pa
      where romaneio_id = p_romaneio_id
        and tipo_movimento = 'baixa'
  ) then
    raise exception 'romaneio has no PA movement to reverse';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  for v_movimento in
    select *
      from public.exp_romaneio_movimentos_pa
      where romaneio_id = p_romaneio_id
        and tipo_movimento = 'baixa'
    for update
  loop
    if v_movimento.lote_pa_id is not null then
      perform 1
        from public.est_lotes_pa
        where id = v_movimento.lote_pa_id
        for update;
    end if;

    insert into public.exp_romaneio_movimentos_pa(
      romaneio_id,
      romaneio_item_id,
      pedido_id,
      pedido_item_id,
      produto_embalagem_id,
      lote_pa_ref,
      lote_pa_id,
      tipo_movimento,
      quantidade,
      observacao,
      created_by
    )
    values (
      p_romaneio_id,
      v_movimento.romaneio_item_id,
      v_movimento.pedido_id,
      v_movimento.pedido_item_id,
      v_movimento.produto_embalagem_id,
      v_movimento.lote_pa_ref,
      v_movimento.lote_pa_id,
      'estorno',
      -1 * v_movimento.quantidade,
      trim(p_motivo),
      v_actor
    );

    if v_movimento.lote_pa_id is not null then
      insert into public.est_movimentos_pa(
        lote_pa_id,
        produto_embalagem_id,
        tipo_movimento,
        quantidade,
        origem_modulo,
        origem_tabela,
        origem_id,
        observacao,
        created_by
      )
      values (
        v_movimento.lote_pa_id,
        v_movimento.produto_embalagem_id,
        'estorno_saida',
        v_movimento.quantidade,
        'romaneio',
        'exp_romaneios',
        p_romaneio_id::text,
        trim(p_motivo),
        v_actor
      );

      perform public.sync_est_lote_pa_status(v_movimento.lote_pa_id);
    end if;
  end loop;

  update public.est_reservas_pa
     set status = 'estornada',
         motivo_liberacao = trim(p_motivo),
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status = 'baixada';

  update public.exp_romaneio_itens
     set status = 'estornado',
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status = 'confirmado';

  update public.exp_romaneios
     set status = 'estornado',
         estornado_at = now(),
         updated_by = v_actor,
         observacao = concat_ws(' | ', observacao, concat('estorno: ', trim(p_motivo)))
   where id = p_romaneio_id;

  update public.com_pedidos
     set status = 'open',
         updated_by = v_actor
   where id = v_pedido_id
     and status = 'fulfilled';

  perform public.log_action(
    'expedicao.romaneio_estornado',
    'exp_romaneios',
    p_romaneio_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', 'estornado',
      'pedido_id', v_pedido_id,
      'motivo', trim(p_motivo),
      'estoque_pa_revertido', true
    ),
    jsonb_build_object('source', 'estornar_exp_romaneio')
  );

  return p_romaneio_id;
end;
$$;

revoke all on function public.sync_est_lote_pa_status(bigint) from public;

revoke all on function public.create_est_lote_pa(bigint, text, numeric, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pa(bigint, text, numeric, text, date, date, text, text) to authenticated;

revoke all on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text) from public;
grant execute on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text) to authenticated;

revoke all on function public.registrar_est_ajuste_pa(bigint, numeric, text) from public;
grant execute on function public.registrar_est_ajuste_pa(bigint, numeric, text) to authenticated;

revoke all on function public.confirmar_exp_romaneio(bigint, text) from public;
grant execute on function public.confirmar_exp_romaneio(bigint, text) to authenticated;

revoke all on function public.cancelar_exp_romaneio(bigint, text) from public;
grant execute on function public.cancelar_exp_romaneio(bigint, text) to authenticated;

revoke all on function public.estornar_exp_romaneio(bigint, text) from public;
grant execute on function public.estornar_exp_romaneio(bigint, text) to authenticated;
