insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.mp.consume.op', 'estoque', 'Consumir materia-prima na finalizacao de OP', true, 196),
  ('estoque.pa.consume.op', 'estoque', 'Consumir produto acabado na finalizacao de OP ou reprocessamento', true, 197),
  ('estoque.pi.consume.op', 'estoque', 'Consumir produto intermediario na finalizacao de OP ou reprocessamento', true, 198),
  ('estoque.pa.entry.op', 'estoque', 'Gerar entrada de produto acabado por OP finalizada', true, 199),
  ('estoque.pi.entry.op', 'estoque', 'Gerar entrada de produto intermediario por OP finalizada', true, 200),
  ('pcp.blocked_lot.release', 'pcp', 'Liberar lote PA ou PI bloqueado por CQ, experimental ou desenvolvimento', true, 309)
on conflict (action_key) do update
set description = excluded.description,
    module = excluded.module,
    sort_order = excluded.sort_order;

create or replace function public.log_rpc_failed(
  p_action_key text,
  p_domain text,
  p_entity_type text,
  p_entity_id text default null,
  p_action text default null,
  p_origin text default 'application',
  p_metadata_json jsonb default '{}'::jsonb,
  p_permission_context jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_domain text;
  v_entity_type text;
  v_action text;
  v_permission_context jsonb;
begin
  v_action_key := nullif(trim(p_action_key), '');
  v_domain := lower(nullif(trim(p_domain), ''));
  v_entity_type := nullif(trim(p_entity_type), '');
  v_action := coalesce(nullif(trim(p_action), ''), concat(coalesce(v_domain, 'rpc'), '.rpc_failed'));
  v_permission_context := jsonb_build_object(
    'alcada_usada', v_action_key,
    'decision', 'failed'
  ) || coalesce(p_permission_context, '{}'::jsonb);

  if v_action_key is null then
    raise exception 'action_key is required';
  end if;
  if v_domain is null then
    raise exception 'audit domain is required';
  end if;
  if v_entity_type is null then
    raise exception 'audit entity_type is required';
  end if;

  return public.log_audit_event(
    v_domain,
    v_entity_type,
    p_entity_id,
    v_action,
    v_action_key,
    'failed',
    null,
    null,
    v_permission_context,
    coalesce(nullif(trim(p_origin), ''), 'application'),
    coalesce(p_metadata_json, '{}'::jsonb)
  );
end;
$$;

create or replace function public.pcp_op_finish_audit_snapshot(p_op_id bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'op', (
      select to_jsonb(op)
        from public.pcp_ordens_producao op
       where op.id = p_op_id
    ),
    'cq_resultados', coalesce((
      select jsonb_agg(to_jsonb(cq) order by cq.id)
        from public.pcp_op_cq_resultados cq
       where cq.op_id = p_op_id
    ), '[]'::jsonb),
    'reservas', coalesce((
      select jsonb_agg(to_jsonb(reserva) order by reserva.op_componente_id, reserva.id)
        from public.pcp_op_reservas_componentes reserva
       where reserva.op_id = p_op_id
    ), '[]'::jsonb),
    'consumos', coalesce((
      select jsonb_agg(to_jsonb(consumo) order by consumo.id)
        from public.pcp_op_consumos_componentes consumo
       where consumo.op_id = p_op_id
    ), '[]'::jsonb),
    'produtos_gerados', coalesce((
      select jsonb_agg(to_jsonb(produto) order by produto.id)
        from public.pcp_op_produtos_gerados produto
       where produto.op_id = p_op_id
    ), '[]'::jsonb),
    'mp_saldos', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.lote_mp_id)
        from public.est_lotes_mp_saldos saldo
       where saldo.lote_mp_id in (
         select reserva.lote_mp_id
           from public.pcp_op_reservas_componentes reserva
          where reserva.op_id = p_op_id
            and reserva.lote_mp_id is not null
       )
    ), '[]'::jsonb),
    'pa_saldos', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
        from public.est_lotes_pa_saldos saldo
       where saldo.lote_pa_id in (
         select reserva.lote_pa_id
           from public.pcp_op_reservas_componentes reserva
          where reserva.op_id = p_op_id
            and reserva.lote_pa_id is not null
         union
         select produto.lote_pa_id
           from public.pcp_op_produtos_gerados produto
          where produto.op_id = p_op_id
            and produto.lote_pa_id is not null
       )
    ), '[]'::jsonb),
    'pi_saldos', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pi_id)
        from public.est_lotes_pi_saldos saldo
       where saldo.lote_pi_id in (
         select reserva.lote_pi_id
           from public.pcp_op_reservas_componentes reserva
          where reserva.op_id = p_op_id
            and reserva.lote_pi_id is not null
         union
         select produto.lote_pi_id
           from public.pcp_op_produtos_gerados produto
          where produto.op_id = p_op_id
            and produto.lote_pi_id is not null
       )
    ), '[]'::jsonb),
    'movimentos_mp', coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
        from public.est_movimentos_mp movimento
       where movimento.origem_tabela = 'pcp_ordens_producao'
         and movimento.origem_id = p_op_id::text
    ), '[]'::jsonb),
    'movimentos_pa', coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
        from public.est_movimentos_pa movimento
       where movimento.origem_tabela = 'pcp_ordens_producao'
         and movimento.origem_id = p_op_id::text
    ), '[]'::jsonb),
    'movimentos_pi', coalesce((
      select jsonb_agg(to_jsonb(movimento) order by movimento.id)
        from public.est_movimentos_pi movimento
       where movimento.origem_tabela = 'pcp_ordens_producao'
         and movimento.origem_id = p_op_id::text
    ), '[]'::jsonb)
  );
