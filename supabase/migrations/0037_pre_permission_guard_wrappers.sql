-- Pre-permission wrappers.
-- These wrappers prevent unauthorized actors from receiving parameter/status
-- validation details before the permission denial.

alter function public.cancelar_com_pedido(bigint, text)
  rename to cancelar_com_pedido_impl_0037;

create or replace function public.cancelar_com_pedido(
  p_pedido_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.cancel');
  return public.cancelar_com_pedido_impl_0037(p_pedido_id, p_motivo);
end;
$$;

alter function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text)
  rename to create_com_pedido_operacional_impl_0037;

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_action_key text;
begin
  v_actor := public.current_actor_id();

  if p_vendedor_id is not null and exists (
    select 1
      from public.cad_pessoas_comerciais vendedor
     where vendedor.id = p_vendedor_id
       and vendedor.user_profile_id = v_actor
  ) then
    v_action_key := 'pedidos.create.own';
  else
    v_action_key := 'pedidos.create.any';
  end if;

  perform public.require_current_user_permission(v_action_key);

  return public.create_com_pedido_operacional_impl_0037(
    p_cliente_id,
    p_produto_embalagem_id,
    p_quantidade,
    p_valor_unitario,
    p_propriedade_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    p_vendedor_id,
    p_percentual_comissao,
    p_observacao
  );
end;
$$;

alter function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text)
  rename to create_com_pedido_troca_impl_0037;

