"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function assignOrderCommissionAction(formData: FormData) {
  requireConfigured();
  const orderId = positiveInteger(formData, "pedido_id");
  const personId = positiveInteger(formData, "pessoa_id");
  const percentage = positiveNumber(formData, "percentual_comissao");
  const role = field(formData, "papel_comissao");
  const reason = field(formData, "justificativa");
  if (!orderId || !personId || !percentage || !new Set(["vendedor", "agente", "gerente", "outro"]).has(role) || reason.length < 10) {
    redirect("/pedidos/financeiro?result=invalid_assignment#previsoes");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "definir_com_pedido_comissao", {
    p_pedido_id: orderId, p_pessoa_id: personId, p_papel_comissao: role,
    p_percentual_comissao: percentage, p_justificativa: reason,
  }, { metadata: { action_key: "pedidos.commissions.assign", axis: "change_type", domain: "pedidos", entity: "com_pedido_comissionados", entity_id: String(orderId), failure_action: "pedidos.comissao_definicao_failed" } });
  if (error) redirect(`/pedidos/financeiro?result=${mapError(error.message)}#previsoes`);
  revalidatePath("/pedidos/financeiro");
  redirect("/pedidos/financeiro?result=commission_assigned#previsoes");
}

export async function registerReceiptAction(formData: FormData) {
  requireConfigured();
  const idempotencyKey = uuid(formData, "idempotency_key");
  const orderId = positiveInteger(formData, "pedido_id");
  const value = positiveNumber(formData, "valor_recebido");
  const date = field(formData, "data_recebimento");
  if (!idempotencyKey || !orderId || !value || !date) redirect("/pedidos/financeiro?result=invalid_receipt#recebimentos");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_com_recebimento_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_pedido_id: orderId,
    p_valor_recebido: value,
    p_data_recebimento: date,
    p_forma_recebimento: optionalField(formData, "forma_recebimento"),
    p_observacao: optionalField(formData, "observacao"),
  }, { metadata: { action_key: "financeiro.receipts.register", axis: "financial_event", domain: "financeiro", entity: "com_recebimentos", entity_id: String(orderId), failure_action: "financeiro.recebimento_failed" } });
  if (error) redirect(`/pedidos/financeiro?result=${mapError(error.message)}#recebimentos`);
  revalidatePath("/pedidos/financeiro");
  redirect("/pedidos/financeiro?result=receipt_registered#recebimentos");
}

export async function payCommissionAction(formData: FormData) {
  requireConfigured();
  const personId = positiveInteger(formData, "pessoa_id");
  const value = positiveNumber(formData, "valor_pago");
  const date = field(formData, "data_pagamento");
  if (!personId || !value || !date) redirect("/pedidos/financeiro?result=invalid_payment#comissoes");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_fin_comissao_pagamento", {
    p_pessoa_id: personId,
    p_valor_pago: value,
    p_data_pagamento: date,
    p_forma_pagamento: optionalField(formData, "forma_pagamento"),
    p_motivo: optionalField(formData, "referencia_pagamento"),
  }, { metadata: { action_key: "financeiro.commissions.pay", axis: "financial_event", domain: "financeiro", entity: "fin_comissao_movimentos", entity_id: String(personId), failure_action: "financeiro.comissao_pagamento_failed" } });
  if (error) redirect(`/pedidos/financeiro?result=${mapError(error.message)}#comissoes`);
  revalidatePath("/pedidos/financeiro");
  redirect("/pedidos/financeiro?result=commission_paid#comissoes");
}

export async function adjustCommissionAction(formData: FormData) {
  requireConfigured();
  const personId = positiveInteger(formData, "pessoa_id");
  const value = signedNumber(formData, "valor_ajuste");
  const reason = field(formData, "motivo_codigo");
  const detail = optionalField(formData, "motivo_detalhe");
  const reasons = new Set(["correcao_calculo", "estorno_devolucao", "acordo_comercial", "compensacao_futura", "outro"]);
  if (!personId || !value || !reasons.has(reason) || (reason === "outro" && (!detail || detail.length < 10))) redirect("/pedidos/financeiro?result=invalid_adjustment#ajustes");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_fin_comissao_ajuste", {
    p_pessoa_id: personId,
    p_valor_ajuste: value,
    p_motivo: reason,
    p_referencia_json: { motivo_detalhe: detail },
  }, { metadata: { action_key: "financeiro.commissions.adjust", axis: "financial_event", domain: "financeiro", entity: "fin_comissao_movimentos", entity_id: String(personId), failure_action: "financeiro.comissao_ajuste_failed" } });
  if (error) redirect(`/pedidos/financeiro?result=${mapError(error.message)}#ajustes`);
  revalidatePath("/pedidos/financeiro");
  redirect("/pedidos/financeiro?result=commission_adjusted#ajustes");
}

function requireConfigured() { if (!getRuntimeStatus().supabaseConfigured) redirect("/pedidos/financeiro?result=not_configured"); }
function field(data: FormData, name: string) { return String(data.get(name) ?? "").trim(); }
function optionalField(data: FormData, name: string) { return field(data, name) || null; }
function positiveInteger(data: FormData, name: string) { const value = Number(field(data, name)); return Number.isInteger(value) && value > 0 ? value : null; }
function positiveNumber(data: FormData, name: string) { const value = signedNumber(data, name); return value !== null && value > 0 ? value : null; }
function signedNumber(data: FormData, name: string) { const value = Number(field(data, name).replace(",", ".")); return Number.isFinite(value) && value !== 0 ? value : null; }
function uuid(data: FormData, name: string) { const value = field(data, name); return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null; }
function mapError(message: string) {
  const value = message.toLowerCase();
  if (value.includes("not allowed") || value.includes("permission")) return "not_allowed";
  if (value.includes("exceeds order balance")) return "receipt_exceeds_balance";
  if (value.includes("exceeds available balance")) return "payment_exceeds_balance";
  if (value.includes("ja_liberada") || value.includes("already")) return "already_processed";
  return "operation_failed";
}
