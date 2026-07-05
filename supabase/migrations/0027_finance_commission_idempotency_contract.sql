create unique index if not exists idx_com_comissao_liberacoes_alocacao_comissionado_once
  on public.com_comissao_liberacoes(alocacao_id, comissionado_id)
  where status = 'liberada' and alocacao_id is not null;

create unique index if not exists idx_fin_comissao_movimentos_liberacao_credit_once
  on public.fin_comissao_movimentos(liberacao_id, tipo_movimento)
  where tipo_movimento = 'credito_liberacao' and liberacao_id is not null;

alter table public.fin_comissao_movimentos
  add column if not exists motivo_codigo text;

do $$
begin
  alter table public.fin_comissao_movimentos
    add constraint fin_comissao_movimentos_motivo_codigo_check check (
      tipo_movimento <> 'ajuste_manual'
      or motivo_codigo in (
        'correcao_calculo',
        'estorno_devolucao',
        'acordo_comercial',
        'compensacao_futura',
        'outro'
      )
    );
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  alter table public.fin_comissao_movimentos
    add constraint fin_comissao_movimentos_outro_detalhe_check check (
      tipo_movimento <> 'ajuste_manual'
      or motivo_codigo <> 'outro'
      or nullif(trim(memoria_calculo_json->>'motivo_detalhe'), '') is not null
    );
exception
  when duplicate_object then null;
end;
$$;

comment on column public.fin_comissao_movimentos.motivo_codigo is
  'Motivo padronizado para ajuste manual de comissao: correcao_calculo, estorno_devolucao, acordo_comercial, compensacao_futura ou outro com motivo_detalhe.';

