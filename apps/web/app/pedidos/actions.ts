"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_TIPO_PEDIDO = new Set(["venda", "bonificacao", "devolucao"]);
const ALLOWED_STATUS_INICIAL = new Set(["draft", "open", "blocked"]);
const DECIMAL_SEPARATOR = /,/g;

export async function createPedidoRascunhoAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/pedidos?result=not_configured#novo-pedido");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
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
  const { error } = await supabase.rpc("create_com_pedido_rascunho", {
    p_cliente_id: clienteId,
    p_data_pedido: dataPedido,
    p_observacao: optionalField(formData, "observacao"),
    p_percentual_comissao: percentualComissao,
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
  if (normalized.includes("permission") || normalized.includes("row-level security")) {
    return "permission_denied";
  }
  return "save_failed";
}
