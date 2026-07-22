"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_TIPO_PEDIDO = new Set(["venda", "bonificacao", "devolucao", "mostruario"]);
const ALLOWED_MOTIVO_TROCA = new Set(["qualidade", "avaria_transporte", "erro_separacao", "erro_comercial", "acordo_comercial", "outro"]);
const DECIMAL_SEPARATOR = /,/g;

export async function criarPedidoComercialAction(formData: FormData) {
  const tipoPedido = field(formData, "tipo_pedido") || "venda";
  if (tipoPedido === "troca") {
    return criarTrocaPedidoAction(formData);
  }
  if (["mostruario", "bonificacao"].includes(tipoPedido)) {
    return criarPedidoEspecialVendedorAction(formData);
  }
  if (tipoPedido !== "venda") {
    redirect("/pedidos?result=invalid_order_type#novo-pedido");
  }
  return criarPedidoVendedorAction(formData);
}

export async function criarPedidoEspecialVendedorAction(formData: FormData) {
  const idempotencyKey = uuid(formData, "idempotency_key");
  const vinculoId = optionalInteger(formData, "cliente_vendedor_vinculo_id");
  const produtoEmbalagemId = optionalInteger(formData, "produto_embalagem_id");
  const quantidade = optionalNumber(formData, "quantidade");
  const tipoPedido = field(formData, "tipo_pedido");
  const dataPedido = field(formData, "data_pedido");
  const justificativa = field(formData, "observacao");
  if (!idempotencyKey || !vinculoId || !produtoEmbalagemId || quantidade === null || quantidade <= 0 || !dataPedido || !["bonificacao", "mostruario"].includes(tipoPedido)) {
    redirect("/pedidos?result=missing_order_required#novo-pedido");
  }
  if (tipoPedido === "bonificacao" && justificativa.length < 10) {
    redirect("/pedidos?result=missing_bonus_reason#novo-pedido");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_com_pedido_vendedor_especial_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_cliente_vendedor_vinculo_id: vinculoId,
    p_data_pedido: dataPedido,
    p_justificativa: justificativa || null,
    p_produto_embalagem_id: produtoEmbalagemId,
    p_quantidade: quantidade,
    p_tipo_pedido: tipoPedido
  }, {
    metadata: {
      action_key: "pedidos.create.own",
      axis: "own_any",
      domain: "pedidos",
      entity: "com_pedidos",
      failure_action: "pedidos.special_create_failed"
    }
  });
  if (error) redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-pedido`);
  revalidatePath("/pedidos");
  redirect("/pedidos?result=pedido_pending_approval#historico");
}

export async function criarPedidoVendedorAction(formData: FormData) {
  const idempotencyKey = uuid(formData, "idempotency_key");
  const vinculoId = optionalInteger(formData, "cliente_vendedor_vinculo_id");
  const itensJson = field(formData, "itens_json");
  const dataPedido = field(formData, "data_pedido");
  let items: Array<{ produto_embalagem_id: number; quantidade: number; valor_unitario: number }> = [];
  try {
    const parsed: unknown = JSON.parse(itensJson);
    items = Array.isArray(parsed) ? parsed : [];
  } catch {
    items = [];
  }
  if (!idempotencyKey || !vinculoId || !dataPedido || !items.length || items.some((item) => !item.produto_embalagem_id || item.quantidade <= 0 || item.valor_unitario < 0)) {
    redirect("/pedidos?result=missing_order_required#novo-pedido");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_com_pedido_vendedor_itens_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_cliente_vendedor_vinculo_id: vinculoId,
    p_data_pedido: dataPedido,
    p_itens_jsonb: items,
    p_observacao: optionalField(formData, "observacao"),
  }, {
    metadata: {
      action_key: "pedidos.create.own",
      axis: "own_any",
      domain: "pedidos",
      entity: "com_pedidos",
      failure_action: "pedidos.create_failed"
    }
  });
  if (error) redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-pedido`);
  revalidatePath("/pedidos");
  redirect("/pedidos?result=pedido_pending_approval#historico");
}