create or replace function public.liberar_fin_comissoes_recebimento(p_recebimento_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_recebimento record;
  v_alocacao record;
  v_comissionado record;
  v_liberacao_id bigint;
  v_movimento_id bigint;
  v_percentual_recebido numeric;
  v_valor_liberar numeric;
  v_release_after jsonb;
  v_total_liberacoes integer := 0;
begin
  if p_recebimento_id is null or p_recebimento_id <= 0 then
    raise exception 'recebimento_id is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.release',
    'financeiro',
    'com_comissao_liberacoes',
    'financial_event',
    jsonb_build_object('event', 'commission_release')
  );

  v_actor := public.current_actor_id();

  select *
    into v_recebimento
    from public.com_recebimentos
   where id = p_recebimento_id
   for update;

  if v_recebimento.id is null then
    raise exception 'recebimento not found';
  end if;
  if v_recebimento.status <> 'active' then
    raise exception 'receipt status does not allow commission release';
  end if;

  for v_alocacao in
    select
      alocacao.id,
      alocacao.recebimento_id,
      alocacao.pedido_id,
      alocacao.nota_fiscal_id,
      alocacao.valor_alocado,
      pedido.valor_total as pedido_valor_total,
      pedido.tipo_pedido as pedido_tipo,
      pedido.status as pedido_status
    from public.fin_recebimento_alocacoes alocacao
    join public.com_pedidos pedido on pedido.id = alocacao.pedido_id
    where alocacao.recebimento_id = p_recebimento_id
    order by alocacao.id
    for update of alocacao
  loop
    if exists (
      select 1
        from public.com_comissao_liberacoes liberacao
       where liberacao.alocacao_id = v_alocacao.id
         and liberacao.status = 'liberada'
    ) then
      raise exception 'comissao_ja_liberada_para_este_recebimento';
    end if;

    if v_alocacao.pedido_status in ('draft', 'blocked', 'cancelled') then
      raise exception 'pedido status does not allow commission release';
    end if;
    if v_alocacao.pedido_tipo <> 'venda' or v_alocacao.pedido_valor_total <= 0 then
      raise exception 'pedido does not allow commission release';
    end if;

    v_percentual_recebido := least(v_alocacao.valor_alocado / v_alocacao.pedido_valor_total, 1);

    for v_comissionado in
      select id, pessoa_id, valor_previsto
        from public.com_pedido_comissionados
       where pedido_id = v_alocacao.pedido_id
         and status in ('prevista', 'liberada')
         and valor_previsto > 0
       order by id
    loop
      v_valor_liberar := v_comissionado.valor_previsto * v_percentual_recebido;

      if v_valor_liberar > 0 then
        insert into public.com_comissao_liberacoes(
          recebimento_id,
          alocacao_id,
          pedido_id,
          comissionado_id,
          pessoa_id,
          valor_liberado,
          percentual_recebido_snapshot,
          status,
          memoria_calculo_json,
          correlation_id,
          created_by
        )
        values (
          p_recebimento_id,
          v_alocacao.id,
          v_alocacao.pedido_id,
          v_comissionado.id,
          v_comissionado.pessoa_id,
          v_valor_liberar,
          v_percentual_recebido,
          'liberada',
          jsonb_build_object(
            'modelo_calculo', 'incremental_por_evento',
            'valor_previsto_total', v_comissionado.valor_previsto,
            'valor_alocado_recebimento', v_alocacao.valor_alocado,
            'valor_liberado_neste_recebimento', v_valor_liberar,
            'percentual_recebido_snapshot', v_percentual_recebido,
            'correlation_id', v_recebimento.correlation_id
          ),
          v_recebimento.correlation_id,
          v_actor
        )
        returning id into v_liberacao_id;

        insert into public.fin_comissao_movimentos(
          pessoa_id,
          pedido_id,
          recebimento_id,
          alocacao_id,
          liberacao_id,
          tipo_movimento,
          valor,
          memoria_calculo_json,
          created_by
        )
        values (
          v_comissionado.pessoa_id,
          v_alocacao.pedido_id,
          p_recebimento_id,
          v_alocacao.id,
          v_liberacao_id,
          'credito_liberacao',
          v_valor_liberar,
          jsonb_build_object(
            'source', 'liberar_fin_comissoes_recebimento',
            'modelo_calculo', 'incremental_por_evento',
            'correlation_id', v_recebimento.correlation_id,
            'comissionado_id', v_comissionado.id,
            'percentual_recebido_snapshot', v_percentual_recebido
          ),
          v_actor
        )
        returning id into v_movimento_id;

        update public.com_pedido_comissionados
           set status = 'liberada',
               updated_by = v_actor
         where id = v_comissionado.id;

        select jsonb_build_object(
          'liberacao', to_jsonb(liberacao),
          'movimento', to_jsonb(movimento)
        )
          into v_release_after
          from public.com_comissao_liberacoes liberacao
          join public.fin_comissao_movimentos movimento on movimento.id = v_movimento_id
         where liberacao.id = v_liberacao_id;

        perform public.log_audited_rpc_change(
          'financeiro',
          'com_comissao_liberacoes',
          v_liberacao_id::text,
          'financeiro.comissao_liberada',
          'financeiro.commissions.release',
          v_permission_context || jsonb_build_object(
            'correlation_id', v_recebimento.correlation_id,
            'receipt_action_key', 'financeiro.receipts.register',
            'alocacao_id', v_alocacao.id
          ),
          null,
          v_release_after,
          jsonb_build_object(
            'source', 'liberar_fin_comissoes_recebimento',
            'correlation_id', v_recebimento.correlation_id,
            'recebimento_id', p_recebimento_id,
            'alocacao_id', v_alocacao.id,
            'pedido_id', v_alocacao.pedido_id,
            'pessoa_id', v_comissionado.pessoa_id,
            'valor_liberado', v_valor_liberar,
            'modelo_calculo', 'incremental_por_evento'
          )
        );

        v_total_liberacoes := v_total_liberacoes + 1;
      end if;
    end loop;
  end loop;

  return v_total_liberacoes;
end;
$$;

