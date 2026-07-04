create table if not exists public.exp_romaneios (
  id bigint generated always as identity primary key,
  codigo_romaneio text not null unique,
  pedido_id bigint not null references public.com_pedidos(id),
  tipo_separacao text not null default 'parcial',
  status text not null default 'draft',
  data_romaneio date not null default current_date,
  observacao text,
  confirmado_at timestamptz,
  cancelado_at timestamptz,
  estornado_at timestamptz,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exp_romaneios_tipo_check check (tipo_separacao in ('total', 'parcial')),
  constraint exp_romaneios_status_check check (status in ('draft', 'separacao', 'confirmado', 'cancelado', 'estornado'))
);

create table if not exists public.exp_romaneio_itens (
  id bigint generated always as identity primary key,
  romaneio_id bigint not null references public.exp_romaneios(id),
  pedido_id bigint not null references public.com_pedidos(id),
  pedido_item_id bigint not null references public.com_pedido_itens(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  lote_pa_ref text,
  quantidade_romaneada numeric not null,
  quantidade_reservada numeric not null default 0,
  status text not null default 'draft',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exp_romaneio_itens_status_check check (status in ('draft', 'reservado', 'confirmado', 'cancelado', 'estornado')),
  constraint exp_romaneio_itens_qtd_check check (quantidade_romaneada > 0),
  constraint exp_romaneio_itens_reserva_check check (quantidade_reservada >= 0 and quantidade_reservada <= quantidade_romaneada)
);

create table if not exists public.exp_romaneio_movimentos_pa (
  id bigint generated always as identity primary key,
  romaneio_id bigint not null references public.exp_romaneios(id),
  romaneio_item_id bigint not null references public.exp_romaneio_itens(id),
  pedido_id bigint not null references public.com_pedidos(id),
  pedido_item_id bigint not null references public.com_pedido_itens(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  lote_pa_ref text,
  tipo_movimento text not null,
  quantidade numeric not null,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint exp_romaneio_mov_pa_tipo_check check (tipo_movimento in ('baixa', 'estorno')),
  constraint exp_romaneio_mov_pa_qtd_check check (
    (tipo_movimento = 'baixa' and quantidade > 0)
    or (tipo_movimento = 'estorno' and quantidade < 0)
  )
);

create index if not exists idx_exp_romaneios_pedido_status on public.exp_romaneios(pedido_id, status);
create index if not exists idx_exp_romaneios_data on public.exp_romaneios(data_romaneio desc, id desc);
create index if not exists idx_exp_romaneio_itens_romaneio on public.exp_romaneio_itens(romaneio_id);
create index if not exists idx_exp_romaneio_itens_pedido_item on public.exp_romaneio_itens(pedido_item_id, status);
create index if not exists idx_exp_romaneio_itens_lote on public.exp_romaneio_itens(lote_pa_ref) where lote_pa_ref is not null;
create index if not exists idx_exp_romaneio_mov_pa_romaneio on public.exp_romaneio_movimentos_pa(romaneio_id, created_at desc);
create index if not exists idx_exp_romaneio_mov_pa_pedido_item on public.exp_romaneio_movimentos_pa(pedido_item_id, created_at desc);

drop trigger if exists trg_exp_romaneios_updated_at on public.exp_romaneios;
create trigger trg_exp_romaneios_updated_at before update on public.exp_romaneios
for each row execute function public.touch_updated_at();

drop trigger if exists trg_exp_romaneio_itens_updated_at on public.exp_romaneio_itens;
create trigger trg_exp_romaneio_itens_updated_at before update on public.exp_romaneio_itens
for each row execute function public.touch_updated_at();

alter table public.exp_romaneios enable row level security;
alter table public.exp_romaneio_itens enable row level security;
alter table public.exp_romaneio_movimentos_pa enable row level security;

create policy "authenticated full romaneio access" on public.exp_romaneios
for all to authenticated using (true) with check (true);
create policy "authenticated full romaneio item access" on public.exp_romaneio_itens
for all to authenticated using (true) with check (true);
create policy "authenticated full romaneio pa movement access" on public.exp_romaneio_movimentos_pa
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('romaneios.view', 'romaneios', 'Ver romaneios, separacoes e movimentos de PA', true, 401),
  ('romaneios.create', 'romaneios', 'Criar romaneio em rascunho ou separacao', true, 402),
  ('romaneios.reserve', 'romaneios', 'Colocar romaneio em separacao e reservar lote de PA', true, 403),
  ('romaneios.confirm', 'romaneios', 'Confirmar romaneio e gerar baixa auditavel de PA', true, 404),
  ('romaneios.cancel', 'romaneios', 'Cancelar ou estornar romaneio com motivo auditavel', true, 405)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace view public.exp_pedido_item_romaneio_saldos as
select
  item.id as pedido_item_id,
  item.pedido_id,
  item.produto_embalagem_id,
  item.quantidade as quantidade_pedido,
  coalesce(sum(case when rom.status = 'confirmado' and rom_item.status = 'confirmado' then rom_item.quantidade_romaneada else 0 end), 0) as quantidade_confirmada,
  coalesce(sum(case when rom.status in ('draft', 'separacao') and rom_item.status in ('draft', 'reservado') then rom_item.quantidade_romaneada else 0 end), 0) as quantidade_em_separacao,
  item.quantidade
    - coalesce(sum(case when rom.status = 'confirmado' and rom_item.status = 'confirmado' then rom_item.quantidade_romaneada else 0 end), 0) as quantidade_pendente
from public.com_pedido_itens item
left join public.exp_romaneio_itens rom_item
  on rom_item.pedido_item_id = item.id
  and rom_item.status not in ('cancelado', 'estornado')
left join public.exp_romaneios rom
  on rom.id = rom_item.romaneio_id
  and rom.status not in ('cancelado', 'estornado')
where item.status = 'active'
group by item.id, item.pedido_id, item.produto_embalagem_id, item.quantidade;

grant select on public.exp_pedido_item_romaneio_saldos to authenticated;

create or replace function public.create_exp_romaneio(
  p_pedido_id bigint,
  p_pedido_item_id bigint,
  p_quantidade_romaneada numeric,
  p_lote_pa_ref text default null,
  p_tipo_separacao text default 'parcial',
  p_status text default 'draft',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_codigo_romaneio text;
  v_romaneio_id bigint;
  v_romaneio_item_id bigint;
  v_pedido_status text;
  v_tipo_pedido text;
  v_produto_embalagem_id bigint;
  v_quantidade_pedido numeric;
  v_quantidade_comprometida numeric;
  v_quantidade_pendente numeric;
  v_item_status text;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_pedido_item_id is null or p_pedido_item_id <= 0 then
    raise exception 'pedido_item_id is required';
  end if;
  if p_quantidade_romaneada is null or p_quantidade_romaneada <= 0 then
    raise exception 'quantidade_romaneada must be greater than zero';
  end if;
  if p_tipo_separacao not in ('total', 'parcial') then
    raise exception 'invalid tipo_separacao';
  end if;
  if p_status not in ('draft', 'separacao') then
    raise exception 'invalid romaneio initial status';
  end if;
  if p_status = 'separacao' and nullif(trim(p_lote_pa_ref), '') is null then
    raise exception 'lote_pa_ref is required for separacao';
  end if;

  select status, tipo_pedido
    into v_pedido_status, v_tipo_pedido
    from public.com_pedidos
    where id = p_pedido_id
    for update;

  if v_pedido_status is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido_status <> 'open' then
    raise exception 'pedido status does not allow romaneio';
  end if;
  if v_tipo_pedido not in ('venda', 'bonificacao') then
    raise exception 'pedido type does not allow romaneio';
  end if;

  select produto_embalagem_id, quantidade, status
    into v_produto_embalagem_id, v_quantidade_pedido, v_item_status
    from public.com_pedido_itens
    where id = p_pedido_item_id
      and pedido_id = p_pedido_id
    for update;

  if v_produto_embalagem_id is null then
    raise exception 'pedido item not found';
  end if;
  if v_item_status <> 'active' then
    raise exception 'pedido item status does not allow romaneio';
  end if;

  select coalesce(sum(rom_item.quantidade_romaneada), 0)
    into v_quantidade_comprometida
    from public.exp_romaneio_itens rom_item
    join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
    where rom_item.pedido_item_id = p_pedido_item_id
      and rom.status in ('draft', 'separacao', 'confirmado')
      and rom_item.status in ('draft', 'reservado', 'confirmado');

  v_quantidade_pendente := v_quantidade_pedido - v_quantidade_comprometida;

  if p_quantidade_romaneada > v_quantidade_pendente then
    raise exception 'romaneio exceeds pending order quantity';
  end if;
  if p_tipo_separacao = 'total' and p_quantidade_romaneada <> v_quantidade_pendente then
    raise exception 'total romaneio must match pending quantity';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  v_codigo_romaneio := concat(
    'ROM-',
    to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'),
    '-',
    upper(substr(md5(random()::text), 1, 4))
  );

  insert into public.exp_romaneios(
    codigo_romaneio,
    pedido_id,
    tipo_separacao,
    status,
    data_romaneio,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_romaneio,
    p_pedido_id,
    p_tipo_separacao,
    p_status,
    current_date,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_romaneio_id;

  insert into public.exp_romaneio_itens(
    romaneio_id,
    pedido_id,
    pedido_item_id,
    produto_embalagem_id,
    lote_pa_ref,
    quantidade_romaneada,
    quantidade_reservada,
    status,
    created_by,
    updated_by
  )
  values (
    v_romaneio_id,
    p_pedido_id,
    p_pedido_item_id,
    v_produto_embalagem_id,
    nullif(trim(p_lote_pa_ref), ''),
    p_quantidade_romaneada,
    case when p_status = 'separacao' then p_quantidade_romaneada else 0 end,
    case when p_status = 'separacao' then 'reservado' else 'draft' end,
    v_actor,
    v_actor
  )
  returning id into v_romaneio_item_id;

  perform public.log_action(
    'expedicao.romaneio_created',
    'exp_romaneios',
    v_romaneio_id::text,
    'success',
    null,
    jsonb_build_object(
      'codigo_romaneio', v_codigo_romaneio,
      'pedido_id', p_pedido_id,
      'pedido_item_id', p_pedido_item_id,
      'romaneio_item_id', v_romaneio_item_id,
      'tipo_separacao', p_tipo_separacao,
      'status', p_status,
      'lote_pa_ref', nullif(trim(p_lote_pa_ref), ''),
      'quantidade_romaneada', p_quantidade_romaneada,
      'quantidade_pendente_antes', v_quantidade_pendente
    ),
    jsonb_build_object('source', 'create_exp_romaneio')
  );

  return v_romaneio_id;
end;
$$;

create or replace function public.registrar_exp_romaneio_separacao(
  p_romaneio_id bigint,
  p_lote_pa_ref text,
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
begin
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if nullif(trim(p_lote_pa_ref), '') is null then
    raise exception 'lote_pa_ref is required';
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
    raise exception 'romaneio status does not allow separation';
  end if;

  select status
    into v_pedido_status
    from public.com_pedidos
    where id = v_pedido_id
    for update;

  if v_pedido_status <> 'open' then
    raise exception 'pedido status does not allow romaneio separation';
  end if;
  if not exists (
    select 1
      from public.exp_romaneio_itens
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

  update public.exp_romaneio_itens
     set lote_pa_ref = trim(p_lote_pa_ref),
         quantidade_reservada = quantidade_romaneada,
         status = 'reservado',
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status in ('draft', 'reservado');

  update public.exp_romaneios
     set status = 'separacao',
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_romaneio_id;

  perform public.log_action(
    'expedicao.romaneio_separacao_registrada',
    'exp_romaneios',
    p_romaneio_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', 'separacao',
      'pedido_id', v_pedido_id,
      'lote_pa_ref', trim(p_lote_pa_ref),
      'observacao', nullif(trim(p_observacao), '')
    ),
    jsonb_build_object('source', 'registrar_exp_romaneio_separacao')
  );

  return p_romaneio_id;
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
  if exists (
    select 1 from public.exp_romaneio_itens
    where romaneio_id = p_romaneio_id
      and status in ('draft', 'reservado')
      and nullif(trim(lote_pa_ref), '') is null
  ) then
    raise exception 'lote_pa_ref is required before confirmation';
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
      rom_item.lote_pa_ref,
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
      v_item.lote_pa_ref,
      'baixa',
      v_item.quantidade_romaneada,
      nullif(trim(p_observacao), ''),
      v_actor
    );
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
      'observacao', nullif(trim(p_observacao), '')
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
  v_status_anterior text;
  v_pedido_id bigint;
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

  update public.exp_romaneio_itens
     set status = 'cancelado',
         quantidade_reservada = 0,
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status in ('draft', 'reservado');

  update public.exp_romaneios
     set status = 'cancelado',
         cancelado_at = now(),
         updated_by = v_actor,
         observacao = concat_ws(' | ', observacao, concat('cancelamento: ', trim(p_motivo)))
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
      'motivo', trim(p_motivo)
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
    insert into public.exp_romaneio_movimentos_pa(
      romaneio_id,
      romaneio_item_id,
      pedido_id,
      pedido_item_id,
      produto_embalagem_id,
      lote_pa_ref,
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
      'estorno',
      -1 * v_movimento.quantidade,
      trim(p_motivo),
      v_actor
    );
  end loop;

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
      'motivo', trim(p_motivo)
    ),
    jsonb_build_object('source', 'estornar_exp_romaneio')
  );

  return p_romaneio_id;
end;
$$;

revoke all on function public.create_exp_romaneio(bigint, bigint, numeric, text, text, text, text) from public;
grant execute on function public.create_exp_romaneio(bigint, bigint, numeric, text, text, text, text) to authenticated;

revoke all on function public.registrar_exp_romaneio_separacao(bigint, text, text) from public;
grant execute on function public.registrar_exp_romaneio_separacao(bigint, text, text) to authenticated;

revoke all on function public.confirmar_exp_romaneio(bigint, text) from public;
grant execute on function public.confirmar_exp_romaneio(bigint, text) to authenticated;

revoke all on function public.cancelar_exp_romaneio(bigint, text) from public;
grant execute on function public.cancelar_exp_romaneio(bigint, text) to authenticated;

revoke all on function public.estornar_exp_romaneio(bigint, text) from public;
grant execute on function public.estornar_exp_romaneio(bigint, text) to authenticated;
