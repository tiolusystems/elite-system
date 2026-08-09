"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_STAGES = new Set([
  "producao",
  "separacao_mp",
  "conferencia_mp",
  "formulacao",
  "amostragem",
  "controle_qualidade",
  "limpeza_equipamento",
  "liberacao_equipamento",
  "envase"
]);

export async function createControlledProcedureVersionAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) redirectWith("not_configured", "novo-pop");

  const code = field(formData, "codigo");
  const title = field(formData, "titulo");
  const purpose = field(formData, "finalidade");
  const revision = field(formData, "revisao");
  const effectiveFrom = field(formData, "vigencia_inicio");
  const documentReference = field(formData, "referencia_documental");
  const content = field(formData, "conteudo");
  const reason = field(formData, "justificativa");
  if (!code || !title || !purpose || !revision || !effectiveFrom || !documentReference || !content || reason.length < 10) {
    redirectWith("missing_required", "novo-pop");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_pcp_pop_version", {
    p_codigo: code,
    p_conteudo: content,
    p_finalidade: purpose,
    p_justificativa: reason,
    p_pop_id: optionalInteger(formData, "pop_id"),
    p_referencia_documental: documentReference,
    p_revisao: revision,
    p_titulo: title,
    p_vigencia_inicio: effectiveFrom
  });
  if (error) redirectWith(mapError(error.message), "novo-pop");
  finish("version_created");
}

export async function publishControlledProcedureVersionAction(formData: FormData) {
  const versionId = optionalInteger(formData, "pop_versao_id");
  const reason = field(formData, "justificativa");
  if (!versionId || reason.length < 10) redirectWith("missing_reason", "catalogo-pops");

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "publish_pcp_pop_version", {
    p_justificativa: reason,
    p_pop_versao_id: versionId
  });
  if (error) redirectWith(mapError(error.message), "catalogo-pops");
  finish("version_published");
}

export async function setControlledProcedureStateAction(formData: FormData) {
  const popId = optionalInteger(formData, "pop_id");
  const active = field(formData, "active") === "true";
  const reason = field(formData, "motivo");
  if (!popId || reason.length < 10) redirectWith("missing_reason", "catalogo-pops");

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "set_pcp_pop_active_state", {
    p_active: active,
    p_motivo: reason,
    p_pop_id: popId
  });
  if (error) redirectWith(mapError(error.message), "catalogo-pops");
  finish(active ? "pop_activated" : "pop_deactivated");
}

export async function setControlledProcedureApplicabilityAction(formData: FormData) {
  const versionId = optionalInteger(formData, "pop_versao_id");
  const stage = field(formData, "etapa");
  const active = field(formData, "active") !== "false";
  const displayOrder = optionalInteger(formData, "ordem_exibicao") ?? 0;
  const reason = field(formData, "motivo");
  if (!versionId || !ALLOWED_STAGES.has(stage) || displayOrder < 0 || reason.length < 10) {
    redirectWith("invalid_applicability", "aplicabilidade");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "set_pcp_pop_applicability", {
    p_active: active,
    p_etapa: stage,
    p_formula_versao_id: optionalInteger(formData, "formula_versao_id"),
    p_motivo: reason,
    p_ordem_exibicao: displayOrder,
    p_pop_versao_id: versionId
  });
  if (error) redirectWith(mapError(error.message), "aplicabilidade");
  finish(active ? "applicability_added" : "applicability_removed");
}

function finish(result: string): never {
  revalidatePath("/qualidade/pops");
  revalidatePath("/producao/ordens");
  revalidatePath("/producao/qualidade");
  redirect(`/qualidade/pops?result=${result}`);
}

function redirectWith(result: string, anchor: string): never {
  redirect(`/qualidade/pops?result=${encodeURIComponent(result)}#${anchor}`);
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = Number(field(formData, name));
  return Number.isInteger(value) && value > 0 ? value : null;
}

function mapError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("not allowed")) return "permission_denied";
  if (normalized.includes("module unavailable")) return "module_unavailable";
  if (normalized.includes("duplicate") || normalized.includes("unique")) return "duplicate";
  if (normalized.includes("already has")) return "same_state";
  if (normalized.includes("published and effective")) return "publish_required";
  if (normalized.includes("must be active")) return "active_required";
  return "operation_failed";
}
