-- PCP packaging order: reserve PI/package lots, start, finish and create PA lots.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pcp.envase.reserve', 'pcp', 'Reservar lotes de embalagens para envase', true, 322, 'pcp', 'write'),
  ('pcp.envase.start', 'pcp', 'Iniciar ordem de envase', true, 323, 'pcp', 'write'),
  ('pcp.envase.finish', 'pcp', 'Finalizar envase e gerar lotes PA', true, 324, 'pcp', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.pcp_ordem_envase_reservas (
  id bigint generated always as identity primary key,
  ordem_envase_id bigint not null references public.pcp_ordens_envase(id) on delete restrict,
  tipo_reserva text not null,
  embalagem_planejada_id bigint references public.pcp_ordem_envase_embalagens(id) on delete restrict,
  lote_pi_id bigint references public.est_lotes_pi(id) on delete restrict,
  lote_mp_id bigint references public.est_lotes_mp(id) on delete restrict,
  quantidade_reservada numeric not null,
  status text not null default 'ativa',
  motivo_liberacao text,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  updated_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pcp_ordem_envase_reservas_tipo_check check (tipo_reserva in ('PI', 'EMBALAGEM')),
  constraint pcp_ordem_envase_reservas_status_check check (status in ('ativa', 'consumida', 'liberada', 'estornada')),
  constraint pcp_ordem_envase_reservas_quantidade_check check (quantidade_reservada > 0),
  constraint pcp_ordem_envase_reservas_alvo_check check (
    (tipo_reserva = 'PI' and embalagem_planejada_id is null and lote_pi_id is not null and lote_mp_id is null)
    or
    (tipo_reserva = 'EMBALAGEM' and embalagem_planejada_id is not null and lote_pi_id is null and lote_mp_id is not null)
  )
);

create unique index ux_pcp_ordem_envase_reserva_pi_ativa
  on public.pcp_ordem_envase_reservas(ordem_envase_id)
  where tipo_reserva = 'PI' and status = 'ativa';
create unique index ux_pcp_ordem_envase_reserva_embalagem_lote_ativa
  on public.pcp_ordem_envase_reservas(embalagem_planejada_id, lote_mp_id)
  where tipo_reserva = 'EMBALAGEM' and status = 'ativa';
create index idx_pcp_ordem_envase_reservas_pi on public.pcp_ordem_envase_reservas(lote_pi_id, status);
create index idx_pcp_ordem_envase_reservas_mp on public.pcp_ordem_envase_reservas(lote_mp_id, status);

create table public.pcp_ordem_envase_lotes_pa (
  id bigint generated always as identity primary key,
  ordem_envase_id bigint not null references public.pcp_ordens_envase(id) on delete restrict,
  lote_pa_id bigint not null unique references public.est_lotes_pa(id) on delete restrict,
  quantidade numeric not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint pcp_ordem_envase_lotes_pa_quantidade_check check (
    quantidade > 0 and quantidade = trunc(quantidade)
  )
);

create index idx_pcp_ordem_envase_lotes_pa_ordem on public.pcp_ordem_envase_lotes_pa(ordem_envase_id, id);

create trigger trg_pcp_ordem_envase_lotes_pa_append_only
before update or delete on public.pcp_ordem_envase_lotes_pa
for each row execute function public.block_pcp_envase_history_mutation();
create trigger trg_pcp_ordem_envase_lotes_pa_no_truncate
before truncate on public.pcp_ordem_envase_lotes_pa
for each statement execute function public.block_pcp_envase_history_mutation();

alter table public.pcp_ordem_envase_reservas enable row level security;
alter table public.pcp_ordem_envase_lotes_pa enable row level security;
create policy "authorized read pcp_ordem_envase_reservas"
  on public.pcp_ordem_envase_reservas for select to authenticated
  using (public.can_current_user('pcp.envase.view'));
create policy "authorized read pcp_ordem_envase_lotes_pa"
  on public.pcp_ordem_envase_lotes_pa for select to authenticated
  using (public.can_current_user('pcp.envase.view'));

create or replace function public.create_pcp_envase_pi_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pcp_ordem_envase_reservas(
    ordem_envase_id, tipo_reserva, lote_pi_id, quantidade_reservada,
    created_by, updated_by
  ) values (
    new.id, 'PI', new.lote_pi_origem_id, new.volume_planejado_l,
    new.emitida_por, new.emitida_por
  );
  return new;
end;
$$;

create trigger trg_pcp_ordem_envase_reserva_pi
after insert on public.pcp_ordens_envase
for each row execute function public.create_pcp_envase_pi_reservation();

insert into public.pcp_ordem_envase_reservas(
  ordem_envase_id, tipo_reserva, lote_pi_id, quantidade_reservada,
  created_by, updated_by
)
select
  packaging_order.id, 'PI', packaging_order.lote_pi_origem_id, packaging_order.volume_planejado_l,
  packaging_order.emitida_por, packaging_order.emitida_por
from public.pcp_ordens_envase packaging_order
where packaging_order.status not in ('cancelada', 'finalizada')
  and not exists (
    select 1 from public.pcp_ordem_envase_reservas reservation
     where reservation.ordem_envase_id = packaging_order.id and reservation.tipo_reserva = 'PI'
  );

create or replace view public.est_lotes_mp_saldos
with (security_invoker = true)
as
with movimentos as (
  select lote_mp_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_mp group by lote_mp_id
), reservas as (
  select lote_mp_id, sum(quantidade_reservada) as quantidade_reservada
  from (
    select lote_mp_id, quantidade_reservada
      from public.pcp_op_reservas_componentes
     where status = 'ativa' and tipo_componente = 'MP'
    union all
    select lote_mp_id, quantidade_reservada
      from public.pcp_ordem_envase_reservas
     where status = 'ativa' and tipo_reserva = 'EMBALAGEM'
  ) reservation group by lote_mp_id
)
select lote.id as lote_mp_id, lote.materia_prima_id, lote.codigo_lote, lote.status,
  lote.data_fabricacao, lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref, lote.observacao, lote.created_at, lote.updated_at
from public.est_lotes_mp lote
left join movimentos on movimentos.lote_mp_id = lote.id
left join reservas on reservas.lote_mp_id = lote.id;

create or replace view public.est_lotes_pi_saldos
with (security_invoker = true)
as
with movimentos as (
  select lote_pi_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_pi group by lote_pi_id
), reservas as (
  select lote_pi_id, sum(quantidade_reservada) as quantidade_reservada
  from (
    select lote_pi_id, quantidade_reservada
      from public.pcp_op_reservas_componentes
     where status = 'ativa' and tipo_componente = 'PI'
    union all
    select lote_pi_id, quantidade_reservada
      from public.pcp_ordem_envase_reservas
     where status = 'ativa' and tipo_reserva = 'PI'
  ) reservation group by lote_pi_id
)
select lote.id as lote_pi_id, lote.produto_id, lote.codigo_lote, lote.status,
  lote.data_fabricacao, lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref, lote.observacao, lote.created_at, lote.updated_at
from public.est_lotes_pi lote
left join movimentos on movimentos.lote_pi_id = lote.id
left join reservas on reservas.lote_pi_id = lote.id;

create or replace function public.pcp_envase_volume_pi_disponivel(p_lote_pi_id bigint)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select balance.saldo_disponivel
      from public.est_lotes_pi_saldos balance
     where balance.lote_pi_id = p_lote_pi_id
  ), 0)
