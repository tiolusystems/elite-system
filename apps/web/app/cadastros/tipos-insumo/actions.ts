"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { normalizeKey } from "@/lib/normalization";
import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const STATUS = new Set(["active", "pending_review"]);

export async function createInputTypeAction(formData: FormData) {
  requireConfigured("/cadastros/tipos-insumo?result=not_configured");
  const code = field(formData, "codigo").toUpperCase();
  const name = field(formData, "nome");
  const status = field(formData, "status") || "pending_review";
  const reason = field(formData, "motivo");
  const displayOrder = Number(field(formData, "ordem_exibicao") || "100");
  if (!code || !name || !reason) redirect("/cadastros/tipos-insumo?result=missing_required#novo-tipo");
  if (!STATUS.has(status) || !Number.isInteger(displayOrder) || displayOrder < 0) redirect("/cadastros/tipos-insumo?result=invalid_value#novo-tipo");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_tipo_insumo", {
    p_codigo: code, p_descricao: optionalField(formData, "descricao"), p_motivo: reason,
    p_nome: name, p_ordem_exibicao: displayOrder, p_status: status
  });
  if (error) redirectResult(mapError(error.message), "#novo-tipo");
  refreshCatalog();
  redirectResult("input_type_created");
}

export async function updateInputTypeAction(formData: FormData) {
  requireConfigured("/cadastros/tipos-insumo?result=not_configured");
  const id = positiveInteger(formData, "tipo_insumo_id");
  const code = field(formData, "codigo").toUpperCase();
  const name = field(formData, "nome");
  const reason = field(formData, "motivo");
  const displayOrder = Number(field(formData, "ordem_exibicao") || "100");
  if (!id || !code || !name || !reason || !Number.isInteger(displayOrder) || displayOrder < 0) redirectResult("missing_required", "#editar-tipo", id);
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_tipo_insumo", {
    p_codigo: code, p_descricao: optionalField(formData, "descricao"), p_motivo: reason,
    p_nome: name, p_ordem_exibicao: displayOrder, p_tipo_insumo_id: id
  });
  if (error) redirectResult(mapError(error.message), "#editar-tipo", id);
  refreshCatalog();
  redirectResult("input_type_updated", "#editar-tipo", id);
}

export async function activateInputTypeAction(formData: FormData) {
  return changeStatus(formData, "activate_cad_tipo_insumo", "input_type_activated");
}

export async function deactivateInputTypeAction(formData: FormData) {
  return changeStatus(formData, "deactivate_cad_tipo_insumo", "input_type_deactivated");
}

export async function setMaterialInputTypeAction(formData: FormData) {
  requireConfigured("/cadastros/materias-primas?result=not_configured");
  const materialId = positiveInteger(formData, "materia_prima_id");
  const inputTypeId = optionalPositiveInteger(formData, "tipo_insumo_id");
  const reason = field(formData, "motivo");
  if (!materialId || !reason) redirect("/cadastros/materias-primas?result=missing_required#classificacao");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "set_cad_materia_prima_tipo", {
    p_materia_prima_id: materialId, p_motivo: reason, p_tipo_insumo_id: inputTypeId
  });
  if (error) redirect(`/cadastros/materias-primas?selected=${materialId}&result=${mapError(error.message)}#classificacao`);
  refreshCatalog();
  redirect(`/cadastros/materias-primas?selected=${materialId}&result=material_input_type_saved#classificacao`);
}

export async function createGovernedMaterialAction(formData: FormData) {
  requireConfigured("/cadastros/materias-primas?result=not_configured");
  const name = field(formData, "nome");
  const sku = field(formData, "sku_corrigido").toUpperCase();
  const unit = field(formData, "unidade_base_estoque").toUpperCase();
  const status = field(formData, "status") || "active";
  const inputTypeId = optionalPositiveInteger(formData, "tipo_insumo_id");
  if (!name || !sku || !unit) redirect("/cadastros/materias-primas?result=missing_required#nova-mp");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_materia_prima_governada", {
    p_codigo_ads: optionalField(formData, "codigo_ads"), p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_densidade: optionalNumber(formData, "densidade"), p_estoque_minimo: optionalNumber(formData, "estoque_minimo"),
    p_ibama: optionalField(formData, "ibama"), p_ncm: optionalField(formData, "ncm"),
    p_nome: name, p_nome_norm: normalizeKey(name),
    p_payload_origem_json: { source: "cadastros_materias_primas", governed_input_type: true },
    p_sku_corrigido: sku, p_status: status, p_tipo_insumo_id: inputTypeId, p_unidade_base_estoque: unit
  });
  if (error) redirect(`/cadastros/materias-primas?result=${mapError(error.message)}#nova-mp`);
  refreshCatalog();
  redirect("/cadastros/materias-primas?result=mp_created#nova-mp");
}

async function changeStatus(formData: FormData, rpc: string, result: string) {
  requireConfigured("/cadastros/tipos-insumo?result=not_configured");
  const id = positiveInteger(formData, "tipo_insumo_id");
  const reason = field(formData, "motivo");
  if (!id || !reason) redirectResult("missing_required", "#editar-tipo", id);
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, rpc, { p_motivo: reason, p_tipo_insumo_id: id });
  if (error) redirectResult(mapError(error.message), "#editar-tipo", id);
  refreshCatalog();
  redirectResult(result, "#editar-tipo", id);
}

function refreshCatalog() {
  revalidatePath("/cadastros/tipos-insumo");
  revalidatePath("/cadastros/materias-primas");
  revalidatePath("/cadastros/tecnicos");
}
function requireConfigured(target: string) { if (!getRuntimeStatus().supabaseConfigured) redirect(target); }
function redirectResult(result: string, hash = "", selected?: number | null): never {
  redirect(`/cadastros/tipos-insumo?result=${encodeURIComponent(result)}${selected ? `&selected=${selected}` : ""}${hash}`);
}
function field(data: FormData, key: string) { return String(data.get(key) ?? "").trim(); }
function optionalField(data: FormData, key: string) { return field(data, key) || null; }
function positiveInteger(data: FormData, key: string) { const value = Number(field(data, key)); return Number.isInteger(value) && value > 0 ? value : null; }
function optionalPositiveInteger(data: FormData, key: string) { return field(data, key) ? positiveInteger(data, key) : null; }
function optionalNumber(data: FormData, key: string) { const raw = field(data, key).replace(",", "."); return raw ? Number(raw) : null; }
function mapError(message: string) {
  const value = message.toLowerCase();
  if (value.includes("not allowed")) return "not_allowed";
  if (value.includes("duplicate") || value.includes("unique")) return "duplicated";
  if (value.includes("active input type not found")) return "invalid_input_type";
  if (value.includes("not found")) return "not_found";
  if (value.includes("required")) return "missing_required";
  return "operation_failed";
}