$$;

create or replace function public.finalizar_pcp_op(
  p_op_id bigint,
  p_outputs_jsonb jsonb,
  p_cq_status text,
  p_ph numeric,
  p_densidade_kg_l numeric,
  p_volume_l numeric,
  p_massa_kg numeric,
  p_temperatura_c numeric,
  p_separador_mp text,
  p_conferente_mp text,
  p_formuladores_jsonb jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
  v_reserva record;
  v_output jsonb;
  v_tipo_produto text;
  v_quantidade numeric;
  v_output_target_id bigint;
  v_target_status text;
  v_status_lote text;
  v_lote_pa_id bigint;
  v_lote_pi_id bigint;
  v_tipo_entrada text;
  v_cq_id bigint;
  v_correlation_id text;
  v_before jsonb;
  v_after jsonb;
  v_finish_context jsonb;
  v_cq_context jsonb;
  v_mp_consume_context jsonb;
  v_pa_consume_context jsonb;
  v_pi_consume_context jsonb;
  v_pa_entry_context jsonb;
  v_pi_entry_context jsonb;
  v_need_mp_consume boolean := false;
  v_need_pa_consume boolean := false;
  v_need_pi_consume boolean := false;
  v_need_pa_entry boolean := false;
  v_need_pi_entry boolean := false;
begin
  if p_op_id is null or p_op_id <= 0 then
    raise exception 'op_id is required';
  end if;
  if p_outputs_jsonb is null or jsonb_typeof(p_outputs_jsonb) <> 'array' or jsonb_array_length(p_outputs_jsonb) = 0 then
    raise exception 'outputs_jsonb must be a non-empty array';
  end if;
  if p_cq_status not in ('aprovado', 'bloqueado', 'reprovado') then
    raise exception 'invalid cq_status';
  end if;
  if p_ph is null or p_ph < 0 then
    raise exception 'ph is required';
  end if;
  if p_densidade_kg_l is null or p_densidade_kg_l <= 0 then
    raise exception 'densidade_kg_l is required';
  end if;
  if p_volume_l is null or p_volume_l <= 0 then
    raise exception 'volume_l is required';
  end if;
  if p_massa_kg is null or p_massa_kg <= 0 then
    raise exception 'massa_kg is required';
  end if;
  if p_temperatura_c is null then
    raise exception 'temperatura_c is required';
  end if;
  if nullif(trim(p_separador_mp), '') is null then
    raise exception 'separador_mp is required';
  end if;
  if nullif(trim(p_conferente_mp), '') is null then
    raise exception 'conferente_mp is required';
  end if;
  if p_formuladores_jsonb is null or jsonb_typeof(p_formuladores_jsonb) <> 'array' or jsonb_array_length(p_formuladores_jsonb) = 0 then
    raise exception 'formuladores_jsonb must be a non-empty array';
  end if;

  v_correlation_id := concat('pcp_op:', p_op_id::text, ':finish');

  v_finish_context := public.begin_audited_rpc(
    'pcp.op.finish',
    'pcp',
    'pcp_ordens_producao',
    'movement_event',
    jsonb_build_object(
      'event', 'finish',
      'correlation_id', v_correlation_id,
      'source', 'finalizar_pcp_op'
    )
  );

  v_cq_context := public.begin_audited_rpc(
    'pcp.cq.record',
    'pcp',
    'pcp_op_cq_resultados',
    'status_transition',
    jsonb_build_object(
      'event', 'record_cq',
      'correlation_id', v_correlation_id,
      'source', 'finalizar_pcp_op'
    )
  );

  select *
    into v_op
    from public.pcp_ordens_producao
   where id = p_op_id
   for update;

  if not found then
    raise exception 'OP not found';
  end if;
  if v_op.tipo_op = 'mapa_documental' then
    raise exception 'MAPA documental OP does not finish stock production';
  end if;
  if v_op.status not in ('planned', 'in_process') then
    raise exception 'OP status does not allow finish';
  end if;
  if exists (select 1 from public.pcp_op_cq_resultados where op_id = p_op_id) then
    raise exception 'OP already has CQ result';
  end if;
  if exists (
    select 1
      from public.pcp_op_componentes_planejados comp
     where comp.op_id = p_op_id
       and coalesce((
         select sum(reserva.quantidade_reservada)
           from public.pcp_op_reservas_componentes reserva
          where reserva.op_componente_id = comp.id
            and reserva.status = 'ativa'
       ), 0) <> comp.quantidade_planejada
  ) then
    raise exception 'OP active reservations must match planned component quantities before finish';
  end if;

  for v_output in
    select value from jsonb_array_elements(p_outputs_jsonb)
  loop
    v_tipo_produto := upper(nullif(trim(v_output->>'tipo_produto'), ''));
    if v_tipo_produto not in ('PA', 'PI') then
      raise exception 'invalid generated product type';
    end if;
    if nullif(trim(v_output->>'quantidade'), '') is null then
      raise exception 'generated product quantity is required';
    end if;
    v_quantidade := (v_output->>'quantidade')::numeric;
    if v_quantidade <= 0 then
      raise exception 'generated product quantity must be greater than zero';
    end if;

    if v_tipo_produto = 'PA' then
      if nullif(trim(v_output->>'produto_embalagem_id'), '') is null then
        raise exception 'PA output requires produto_embalagem_id';
      end if;
      v_output_target_id := (v_output->>'produto_embalagem_id')::bigint;
      select status
        into v_target_status
        from public.cad_produto_embalagens
       where id = v_output_target_id;
      if v_target_status is null then
        raise exception 'PA output produto_embalagem not found';
      end if;
      if v_target_status <> 'active' then
        raise exception 'PA output produto_embalagem status does not allow production entry';
      end if;
      v_need_pa_entry := true;
    else
      if nullif(trim(v_output->>'produto_id'), '') is null then
        raise exception 'PI output requires produto_id';
      end if;
      v_output_target_id := (v_output->>'produto_id')::bigint;
      select status
        into v_target_status
        from public.cad_produtos_base
       where id = v_output_target_id;
      if v_target_status is null then
        raise exception 'PI output produto not found';
      end if;
      if v_target_status <> 'active' then
        raise exception 'PI output produto status does not allow production entry';
      end if;
      v_need_pi_entry := true;
    end if;
  end loop;

  select exists (
    select 1
      from public.pcp_op_reservas_componentes reserva
     where reserva.op_id = p_op_id
       and reserva.status = 'ativa'
       and reserva.tipo_componente = 'MP'
  ) into v_need_mp_consume;

  select exists (
    select 1
      from public.pcp_op_reservas_componentes reserva
     where reserva.op_id = p_op_id
       and reserva.status = 'ativa'
       and reserva.tipo_componente = 'PA'
  ) into v_need_pa_consume;

  select exists (
    select 1
      from public.pcp_op_reservas_componentes reserva
     where reserva.op_id = p_op_id
       and reserva.status = 'ativa'
       and reserva.tipo_componente = 'PI'
  ) into v_need_pi_consume;

  if v_need_mp_consume then
    v_mp_consume_context := public.begin_audited_rpc(
      'estoque.mp.consume.op',
      'estoque',
      'pcp_ordens_producao',
      'movement_event',
      jsonb_build_object('familia', 'MP', 'event', 'consume', 'origem', 'op', 'correlation_id', v_correlation_id, 'source', 'finalizar_pcp_op')
    );
  end if;
  if v_need_pa_consume then
    v_pa_consume_context := public.begin_audited_rpc(
      'estoque.pa.consume.op',
      'estoque',
      'pcp_ordens_producao',
      'movement_event',
      jsonb_build_object('familia', 'PA', 'event', 'consume', 'origem', 'op', 'correlation_id', v_correlation_id, 'source', 'finalizar_pcp_op')
    );
  end if;
  if v_need_pi_consume then
    v_pi_consume_context := public.begin_audited_rpc(
      'estoque.pi.consume.op',
      'estoque',
      'pcp_ordens_producao',
      'movement_event',
      jsonb_build_object('familia', 'PI', 'event', 'consume', 'origem', 'op', 'correlation_id', v_correlation_id, 'source', 'finalizar_pcp_op')
    );
  end if;
  if v_need_pa_entry then
    v_pa_entry_context := public.begin_audited_rpc(
      'estoque.pa.entry.op',
      'estoque',
      'pcp_ordens_producao',
      'movement_event',
      jsonb_build_object('familia', 'PA', 'event', 'entry', 'origem', 'op', 'correlation_id', v_correlation_id, 'source', 'finalizar_pcp_op')
    );
  end if;
  if v_need_pi_entry then
    v_pi_entry_context := public.begin_audited_rpc(
      'estoque.pi.entry.op',
      'estoque',
      'pcp_ordens_producao',
      'movement_event',
      jsonb_build_object('familia', 'PI', 'event', 'entry', 'origem', 'op', 'correlation_id', v_correlation_id, 'source', 'finalizar_pcp_op')
    );
  end if;

  v_before := public.pcp_op_finish_audit_snapshot(p_op_id);
  v_actor := public.current_actor_id();
  v_status_lote := case
    when v_op.tipo_op in ('experimental', 'desenvolvimento') or p_cq_status <> 'aprovado' then 'bloqueado'
    else 'disponivel'
  end;
  v_tipo_entrada := case
    when v_op.tipo_op = 'reprocessamento' then 'transformacao_entrada'
    else 'entrada_producao'
  end;

  insert into public.pcp_op_cq_resultados(
    op_id,
    cq_status,
    ph,
    densidade_kg_l,
    volume_l,
    massa_kg,
    temperatura_c,
    separador_mp,
    conferente_mp,
    formuladores_json,
    observacao,
    created_by
  )
  values (
    p_op_id,
    p_cq_status,
    p_ph,
    p_densidade_kg_l,
    p_volume_l,
    p_massa_kg,
    p_temperatura_c,
    trim(p_separador_mp),
    trim(p_conferente_mp),
    p_formuladores_jsonb,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_cq_id;

  for v_reserva in
    select reserva.*, comp.materia_prima_id, comp.produto_embalagem_id, comp.produto_id
      from public.pcp_op_reservas_componentes reserva
      join public.pcp_op_componentes_planejados comp on comp.id = reserva.op_componente_id
     where reserva.op_id = p_op_id
       and reserva.status = 'ativa'
     order by reserva.op_componente_id, reserva.id
     for update of reserva
  loop
    if v_reserva.tipo_componente = 'MP' then
      insert into public.est_movimentos_mp(
        lote_mp_id,
        materia_prima_id,
        tipo_movimento,
        quantidade,
        origem_modulo,
        origem_tabela,
        origem_id,
        observacao,
        created_by
      )
      values (
        v_reserva.lote_mp_id,
        v_reserva.materia_prima_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_mp_status(v_reserva.lote_mp_id);
    elsif v_reserva.tipo_componente = 'PA' then
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
        v_reserva.produto_embalagem_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_pa_status(v_reserva.lote_pa_id);
    else
      insert into public.est_movimentos_pi(
        lote_pi_id,
        produto_id,
        tipo_movimento,
        quantidade,
        origem_modulo,
        origem_tabela,
        origem_id,
        observacao,
        created_by
      )
      values (
        v_reserva.lote_pi_id,
        v_reserva.produto_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_pi_status(v_reserva.lote_pi_id);
    end if;

    insert into public.pcp_op_consumos_componentes(
      op_id,
      op_componente_id,
      reserva_id,
      tipo_componente,
      lote_mp_id,
      lote_pa_id,
      lote_pi_id,
      quantidade_consumida,
      created_by
    )
    values (
      p_op_id,
      v_reserva.op_componente_id,
      v_reserva.id,
      v_reserva.tipo_componente,
      v_reserva.lote_mp_id,
      v_reserva.lote_pa_id,
      v_reserva.lote_pi_id,
      v_reserva.quantidade_reservada,
      v_actor
    );

    update public.pcp_op_reservas_componentes
       set status = 'baixada',
           updated_by = v_actor
     where id = v_reserva.id;

    update public.pcp_op_componentes_planejados
       set status = 'consumed'
     where id = v_reserva.op_componente_id;
  end loop;

  for v_output in
    select value from jsonb_array_elements(p_outputs_jsonb)
  loop
    v_tipo_produto := upper(nullif(trim(v_output->>'tipo_produto'), ''));
    v_quantidade := (v_output->>'quantidade')::numeric;

    if v_tipo_produto = 'PA' then
      insert into public.est_lotes_pa(
        produto_embalagem_id,
        codigo_lote,
        status,
        data_fabricacao,
        origem_ref,
        observacao,
        created_by,
        updated_by
      )
      values (
        (v_output->>'produto_embalagem_id')::bigint,
        public.next_est_codigo_lote('PA'),
        v_status_lote,
        current_date,
        v_correlation_id,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor,
        v_actor
      )
      returning id into v_lote_pa_id;

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
        v_lote_pa_id,
        (v_output->>'produto_embalagem_id')::bigint,
        v_tipo_entrada,
        v_quantidade,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );

      if v_status_lote <> 'bloqueado' then
        perform public.sync_est_lote_pa_status(v_lote_pa_id);
      end if;

      insert into public.pcp_op_produtos_gerados(
        op_id,
        tipo_produto,
        produto_embalagem_id,
        lote_pa_id,
        quantidade,
        status_lote,
        observacao,
        created_by
      )
      values (
        p_op_id,
        'PA',
        (v_output->>'produto_embalagem_id')::bigint,
        v_lote_pa_id,
        v_quantidade,
        v_status_lote,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );
    else
      insert into public.est_lotes_pi(
        produto_id,
        codigo_lote,
        status,
        data_fabricacao,
        origem_ref,
        observacao,
        created_by,
        updated_by
      )
      values (
        (v_output->>'produto_id')::bigint,
        public.next_est_codigo_lote('PI'),
        v_status_lote,
        current_date,
        v_correlation_id,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor,
        v_actor
      )
      returning id into v_lote_pi_id;

      insert into public.est_movimentos_pi(
        lote_pi_id,
        produto_id,
        tipo_movimento,
        quantidade,
        origem_modulo,
        origem_tabela,
        origem_id,
        observacao,
        created_by
      )
      values (
        v_lote_pi_id,
        (v_output->>'produto_id')::bigint,
        v_tipo_entrada,
        v_quantidade,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );

      if v_status_lote <> 'bloqueado' then
        perform public.sync_est_lote_pi_status(v_lote_pi_id);
      end if;

      insert into public.pcp_op_produtos_gerados(
        op_id,
        tipo_produto,
        produto_id,
        lote_pi_id,
        quantidade,
        status_lote,
        observacao,
        created_by
      )
      values (
        p_op_id,
        'PI',
        (v_output->>'produto_id')::bigint,
        v_lote_pi_id,
        v_quantidade,
        v_status_lote,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );
    end if;
  end loop;

  update public.pcp_ordens_producao
     set status = 'completed',
         cq_status = p_cq_status,
         completed_at = now(),
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_op_id;

  v_after := public.pcp_op_finish_audit_snapshot(p_op_id);

  perform public.log_audited_rpc_change(
    'pcp',
    'pcp_ordens_producao',
    p_op_id::text,
    'pcp.op_finished',
    'pcp.op.finish',
    v_finish_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'finalizar_pcp_op',
      'correlation_id', v_correlation_id,
      'cq_status', p_cq_status,
      'status_lote', v_status_lote,
      'outputs', jsonb_array_length(p_outputs_jsonb)
    ),
    'database_rpc'
  );

  perform public.log_audited_rpc_change(
    'pcp',
    'pcp_op_cq_resultados',
    v_cq_id::text,
    'pcp.cq_recorded',
    'pcp.cq.record',
    v_cq_context,
    v_before->'cq_resultados',
    v_after->'cq_resultados',
    jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id, 'cq_status', p_cq_status),
    'database_rpc'
  );

  if v_need_mp_consume then
    perform public.log_audited_rpc_change(
      'estoque',
      'pcp_ordens_producao',
      p_op_id::text,
      'estoque.mp_consumed_by_op',
      'estoque.mp.consume.op',
      v_mp_consume_context,
      jsonb_build_object('saldos', v_before->'mp_saldos', 'reservas', v_before->'reservas', 'movimentos', v_before->'movimentos_mp'),
      jsonb_build_object('saldos', v_after->'mp_saldos', 'reservas', v_after->'reservas', 'movimentos', v_after->'movimentos_mp'),
      jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id),
      'database_rpc'
    );
  end if;
  if v_need_pa_consume then
    perform public.log_audited_rpc_change(
      'estoque',
      'pcp_ordens_producao',
      p_op_id::text,
      'estoque.pa_consumed_by_op',
      'estoque.pa.consume.op',
      v_pa_consume_context,
      jsonb_build_object('saldos', v_before->'pa_saldos', 'reservas', v_before->'reservas', 'movimentos', v_before->'movimentos_pa'),
      jsonb_build_object('saldos', v_after->'pa_saldos', 'reservas', v_after->'reservas', 'movimentos', v_after->'movimentos_pa'),
      jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id),
      'database_rpc'
    );
  end if;
  if v_need_pi_consume then
    perform public.log_audited_rpc_change(
      'estoque',
      'pcp_ordens_producao',
      p_op_id::text,
      'estoque.pi_consumed_by_op',
      'estoque.pi.consume.op',
      v_pi_consume_context,
      jsonb_build_object('saldos', v_before->'pi_saldos', 'reservas', v_before->'reservas', 'movimentos', v_before->'movimentos_pi'),
      jsonb_build_object('saldos', v_after->'pi_saldos', 'reservas', v_after->'reservas', 'movimentos', v_after->'movimentos_pi'),
      jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id),
      'database_rpc'
    );
  end if;
  if v_need_pa_entry then
    perform public.log_audited_rpc_change(
      'estoque',
      'pcp_ordens_producao',
      p_op_id::text,
      'estoque.pa_entry_from_op',
      'estoque.pa.entry.op',
      v_pa_entry_context,
      jsonb_build_object('saldos', v_before->'pa_saldos', 'produtos_gerados', v_before->'produtos_gerados', 'movimentos', v_before->'movimentos_pa'),
      jsonb_build_object('saldos', v_after->'pa_saldos', 'produtos_gerados', v_after->'produtos_gerados', 'movimentos', v_after->'movimentos_pa'),
      jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id),
      'database_rpc'
    );
  end if;
  if v_need_pi_entry then
    perform public.log_audited_rpc_change(
      'estoque',
      'pcp_ordens_producao',
      p_op_id::text,
      'estoque.pi_entry_from_op',
      'estoque.pi.entry.op',
      v_pi_entry_context,
      jsonb_build_object('saldos', v_before->'pi_saldos', 'produtos_gerados', v_before->'produtos_gerados', 'movimentos', v_before->'movimentos_pi'),
      jsonb_build_object('saldos', v_after->'pi_saldos', 'produtos_gerados', v_after->'produtos_gerados', 'movimentos', v_after->'movimentos_pi'),
      jsonb_build_object('source', 'finalizar_pcp_op', 'correlation_id', v_correlation_id, 'op_id', p_op_id),
      'database_rpc'
    );
  end if;

  return p_op_id;
