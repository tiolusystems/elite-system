insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.post_payment_reversal', 'pedidos', 'Registrar devolucao/estorno operacional de pedido ja cumprido com comissao paga', true, 111)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

alter table public.fat_notas_fiscais
  add column if not exists nota_devolvida_id bigint references public.fat_notas_fiscais(id);

alter table public.fat_nota_fiscal_itens
  add column if not exists nota_item_devolvido_id bigint references public.fat_nota_fiscal_itens(id);

create index if not exists idx_fat_nf_devolvida
  on public.fat_notas_fiscais(nota_devolvida_id)
  where nota_devolvida_id is not null;

create index if not exists idx_fat_nf_itens_devolvidos
  on public.fat_nota_fiscal_itens(nota_item_devolvido_id)
  where nota_item_devolvido_id is not null;

comment on column public.fat_notas_fiscais.nota_devolvida_id is
  'Usado apenas para NF de devolucao -> NF original devolvida. Nao usar para remessa vinculada ou complemento.';

comment on column public.fat_nota_fiscal_itens.nota_item_devolvido_id is
  'Item fiscal original devolvido. Permite reconciliar devolucao parcial sem editar a NF original.';

alter table public.fat_notas_fiscais
  drop constraint if exists fat_notas_fiscais_tipo_check;

alter table public.fat_notas_fiscais
  add constraint fat_notas_fiscais_tipo_check check (
    tipo in ('remessa_total', 'simples_faturamento', 'remessa_vinculada', 'complementar', 'devolucao')
  );

alter table public.fat_notas_fiscais
  drop constraint if exists fat_notas_fiscais_ref_exclusiva_check;

alter table public.fat_notas_fiscais
  add constraint fat_notas_fiscais_ref_exclusiva_check check (
    num_nonnulls(nota_pai_id, nota_complementada_id, nota_devolvida_id) <= 1
  );

alter table public.fat_notas_fiscais
  drop constraint if exists fat_notas_fiscais_tipo_ref_check;

alter table public.fat_notas_fiscais
  add constraint fat_notas_fiscais_tipo_ref_check check (
    (
      tipo = 'remessa_total'
      and romaneio_id is not null
      and nota_pai_id is null
      and nota_complementada_id is null
      and nota_devolvida_id is null
    )
    or (
      tipo = 'simples_faturamento'
      and romaneio_id is null
      and nota_pai_id is null
      and nota_complementada_id is null
      and nota_devolvida_id is null
    )
    or (
      tipo = 'remessa_vinculada'
      and romaneio_id is not null
      and nota_pai_id is not null
      and nota_complementada_id is null
      and nota_devolvida_id is null
    )
    or (
      tipo = 'complementar'
      and romaneio_id is null
      and nota_pai_id is null
      and nota_complementada_id is not null
      and nota_devolvida_id is null
    )
    or (
      tipo = 'devolucao'
      and romaneio_id is null
      and nota_pai_id is null
      and nota_complementada_id is null
      and nota_devolvida_id is not null
    )
  );

comment on column public.fat_nota_fiscal_eventos.payload_json is
  'Contrato por tipo_evento: emitida(protocolo_autorizacao, ambiente; para devolucao, incluir motivo_devolucao e nota_devolvida_id), cancelada(protocolo_cancelamento, justificativa), carta_correcao(sequencia_cce, texto_correcao), substituida(nota_substituta_id, motivo_substituicao), inutilizada(numero_inicial, numero_final, protocolo_inutilizacao, justificativa), complementada(nota_complementar_id, motivo_complemento).';

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
      'pedido_status_preserved', true,
      'commission_status_preserved', true,
      'correlation_id', concat('pedido:', p_pedido_id::text, ':post_payment_reversal:', v_nota_devolucao_id::text)
    )
  );

  return v_nota_devolucao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) from public;
grant execute on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) to authenticated;
