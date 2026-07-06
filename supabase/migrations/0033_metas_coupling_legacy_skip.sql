create or replace function public.cancelar_com_pedido(
  p_pedido_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_before jsonb;
  v_after jsonb;
  v_meta_movimentos_count integer := 0;
  v_meta_cancel_applied boolean := false;
  v_meta_skip_reason text;
  v_target_correlation_id text;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_target_correlation_id := concat('pedido:', p_pedido_id::text, ':target_cancel');

  v_permission_context := public.begin_audited_rpc(
    'pedidos.cancel',
    'pedidos',
    'com_pedidos',
    'status_transition',
    jsonb_build_object('event', 'cancel', 'correlation_id', v_target_correlation_id)
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status in ('cancelled', 'fulfilled') then
    raise exception 'pedido status does not allow cancellation';
  end if;
  if exists (
    select 1
      from public.exp_romaneios romaneio
     where romaneio.pedido_id = p_pedido_id
       and romaneio.status not in ('cancelado', 'estornado')
  ) then
    raise exception 'pedido has active romaneio; cancel romaneio first';
  end if;
  if exists (
    select 1
      from public.fat_notas_fiscais nota
     where nota.pedido_id = p_pedido_id
       and nota.status_atual not in ('cancelada', 'inutilizada')
  ) then
    raise exception 'pedido has active nota fiscal; cancel fiscal document first';
  end if;
  if exists (
    select 1
      from public.com_recebimentos recebimento
     where recebimento.pedido_id = p_pedido_id
       and coalesce(recebimento.status, 'active') = 'active'
  ) then
    raise exception 'pedido has active receipt; reverse receipt first';
  end if;
  if exists (
    select 1
      from public.com_pedido_comissionados comissionado
     where comissionado.pedido_id = p_pedido_id
       and comissionado.status = 'paga'
  ) or exists (
    select 1
      from public.fin_comissao_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'debito_pagamento'
  ) then
    raise exception 'pedido has paid commission; use post-payment reversal flow';
  end if;
  if exists (
    select 1
      from public.pcp_ordens_producao op
     where op.pedido_id = p_pedido_id
       and op.status in ('draft', 'planned', 'in_process')
  ) then
    raise exception 'pedido has active OP; cancel OP first';
  end if;

  perform public.validate_com_pedido_status_transition(v_pedido.status, 'cancelled', 'cancel');

  v_actor := public.current_actor_id();
  v_before := public.com_pedido_audit_snapshot(p_pedido_id);

  update public.com_pedidos
     set status = 'cancelled',
         updated_by = v_actor
   where id = p_pedido_id;

  update public.com_pedido_itens
     set status = 'cancelled',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status = 'active';

  update public.com_pedido_comissionados
     set status = 'cancelada',
         updated_by = v_actor
   where pedido_id = p_pedido_id
     and status in ('prevista', 'bloqueada');

  if exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'venda_aberta'
  ) then
    v_meta_movimentos_count := public.registrar_com_meta_cancelamento_pedido(
      p_pedido_id,
      'cancelamento_pedido',
      trim(p_motivo),
      current_date
    );
    v_meta_cancel_applied := true;
  else
    v_meta_skip_reason := 'sem_venda_aberta_no_ledger';
  end if;

  v_after := public.com_pedido_audit_snapshot(p_pedido_id);

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    p_pedido_id::text,
    'pedidos.pedido_cancelado',
    'pedidos.cancel',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'cancelar_com_pedido',
      'pedido_id', p_pedido_id,
      'motivo', trim(p_motivo),
      'motivo_codigo_meta', 'cancelamento_pedido',
      'status_anterior', v_pedido.status,
      'status_resultante', 'cancelled',
      'meta_cancel_applied', v_meta_cancel_applied,
      'meta_movimentos_count', v_meta_movimentos_count,
      'meta_skip_reason', v_meta_skip_reason,
      'correlation_id', v_target_correlation_id
    )
  );

  return p_pedido_id;
end;
$$;

