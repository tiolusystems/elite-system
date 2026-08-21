"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
    redirectOrder(formData, "invalid_order_type");
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
    redirectOrder(formData, "missing_order_required");
  }
  if (tipoPedido === "bonificacao" && justificativa.length < 10) {
    redirectOrder(formData, "missing_bonus_reason");
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
  if (error) redirectOrder(formData, mapSupabaseError(error.message));
  revalidatePath("/pedidos");
  redirectOrder(formData, "pedido_pending_approval", "#historico");
}

export async function criarPedidoVendedorAction(formData: FormData) {
  const idempotencyKey = uuid(formData, "idempotency_key");
  const proposalJson = field(formData, "proposta_json");
  const previewHash = field(formData, "preview_hash");
  const justification = optionalField(formData, "justificativa_comercial");
  const discountsConfirmed = field(formData, "confirmacao_descontos") === "on";
  let proposal: Record<string, unknown> | null = null;
  try {
    const parsed: unknown = JSON.parse(proposalJson);
    proposal = parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    proposal = null;
  }
  if (!idempotencyKey || !proposal || !/^[0-9a-f]{64}$/.test(previewHash)) {
    redirectOrder(formData, "commercial_review_incomplete");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "confirmar_com_revisao_comercial_venda_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_confirmacao_descontos: discountsConfirmed,
    p_justificativa_comercial: justification,
    p_preview_hash: previewHash,
    p_proposta: proposal
  }, {
    metadata: {
      action_key: "pedidos.commercial_review.confirm",
      axis: "change_type",
      domain: "pedidos",
      entity: "com_pedido_confirmacoes_comerciais",
      failure_action: "pedidos.commercial_review_confirm_failed"
    }
  });
  if (error) redirectOrder(formData, mapSupabaseError(error.message));
  revalidatePath("/pedidos");
  redirectOrder(formData, "pedido_pending_approval", "#historico");
}

export async function preverRevisaoComercialAction(proposal: unknown): Promise<{
  data: Record<string, unknown> | null;
  error: string | null;
}> {
  if (!proposal || typeof proposal !== "object" || Array.isArray(proposal)) {
    return { data: null, error: "Complete os dados comerciais antes de calcular a revisão." };
  }
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("prever_com_revisao_comercial_venda", {
    p_proposta: proposal
  });
  if (error) return { data: null, error: commercialReviewError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return { data: null, error: "A revisão comercial não retornou um resultado válido." };
  }
  return { data: data as Record<string, unknown>, error: null };
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
  const target = creditAdjustmentTarget(formData, clienteId);
  if (!idempotencyKey || !clienteId || limiteNovo === null || limiteNovo < 0 || justificativa.length < 10) {
    redirectCreditAdjustment(target, "invalid_credit_limit");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "ajustar_com_limite_credito_cliente_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_cliente_id: clienteId,
    p_justificativa: justificativa,
    p_limite_novo: limiteNovo
  }, {
    metadata: {
      action_key: "financeiro.credit_limits.adjust",
      axis: "change_type",
      domain: "financeiro",
      entity: "cad_limites_credito_cliente",
      entity_id: String(clienteId),
      failure_action: "financeiro.credit_limit_adjust_failed"
    }
  });
  if (error) redirectCreditAdjustment(target, mapSupabaseError(error.message));
  revalidatePath("/pedidos");
  revalidatePath("/cadastros");
  redirectCreditAdjustment(target, "credit_limit_adjusted");
}

function creditAdjustmentTarget(formData: FormData, clienteId: number | null): { path: string; hash: string } {
  const requestedPath = field(formData, "return_to");
  const clientPath = clienteId
    ? `/cadastros?grupo=clientes&cliente=${clienteId}&secao=credito`
    : null;
  return clientPath && requestedPath === clientPath
    ? { path: clientPath, hash: "#credito-cliente" }
    : { path: "/pedidos", hash: "#aprovacoes" };
}

function redirectCreditAdjustment(target: { path: string; hash: string }, result: string): never {
  const separator = target.path.includes("?") ? "&" : "?";
  redirect(`${target.path}${separator}result=${encodeURIComponent(result)}${target.hash}`);
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
  if (normalized.includes("delivery schedule") || normalized.includes("delivery items")) {
    return "missing_delivery_schedule";
  }
  if (normalized.includes("delivery date")) {
    return "invalid_delivery_date";
  }
  if (normalized.includes("delivery property") || normalized.includes("delivery establishment") || normalized.includes("delivery address") || normalized.includes("delivery location")) {
    return "invalid_delivery_location";
  }
  if (normalized.includes("sale item is inactive") || normalized.includes("invalid order item")) {
    return "invalid_sale_item";
  }
  if (normalized.includes("idempotency key reused")) {
    return "idempotency_conflict";
  }
  if (normalized.includes("previsualizacao comercial desatualizada")) {
    return "commercial_review_stale";
  }
  if (normalized.includes("revisao comercial") || normalized.includes("confirmacao comercial")) {
    return "commercial_review_incomplete";
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
  if (normalized.includes("commercial identity not linked")) {
    return "commercial_identity_required";
  }
  if (normalized.includes("justification")) {
    return "invalid_justification";
  }
  return "save_failed";
}

function commercialReviewError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("permission") || normalized.includes("permissao")) {
    return "Sua conta não possui alçada para calcular esta revisão comercial.";
  }
  if (normalized.includes("carteira") || normalized.includes("identidade comercial")) {
    return "O cliente não está disponível na carteira operacional desta conta.";
  }
  if (normalized.includes("lista comercial") || normalized.includes("faixa de preco")) {
    return "Não existe preço de referência aplicável à condição comercial informada.";
  }
  if (normalized.includes("parcela") || normalized.includes("vencimento") || normalized.includes("pmp")) {
    return "Revise os valores e vencimentos da condição financeira.";
  }
  if (normalized.includes("entrega") || normalized.includes("programacao")) {
    return "Revise o local, a data e a distribuição das entregas.";
  }
  if (normalized.includes("apresentacao") || normalized.includes("item")) {
    return "Revise os produtos, apresentações e quantidades do pedido.";
  }
  return "Não foi possível calcular a revisão comercial com os dados informados.";
}

function redirectOrder(formData: FormData, result: string, hash = "#novo-pedido"): never {
  const linkId = optionalInteger(formData, "cliente_vendedor_vinculo_id");
  const search = field(formData, "return_search");
  const page = optionalInteger(formData, "return_page");
  const query = new URLSearchParams({ result });
  if (linkId) query.set("cliente", String(linkId));
  if (search) query.set("busca", search);
  if (page !== null && page >= 0) query.set("pagina", String(page));
  redirect(`/pedidos?${query.toString()}${hash}`);
}