create or replace function public.create_com_pedido_troca(
  p_pedido_origem_id bigint,
  p_pedido_item_origem_id bigint,
  p_produto_embalagem_id bigint default null,
  p_quantidade numeric default null,
  p_status text default 'open',
  p_data_pedido date default current_date,
  p_motivo_troca text default 'qualidade',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.exchange.create');
  return public.create_com_pedido_troca_impl_0037(
    p_pedido_origem_id,
    p_pedido_item_origem_id,
    p_produto_embalagem_id,
    p_quantidade,
    p_status,
    p_data_pedido,
    p_motivo_troca,
    p_observacao
  );
end;
$$;

alter function public.create_pcp_formula_versao(bigint, text, text, jsonb, text)
  rename to create_pcp_formula_versao_impl_0037;

create or replace function public.create_pcp_formula_versao(
  p_produto_id bigint,
  p_tipo_receita text,
  p_justificativa text,
  p_componentes_jsonb jsonb default '[]'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_count integer;
begin
  select count(*)
    into v_existing_count
    from public.pcp_formula_versoes
   where produto_id = p_produto_id
     and tipo_receita = p_tipo_receita;

  if v_existing_count = 0 then
    perform public.require_current_user_permission('pcp.formula.create');
  else
    perform public.require_current_user_permission('pcp.formula.change');
  end if;

  return public.create_pcp_formula_versao_impl_0037(
    p_produto_id,
    p_tipo_receita,
    p_justificativa,
    p_componentes_jsonb,
    p_observacao
  );
end;
$$;

alter function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text)
  rename to emitir_fat_nota_fiscal_impl_0037;

create or replace function public.emitir_fat_nota_fiscal(
  p_pedido_id bigint,
  p_tipo text,
  p_itens_jsonb jsonb,
  p_chave_nfe text default null,
  p_numero text default null,
  p_serie text default null,
  p_data_emissao date default current_date,
  p_valor_nf numeric default 0,
  p_romaneio_id bigint default null,
  p_nota_pai_id bigint default null,
  p_nota_complementada_id bigint default null,
  p_payload_json jsonb default '{}'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('faturamento.nf.issue');
  return public.emitir_fat_nota_fiscal_impl_0037(
    p_pedido_id,
    p_tipo,
    p_itens_jsonb,
    p_chave_nfe,
    p_numero,
    p_serie,
    p_data_emissao,
    p_valor_nf,
    p_romaneio_id,
    p_nota_pai_id,
    p_nota_complementada_id,
    p_payload_json,
    p_observacao
  );
end;
$$;

alter function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text)
  rename to finalizar_pcp_op_impl_0037;

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
begin
  perform public.require_current_user_permission('pcp.op.finish');
  return public.finalizar_pcp_op_impl_0037(
    p_op_id,
    p_outputs_jsonb,
    p_cq_status,
    p_ph,
    p_densidade_kg_l,
    p_volume_l,
    p_massa_kg,
    p_temperatura_c,
    p_separador_mp,
    p_conferente_mp,
    p_formuladores_jsonb,
    p_observacao
  );
end;
$$;

alter function public.liberar_fin_comissoes_recebimento(bigint)
  rename to liberar_fin_comissoes_recebimento_impl_0037;

create or replace function public.liberar_fin_comissoes_recebimento(p_recebimento_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('financeiro.commissions.release');
  return public.liberar_fin_comissoes_recebimento_impl_0037(p_recebimento_id);
end;
$$;

alter function public.liberar_pcp_lote_bloqueado(text, bigint, text)
  rename to liberar_pcp_lote_bloqueado_impl_0037;

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
begin
  perform public.require_current_user_permission('pcp.blocked_lot.release');
  return public.liberar_pcp_lote_bloqueado_impl_0037(p_tipo_lote, p_lote_id, p_motivo);
end;
$$;

alter function public.registrar_com_meta_ajuste_manual(bigint, bigint, numeric, text, text, jsonb)
  rename to registrar_com_meta_ajuste_manual_impl_0037;

create or replace function public.registrar_com_meta_ajuste_manual(
  p_periodo_id bigint,
  p_pessoa_id bigint,
  p_valor_meta numeric,
  p_motivo_codigo text,
  p_motivo_detalhe text default null,
  p_memoria_calculo_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('metas.adjust');
  return public.registrar_com_meta_ajuste_manual_impl_0037(
    p_periodo_id,
    p_pessoa_id,
    p_valor_meta,
    p_motivo_codigo,
    p_motivo_detalhe,
    p_memoria_calculo_json
  );
end;
$$;

alter function public.registrar_com_meta_cancelamento_pedido(bigint, text, text, date)
  rename to registrar_com_meta_cancelamento_pedido_impl_0037;

create or replace function public.registrar_com_meta_cancelamento_pedido(
  p_pedido_id bigint,
  p_motivo_codigo text default 'cancelamento_pedido',
  p_motivo_detalhe text default null,
  p_data_evento date default current_date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('metas.cancellations.register');
  return public.registrar_com_meta_cancelamento_pedido_impl_0037(
    p_pedido_id,
    p_motivo_codigo,
    p_motivo_detalhe,
    p_data_evento
  );
end;
$$;

alter function public.registrar_com_meta_devolucao_nf(bigint)
  rename to registrar_com_meta_devolucao_nf_impl_0037;

create or replace function public.registrar_com_meta_devolucao_nf(p_nota_fiscal_devolucao_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('metas.returns.register');
  return public.registrar_com_meta_devolucao_nf_impl_0037(p_nota_fiscal_devolucao_id);
end;
$$;

alter function public.registrar_com_meta_venda_aberta(bigint)
  rename to registrar_com_meta_venda_aberta_impl_0037;

create or replace function public.registrar_com_meta_venda_aberta(p_pedido_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('metas.sales.register');
  return public.registrar_com_meta_venda_aberta_impl_0037(p_pedido_id);
end;
$$;

alter function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  rename to registrar_com_pedido_decisao_credito_impl_0037;

create or replace function public.registrar_com_pedido_decisao_credito(
  p_pedido_id bigint,
  p_decisao text,
  p_motivo text default null,
  p_limite_disponivel_snapshot numeric default null,
  p_inadimplencia_snapshot numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.credit.review');
  return public.registrar_com_pedido_decisao_credito_impl_0037(
    p_pedido_id,
    p_decisao,
    p_motivo,
    p_limite_disponivel_snapshot,
    p_inadimplencia_snapshot,
    p_observacao
  );
end;
$$;

alter function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text)
  rename to registrar_com_pedido_estorno_pos_pagamento_impl_0037;

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
begin
  perform public.require_current_user_permission('pedidos.post_payment_reversal');
  return public.registrar_com_pedido_estorno_pos_pagamento_impl_0037(
    p_pedido_id,
    p_nota_fiscal_origem_id,
    p_itens_jsonb,
    p_motivo_devolucao,
    p_chave_nfe,
    p_numero,
    p_serie,
    p_data_emissao,
    p_payload_json,
    p_observacao
  );
end;
$$;

alter function public.registrar_fat_nota_fiscal_evento(bigint, text, text, jsonb)
  rename to registrar_fat_nota_fiscal_evento_impl_0037;

create or replace function public.registrar_fat_nota_fiscal_evento(
  p_nota_fiscal_id bigint,
  p_tipo_evento text,
  p_motivo text,
  p_payload_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo_evento text;
  v_action_key text;
begin
  v_tipo_evento := nullif(trim(p_tipo_evento), '');

  if v_tipo_evento = 'emitida' then
    v_action_key := 'faturamento.nf.issue';
  elsif v_tipo_evento in ('cancelada', 'inutilizada') then
    v_action_key := 'faturamento.nf.cancel';
  elsif v_tipo_evento = 'carta_correcao' then
    v_action_key := 'faturamento.nf.correct';
  elsif v_tipo_evento = 'substituida' then
    v_action_key := 'faturamento.nf.substitute';
  elsif v_tipo_evento = 'complementada' then
    v_action_key := 'faturamento.nf.complement';
  else
    v_action_key := 'faturamento.nf.issue';
  end if;

  perform public.require_current_user_permission(v_action_key);

  return public.registrar_fat_nota_fiscal_evento_impl_0037(
    p_nota_fiscal_id,
    p_tipo_evento,
    p_motivo,
    p_payload_json
  );
end;
$$;

alter function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb)
  rename to registrar_fin_comissao_ajuste_impl_0037;

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
begin
  perform public.require_current_user_permission('financeiro.commissions.adjust');
  return public.registrar_fin_comissao_ajuste_impl_0037(
    p_pessoa_id,
    p_valor_ajuste,
    p_motivo,
    p_referencia_json
  );
end;
$$;

alter function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text)
  rename to registrar_fin_comissao_pagamento_impl_0037;

create or replace function public.registrar_fin_comissao_pagamento(
  p_pessoa_id bigint,
  p_valor_pago numeric,
  p_data_pagamento date default current_date,
  p_forma_pagamento text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('financeiro.commissions.pay');
  return public.registrar_fin_comissao_pagamento_impl_0037(
    p_pessoa_id,
    p_valor_pago,
    p_data_pagamento,
    p_forma_pagamento,
    p_motivo
  );
end;
$$;

alter function public.registrar_fin_recebimento_alocado(bigint, numeric, date, text, text, jsonb)
  rename to registrar_fin_recebimento_alocado_impl_0037;

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
begin
  perform public.require_current_user_permission('financeiro.receipts.register');
  return public.registrar_fin_recebimento_alocado_impl_0037(
    p_cliente_id,
    p_valor_recebido,
    p_data_recebimento,
    p_forma_recebimento,
    p_observacao,
    p_alocacoes_json
  );
end;
$$;

alter function public.upsert_com_meta_periodo(text, text, date, date, text, text)
  rename to upsert_com_meta_periodo_impl_0037;

create or replace function public.upsert_com_meta_periodo(
  p_codigo text,
  p_nome text,
  p_data_inicio date,
  p_data_fim date,
  p_status text default 'active',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('metas.periods.manage');
  return public.upsert_com_meta_periodo_impl_0037(
    p_codigo,
    p_nome,
    p_data_inicio,
    p_data_fim,
    p_status,
    p_observacao
  );
end;
$$;

revoke all on function public.cancelar_com_pedido_impl_0037(bigint, text) from public, authenticated;
revoke all on function public.create_com_pedido_operacional_impl_0037(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public, authenticated;
revoke all on function public.create_com_pedido_troca_impl_0037(bigint, bigint, bigint, numeric, text, date, text, text) from public, authenticated;
revoke all on function public.create_pcp_formula_versao_impl_0037(bigint, text, text, jsonb, text) from public, authenticated;
revoke all on function public.emitir_fat_nota_fiscal_impl_0037(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) from public, authenticated;
revoke all on function public.finalizar_pcp_op_impl_0037(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) from public, authenticated;
revoke all on function public.liberar_fin_comissoes_recebimento_impl_0037(bigint) from public, authenticated;
revoke all on function public.liberar_pcp_lote_bloqueado_impl_0037(text, bigint, text) from public, authenticated;
revoke all on function public.registrar_com_meta_ajuste_manual_impl_0037(bigint, bigint, numeric, text, text, jsonb) from public, authenticated;
revoke all on function public.registrar_com_meta_cancelamento_pedido_impl_0037(bigint, text, text, date) from public, authenticated;
revoke all on function public.registrar_com_meta_devolucao_nf_impl_0037(bigint) from public, authenticated;
revoke all on function public.registrar_com_meta_venda_aberta_impl_0037(bigint) from public, authenticated;
revoke all on function public.registrar_com_pedido_decisao_credito_impl_0037(bigint, text, text, numeric, numeric, text) from public, authenticated;
revoke all on function public.registrar_com_pedido_estorno_pos_pagamento_impl_0037(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) from public, authenticated;
revoke all on function public.registrar_fat_nota_fiscal_evento_impl_0037(bigint, text, text, jsonb) from public, authenticated;
revoke all on function public.registrar_fin_comissao_ajuste_impl_0037(bigint, numeric, text, jsonb) from public, authenticated;
revoke all on function public.registrar_fin_comissao_pagamento_impl_0037(bigint, numeric, date, text, text) from public, authenticated;
revoke all on function public.registrar_fin_recebimento_alocado_impl_0037(bigint, numeric, date, text, text, jsonb) from public, authenticated;
revoke all on function public.upsert_com_meta_periodo_impl_0037(text, text, date, date, text, text) from public, authenticated;

revoke all on function public.cancelar_com_pedido(bigint, text) from public;
revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) from public;
revoke all on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) from public;
revoke all on function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) from public;
revoke all on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) from public;
revoke all on function public.liberar_fin_comissoes_recebimento(bigint) from public;
revoke all on function public.liberar_pcp_lote_bloqueado(text, bigint, text) from public;
revoke all on function public.registrar_com_meta_ajuste_manual(bigint, bigint, numeric, text, text, jsonb) from public;
revoke all on function public.registrar_com_meta_cancelamento_pedido(bigint, text, text, date) from public;
revoke all on function public.registrar_com_meta_devolucao_nf(bigint) from public;
revoke all on function public.registrar_com_meta_venda_aberta(bigint) from public;
revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) from public;
revoke all on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) from public;
revoke all on function public.registrar_fat_nota_fiscal_evento(bigint, text, text, jsonb) from public;
revoke all on function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb) from public;
revoke all on function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text) from public;
revoke all on function public.registrar_fin_recebimento_alocado(bigint, numeric, date, text, text, jsonb) from public;
revoke all on function public.upsert_com_meta_periodo(text, text, date, date, text, text) from public;

