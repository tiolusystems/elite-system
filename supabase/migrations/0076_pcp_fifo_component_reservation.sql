-- DEC-013: deterministic FIFO reservation and governed override.

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order, runtime_module_key, runtime_access_kind)
values ('pcp.op.reserve_override_fifo', 'pcp', 'Ignorar lote FIFO em reserva de OP', false, 325, 'pcp', 'write')
on conflict (action_key) do nothing;

alter table public.pcp_op_reservas_componentes
  add column if not exists ordem_fifo integer,
  add column if not exists fifo_desviado boolean not null default false,
  add column if not exists fifo_justificativa text,
  drop constraint if exists pcp_op_reserva_fifo_ordem_check,
  drop constraint if exists pcp_op_reserva_fifo_justificativa_check,
  add constraint pcp_op_reserva_fifo_ordem_check check (ordem_fifo is null or ordem_fifo > 0),
  add constraint pcp_op_reserva_fifo_justificativa_check check (
    (not fifo_desviado and fifo_justificativa is null)
    or (fifo_desviado and char_length(btrim(fifo_justificativa)) >= 10)
  );

alter function public.reservar_pcp_op_componente(bigint,bigint,bigint,bigint,numeric,text)
  rename to reservar_pcp_op_componente_impl_0076;

create or replace function public.pcp_lote_fifo_posicao(p_tipo text, p_target_id bigint, p_lote_id bigint)
returns integer language plpgsql stable security definer set search_path = public as $$
declare v_position integer;
begin
  if p_tipo = 'MP' then
    select ranked.position into v_position from (
      select balance.lote_mp_id, row_number() over (order by coalesce((
        select min(movement.created_at) from public.est_movimentos_mp movement
        where movement.lote_mp_id = balance.lote_mp_id and movement.quantidade > 0
      ), balance.created_at), balance.lote_mp_id)::integer position
      from public.est_lotes_mp_saldos balance
      where balance.materia_prima_id = p_target_id and balance.status = 'disponivel' and balance.saldo_disponivel > 0
    ) ranked where ranked.lote_mp_id = p_lote_id;
  elsif p_tipo = 'PA' then
    select ranked.position into v_position from (
      select balance.lote_pa_id, row_number() over (order by balance.created_at, balance.lote_pa_id)::integer position
      from public.est_lotes_pa_saldos balance
      where balance.produto_embalagem_id = p_target_id and balance.status = 'disponivel' and balance.saldo_disponivel > 0
    ) ranked where ranked.lote_pa_id = p_lote_id;
  elsif p_tipo = 'PI' then
    select ranked.position into v_position from (
      select balance.lote_pi_id, row_number() over (order by balance.created_at, balance.lote_pi_id)::integer position
      from public.est_lotes_pi_saldos balance
      where balance.produto_id = p_target_id and balance.status = 'disponivel' and balance.saldo_disponivel > 0
    ) ranked where ranked.lote_pi_id = p_lote_id;
  end if;
  return v_position;
end;
$$;