$$;

revoke all on function public.pcp_envase_volume_pi_disponivel(bigint) from public, anon, authenticated;

create or replace function public.reservar_pcp_ordem_envase_embalagem(
  p_embalagem_planejada_id bigint,
  p_lote_mp_id bigint,
  p_quantidade numeric
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_plan record;
  v_lot record;
  v_reserved numeric;
  v_reservation_id bigint;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.envase.reserve', 'pcp', 'pcp_ordem_envase_reservas', 'movement_event',
    jsonb_build_object('event', 'reserve_packaging_lot')
  );
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'quantidade must be greater than zero'; end if;
  perform pg_advisory_xact_lock(hashtextextended('elite:pcp:envase:mp_lot:' || p_lote_mp_id, 0));
  select plan.*, packaging_order.status as ordem_status
    into v_plan
    from public.pcp_ordem_envase_embalagens plan
    join public.pcp_ordens_envase packaging_order on packaging_order.id = plan.ordem_envase_id
   where plan.id = p_embalagem_planejada_id
   for update of packaging_order;
  if not found then raise exception 'planned packaging component not found'; end if;
  if v_plan.ordem_status not in ('emitida', 'em_separacao') then raise exception 'packaging order status does not allow reservation'; end if;
  select balance.* into v_lot from public.est_lotes_mp_saldos balance where balance.lote_mp_id = p_lote_mp_id;
  if not found then raise exception 'packaging material lot not found'; end if;
  if v_lot.materia_prima_id <> v_plan.materia_prima_id then raise exception 'lot does not match planned packaging material'; end if;
  if v_lot.status <> 'disponivel' then raise exception 'packaging material lot is not available'; end if;
  if v_lot.saldo_disponivel < p_quantidade then raise exception 'insufficient packaging material balance'; end if;
  select coalesce(sum(reservation.quantidade_reservada), 0) into v_reserved
    from public.pcp_ordem_envase_reservas reservation
   where reservation.embalagem_planejada_id = p_embalagem_planejada_id and reservation.status = 'ativa';
  if v_reserved + p_quantidade > v_plan.quantidade_planejada then raise exception 'packaging reservations exceed planned quantity'; end if;
  v_actor := public.current_actor_id();
  insert into public.pcp_ordem_envase_reservas(
    ordem_envase_id, tipo_reserva, embalagem_planejada_id, lote_mp_id,
    quantidade_reservada, created_by, updated_by
  ) values (
    v_plan.ordem_envase_id, 'EMBALAGEM', p_embalagem_planejada_id, p_lote_mp_id,
    p_quantidade, v_actor, v_actor
  ) returning id into v_reservation_id;
  update public.pcp_ordens_envase set status = 'em_separacao', updated_at = now()
   where id = v_plan.ordem_envase_id and status = 'emitida';
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_ordem_envase_reservas', v_reservation_id::text,
    'pcp.packaging_material_reserved', 'pcp.envase.reserve', v_context, null,
    (select to_jsonb(reservation) from public.pcp_ordem_envase_reservas reservation where reservation.id = v_reservation_id),
    jsonb_build_object('ordem_envase_id', v_plan.ordem_envase_id), 'database_rpc'
  );
  return v_reservation_id;