create or replace function public.registrar_fin_recebimento_alocado(
  p_cliente_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date default current_date,
  p_forma_recebimento text default null,
  p_observacao text default null,
  p_alocacoes_json jsonb default '[]'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_recebimento_id bigint;
  v_cliente_id bigint;
  v_primeiro_pedido_id bigint;
  v_primeira_nf_id bigint;
  v_total_alocado numeric := 0;
  v_total_recebido_anterior numeric;
  v_allocation jsonb;
  v_pedido_id bigint;
  v_nota_fiscal_id bigint;
  v_valor_alocado numeric;
  v_pedido record;
  v_nota record;
  v_after jsonb;
  v_liberacoes integer;
  v_correlation_id text;
begin
  if p_valor_recebido is null or p_valor_recebido <= 0 then
    raise exception 'valor_recebido must be greater than zero';
  end if;
  if p_data_recebimento is null then
    raise exception 'data_recebimento is required';
  end if;
  if p_alocacoes_json is null or jsonb_typeof(p_alocacoes_json) <> 'array' or jsonb_array_length(p_alocacoes_json) = 0 then
    raise exception 'alocacoes_json must be a non-empty array';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.receipts.register',
    'financeiro',
    'com_recebimentos',
    'financial_event',
    jsonb_build_object('event', 'receipt_register')
  );

  v_actor := public.current_actor_id();
  v_cliente_id := p_cliente_id;

  for v_allocation in
    select value from jsonb_array_elements(p_alocacoes_json)
  loop
    if jsonb_typeof(v_allocation) <> 'object' then
      raise exception 'each allocation must be a json object';
    end if;

    v_pedido_id := nullif(trim(v_allocation->>'pedido_id'), '')::bigint;
    v_nota_fiscal_id := nullif(trim(v_allocation->>'nota_fiscal_id'), '')::bigint;
    v_valor_alocado := nullif(trim(v_allocation->>'valor_alocado'), '')::numeric;

    if v_pedido_id is null or v_pedido_id <= 0 then
      raise exception 'allocation pedido_id is required';
    end if;
    if v_valor_alocado is null or v_valor_alocado <= 0 then
      raise exception 'allocation valor_alocado must be greater than zero';
    end if;

    select id, cliente_id, tipo_pedido, status, valor_total
      into v_pedido
      from public.com_pedidos
     where id = v_pedido_id
     for update;

    if v_pedido.id is null then
      raise exception 'pedido not found';
    end if;
    if v_pedido.status in ('draft', 'blocked', 'cancelled') then
      raise exception 'pedido status does not allow receipt';
    end if;
    if v_pedido.tipo_pedido <> 'venda' or v_pedido.valor_total <= 0 then
      raise exception 'pedido does not allow receipt';
    end if;

    if v_cliente_id is null then
      v_cliente_id := v_pedido.cliente_id;
    elsif v_cliente_id <> v_pedido.cliente_id then
      raise exception 'all receipt allocations must belong to the same cliente';
    end if;

    if v_nota_fiscal_id is not null then
      select id, pedido_id, tipo, status_atual
        into v_nota
        from public.fat_notas_fiscais
       where id = v_nota_fiscal_id
       for update;

      if v_nota.id is null then
        raise exception 'nota fiscal not found';
      end if;
      if v_nota.pedido_id <> v_pedido_id then
        raise exception 'nota fiscal does not belong to allocation pedido';
      end if;
      if v_nota.status_atual <> 'emitida' then
        raise exception 'nota fiscal status does not allow receipt allocation';
      end if;
      if v_nota.tipo = 'remessa_vinculada' then
        raise exception 'linked remittance invoice cannot be commission payment base';
      end if;
    end if;

    select coalesce(sum(valor_alocado), 0)
      into v_total_recebido_anterior
      from public.fin_recebimento_alocacoes
     where pedido_id = v_pedido_id;

    if v_total_recebido_anterior + v_valor_alocado > v_pedido.valor_total then
      raise exception 'receipt exceeds order balance';
    end if;

    if v_primeiro_pedido_id is null then
      v_primeiro_pedido_id := v_pedido_id;
    end if;
    if v_primeira_nf_id is null then
      v_primeira_nf_id := v_nota_fiscal_id;
    end if;

    v_total_alocado := v_total_alocado + v_valor_alocado;
  end loop;

  if abs(v_total_alocado - p_valor_recebido) > 0.0001 then
    raise exception 'sum of allocations must match valor_recebido';
  end if;

  v_correlation_id := 'fin_recebimento:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || ':' || upper(substr(md5(random()::text), 1, 6));

  insert into public.com_recebimentos(
    pedido_id,
    cliente_id,
    nota_fiscal_id,
    valor_recebido,
    data_recebimento,
    forma_recebimento,
    observacao,
    status,
    correlation_id,
    created_by
  )
  values (
    case when jsonb_array_length(p_alocacoes_json) = 1 then v_primeiro_pedido_id else null end,
    v_cliente_id,
    case when jsonb_array_length(p_alocacoes_json) = 1 then v_primeira_nf_id else null end,
    p_valor_recebido,
    p_data_recebimento,
    nullif(trim(p_forma_recebimento), ''),
    nullif(trim(p_observacao), ''),
    'active',
    v_correlation_id,
    v_actor
  )
  returning id into v_recebimento_id;

  for v_allocation in
    select value from jsonb_array_elements(p_alocacoes_json)
  loop
    v_pedido_id := nullif(trim(v_allocation->>'pedido_id'), '')::bigint;
    v_nota_fiscal_id := nullif(trim(v_allocation->>'nota_fiscal_id'), '')::bigint;
    v_valor_alocado := nullif(trim(v_allocation->>'valor_alocado'), '')::numeric;

    insert into public.fin_recebimento_alocacoes(
      recebimento_id,
      pedido_id,
      nota_fiscal_id,
      valor_alocado,
      tipo_alocacao,
      origem,
      memoria_calculo_json,
      created_by
    )
    values (
      v_recebimento_id,
      v_pedido_id,
      v_nota_fiscal_id,
      v_valor_alocado,
      'recebimento',
      case when v_nota_fiscal_id is null then 'pedido' else 'nota_fiscal' end,
      jsonb_build_object(
        'valor_recebido_total', p_valor_recebido,
        'valor_alocado', v_valor_alocado,
        'correlation_id', v_correlation_id
      ),
      v_actor
    );
  end loop;

  v_liberacoes := public.liberar_fin_comissoes_recebimento(v_recebimento_id);
  v_after := public.fin_recebimento_snapshot(v_recebimento_id);

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_recebimentos',
    v_recebimento_id::text,
    'financeiro.recebimento_registrado',
    'financeiro.receipts.register',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fin_recebimento_alocado',
      'correlation_id', v_correlation_id,
      'cliente_id', v_cliente_id,
      'total_alocado', v_total_alocado,
      'alocacoes_count', jsonb_array_length(p_alocacoes_json),
      'liberacoes_count', v_liberacoes,
      'commission_action_key', 'financeiro.commissions.release'
    )
  );

  return v_recebimento_id;
