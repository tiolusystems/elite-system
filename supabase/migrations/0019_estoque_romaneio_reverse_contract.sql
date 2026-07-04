insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.pa.reverse.romaneio', 'estoque', 'Reverter baixa de PA gerada por romaneio confirmado', true, 239)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

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
  v_romaneio record;
  v_before jsonb;
  v_after jsonb;
begin
  perform public.require_current_user_permission('romaneios.cancel');
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_romaneio
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio.status not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow cancellation';
  end if;

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
        from public.est_reservas_pa reserva
        where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb)
    )
    into v_before
    from public.exp_romaneios rom
    where rom.id = p_romaneio_id;

  v_actor := public.current_actor_id();

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

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
        from public.est_reservas_pa reserva
        where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb)
    )
    into v_after
    from public.exp_romaneios rom
    where rom.id = p_romaneio_id;

  perform public.log_audit_event(
    'romaneios',
    'exp_romaneios',
    p_romaneio_id::text,
    'expedicao.romaneio_cancelado',
    'romaneios.cancel',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'romaneios.cancel', 'axis', 'status_transition', 'event', 'cancel'),
    'database_rpc',
    jsonb_build_object(
      'source', 'cancelar_exp_romaneio',
      'motivo', trim(p_motivo),
      'estoque_pa_reserva_liberada', true
    )
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
  v_est_movimento_id bigint;
  v_before jsonb;
  v_after jsonb;
  v_movimentos_reversao jsonb := '[]'::jsonb;
begin
  perform public.require_current_user_permission('romaneios.cancel');
  perform public.require_current_user_permission('estoque.pa.reverse.romaneio');
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

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'pa_saldos', coalesce((
        select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
        from public.est_lotes_pa_saldos saldo
        where saldo.lote_pa_id in (
          select mov.lote_pa_id
          from public.exp_romaneio_movimentos_pa mov
          where mov.romaneio_id = p_romaneio_id
            and mov.tipo_movimento = 'baixa'
            and mov.lote_pa_id is not null
        )
      ), '[]'::jsonb),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
        from public.est_reservas_pa reserva
        where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb)
    )
    into v_before
    from public.exp_romaneios rom
    where rom.id = p_romaneio_id;

  v_actor := public.current_actor_id();

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
      )
      returning id into v_est_movimento_id;

      v_movimentos_reversao := v_movimentos_reversao || jsonb_build_array(jsonb_build_object(
        'est_movimento_id', v_est_movimento_id,
        'lote_pa_id', v_movimento.lote_pa_id,
        'produto_embalagem_id', v_movimento.produto_embalagem_id,
        'quantidade', v_movimento.quantidade,
        'tipo_movimento', 'estorno_saida'
      ));

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

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'pa_saldos', coalesce((
        select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
        from public.est_lotes_pa_saldos saldo
        where saldo.lote_pa_id in (
          select mov.lote_pa_id
          from public.exp_romaneio_movimentos_pa mov
          where mov.romaneio_id = p_romaneio_id
            and mov.lote_pa_id is not null
        )
      ), '[]'::jsonb),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
        from public.est_reservas_pa reserva
        where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb)
    )
    into v_after
    from public.exp_romaneios rom
    where rom.id = p_romaneio_id;

  perform public.log_audit_event(
    'estoque',
    'exp_romaneios',
    p_romaneio_id::text,
    'estoque.pa_romaneio_estornado',
    'estoque.pa.reverse.romaneio',
    'success',
    v_before,
    v_after,
    jsonb_build_object(
      'alcada_usada', 'estoque.pa.reverse.romaneio',
      'business_action_key', 'romaneios.cancel',
      'axis', 'event_movement',
      'familia', 'PA',
      'event', 'reverse',
      'origem', 'romaneio'
    ),
    'database_rpc',
    jsonb_build_object(
      'source', 'estornar_exp_romaneio',
      'motivo', trim(p_motivo),
      'movimentos_reversao', v_movimentos_reversao,
      'pedido_id', v_pedido_id
    )
  );

  return p_romaneio_id;
end;
$$;

revoke all on function public.cancelar_exp_romaneio(bigint, text) from public;
grant execute on function public.cancelar_exp_romaneio(bigint, text) to authenticated;

revoke all on function public.estornar_exp_romaneio(bigint, text) from public;
grant execute on function public.estornar_exp_romaneio(bigint, text) to authenticated;