end;
$$;

create or replace function public.iniciar_pcp_ordem_envase(p_ordem_envase_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.envase.start', 'pcp', 'pcp_ordens_envase', 'status_transition',
    jsonb_build_object('event', 'start_packaging')
  );
  select * into v_order from public.pcp_ordens_envase where id = p_ordem_envase_id for update;
  if not found then raise exception 'packaging order not found'; end if;
  if v_order.status not in ('emitida', 'em_separacao') then raise exception 'packaging order status does not allow start'; end if;
  if not exists (
    select 1 from public.pcp_ordem_envase_reservas reservation
     where reservation.ordem_envase_id = p_ordem_envase_id and reservation.tipo_reserva = 'PI'
       and reservation.status = 'ativa' and reservation.quantidade_reservada = v_order.volume_planejado_l
  ) then raise exception 'active PI reservation does not match planned volume'; end if;
  if exists (
    select 1 from public.pcp_ordem_envase_embalagens plan
     where plan.ordem_envase_id = p_ordem_envase_id
       and coalesce((
         select sum(reservation.quantidade_reservada)
           from public.pcp_ordem_envase_reservas reservation
          where reservation.embalagem_planejada_id = plan.id and reservation.status = 'ativa'
       ), 0) <> plan.quantidade_planejada
  ) then raise exception 'packaging reservations must match every planned component'; end if;
  v_before := to_jsonb(v_order);
  update public.pcp_ordens_envase
     set status = 'em_envase', iniciada_em = now(), updated_at = now()
   where id = p_ordem_envase_id;
  select to_jsonb(packaging_order) into v_after from public.pcp_ordens_envase packaging_order where id = p_ordem_envase_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_ordens_envase', p_ordem_envase_id::text,
    'pcp.packaging_order_started', 'pcp.envase.start', v_context, v_before, v_after,
    jsonb_build_object('correlation_id', v_order.correlation_id), 'database_rpc'
  );
  return p_ordem_envase_id;
end;
$$;