create or replace function public.registrar_com_meta_devolucao_nf(
  p_nota_fiscal_devolucao_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_nota record;
  v_periodo_id bigint;
  v_motivo_devolucao text;
  v_before jsonb;
  v_after jsonb;
  v_item record;
  v_venda record;
  v_movimento_id bigint;
  v_valor_meta numeric;
  v_quantidade_meta numeric;
  v_movimentos jsonb := '[]'::jsonb;
  v_itens_sem_venda_aberta jsonb := '[]'::jsonb;
  v_pessoa_ids bigint[] := array[]::bigint[];
  v_item_sales_count integer;
  v_count integer := 0;
begin
  if p_nota_fiscal_devolucao_id is null or p_nota_fiscal_devolucao_id <= 0 then
    raise exception 'nota_fiscal_devolucao_id is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'metas.returns.register',
    'metas',
    'com_meta_movimentos',
    'target_event',
    jsonb_build_object('event', 'fiscal_return', 'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id)
  );

  select *
    into v_nota
    from public.fat_notas_fiscais
   where id = p_nota_fiscal_devolucao_id
   for update;

  if v_nota.id is null then
    raise exception 'nota fiscal devolucao not found';
  end if;
  if v_nota.tipo <> 'devolucao' then
    raise exception 'nota fiscal must be devolucao to register target return';
  end if;
  if v_nota.status_atual not in ('emitida') then
    raise exception 'nota fiscal devolucao status does not allow target return';
  end if;

  select lower(nullif(trim(evento.payload_json->>'motivo_devolucao'), ''))
    into v_motivo_devolucao
    from public.fat_nota_fiscal_eventos evento
   where evento.nota_fiscal_id = p_nota_fiscal_devolucao_id
     and evento.tipo_evento = 'emitida'
   order by evento.data_evento desc, evento.id desc
   limit 1;

  if v_motivo_devolucao is null then
    raise exception 'motivo_devolucao is required in fiscal return event payload';
  end if;
  if v_motivo_devolucao not in ('qualidade', 'avaria_transporte', 'erro_separacao', 'erro_comercial', 'acordo_comercial', 'outro') then
    raise exception 'invalid motivo_devolucao';
  end if;
  if exists (
    select 1
      from public.com_meta_movimentos movimento
     where movimento.nota_fiscal_id = p_nota_fiscal_devolucao_id
       and movimento.tipo_movimento = 'devolucao'
  ) then
    raise exception 'meta return already registered for nota fiscal';
  end if;

  v_periodo_id := public.resolve_com_meta_periodo(v_nota.data_emissao);
  v_actor := public.current_actor_id();
  v_before := jsonb_build_object(
    'nota_devolucao', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_devolucao_id),
    'motivo_devolucao', v_motivo_devolucao,
    'periodo_id', v_periodo_id
  );

  if v_motivo_devolucao = 'qualidade' then
    v_after := v_before || jsonb_build_object(
      'qualidade_sem_penalizacao', true,
      'movimentos', '[]'::jsonb
    );

    perform public.log_audited_rpc_change(
      'metas',
      'com_meta_movimentos',
      p_nota_fiscal_devolucao_id::text,
      'metas.devolucao_qualidade_sem_abatimento',
      'metas.returns.register',
      v_permission_context,
      v_before,
      v_after,
      jsonb_build_object(
        'source', 'registrar_com_meta_devolucao_nf',
        'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
        'motivo_devolucao', v_motivo_devolucao,
        'movimentos_count', 0,
        'itens_sem_venda_aberta', '[]'::jsonb,
        'itens_sem_venda_aberta_count', 0,
        'correlation_id', concat('nota_fiscal:', p_nota_fiscal_devolucao_id::text, ':target_return')
      )
    );

    return 0;
  end if;

  for v_item in
    select
      item_devolucao.id as nota_fiscal_item_id,
      item_devolucao.pedido_id,
      item_devolucao.pedido_item_id,
      item_devolucao.quantidade,
      item_devolucao.valor_item,
      item_origem.quantidade as quantidade_origem,
      item_origem.valor_item as valor_origem
    from public.fat_nota_fiscal_itens item_devolucao
    join public.fat_nota_fiscal_itens item_origem on item_origem.id = item_devolucao.nota_item_devolvido_id
   where item_devolucao.nota_fiscal_id = p_nota_fiscal_devolucao_id
   order by item_devolucao.id
  loop
    v_item_sales_count := 0;

    for v_venda in
      select *
        from public.com_meta_movimentos movimento
       where movimento.pedido_id = v_item.pedido_id
         and movimento.tipo_movimento = 'venda_aberta'
         and (
           movimento.pedido_item_id = v_item.pedido_item_id
           or movimento.pedido_item_id is null
         )
       order by movimento.id
    loop
      v_item_sales_count := v_item_sales_count + 1;
      perform public.lock_com_meta_pessoa_periodo(v_periodo_id, v_venda.pessoa_id);

      if coalesce(v_item.valor_origem, 0) > 0 then
        v_valor_meta := -1 * abs(v_venda.valor_meta) * least(v_item.valor_item / v_item.valor_origem, 1);
      elsif coalesce(v_item.quantidade_origem, 0) > 0 then
        v_valor_meta := -1 * abs(v_venda.valor_meta) * least(v_item.quantidade / v_item.quantidade_origem, 1);
      else
        raise exception 'returned item has no proportional base for target ledger';
      end if;
      v_quantidade_meta := case
        when v_venda.quantidade_meta is null or v_item.quantidade_origem is null or v_item.quantidade_origem = 0 then null
        else -1 * abs(v_venda.quantidade_meta) * least(v_item.quantidade / v_item.quantidade_origem, 1)
      end;

      if v_valor_meta = 0 then
        continue;
      end if;

      insert into public.com_meta_movimentos(
        periodo_id,
        pessoa_id,
        comissionado_id,
        pedido_id,
        pedido_item_id,
        nota_fiscal_id,
        nota_fiscal_item_id,
        tipo_movimento,
        papel_meta,
        valor_meta,
        quantidade_meta,
        data_evento,
        data_competencia,
        origem_modulo,
        origem_tabela,
        origem_id,
        motivo_codigo,
        motivo_detalhe,
        memoria_calculo_json,
        created_by
      )
      values (
        v_periodo_id,
        v_venda.pessoa_id,
        v_venda.comissionado_id,
        v_item.pedido_id,
        v_item.pedido_item_id,
        p_nota_fiscal_devolucao_id,
        v_item.nota_fiscal_item_id,
        'devolucao',
        v_venda.papel_meta,
        v_valor_meta,
        v_quantidade_meta,
        v_nota.data_emissao,
        v_nota.data_emissao,
        'devolucao_fiscal',
        'fat_nota_fiscal_itens',
        v_item.nota_fiscal_item_id::text,
        v_motivo_devolucao,
        null,
        jsonb_build_object(
          'source', 'registrar_com_meta_devolucao_nf',
          'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
          'nota_fiscal_item_devolucao_id', v_item.nota_fiscal_item_id,
          'venda_movimento_id', v_venda.id,
          'period_rule', 'data_evento',
          'devolucao_abate_periodo_vigente', true
        ),
        v_actor
      )
      returning id into v_movimento_id;

      v_count := v_count + 1;
      v_pessoa_ids := array_append(v_pessoa_ids, v_venda.pessoa_id);
      v_movimentos := v_movimentos || jsonb_build_array(jsonb_build_object(
        'movimento_id', v_movimento_id,
        'venda_movimento_id', v_venda.id,
        'nota_fiscal_item_id', v_item.nota_fiscal_item_id,
        'pessoa_id', v_venda.pessoa_id,
        'valor_meta', v_valor_meta
      ));
    end loop;

    if v_item_sales_count = 0 then
      v_itens_sem_venda_aberta := v_itens_sem_venda_aberta || jsonb_build_array(jsonb_build_object(
        'nota_fiscal_item_id', v_item.nota_fiscal_item_id,
        'pedido_id', v_item.pedido_id,
        'pedido_item_id', v_item.pedido_item_id,
        'motivo', 'sem_venda_aberta_no_ledger'
      ));
    end if;
  end loop;

  if v_count = 0 and jsonb_array_length(v_itens_sem_venda_aberta) = 0 then
    raise exception 'no target return movements were generated';
  end if;

  v_after := jsonb_build_object(
    'nota_devolucao', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_devolucao_id),
    'periodo_id', v_periodo_id,
    'motivo_devolucao', v_motivo_devolucao,
    'movimentos', v_movimentos,
    'itens_sem_venda_aberta', v_itens_sem_venda_aberta,
    'itens_sem_venda_aberta_count', jsonb_array_length(v_itens_sem_venda_aberta),
    'saldos_after', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.pessoa_id, saldo.papel_meta)
        from public.com_meta_saldos_pessoa_periodo saldo
       where saldo.periodo_id = v_periodo_id
         and saldo.pessoa_id = any(v_pessoa_ids)
    ), '[]'::jsonb)
  );

  perform public.log_audited_rpc_change(
    'metas',
    'com_meta_movimentos',
    p_nota_fiscal_devolucao_id::text,
    'metas.devolucao_registrada',
    'metas.returns.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_meta_devolucao_nf',
      'nota_fiscal_devolucao_id', p_nota_fiscal_devolucao_id,
      'periodo_id', v_periodo_id,
      'motivo_devolucao', v_motivo_devolucao,
      'movimentos_count', v_count,
      'itens_sem_venda_aberta', v_itens_sem_venda_aberta,
      'itens_sem_venda_aberta_count', jsonb_array_length(v_itens_sem_venda_aberta),
      'correlation_id', concat('nota_fiscal:', p_nota_fiscal_devolucao_id::text, ':target_return')
    )
  );

  return v_count;
