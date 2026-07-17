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
  const unitId = positiveInteger(formData, "unidade_base_estoque_id");
  const status = field(formData, "status") || "active";
  const inputTypeId = optionalPositiveInteger(formData, "tipo_insumo_id");
  if (!name || !sku || !unitId) redirect("/cadastros/materias-primas?result=missing_required#nova-mp");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_materia_prima_governada", {
    p_codigo_ads: optionalField(formData, "codigo_ads"), p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_densidade: optionalNumber(formData, "densidade"), p_estoque_minimo: optionalNumber(formData, "estoque_minimo"),
    p_ibama: optionalField(formData, "ibama"), p_ncm: optionalField(formData, "ncm"),
    p_nome: name, p_nome_norm: normalizeKey(name),
    p_payload_origem_json: { source: "cadastros_materias_primas", governed_input_type: true },
    p_confirmar_possivel_duplicidade: false, p_motivo_duplicidade: null,
    p_sku_corrigido: sku, p_status: status, p_tipo_insumo_id: inputTypeId, p_unidade_base_estoque_id: unitId
  });
  if (error) redirect(`/cadastros/materias-primas?result=${mapError(error.message)}#nova-mp`);
  refreshCatalog();
  redirect("/cadastros/materias-primas?result=mp_created#nova-mp");
}

export type MaterialDuplicateCandidate = {
  materia_prima_id: number;
  sku_corrigido: string;
  nome: string;
  tipo_insumo_nome: string | null;
  unidade_nome: string;
  codigo_legado: string | null;
  motivos: string[];
};

export type GovernedMaterialCreateState = {
  status: "idle" | "review_required" | "created" | "error";
  message?: string;
  candidates: MaterialDuplicateCandidate[];
  values?: Record<string, string>;
};

export async function reviewAndCreateGovernedMaterialAction(
  _previous: GovernedMaterialCreateState,
  formData: FormData
): Promise<GovernedMaterialCreateState> {
  if (!getRuntimeStatus().supabaseConfigured) return { status: "error", message: "Ambiente não configurado.", candidates: [] };
  const values = Object.fromEntries([
    "nome", "sku_corrigido", "codigo_legado", "tipo_insumo_id", "unidade_base_estoque_id",
    "densidade", "estoque_minimo", "status", "ncm", "ibama", "codigo_ads"
  ].map((key) => [key, field(formData, key)]));
  const name = values.nome;
  const sku = values.sku_corrigido.toUpperCase();
  const unitId = positiveInteger(formData, "unidade_base_estoque_id");
  const inputTypeId = optionalPositiveInteger(formData, "tipo_insumo_id");
  if (!name || !sku || !unitId) return { status: "error", message: "Preencha nome, SKU e unidade base.", candidates: [], values };

  const supabase = await createSupabaseServerClient();
  const { data: possible, error: reviewError } = await auditedRpc<MaterialDuplicateCandidate[]>(
    supabase,
    "find_cad_materia_prima_possible_duplicates",
    { p_codigo_legado: values.codigo_legado || null, p_nome: name },
    { metadata: { action_key: "cadastros.materias_primas.create", axis: "field_risk", domain: "cadastros", entity: "cad_materias_primas" } }
  );
  if (reviewError) return { status: "error", message: "Não foi possível verificar duplicidades.", candidates: [], values };
  const candidates = possible ?? [];
  const confirmed = field(formData, "confirmar_possivel_duplicidade") === "sim";
  const duplicateReason = field(formData, "motivo_duplicidade");
  if (candidates.length > 0 && (!confirmed || !duplicateReason)) {
    return { status: "review_required", message: "Revise os registros semelhantes antes de confirmar.", candidates, values };
  }

  const { error } = await auditedRpc(supabase, "create_cad_materia_prima_governada", {
    p_codigo_ads: values.codigo_ads || null, p_codigo_legado: values.codigo_legado || null,
    p_confirmar_possivel_duplicidade: confirmed, p_densidade: optionalNumber(formData, "densidade"),
    p_estoque_minimo: optionalNumber(formData, "estoque_minimo"), p_ibama: values.ibama || null,
    p_motivo_duplicidade: duplicateReason || null, p_ncm: values.ncm || null,
    p_nome: name, p_nome_norm: normalizeKey(name),
    p_payload_origem_json: { source: "cadastros_materias_primas", governed_relations: true },
    p_sku_corrigido: sku, p_status: values.status || "active",
    p_tipo_insumo_id: inputTypeId, p_unidade_base_estoque_id: unitId
  });
  if (error) return { status: "error", message: mapCreateMaterialError(error.message), candidates, values };
  refreshCatalog();
  return { status: "created", message: "Matéria-prima cadastrada com sucesso.", candidates: [] };
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

function mapCreateMaterialError(message: string) {
  const value = message.toLowerCase();
  if (value.includes("duplicate") || value.includes("unique")) return "Já existe matéria-prima com este SKU.";
  if (value.includes("active base unit not found")) return "A unidade selecionada não está disponível.";
  if (value.includes("active input type not found")) return "O tipo de insumo selecionado não está disponível.";
  if (value.includes("not allowed")) return "Seu usuário não possui permissão para cadastrar matéria-prima.";
  return "Não foi possível cadastrar a matéria-prima. Revise os dados e tente novamente.";
}