create or replace function public.finalizar_pcp_ordem_envase(
  p_ordem_envase_id bigint,
  p_lotes_pa_jsonb jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_order record;
  v_reservation record;
  v_output jsonb;
  v_quantity numeric;
  v_total numeric := 0;
  v_lote_pa_id bigint;
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.envase.finish', 'pcp', 'pcp_ordens_envase', 'movement_event',
    jsonb_build_object('event', 'finish_packaging')
  );
  if p_lotes_pa_jsonb is null or jsonb_typeof(p_lotes_pa_jsonb) <> 'array'
     or jsonb_array_length(p_lotes_pa_jsonb) = 0 then
    raise exception 'lotes_pa_jsonb must be a non-empty array';
  end if;
  select * into v_order from public.pcp_ordens_envase where id = p_ordem_envase_id for update;
  if not found then raise exception 'packaging order not found'; end if;
  if v_order.status <> 'em_envase' then raise exception 'packaging order must be in progress before finish'; end if;
  for v_output in select value from jsonb_array_elements(p_lotes_pa_jsonb) loop
    v_quantity := nullif(btrim(v_output->>'quantidade'), '')::numeric;
    if v_quantity is null or v_quantity <= 0 or v_quantity <> trunc(v_quantity) then
      raise exception 'PA lot quantity must be a positive whole number';
    end if;
    v_total := v_total + v_quantity;
  end loop;
  if v_total <> v_order.quantidade_pa_planejada then raise exception 'PA lot quantities must match planned finished packages'; end if;
  v_before := to_jsonb(v_order);
  v_actor := public.current_actor_id();
  for v_reservation in
    select reservation.*, plan.materia_prima_id
      from public.pcp_ordem_envase_reservas reservation
      left join public.pcp_ordem_envase_embalagens plan on plan.id = reservation.embalagem_planejada_id
     where reservation.ordem_envase_id = p_ordem_envase_id and reservation.status = 'ativa'
     order by reservation.id for update of reservation
  loop
    update public.pcp_ordem_envase_reservas
       set status = 'consumida', updated_by = v_actor, updated_at = now()
     where id = v_reservation.id;
    if v_reservation.tipo_reserva = 'PI' then
      insert into public.est_movimentos_pi(
        lote_pi_id, produto_id, tipo_movimento, quantidade, origem_modulo,
        origem_tabela, origem_id, observacao, created_by
      )
      select v_reservation.lote_pi_id, lot.produto_id, 'transformacao_saida',
        -v_reservation.quantidade_reservada, 'pcp', 'pcp_ordens_envase',
        p_ordem_envase_id::text, nullif(btrim(p_observacao), ''), v_actor
      from public.est_lotes_pi lot where lot.id = v_reservation.lote_pi_id;
      perform public.sync_est_lote_pi_status(v_reservation.lote_pi_id);
    else
      insert into public.est_movimentos_mp(
        lote_mp_id, materia_prima_id, tipo_movimento, quantidade, origem_modulo,
        origem_tabela, origem_id, observacao, created_by
      ) values (
        v_reservation.lote_mp_id, v_reservation.materia_prima_id, 'consumo_op',
        -v_reservation.quantidade_reservada, 'pcp', 'pcp_ordens_envase',
        p_ordem_envase_id::text, nullif(btrim(p_observacao), ''), v_actor
      );
      perform public.sync_est_lote_mp_status(v_reservation.lote_mp_id);
    end if;
  end loop;
  for v_output in select value from jsonb_array_elements(p_lotes_pa_jsonb) loop
    v_quantity := (v_output->>'quantidade')::numeric;
    v_lote_pa_id := public.create_est_lote_pa_auto(
      v_order.produto_embalagem_id, v_quantity, 'transformacao_entrada', 'disponivel',
      current_date, null, v_order.correlation_id, nullif(btrim(v_output->>'observacao'), '')
    );
    insert into public.pcp_ordem_envase_lotes_pa(
      ordem_envase_id, lote_pa_id, quantidade, created_by
    ) values (p_ordem_envase_id, v_lote_pa_id, v_quantity, v_actor);
  end loop;
  update public.pcp_ordens_envase
     set status = 'finalizada', finalizada_em = now(), updated_at = now(),
         observacao = coalesce(nullif(btrim(p_observacao), ''), observacao)
   where id = p_ordem_envase_id;
  select jsonb_build_object(
    'ordem', to_jsonb(packaging_order),
    'lotes_pa', (select jsonb_agg(to_jsonb(output) order by output.id)
      from public.pcp_ordem_envase_lotes_pa output where output.ordem_envase_id = packaging_order.id)
  ) into v_after from public.pcp_ordens_envase packaging_order where packaging_order.id = p_ordem_envase_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_ordens_envase', p_ordem_envase_id::text,
    'pcp.packaging_order_finished', 'pcp.envase.finish', v_context, v_before, v_after,
    jsonb_build_object('correlation_id', v_order.correlation_id), 'database_rpc'
  );
  return p_ordem_envase_id;
end;
$$;

revoke all on function public.create_pcp_envase_pi_reservation() from public, anon, authenticated;
revoke all on function public.reservar_pcp_ordem_envase_embalagem(bigint, bigint, numeric) from public, anon;
revoke all on function public.iniciar_pcp_ordem_envase(bigint) from public, anon;
revoke all on function public.finalizar_pcp_ordem_envase(bigint, jsonb, text) from public, anon;
grant execute on function public.reservar_pcp_ordem_envase_embalagem(bigint, bigint, numeric) to authenticated;
grant execute on function public.iniciar_pcp_ordem_envase(bigint) to authenticated;
grant execute on function public.finalizar_pcp_ordem_envase(bigint, jsonb, text) to authenticated;

revoke all on public.pcp_ordem_envase_reservas from public, anon;
revoke all on public.pcp_ordem_envase_lotes_pa from public, anon;
revoke insert, update, delete, truncate on public.pcp_ordem_envase_reservas from authenticated;
revoke insert, update, delete, truncate on public.pcp_ordem_envase_lotes_pa from authenticated;
grant select on public.pcp_ordem_envase_reservas to authenticated;
grant select on public.pcp_ordem_envase_lotes_pa to authenticated;
grant select on public.est_lotes_mp_saldos to authenticated;
grant select on public.est_lotes_pi_saldos to authenticated;