end;
$$;

create or replace function public.registrar_com_pedido_estorno_pos_pagamento(
  p_pedido_id bigint,
  p_nota_fiscal_origem_id bigint,
  p_itens_jsonb jsonb,
  p_motivo_devolucao text,
  p_chave_nfe text default null,
  p_numero text default null,
  p_serie text default null,
  p_data_emissao date default current_date,
  p_payload_json jsonb default '{}'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_pedido record;
  v_nota_origem record;
  v_item_json jsonb;
  v_nf_item_origem record;
  v_lote record;
  v_nota_fiscal_item_id bigint;
  v_lote_pa_id bigint;
  v_quantidade numeric;
  v_valor_item numeric;
  v_quantidade_devolvida_anterior numeric;
  v_valor_nf numeric := 0;
  v_prepared_items jsonb := '[]'::jsonb;
  v_prepared_item jsonb;
  v_lote_ids bigint[] := array[]::bigint[];
  v_movimentos_pa jsonb := '[]'::jsonb;
  v_motivo_devolucao text;
  v_payload_json jsonb;
  v_nota_devolucao_id bigint;
  v_nf_item_devolucao_id bigint;
  v_movimento_pa_id bigint;
  v_meta_return_movimentos_count integer := 0;
  v_target_correlation_id text;
  v_pedido_correlation_id text;
  v_before jsonb;
  v_after jsonb;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_nota_fiscal_origem_id is null or p_nota_fiscal_origem_id <= 0 then
    raise exception 'nota_fiscal_origem_id is required';
  end if;
  if p_itens_jsonb is null or jsonb_typeof(p_itens_jsonb) <> 'array' or jsonb_array_length(p_itens_jsonb) = 0 then
    raise exception 'itens_jsonb must be a non-empty array';
  end if;
  if p_data_emissao is null then
    raise exception 'data_emissao is required';
  end if;

  v_motivo_devolucao := lower(nullif(trim(p_motivo_devolucao), ''));
  if v_motivo_devolucao not in ('qualidade', 'avaria_transporte', 'erro_separacao', 'erro_comercial', 'acordo_comercial', 'outro') then
    raise exception 'invalid motivo_devolucao';
  end if;
  if v_motivo_devolucao = 'outro' and nullif(trim(p_observacao), '') is null then
    raise exception 'observacao is required when motivo_devolucao is outro';
  end if;

  v_payload_json := coalesce(p_payload_json, '{}'::jsonb);
  if jsonb_typeof(v_payload_json) <> 'object' then
    raise exception 'payload_json must be a json object';
  end if;
  if v_payload_json = '{}'::jsonb then
    v_payload_json := jsonb_build_object(
      'protocolo_autorizacao', 'manual-pos-pagamento',
      'ambiente', 'interno'
    );
  end if;
  v_payload_json := v_payload_json || jsonb_build_object(
    'motivo_devolucao', v_motivo_devolucao,
    'nota_devolvida_id', p_nota_fiscal_origem_id
  );
  perform public.fat_validate_event_payload('emitida', v_payload_json);

  v_permission_context := public.begin_audited_rpc(
    'pedidos.post_payment_reversal',
    'pedidos',
    'com_pedidos',
    'fiscal_event',
    jsonb_build_object(
      'event', 'post_payment_reversal',
      'motivo_devolucao', v_motivo_devolucao,
      'nota_fiscal_origem_id', p_nota_fiscal_origem_id
    )
  );

  select *
    into v_pedido
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if v_pedido.id is null then
    raise exception 'pedido not found';
  end if;
  if v_pedido.status <> 'fulfilled' then
    raise exception 'pedido must remain fulfilled; post-payment reversal requires fulfilled status';
  end if;
  if v_pedido.tipo_pedido <> 'venda' then
    raise exception 'only venda pedido allows post-payment reversal';
  end if;
  if not exists (
    select 1
      from public.com_pedido_comissionados comissionado
     where comissionado.pedido_id = p_pedido_id
       and comissionado.status = 'paga'
  ) and not exists (
    select 1
      from public.fin_comissao_movimentos movimento
     where movimento.pedido_id = p_pedido_id
       and movimento.tipo_movimento = 'debito_pagamento'
  ) then
    raise exception 'pedido has no paid commission; use unpaid cancellation or return flow';
  end if;

  select *
    into v_nota_origem
    from public.fat_notas_fiscais
   where id = p_nota_fiscal_origem_id
   for update;

  if v_nota_origem.id is null then
    raise exception 'nota fiscal origem not found';
  end if;
  if v_nota_origem.pedido_id <> p_pedido_id then
    raise exception 'nota fiscal origem does not belong to pedido';
  end if;
  if v_nota_origem.status_atual <> 'emitida' then
    raise exception 'nota fiscal origem status does not allow return';
  end if;
  if v_nota_origem.tipo not in ('remessa_total', 'simples_faturamento', 'remessa_vinculada', 'complementar') then
    raise exception 'nota fiscal origem type does not allow return';
  end if;

  v_before := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'nota_origem', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_origem_id),
    'pa_saldos', '[]'::jsonb
  );

  for v_item_json in
    select value from jsonb_array_elements(p_itens_jsonb)
  loop
    if jsonb_typeof(v_item_json) <> 'object' then
      raise exception 'each return item must be a json object';
    end if;

    v_nota_fiscal_item_id := coalesce(
      nullif(trim(v_item_json->>'nota_fiscal_item_id'), '')::bigint,
      nullif(trim(v_item_json->>'nf_item_id'), '')::bigint
    );
    v_lote_pa_id := nullif(trim(v_item_json->>'lote_pa_id'), '')::bigint;
    v_quantidade := nullif(trim(v_item_json->>'quantidade'), '')::numeric;
    v_valor_item := case
      when nullif(trim(v_item_json->>'valor_item'), '') is null then null
      else (v_item_json->>'valor_item')::numeric
    end;

    if v_nota_fiscal_item_id is null or v_nota_fiscal_item_id <= 0 then
      raise exception 'nota_fiscal_item_id is required';
    end if;
    if v_lote_pa_id is null or v_lote_pa_id <= 0 then
      raise exception 'lote_pa_id is required';
    end if;
    if v_quantidade is null or v_quantidade <= 0 then
      raise exception 'quantidade must be greater than zero';
    end if;

    select
        nf_item.id,
        nf_item.nota_fiscal_id,
        nf_item.pedido_id,
        nf_item.pedido_item_id,
        nf_item.produto_embalagem_id,
        nf_item.quantidade,
        nf_item.valor_item,
        pedido_item.status as pedido_item_status
      into v_nf_item_origem
      from public.fat_nota_fiscal_itens nf_item
      join public.com_pedido_itens pedido_item on pedido_item.id = nf_item.pedido_item_id
     where nf_item.id = v_nota_fiscal_item_id
     for update of nf_item, pedido_item;

    if v_nf_item_origem.id is null then
      raise exception 'nota fiscal item origem not found';
    end if;
    if v_nf_item_origem.nota_fiscal_id <> p_nota_fiscal_origem_id then
      raise exception 'nota fiscal item origem does not belong to nota fiscal origem';
    end if;
    if v_nf_item_origem.pedido_id <> p_pedido_id then
      raise exception 'nota fiscal item origem does not belong to pedido';
    end if;
    if v_nf_item_origem.pedido_item_status <> 'active' then
      raise exception 'pedido item origem status does not allow return';
    end if;

    select *
      into v_lote
      from public.est_lotes_pa
     where id = v_lote_pa_id
     for update;

    if v_lote.id is null then
      raise exception 'PA lot not found';
    end if;
    if v_lote.status = 'cancelado' then
      raise exception 'cancelled PA lot does not allow return';
    end if;
    if v_lote.produto_embalagem_id <> v_nf_item_origem.produto_embalagem_id then
      raise exception 'PA lot product does not match returned fiscal item';
    end if;

    select coalesce(sum(item_devolucao.quantidade), 0)
      into v_quantidade_devolvida_anterior
      from public.fat_nota_fiscal_itens item_devolucao
      join public.fat_notas_fiscais nf_devolucao on nf_devolucao.id = item_devolucao.nota_fiscal_id
     where item_devolucao.nota_item_devolvido_id = v_nota_fiscal_item_id
       and nf_devolucao.tipo = 'devolucao'
       and nf_devolucao.status_atual not in ('cancelada', 'inutilizada');

    if v_quantidade_devolvida_anterior + v_quantidade > v_nf_item_origem.quantidade then
      raise exception 'return quantity exceeds original fiscal item quantity';
    end if;

    v_valor_item := coalesce(
      v_valor_item,
      case
        when v_nf_item_origem.quantidade > 0 then (v_nf_item_origem.valor_item / v_nf_item_origem.quantidade) * v_quantidade
        else 0
      end
    );
    if v_valor_item < 0 then
      raise exception 'valor_item must be greater than or equal to zero';
    end if;

    v_prepared_items := v_prepared_items || jsonb_build_array(jsonb_build_object(
      'nota_fiscal_item_id', v_nota_fiscal_item_id,
      'pedido_item_id', v_nf_item_origem.pedido_item_id,
      'produto_embalagem_id', v_nf_item_origem.produto_embalagem_id,
      'lote_pa_id', v_lote_pa_id,
      'quantidade', v_quantidade,
      'valor_item', v_valor_item,
      'quantidade_devolvida_anterior', v_quantidade_devolvida_anterior
    ));
    v_valor_nf := v_valor_nf + v_valor_item;
    v_lote_ids := array_append(v_lote_ids, v_lote_pa_id);
  end loop;

  v_actor := public.current_actor_id();

  insert into public.fat_notas_fiscais(
    pedido_id,
    nota_devolvida_id,
    chave_nfe,
    numero,
    serie,
    data_emissao,
    valor_nf,
    tipo,
    status_atual,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_pedido_id,
    p_nota_fiscal_origem_id,
    nullif(trim(p_chave_nfe), ''),
    nullif(trim(p_numero), ''),
    nullif(trim(p_serie), ''),
    p_data_emissao,
    v_valor_nf,
    'devolucao',
    'emitida',
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_nota_devolucao_id;

  for v_prepared_item in
    select value from jsonb_array_elements(v_prepared_items)
  loop
    insert into public.fat_nota_fiscal_itens(
      nota_fiscal_id,
      pedido_id,
      pedido_item_id,
      nota_item_devolvido_id,
      produto_embalagem_id,
      quantidade,
      valor_item
    )
    values (
      v_nota_devolucao_id,
      p_pedido_id,
      (v_prepared_item->>'pedido_item_id')::bigint,
      (v_prepared_item->>'nota_fiscal_item_id')::bigint,
      (v_prepared_item->>'produto_embalagem_id')::bigint,
      (v_prepared_item->>'quantidade')::numeric,
      (v_prepared_item->>'valor_item')::numeric
    )
    returning id into v_nf_item_devolucao_id;

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
      (v_prepared_item->>'lote_pa_id')::bigint,
      (v_prepared_item->>'produto_embalagem_id')::bigint,
      'estorno_saida',
      (v_prepared_item->>'quantidade')::numeric,
      'devolucao_pedido',
      'fat_notas_fiscais',
      v_nota_devolucao_id::text,
      coalesce(nullif(trim(p_observacao), ''), concat('devolucao pos-pagamento: ', v_motivo_devolucao)),
      v_actor
    )
    returning id into v_movimento_pa_id;

    perform public.sync_est_lote_pa_status((v_prepared_item->>'lote_pa_id')::bigint);

    v_movimentos_pa := v_movimentos_pa || jsonb_build_array(jsonb_build_object(
      'movimento_pa_id', v_movimento_pa_id,
      'nota_fiscal_item_id', v_nf_item_devolucao_id,
      'nota_item_devolvido_id', (v_prepared_item->>'nota_fiscal_item_id')::bigint,
      'lote_pa_id', (v_prepared_item->>'lote_pa_id')::bigint,
      'produto_embalagem_id', (v_prepared_item->>'produto_embalagem_id')::bigint,
      'quantidade', (v_prepared_item->>'quantidade')::numeric,
      'tipo_movimento', 'estorno_saida'
    ));
  end loop;

  insert into public.fat_nota_fiscal_eventos(
    nota_fiscal_id,
    tipo_evento,
    data_evento,
    motivo,
    payload_json,
    created_by
  )
  values (
    v_nota_devolucao_id,
    'emitida',
    now(),
    coalesce(nullif(trim(p_observacao), ''), concat('devolucao pos-pagamento: ', v_motivo_devolucao)),
    v_payload_json,
    v_actor
  );

  v_meta_return_movimentos_count := public.registrar_com_meta_devolucao_nf(v_nota_devolucao_id);
  v_target_correlation_id := concat('nota_fiscal:', v_nota_devolucao_id::text, ':target_return');
  v_pedido_correlation_id := concat('pedido:', p_pedido_id::text, ':post_payment_reversal:', v_nota_devolucao_id::text);

  v_after := jsonb_build_object(
    'pedido', public.com_pedido_audit_snapshot(p_pedido_id),
    'nota_origem', public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_origem_id),
    'nota_devolucao', public.fat_nota_fiscal_audit_snapshot(v_nota_devolucao_id),
    'pa_saldos', coalesce((
      select jsonb_agg(to_jsonb(saldo) order by saldo.lote_pa_id)
        from public.est_lotes_pa_saldos saldo
       where saldo.lote_pa_id = any(v_lote_ids)
    ), '[]'::jsonb),
    'movimentos_pa', v_movimentos_pa,
    'meta_return_movimentos_count', v_meta_return_movimentos_count,
    'pedido_status_after', (
      select pedido.status from public.com_pedidos pedido where pedido.id = p_pedido_id
    )
  );

  perform public.log_audited_rpc_change(
    'pedidos',
    'com_pedidos',
    p_pedido_id::text,
    'pedidos.estorno_pos_pagamento_registrado',
    'pedidos.post_payment_reversal',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_com_pedido_estorno_pos_pagamento',
      'pedido_id', p_pedido_id,
      'nota_fiscal_origem_id', p_nota_fiscal_origem_id,
      'nota_fiscal_devolucao_id', v_nota_devolucao_id,
      'motivo_devolucao', v_motivo_devolucao,
      'valor_nf_devolucao', v_valor_nf,
      'itens', jsonb_array_length(v_prepared_items),
      'movimentos_pa', v_movimentos_pa,
      'meta_return_movimentos_count', v_meta_return_movimentos_count,
      'pedido_status_preserved', true,
      'commission_status_preserved', true,
      'correlation_id', v_target_correlation_id,
      'pedido_correlation_id', v_pedido_correlation_id
    )
  );

  return v_nota_devolucao_id;
end;
$$;

revoke all on function public.cancelar_com_pedido(bigint, text) from public;
revoke all on function public.registrar_com_meta_devolucao_nf(bigint) from public;
revoke all on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) from public;

grant execute on function public.cancelar_com_pedido(bigint, text) to authenticated;
grant execute on function public.registrar_com_meta_devolucao_nf(bigint) to authenticated;
grant execute on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) to authenticated;