create or replace function public.reservar_pcp_op_componente(
  p_op_componente_id bigint, p_lote_mp_id bigint default null, p_lote_pa_id bigint default null,
  p_lote_pi_id bigint default null, p_quantidade_reservada numeric default null, p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_component record; v_lot_id bigint; v_target_id bigint; v_position integer;
  v_reservation_id bigint; v_override boolean;
begin
  perform public.require_current_user_permission('pcp.op.reserve_components');
  perform pg_advisory_xact_lock(hashtextextended('pcp_fifo_component:' || p_op_componente_id::text, 0));
  select * into v_component from public.pcp_op_componentes_planejados where id = p_op_componente_id;
  if not found then raise exception 'OP component not found'; end if;
  v_lot_id := case v_component.tipo_componente when 'MP' then p_lote_mp_id when 'PA' then p_lote_pa_id else p_lote_pi_id end;
  v_target_id := case v_component.tipo_componente when 'MP' then v_component.materia_prima_id
    when 'PA' then v_component.produto_embalagem_id else v_component.produto_id end;
  v_position := public.pcp_lote_fifo_posicao(v_component.tipo_componente, v_target_id, v_lot_id);
  v_override := coalesce(v_position, 0) > 1;
  if v_override then
    perform public.require_current_user_permission('pcp.op.reserve_override_fifo');
    if char_length(coalesce(btrim(p_observacao), '')) < 10 then
      raise exception 'FIFO override requires justification with at least 10 characters';
    end if;
  end if;
  v_reservation_id := public.reservar_pcp_op_componente_impl_0076(
    p_op_componente_id, p_lote_mp_id, p_lote_pa_id, p_lote_pi_id, p_quantidade_reservada, p_observacao);
  update public.pcp_op_reservas_componentes set ordem_fifo = v_position, fifo_desviado = v_override,
    fifo_justificativa = case when v_override then btrim(p_observacao) else null end where id = v_reservation_id;
  if v_override then
    perform public.log_action('pcp.op_fifo_override', 'pcp_op_reservas_componentes', v_reservation_id::text,
      'success', null, jsonb_build_object('ordem_fifo', v_position, 'justificativa', btrim(p_observacao)),
      jsonb_build_object('source', 'reservar_pcp_op_componente'));
  end if;
  return v_reservation_id;
end;
$$;

create or replace function public.reservar_pcp_op_componente_fifo(p_op_componente_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v_component record; v_lot record; v_remaining numeric; v_quantity numeric; v_count integer := 0;
begin
  perform public.require_current_user_permission('pcp.op.reserve_components');
  perform pg_advisory_xact_lock(hashtextextended('pcp_fifo_component:' || p_op_componente_id::text, 0));
  select component.*, coalesce((select sum(reservation.quantidade_reservada)
    from public.pcp_op_reservas_componentes reservation
    where reservation.op_componente_id = component.id and reservation.status = 'ativa'), 0) already_reserved
  into v_component from public.pcp_op_componentes_planejados component
  where component.id = p_op_componente_id for update;
  if not found then raise exception 'OP component not found'; end if;
  v_remaining := v_component.quantidade_planejada - v_component.already_reserved;
  if v_remaining <= 0 then raise exception 'OP component is already fully reserved'; end if;

  for v_lot in select * from (
    select 'MP'::text kind, balance.lote_mp_id lot_id, balance.saldo_disponivel,
      coalesce((select min(m.created_at) from public.est_movimentos_mp m
        where m.lote_mp_id = balance.lote_mp_id and m.quantidade > 0), balance.created_at) entered_at
    from public.est_lotes_mp_saldos balance
    where v_component.tipo_componente = 'MP' and balance.materia_prima_id = v_component.materia_prima_id
      and balance.status = 'disponivel' and balance.saldo_disponivel > 0
    union all
    select 'PA', balance.lote_pa_id, balance.saldo_disponivel, balance.created_at
    from public.est_lotes_pa_saldos balance
    where v_component.tipo_componente = 'PA' and balance.produto_embalagem_id = v_component.produto_embalagem_id
      and balance.status = 'disponivel' and balance.saldo_disponivel > 0
    union all
    select 'PI', balance.lote_pi_id, balance.saldo_disponivel, balance.created_at
    from public.est_lotes_pi_saldos balance
    where v_component.tipo_componente = 'PI' and balance.produto_id = v_component.produto_id
      and balance.status = 'disponivel' and balance.saldo_disponivel > 0
  ) lots order by entered_at, lot_id loop
    exit when v_remaining <= 0;
    v_quantity := least(v_remaining, v_lot.saldo_disponivel);
    perform public.reservar_pcp_op_componente_impl_0076(p_op_componente_id,
      case when v_lot.kind = 'MP' then v_lot.lot_id else null end,
      case when v_lot.kind = 'PA' then v_lot.lot_id else null end,
      case when v_lot.kind = 'PI' then v_lot.lot_id else null end,
      v_quantity, 'Reserva automatica FIFO');
    update public.pcp_op_reservas_componentes set ordem_fifo = v_count + 1, fifo_desviado = false
    where op_componente_id = p_op_componente_id and status = 'ativa'
      and ((v_lot.kind = 'MP' and lote_mp_id = v_lot.lot_id)
        or (v_lot.kind = 'PA' and lote_pa_id = v_lot.lot_id)
        or (v_lot.kind = 'PI' and lote_pi_id = v_lot.lot_id));
    v_count := v_count + 1; v_remaining := v_remaining - v_quantity;
  end loop;
  if v_remaining > 0 then raise exception 'insufficient stock available for full FIFO reservation'; end if;
  perform public.log_action('pcp.op_componente_fifo_reserved', 'pcp_op_componentes_planejados',
    p_op_componente_id::text, 'success', null,
    jsonb_build_object('lotes_utilizados', v_count, 'quantidade_total', v_component.quantidade_planejada),
    jsonb_build_object('source', 'reservar_pcp_op_componente_fifo'));
  return v_count;
end;
$$;

revoke all on function public.reservar_pcp_op_componente_impl_0076(bigint,bigint,bigint,bigint,numeric,text) from public, anon, authenticated;
revoke all on function public.pcp_lote_fifo_posicao(text,bigint,bigint) from public, anon, authenticated;
revoke all on function public.reservar_pcp_op_componente(bigint,bigint,bigint,bigint,numeric,text) from public, anon;
revoke all on function public.reservar_pcp_op_componente_fifo(bigint) from public, anon;
grant execute on function public.reservar_pcp_op_componente(bigint,bigint,bigint,bigint,numeric,text) to authenticated;
grant execute on function public.reservar_pcp_op_componente_fifo(bigint) to authenticated;