export async function decidirPedidoGerencialAction(formData: FormData) {
  const idempotencyKey = uuid(formData, "idempotency_key");
  const pedidoId = optionalInteger(formData, "pedido_id");
  const decisao = field(formData, "decisao");
  const justificativa = field(formData, "justificativa");
  if (!idempotencyKey || !pedidoId || !["liberado", "bloqueado"].includes(decisao) || justificativa.length < 10) {
    redirect("/pedidos?result=invalid_manager_decision#aprovacoes");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_com_pedido_decisao_gerencial_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_decisao: decisao,
    p_justificativa: justificativa,
    p_pedido_id: pedidoId
  }, {
    metadata: {
      action_key: "pedidos.credit.review",
      axis: "status_transition",
      domain: "pedidos",
      entity: "com_pedido_credito_decisoes",
      entity_id: String(pedidoId),
      failure_action: "pedidos.credit_review_failed"
    }
  });
  if (error) redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#aprovacoes`);
  revalidatePath("/pedidos");
  redirect(`/pedidos?result=${decisao === "liberado" ? "order_approved" : "order_rejected"}#aprovacoes`);
}

export async function ajustarLimiteCreditoAction(formData: FormData) {
  const idempotencyKey = uuid(formData, "idempotency_key");
  const clienteId = optionalInteger(formData, "cliente_id");
  const limiteNovo = optionalNumber(formData, "limite_novo");
  const justificativa = field(formData, "justificativa_limite");
  if (!idempotencyKey || !clienteId || limiteNovo === null || limiteNovo < 0 || justificativa.length < 10) {
    redirect("/pedidos?result=invalid_credit_limit#aprovacoes");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "ajustar_com_limite_credito_cliente_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_cliente_id: clienteId,
    p_justificativa: justificativa,
    p_limite_novo: limiteNovo
  }, {
    metadata: {
      action_key: "pedidos.credit.limit.adjust",
      axis: "change_type",
      domain: "pedidos",
      entity: "cad_limites_credito_cliente",
      entity_id: String(clienteId),
      failure_action: "pedidos.credit_limit_adjust_failed"
    }
  });
  if (error) redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#aprovacoes`);
  revalidatePath("/pedidos");
  redirect("/pedidos?result=credit_limit_adjusted#aprovacoes");
}

