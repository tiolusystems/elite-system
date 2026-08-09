"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function registerValuedMpEntryAction(formData: FormData) {
  const materiaPrimaId = integer(formData, "materia_prima_id");
  const idempotencyKey = field(formData, "idempotency_key");
  const returnQuery = field(formData, "return_query");
  const destination = `/producao/estoque?${returnQuery || "familia=MP"}`;

  if (!getRuntimeStatus().supabaseConfigured) redirect(`${destination}&result=not_configured#entrada-mp`);
  if (!materiaPrimaId || !UUID.test(idempotencyKey) || !positive(formData, "quantidade")
      || !field(formData, "codigo_lote_fornecedor") || !field(formData, "documento_ref")) {
    redirect(`${destination}&result=missing_stock_entry#entrada-mp`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_est_entrada_mp_idempotente", {
    p_codigo_lote_fornecedor: field(formData, "codigo_lote_fornecedor"),
    p_data_documento: nullable(formData, "data_documento"),
    p_data_fabricacao: nullable(formData, "data_fabricacao"),
    p_data_validade: nullable(formData, "data_validade"),
    p_difal_icms: number(formData, "difal_icms"),
    p_difal_motivo: nullable(formData, "difal_motivo"),
    p_difal_status: field(formData, "difal_status") || "not_applicable",
    p_documento_ref: field(formData, "documento_ref"),
    p_frete: number(formData, "frete"),
    p_idempotency_key: idempotencyKey,
    p_materia_prima_id: materiaPrimaId,
    p_observacao: nullable(formData, "observacao"),
    p_outras_despesas: number(formData, "outras_despesas"),
    p_quantidade: number(formData, "quantidade"),
    p_status_lote: field(formData, "status_lote") || "bloqueado",
    p_uf_emitente: nullable(formData, "uf_emitente"),
    p_unidade_origem: field(formData, "unidade_origem") || "UN_BASE",
    p_valor_materia_prima: number(formData, "valor_materia_prima")
  });

  if (error) redirect(`${destination}&result=${encodeURIComponent(mapEntryError(error.message))}#entrada-mp`);
  revalidatePath("/producao/estoque");
  revalidatePath("/producao/ordens");
  redirect(`${destination}&result=stock_entry_created#lotes`);
}

function field(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function nullable(formData: FormData, name: string) {
  return field(formData, name) || null;
}

function number(formData: FormData, name: string) {
  const parsed = Number(field(formData, name).replace(",", ".") || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function integer(formData: FormData, name: string) {
  const parsed = Number(field(formData, name));
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function positive(formData: FormData, name: string) {
  return number(formData, name) > 0;
}

function mapEntryError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("not allowed") || normalized.includes("permission")) return "not_allowed";
  if (normalized.includes("difal")) return "invalid_stock_difal";
  if (normalized.includes("idempotency")) return "stock_entry_repeated_payload";
  if (normalized.includes("date") || normalized.includes("validade")) return "invalid_stock_dates";
  return "stock_entry_failed";
}
