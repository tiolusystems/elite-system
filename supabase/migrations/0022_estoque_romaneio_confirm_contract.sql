insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.pa.issue.romaneio', 'estoque', 'Baixar PA por romaneio confirmado', true, 240)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

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
  v_total_reservado numeric;
  v_saldo_fisico numeric;
  v_quantidade_confirmada_outros numeric;
  v_exp_movimento_id bigint;
  v_est_movimento_id bigint;
  v_movimentos_saida jsonb := '[]'::jsonb;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  perform public.require_current_user_permission('romaneios.confirm');
  v_permission_context := public.begin_audited_rpc(
    'estoque.pa.issue.romaneio',
    'estoque',
    'exp_romaneios',
    'movement_event',
    jsonb_build_object(
      'business_action_key', 'romaneios.confirm',
      'familia', 'PA',
      'event', 'issue',
      'origem', 'romaneio',
      'source', 'confirmar_exp_romaneio'
    )
  );

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

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'itens', coalesce((
        select jsonb_agg(to_jsonb(item) order by item.id)
          from public.exp_romaneio_itens item
         where item.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
          from public.est_reservas_pa reserva
         where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'pa_saldos', coalesce((
        select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
          from public.est_lotes_pa_saldos saldo
         where saldo.lote_pa_id in (
           select reserva.lote_pa_id
             from public.est_reservas_pa reserva
            where reserva.romaneio_id = p_romaneio_id
           union
           select mov.lote_pa_id
             from public.exp_romaneio_movimentos_pa mov
            where mov.romaneio_id = p_romaneio_id
              and mov.lote_pa_id is not null
         )
      ), '[]'::jsonb),
      'exp_movimentos_pa', coalesce((
        select jsonb_agg(to_jsonb(mov) order by mov.id)
          from public.exp_romaneio_movimentos_pa mov
         where mov.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'est_movimentos_pa', coalesce((
        select jsonb_agg(to_jsonb(mov) order by mov.id)
          from public.est_movimentos_pa mov
         where mov.origem_modulo = 'romaneio'
           and mov.origem_tabela = 'exp_romaneios'
           and mov.origem_id = p_romaneio_id::text
      ), '[]'::jsonb)
    )
    into v_before
    from public.exp_romaneios rom
   where rom.id = p_romaneio_id;

  v_actor := public.current_actor_id();

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

    select coalesce(sum(quantidade_reservada), 0)
      into v_total_reservado
      from public.est_reservas_pa
     where romaneio_item_id = v_item.id
       and status = 'ativa';

    if v_total_reservado <> v_item.quantidade_romaneada then
      raise exception 'active PA reservations must match romaneio item quantity';
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

    for v_reserva in
      select
          reserva.id,
          reserva.lote_pa_id,
          reserva.quantidade_reservada,
          lote.codigo_lote,
          lote.produto_embalagem_id,
          lote.status as lote_status
        from public.est_reservas_pa reserva
        join public.est_lotes_pa lote on lote.id = reserva.lote_pa_id
       where reserva.romaneio_item_id = v_item.id
         and reserva.status = 'ativa'
       for update of reserva, lote
    loop
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
        v_reserva.quantidade_reservada,
        nullif(trim(p_observacao), ''),
        v_actor
      )
      returning id into v_exp_movimento_id;

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
        -1 * v_reserva.quantidade_reservada,
        'romaneio',
        'exp_romaneios',
        p_romaneio_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      )
      returning id into v_est_movimento_id;

      v_movimentos_saida := v_movimentos_saida || jsonb_build_array(jsonb_build_object(
        'exp_movimento_id', v_exp_movimento_id,
        'est_movimento_id', v_est_movimento_id,
        'reserva_id', v_reserva.id,
        'lote_pa_id', v_reserva.lote_pa_id,
        'produto_embalagem_id', v_item.produto_embalagem_id,
        'quantidade', v_reserva.quantidade_reservada,
        'tipo_movimento', 'saida_romaneio'
      ));

      update public.est_reservas_pa
         set status = 'baixada',
             updated_by = v_actor
       where id = v_reserva.id;

      perform public.sync_est_lote_pa_status(v_reserva.lote_pa_id);
    end loop;
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

  select jsonb_build_object(
      'romaneio', to_jsonb(rom),
      'itens', coalesce((
        select jsonb_agg(to_jsonb(item) order by item.id)
          from public.exp_romaneio_itens item
         where item.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'reservas_pa', coalesce((
        select jsonb_agg(to_jsonb(reserva) order by reserva.id)
          from public.est_reservas_pa reserva
         where reserva.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'pa_saldos', coalesce((
        select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
          from public.est_lotes_pa_saldos saldo
         where saldo.lote_pa_id in (
           select reserva.lote_pa_id
             from public.est_reservas_pa reserva
            where reserva.romaneio_id = p_romaneio_id
           union
           select mov.lote_pa_id
             from public.exp_romaneio_movimentos_pa mov
            where mov.romaneio_id = p_romaneio_id
              and mov.lote_pa_id is not null
         )
      ), '[]'::jsonb),
      'exp_movimentos_pa', coalesce((
        select jsonb_agg(to_jsonb(mov) order by mov.id)
          from public.exp_romaneio_movimentos_pa mov
         where mov.romaneio_id = p_romaneio_id
      ), '[]'::jsonb),
      'est_movimentos_pa', coalesce((
        select jsonb_agg(to_jsonb(mov) order by mov.id)
          from public.est_movimentos_pa mov
         where mov.origem_modulo = 'romaneio'
           and mov.origem_tabela = 'exp_romaneios'
           and mov.origem_id = p_romaneio_id::text
      ), '[]'::jsonb)
    )
    into v_after
    from public.exp_romaneios rom
   where rom.id = p_romaneio_id;

  perform public.log_audited_rpc_change(
    'estoque',
    'exp_romaneios',
    p_romaneio_id::text,
    'estoque.pa_romaneio_confirmado',
    'estoque.pa.issue.romaneio',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'confirmar_exp_romaneio',
      'business_action_key', 'romaneios.confirm',
      'pedido_id', v_pedido_id,
      'status_anterior', v_status_anterior,
      'observacao', nullif(trim(p_observacao), ''),
      'estoque_pa_integrado', true,
      'multilote', true,
      'movimentos_saida', v_movimentos_saida
    ),
    'database_rpc'
  );

  return p_romaneio_id;
end;
$$;

revoke all on function public.confirmar_exp_romaneio(bigint, text) from public;
grant execute on function public.confirmar_exp_romaneio(bigint, text) to authenticated;