end;
$$;

create or replace function public.registrar_fin_comissao_ajuste(
  p_pessoa_id bigint,
  p_valor_ajuste numeric,
  p_motivo text,
  p_referencia_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
  v_motivo_codigo text;
  v_motivo_detalhe text;
  v_referencia jsonb;
begin
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_valor_ajuste is null or p_valor_ajuste = 0 then
    raise exception 'valor_ajuste must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;
  if p_referencia_json is not null and jsonb_typeof(p_referencia_json) <> 'object' then
    raise exception 'referencia_json must be a json object';
  end if;

  v_motivo_codigo := lower(nullif(trim(p_motivo), ''));
  v_referencia := coalesce(p_referencia_json, '{}'::jsonb);
  v_motivo_detalhe := nullif(trim(v_referencia->>'motivo_detalhe'), '');

  if v_motivo_codigo not in ('correcao_calculo', 'estorno_devolucao', 'acordo_comercial', 'compensacao_futura', 'outro') then
    raise exception 'invalid motivo_codigo';
  end if;
  if v_motivo_codigo = 'outro' and v_motivo_detalhe is null then
    raise exception 'motivo_detalhe is required when motivo_codigo is outro';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.adjust',
    'financeiro',
    'fin_comissao_movimentos',
    'financial_event',
    jsonb_build_object('event', 'commission_manual_adjustment', 'motivo_codigo', v_motivo_codigo)
  );

  v_actor := public.current_actor_id();
  v_before := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  if v_before is null then
    raise exception 'pessoa not found';
  end if;

  insert into public.fin_comissao_movimentos(
    pessoa_id,
    tipo_movimento,
    valor,
    motivo,
    motivo_codigo,
    memoria_calculo_json,
    created_by
  )
  values (
    p_pessoa_id,
    'ajuste_manual',
    p_valor_ajuste,
    coalesce(v_motivo_detalhe, v_motivo_codigo),
    v_motivo_codigo,
    v_referencia || jsonb_build_object('motivo_codigo', v_motivo_codigo),
    v_actor
  )
  returning id into v_movimento_id;

  v_after := public.fin_comissao_saldo_snapshot(p_pessoa_id);

  perform public.log_audited_rpc_change(
    'financeiro',
    'fin_comissao_movimentos',
    v_movimento_id::text,
    'financeiro.comissao_ajustada',
    'financeiro.commissions.adjust',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fin_comissao_ajuste',
      'pessoa_id', p_pessoa_id,
      'valor_ajuste', p_valor_ajuste,
      'motivo_codigo', v_motivo_codigo
    )
  );

  return v_movimento_id;
end;
$$;

revoke all on function public.liberar_fin_comissoes_recebimento(bigint) from public;
grant execute on function public.liberar_fin_comissoes_recebimento(bigint) to authenticated;