export async function createPedidoRascunhoAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/pedidos?result=not_configured#novo-pedido");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
  const propriedadeId = optionalInteger(formData, "propriedade_id");
  const produtoEmbalagemId = optionalInteger(formData, "produto_embalagem_id");
  const vendedorId = optionalInteger(formData, "vendedor_id");
  const quantidade = optionalNumber(formData, "quantidade");
  const valorUnitario = optionalNumber(formData, "valor_unitario");
  const percentualComissao = optionalNumber(formData, "percentual_comissao");
  const tipoPedido = field(formData, "tipo_pedido") || "venda";
  const status = "blocked";
  const dataPedido = field(formData, "data_pedido");

  if (!clienteId || !produtoEmbalagemId || quantidade === null || valorUnitario === null || !dataPedido) {
    redirect("/pedidos?result=missing_order_required#novo-pedido");
  }
  if (!Number.isInteger(clienteId) || clienteId <= 0 || !Number.isInteger(produtoEmbalagemId) || produtoEmbalagemId <= 0) {
    redirect("/pedidos?result=invalid_positive_number#novo-pedido");
  }
  if (propriedadeId !== null && (!Number.isInteger(propriedadeId) || propriedadeId <= 0)) {
    redirect("/pedidos?result=invalid_positive_number#novo-pedido");
  }
  if (vendedorId !== null && (!Number.isInteger(vendedorId) || vendedorId <= 0)) {
    redirect("/pedidos?result=invalid_positive_number#novo-pedido");
  }
  if (!Number.isFinite(quantidade) || quantidade <= 0) {
    redirect("/pedidos?result=invalid_positive_number#novo-pedido");
  }
  if (!Number.isFinite(valorUnitario) || valorUnitario < 0) {
    redirect("/pedidos?result=invalid_non_negative_number#novo-pedido");
  }
  if (percentualComissao !== null && (!Number.isFinite(percentualComissao) || percentualComissao < 0)) {
    redirect("/pedidos?result=invalid_non_negative_number#novo-pedido");
  }
  if (!ALLOWED_TIPO_PEDIDO.has(tipoPedido)) {
    redirect("/pedidos?result=invalid_order_type#novo-pedido");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_com_pedido_operacional", {
    p_cliente_id: clienteId,
    p_data_pedido: dataPedido,
    p_observacao: optionalField(formData, "observacao"),
    p_percentual_comissao: percentualComissao,
    p_propriedade_id: propriedadeId,
    p_produto_embalagem_id: produtoEmbalagemId,
    p_quantidade: quantidade,
    p_status: status,
    p_tipo_pedido: tipoPedido,
    p_valor_unitario: valorUnitario,
    p_vendedor_id: vendedorId
  }, {
    metadata: {
      action_key: "pedidos.create",
      axis: "own_any",
      domain: "pedidos",
      entity: "com_pedidos",
      failure_action: "pedidos.create_failed"
    }
  });

  if (error) {
    redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-pedido`);
  }

  revalidatePath("/pedidos");
  redirect("/pedidos?result=pedido_created#novo-pedido");
}

export async function criarTrocaPedidoAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/pedidos?result=not_configured#troca-pedido");
  }

  const idempotencyKey = uuid(formData, "idempotency_key");
  const pedidoOrigemId = optionalInteger(formData, "pedido_origem_id");
  const pedidoItemOrigemId = optionalInteger(formData, "pedido_item_origem_id");
  const produtoEmbalagemId = optionalInteger(formData, "produto_embalagem_id");
  const quantidade = optionalNumber(formData, "quantidade_troca");
  const status = "blocked";
  const dataPedido = field(formData, "data_troca");
  const motivoTroca = field(formData, "motivo_troca") || "qualidade";

  if (!idempotencyKey || !pedidoOrigemId || !pedidoItemOrigemId || !dataPedido) {
    redirect("/pedidos?result=missing_exchange_required#troca-pedido");
  }
  if (!Number.isInteger(pedidoOrigemId) || pedidoOrigemId <= 0 || !Number.isInteger(pedidoItemOrigemId) || pedidoItemOrigemId <= 0) {
    redirect("/pedidos?result=invalid_positive_number#troca-pedido");
  }
  if (produtoEmbalagemId !== null && (!Number.isInteger(produtoEmbalagemId) || produtoEmbalagemId <= 0)) {
    redirect("/pedidos?result=invalid_positive_number#troca-pedido");
  }
  if (quantidade !== null && (!Number.isFinite(quantidade) || quantidade <= 0)) {
    redirect("/pedidos?result=invalid_positive_number#troca-pedido");
  }
  if (!ALLOWED_MOTIVO_TROCA.has(motivoTroca)) {
    redirect("/pedidos?result=invalid_exchange_reason#troca-pedido");
  }
  if (motivoTroca === "outro" && !optionalField(formData, "observacao_troca")) {
    redirect("/pedidos?result=missing_exchange_observation#troca-pedido");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_com_pedido_troca_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_data_pedido: dataPedido,
    p_motivo_troca: motivoTroca,
    p_observacao: optionalField(formData, "observacao_troca"),
    p_pedido_item_origem_id: pedidoItemOrigemId,
    p_pedido_origem_id: pedidoOrigemId,
    p_produto_embalagem_id: produtoEmbalagemId,
    p_quantidade: quantidade,
    p_status: status
  }, {
    metadata: {
      action_key: "pedidos.exchange.create",
      axis: "change_type",
      domain: "pedidos",
      entity: "com_pedidos",
      entity_id: String(pedidoOrigemId),
      failure_action: "pedidos.exchange_create_failed"
    }
  });

  if (error) {
    redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#troca-pedido`);
  }

  revalidatePath("/pedidos");
  redirect("/pedidos?result=exchange_created#troca-pedido");
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function optionalField(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return value || null;
}

function optionalNumber(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  return Number(value.replace(DECIMAL_SEPARATOR, "."));
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  const idPrefix = value.match(/^\s*(\d+)/);
  if (idPrefix) {
    return Number(idPrefix[1]);
  }
  return Number(value);
}

function uuid(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null;
}

function mapSupabaseError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  if (normalized.includes("foreign key")) {
    return "missing_related_record";
  }
  if (normalized.includes("motivo is required")) {
    return "missing_credit_reason";
  }
  if (normalized.includes("does not allow credit decision")) {
    return "invalid_order_status";
  }
  if (normalized.includes("pedido not found")) {
    return "missing_related_record";
  }
  if (normalized.includes("does not allow receipt")) {
    return "invalid_receipt_order";
  }
  if (normalized.includes("receipt exceeds order balance")) {
    return "receipt_exceeds_balance";
  }
  if (normalized.includes("use create_com_pedido_troca")) {
    return "invalid_order_type";
  }
  if (normalized.includes("invalid motivo_troca")) {
    return "invalid_exchange_reason";
  }
  if (normalized.includes("observacao is required when motivo_troca is outro")) {
    return "missing_exchange_observation";
  }
  if (normalized.includes("origem") || normalized.includes("exchange quantity exceeds")) {
    return "invalid_exchange_source";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  if (normalized.includes("outside seller portfolio") || normalized.includes("outside manager team")) {
    return "permission_denied";
  }
  if (normalized.includes("justification")) {
    return "invalid_justification";
  }
  return "save_failed";
}
