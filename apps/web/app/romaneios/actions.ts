"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const DECIMAL_SEPARATOR = /,/g;
export async function createRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#novo-romaneio");
  }

  const idempotencyKey = uuid(formData, "idempotency_key");
  const pedidoId = optionalInteger(formData, "pedido_id");
  const itemIds = formData.getAll("pedido_item_id").map(Number).filter((value) => Number.isInteger(value) && value > 0);
  const itens = itemIds.flatMap((pedidoItemId) => {
    const quantidade = optionalNumber(formData, `quantidade_${pedidoItemId}`);
    return quantidade !== null && quantidade > 0 ? [{ pedido_item_id: pedidoItemId, quantidade }] : [];
  });

  if (!idempotencyKey || !pedidoId || pedidoId <= 0 || itens.length === 0) {
    redirect("/romaneios?result=missing_romaneio_required#novo-romaneio");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "gravar_exp_romaneio_pedido_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_itens: itens,
    p_pedido_id: pedidoId,
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#novo-romaneio`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=romaneio_created#romaneios");
}

export async function reserveRomaneioPaLotAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#reservar-lote");
  }

  const romaneioItemId = optionalInteger(formData, "romaneio_item_id");
  const lotePaId = optionalInteger(formData, "lote_pa_id");
  const quantidadeReservada = optionalNumber(formData, "quantidade_reservada");

  if (!romaneioItemId || romaneioItemId <= 0 || !lotePaId || lotePaId <= 0) {
    redirect("/romaneios?result=missing_reservation_required#reservar-lote");
  }
  if (quantidadeReservada !== null && (!Number.isFinite(quantidadeReservada) || quantidadeReservada <= 0)) {
    redirect("/romaneios?result=invalid_positive_number#reservar-lote");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_est_reserva_pa", {
    p_lote_pa_id: lotePaId,
    p_observacao: null,
    p_quantidade_reservada: quantidadeReservada,
    p_romaneio_item_id: romaneioItemId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#reservar-lote`);
  }

  revalidatePath("/romaneios");
  revalidatePath("/relatorios");
  redirect("/romaneios?result=lot_reserved#romaneios");
}

export async function assignRomaneioLogisticsAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const entregadorId = optionalInteger(formData, "entregador_id");
  const veiculoId = optionalInteger(formData, "veiculo_id");

  if (!romaneioId || romaneioId <= 0 || (!entregadorId && !veiculoId)) {
    redirect("/romaneios?result=missing_logistics_required#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_exp_romaneio_logistica_atribuicao", {
    p_entregador_id: entregadorId,
    p_motivo: null,
    p_romaneio_id: romaneioId,
    p_veiculo_id: veiculoId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=logistics_assigned#romaneios");
}

export async function removeRomaneioLogisticsAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const motivo = field(formData, "motivo");
  if (!romaneioId || romaneioId <= 0 || !motivo) {
    redirect("/romaneios?result=missing_logistics_removal_required#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_exp_romaneio_logistica_remocao", {
    p_motivo: motivo,
    p_romaneio_id: romaneioId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=logistics_removed#romaneios");
}

export async function confirmRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const notaFiscalId = optionalInteger(formData, "nota_fiscal_id");
  if (!romaneioId || romaneioId <= 0 || !notaFiscalId || notaFiscalId <= 0) {
    redirect("/romaneios?result=missing_romaneio_id#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "confirmar_exp_romaneio", {
    p_nota_fiscal_id: notaFiscalId,
    p_romaneio_id: romaneioId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  }

  revalidatePath("/romaneios");
  revalidatePath("/kanban");
  revalidatePath("/relatorios");
  redirect("/romaneios?result=romaneio_confirmed#romaneios");
}

export async function registerExternalFiscalReferenceAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) redirect("/romaneios?result=not_configured#romaneios");
  const idempotencyKey = uuid(formData, "idempotency_key");
  const pedidoId = optionalInteger(formData, "pedido_id");
  const romaneioId = optionalInteger(formData, "romaneio_id");
  const parentId = optionalInteger(formData, "referencia_pai_id");
  const type = field(formData, "tipo");
  const number = field(formData, "numero");
  const reason = field(formData, "motivo");
  if (!idempotencyKey || !pedidoId || !number || reason.length < 5
      || !["simples_faturamento", "remessa_total", "remessa_vinculada"].includes(type)) {
    redirect("/romaneios?result=missing_external_reference#romaneios");
  }
  if (type !== "simples_faturamento" && !romaneioId) redirect("/romaneios?result=missing_external_reference#romaneios");
  if (type === "remessa_vinculada" && !parentId) redirect("/romaneios?result=missing_external_reference_parent#romaneios");

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_fat_referencia_externa_idempotente", {
    p_data_documento: optionalField(formData, "data_documento"),
    p_idempotency_key: idempotencyKey,
    p_motivo: reason,
    p_numero: number,
    p_pedido_id: pedidoId,
    p_referencia_pai_id: parentId,
    p_romaneio_id: type === "simples_faturamento" ? null : romaneioId,
    p_serie: optionalField(formData, "serie"),
    p_tipo: type
  });
  if (error) redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  revalidatePath("/romaneios");
  revalidatePath("/pedidos");
  redirect("/romaneios?result=external_reference_registered#romaneios");
}

export async function correctExternalFiscalReferenceAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) redirect("/romaneios?result=not_configured#romaneios");
  const idempotencyKey = uuid(formData, "idempotency_key");
  const referenceId = optionalInteger(formData, "nota_fiscal_id");
  const number = field(formData, "numero_novo");
  const reason = field(formData, "motivo");
  if (!idempotencyKey || !referenceId || !number || reason.length < 10) {
    redirect("/romaneios?result=missing_external_reference_correction#romaneios");
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "corrigir_fat_referencia_externa_numero_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_motivo: reason,
    p_nota_fiscal_id: referenceId,
    p_numero_novo: number,
    p_serie_nova: optionalField(formData, "serie_nova")
  });
  if (error) redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  revalidatePath("/romaneios");
  redirect("/romaneios?result=external_reference_corrected#romaneios");
}

export async function cancelRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const motivo = field(formData, "motivo");
  if (!romaneioId || romaneioId <= 0 || !motivo) {
    redirect("/romaneios?result=missing_cancel_required#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "cancelar_exp_romaneio", {
    p_motivo: motivo,
    p_romaneio_id: romaneioId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=romaneio_cancelled#romaneios");
}

export async function reverseRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const motivo = field(formData, "motivo");
  if (!romaneioId || romaneioId <= 0 || !motivo) {
    redirect("/romaneios?result=missing_reverse_required#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "estornar_exp_romaneio", {
    p_motivo: motivo,
    p_romaneio_id: romaneioId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#romaneios`);
  }

  revalidatePath("/romaneios");
  revalidatePath("/kanban");
  revalidatePath("/relatorios");
  redirect("/romaneios?result=romaneio_reversed#romaneios");
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
  const parsed = Number(value.replace(DECIMAL_SEPARATOR, "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function uuid(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null;
}

function mapRomaneioError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("module unavailable")) {
    return "module_unavailable";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  if (normalized.includes("idempotency")) return "external_reference_repeated_payload";
  if (normalized.includes("external fiscal") || normalized.includes("shipping reference") || normalized.includes("parent")) {
    return "external_reference_invalid";
  }
  if (normalized.includes("not found") || normalized.includes("foreign key")) {
    return "missing_related_record";
  }
  if (normalized.includes("already exists")) {
    return "duplicated_item";
  }
  if (normalized.includes("already active")) {
    return "logistics_already_active";
  }
  if (normalized.includes("exceeds pending")) {
    return "exceeds_pending";
  }
  if (normalized.includes("total romaneio")) {
    return "invalid_total_quantity";
  }
  if (normalized.includes("insufficient pa")) {
    return "insufficient_stock";
  }
  if (normalized.includes("reservations exceed")) {
    return "reservation_exceeds_item";
  }
  if (normalized.includes("reservations must match") || normalized.includes("active pa reservations must match")) {
    return "reservation_mismatch";
  }
  if (normalized.includes("status does not allow")) {
    return "invalid_status";
  }
  if (normalized.includes("product does not match")) {
    return "lot_product_mismatch";
  }
  if (normalized.includes("active entregador not found") || normalized.includes("active vehicle not found")) {
    return "invalid_logistics_actor";
  }
  if (normalized.includes("no active logistics assignment")) {
    return "missing_logistics_assignment";
  }
  if (normalized.includes("driver and vehicle are required")) {
    return "logistics_incomplete_for_issue";
  }
  if (normalized.includes("invoice must belong")) {
    return "invoice_link_mismatch";
  }
  if (normalized.includes("an emitted shipping invoice is required")) {
    return "invoice_not_ready";
  }
  if (normalized.includes("invoice items must match")) {
    return "invoice_items_mismatch";
  }
  if (normalized.includes("load volumes and weights must be fully configured")) {
    return "load_measurements_pending";
  }
  if (normalized.includes("required") || normalized.includes("must be")) {
    return "missing_required";
  }
  return "save_failed";
}
