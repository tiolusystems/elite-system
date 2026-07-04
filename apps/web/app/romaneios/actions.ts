"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_TIPO_SEPARACAO = new Set(["total", "parcial"]);

export async function createRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#novo-romaneio");
  }

  const pedidoItemId = optionalInteger(formData, "pedido_item_id");
  const quantidadeRomaneada = optionalNumber(formData, "quantidade_romaneada");
  const tipoSeparacao = field(formData, "tipo_separacao") || "parcial";

  if (!pedidoItemId || pedidoItemId <= 0 || quantidadeRomaneada === null || quantidadeRomaneada <= 0) {
    redirect("/romaneios?result=missing_romaneio_required#novo-romaneio");
  }
  if (!ALLOWED_TIPO_SEPARACAO.has(tipoSeparacao)) {
    redirect("/romaneios?result=invalid_separation_type#novo-romaneio");
  }

  const supabase = await createSupabaseServerClient();
  const item = await supabase.from("com_pedido_itens").select("pedido_id").eq("id", pedidoItemId).single();
  const pedidoId = item.data ? Number((item.data as Record<string, unknown>).pedido_id) : null;

  if (item.error || !pedidoId) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(item.error?.message ?? "pedido item not found"))}#novo-romaneio`);
  }

  const { error } = await supabase.rpc("create_exp_romaneio", {
    p_lote_pa_ref: null,
    p_observacao: optionalField(formData, "observacao"),
    p_pedido_id: pedidoId,
    p_pedido_item_id: pedidoItemId,
    p_quantidade_romaneada: quantidadeRomaneada,
    p_status: "draft",
    p_tipo_separacao: tipoSeparacao
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#novo-romaneio`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=romaneio_created#romaneios");
}

export async function addRomaneioItemAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#adicionar-item");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  const pedidoItemId = optionalInteger(formData, "pedido_item_id");
  const quantidadeRomaneada = optionalNumber(formData, "quantidade_romaneada");

  if (!romaneioId || romaneioId <= 0 || !pedidoItemId || pedidoItemId <= 0 || quantidadeRomaneada === null || quantidadeRomaneada <= 0) {
    redirect("/romaneios?result=missing_add_item_required#adicionar-item");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("add_exp_romaneio_item", {
    p_observacao: optionalField(formData, "observacao"),
    p_pedido_item_id: pedidoItemId,
    p_quantidade_romaneada: quantidadeRomaneada,
    p_romaneio_id: romaneioId
  });

  if (error) {
    redirect(`/romaneios?result=${encodeURIComponent(mapRomaneioError(error.message))}#adicionar-item`);
  }

  revalidatePath("/romaneios");
  redirect("/romaneios?result=romaneio_item_added#romaneios");
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
  const { error } = await supabase.rpc("registrar_est_reserva_pa", {
    p_lote_pa_id: lotePaId,
    p_observacao: optionalField(formData, "observacao"),
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

export async function confirmRomaneioAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/romaneios?result=not_configured#romaneios");
  }

  const romaneioId = optionalInteger(formData, "romaneio_id");
  if (!romaneioId || romaneioId <= 0) {
    redirect("/romaneios?result=missing_romaneio_id#romaneios");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("confirmar_exp_romaneio", {
    p_observacao: optionalField(formData, "observacao"),
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
  const { error } = await supabase.rpc("cancelar_exp_romaneio", {
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
  const { error } = await supabase.rpc("estornar_exp_romaneio", {
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
  const idPrefix = value.match(/^\s*(\d+)/);
  return Number(idPrefix ? idPrefix[1] : value);
}

function mapRomaneioError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("permission") || normalized.includes("row-level security")) {
    return "permission_denied";
  }
  if (normalized.includes("not found") || normalized.includes("foreign key")) {
    return "missing_related_record";
  }
  if (normalized.includes("already exists")) {
    return "duplicated_item";
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
  if (normalized.includes("required") || normalized.includes("must be")) {
    return "missing_required";
  }
  return "save_failed";
}