grant execute on function public.cancelar_com_pedido(bigint, text) to authenticated;
grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text) to authenticated;
grant execute on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) to authenticated;
grant execute on function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) to authenticated;
grant execute on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) to authenticated;
grant execute on function public.liberar_fin_comissoes_recebimento(bigint) to authenticated;
grant execute on function public.liberar_pcp_lote_bloqueado(text, bigint, text) to authenticated;
grant execute on function public.registrar_com_meta_ajuste_manual(bigint, bigint, numeric, text, text, jsonb) to authenticated;
grant execute on function public.registrar_com_meta_cancelamento_pedido(bigint, text, text, date) to authenticated;
grant execute on function public.registrar_com_meta_devolucao_nf(bigint) to authenticated;
grant execute on function public.registrar_com_meta_venda_aberta(bigint) to authenticated;
grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) to authenticated;
grant execute on function public.registrar_com_pedido_estorno_pos_pagamento(bigint, bigint, jsonb, text, text, text, text, date, jsonb, text) to authenticated;
grant execute on function public.registrar_fat_nota_fiscal_evento(bigint, text, text, jsonb) to authenticated;
grant execute on function public.registrar_fin_comissao_ajuste(bigint, numeric, text, jsonb) to authenticated;
grant execute on function public.registrar_fin_comissao_pagamento(bigint, numeric, date, text, text) to authenticated;
grant execute on function public.registrar_fin_recebimento_alocado(bigint, numeric, date, text, text, jsonb) to authenticated;
grant execute on function public.upsert_com_meta_periodo(text, text, date, date, text, text) to authenticated;