end;
$$;

create or replace function public.liberar_pcp_lote_bloqueado(
  p_tipo_lote text,
  p_lote_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_tipo_lote text;
  v_before jsonb;
  v_after jsonb;
  v_status_after text;
  v_permission_context jsonb;
  v_correlation_id text;
begin
  v_tipo_lote := upper(nullif(trim(p_tipo_lote), ''));
  if v_tipo_lote not in ('PA', 'PI') then
    raise exception 'tipo_lote must be PA or PI';
  end if;
  if p_lote_id is null or p_lote_id <= 0 then
    raise exception 'lote_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_correlation_id := concat('pcp_lote:', v_tipo_lote, ':', p_lote_id::text, ':release');
  v_permission_context := public.begin_audited_rpc(
    'pcp.blocked_lot.release',
    'pcp',
    case when v_tipo_lote = 'PA' then 'est_lotes_pa' else 'est_lotes_pi' end,
    'status_transition',
    jsonb_build_object(
      'event', 'release_blocked_lot',
      'tipo_lote', v_tipo_lote,
      'correlation_id', v_correlation_id,
      'source', 'liberar_pcp_lote_bloqueado'
    )
  );

  v_actor := public.current_actor_id();

  if v_tipo_lote = 'PA' then
    select jsonb_build_object(
      'lote', to_jsonb(lote),
      'produtos_gerados', coalesce((
        select jsonb_agg(to_jsonb(produto) order by produto.id)
          from public.pcp_op_produtos_gerados produto
         where produto.lote_pa_id = p_lote_id
      ), '[]'::jsonb)
    )
      into v_before
      from public.est_lotes_pa lote
     where lote.id = p_lote_id
       and lote.status = 'bloqueado'
     for update;

    if v_before is null then
      raise exception 'blocked lot not found';
    end if;

    update public.est_lotes_pa
       set status = 'disponivel',
           updated_by = v_actor,
           observacao = concat_ws(' | ', observacao, concat('liberado: ', trim(p_motivo)))
     where id = p_lote_id;

    perform public.sync_est_lote_pa_status(p_lote_id);

    select status
      into v_status_after
      from public.est_lotes_pa
     where id = p_lote_id;

    update public.pcp_op_produtos_gerados
       set status_lote = v_status_after
     where lote_pa_id = p_lote_id;

    select jsonb_build_object(
      'lote', to_jsonb(lote),
      'produtos_gerados', coalesce((
        select jsonb_agg(to_jsonb(produto) order by produto.id)
          from public.pcp_op_produtos_gerados produto
         where produto.lote_pa_id = p_lote_id
      ), '[]'::jsonb)
    )
      into v_after
      from public.est_lotes_pa lote
     where lote.id = p_lote_id;
  else
    select jsonb_build_object(
      'lote', to_jsonb(lote),
      'produtos_gerados', coalesce((
        select jsonb_agg(to_jsonb(produto) order by produto.id)
          from public.pcp_op_produtos_gerados produto
         where produto.lote_pi_id = p_lote_id
      ), '[]'::jsonb)
    )
      into v_before
      from public.est_lotes_pi lote
     where lote.id = p_lote_id
       and lote.status = 'bloqueado'
     for update;

    if v_before is null then
      raise exception 'blocked lot not found';
    end if;

    update public.est_lotes_pi
       set status = 'disponivel',
           updated_by = v_actor,
           observacao = concat_ws(' | ', observacao, concat('liberado: ', trim(p_motivo)))
     where id = p_lote_id;

    perform public.sync_est_lote_pi_status(p_lote_id);

    select status
      into v_status_after
      from public.est_lotes_pi
     where id = p_lote_id;

    update public.pcp_op_produtos_gerados
       set status_lote = v_status_after
     where lote_pi_id = p_lote_id;

    select jsonb_build_object(
      'lote', to_jsonb(lote),
      'produtos_gerados', coalesce((
        select jsonb_agg(to_jsonb(produto) order by produto.id)
          from public.pcp_op_produtos_gerados produto
         where produto.lote_pi_id = p_lote_id
      ), '[]'::jsonb)
    )
      into v_after
      from public.est_lotes_pi lote
     where lote.id = p_lote_id;
  end if;

  perform public.log_audited_rpc_change(
    'pcp',
    case when v_tipo_lote = 'PA' then 'est_lotes_pa' else 'est_lotes_pi' end,
    p_lote_id::text,
    'pcp.lote_bloqueado_liberado',
    'pcp.blocked_lot.release',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'liberar_pcp_lote_bloqueado',
      'correlation_id', v_correlation_id,
      'tipo_lote', v_tipo_lote,
      'motivo', trim(p_motivo),
      'legacy_action_key', 'pcp.experimental.release'
    ),
    'database_rpc'
  );

  return p_lote_id;
end;
$$;

comment on function public.liberar_pcp_lote_bloqueado(text, bigint, text) is
  'Libera lote PA/PI bloqueado gerado por OP. A OP permanece completed; a decisao operacional e sobre o lote fisico bloqueado. Exige pcp.blocked_lot.release.';

revoke all on function public.log_rpc_failed(text, text, text, text, text, text, jsonb, jsonb) from public;
grant execute on function public.log_rpc_failed(text, text, text, text, text, text, jsonb, jsonb) to authenticated;

revoke all on function public.pcp_op_finish_audit_snapshot(bigint) from public;

revoke all on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) from public;
grant execute on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) to authenticated;

revoke all on function public.liberar_pcp_lote_bloqueado(text, bigint, text) from public;
grant execute on function public.liberar_pcp_lote_bloqueado(text, bigint, text) to authenticated;
