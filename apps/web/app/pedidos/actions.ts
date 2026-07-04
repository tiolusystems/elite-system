"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_TIPO_PEDIDO = new Set(["venda", "bonificacao", "devolucao"]);
const ALLOWED_STATUS_INICIAL = new Set(["draft", "open", "blocked"]);
const ALLOWED_DECISAO_CREDITO = new Set(["liberado", "bloqueado", "pendente_aprovacao"]);
const DECIMAL_SEPARATOR = /,/g;

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
  const status = field(formData, "status") || "draft";
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
  if (!ALLOWED_STATUS_INICIAL.has(status)) {
    redirect("/pedidos?result=invalid_initial_status#novo-pedido");
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
  });

  if (error) {
    redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-pedido`);
  }

  revalidatePath("/pedidos");
  redirect("/pedidos?result=pedido_created#novo-pedido");
}

export async function registrarCreditoPedidoAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/pedidos?result=not_configured#credito-pedido");
  }

  const pedidoId = optionalInteger(formData, "pedido_id");
  const decisao = field(formData, "decisao");
  const motivo = optionalField(formData, "motivo");
  const limiteDisponivelSnapshot = optionalNumber(formData, "limite_disponivel_snapshot");
  const inadimplenciaSnapshot = optionalNumber(formData, "inadimplencia_snapshot");

  if (!pedidoId || !decisao) {
    redirect("/pedidos?result=missing_credit_required#credito-pedido");
  }
  if (!Number.isInteger(pedidoId) || pedidoId <= 0) {
    redirect("/pedidos?result=invalid_positive_number#credito-pedido");
  }
  if (!ALLOWED_DECISAO_CREDITO.has(decisao)) {
    redirect("/pedidos?result=invalid_credit_decision#credito-pedido");
  }
  if (decisao !== "liberado" && !motivo) {
    redirect("/pedidos?result=missing_credit_reason#credito-pedido");
  }
  if (limiteDisponivelSnapshot !== null && (!Number.isFinite(limiteDisponivelSnapshot) || limiteDisponivelSnapshot < 0)) {
    redirect("/pedidos?result=invalid_non_negative_number#credito-pedido");
  }
  if (inadimplenciaSnapshot !== null && (!Number.isFinite(inadimplenciaSnapshot) || inadimplenciaSnapshot < 0)) {
    redirect("/pedidos?result=invalid_non_negative_number#credito-pedido");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_com_pedido_decisao_credito", {
    p_decisao: decisao,
    p_inadimplencia_snapshot: inadimplenciaSnapshot,
    p_limite_disponivel_snapshot: limiteDisponivelSnapshot,
    p_motivo: motivo,
    p_observacao: optionalField(formData, "observacao_credito"),
    p_pedido_id: pedidoId
  });

  if (error) {
    redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#credito-pedido`);
  }

  revalidatePath("/pedidos");
  redirect("/pedidos?result=credit_decision_registered#credito-pedido");
}

export async function registrarRecebimentoPedidoAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/pedidos?result=not_configured#recebimento-pedido");
  }

  const pedidoId = optionalInteger(formData, "pedido_id");
  const valorRecebido = optionalNumber(formData, "valor_recebido");
  const dataRecebimento = field(formData, "data_recebimento");

  if (!pedidoId || valorRecebido === null || !dataRecebimento) {
    redirect("/pedidos?result=missing_receipt_required#recebimento-pedido");
  }
  if (!Number.isInteger(pedidoId) || pedidoId <= 0) {
    redirect("/pedidos?result=invalid_positive_number#recebimento-pedido");
  }
  if (!Number.isFinite(valorRecebido) || valorRecebido <= 0) {
    redirect("/pedidos?result=invalid_positive_number#recebimento-pedido");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_com_recebimento", {
    p_data_recebimento: dataRecebimento,
    p_forma_recebimento: optionalField(formData, "forma_recebimento"),
    p_observacao: optionalField(formData, "observacao_recebimento"),
    p_pedido_id: pedidoId,
    p_valor_recebido: valorRecebido
  });

  if (error) {
    redirect(`/pedidos?result=${encodeURIComponent(mapSupabaseError(error.message))}#recebimento-pedido`);
  }

  revalidatePath("/pedidos");
  redirect("/pedidos?result=receipt_registered#recebimento-pedido");
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
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  return "save_failed";
}
