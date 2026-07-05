"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_FORMULA_TYPES = new Set(["producao", "mapa"]);
const ALLOWED_COMPONENT_TYPES = new Set(["MP", "PA", "PI"]);
const ALLOWED_OP_TYPES = new Set(["estoque", "experimental", "desenvolvimento", "reprocessamento", "mapa_documental"]);
const ALLOWED_CQ_STATUS = new Set(["aprovado", "bloqueado", "reprovado"]);
const ALLOWED_OUTPUT_TYPES = new Set(["PA", "PI"]);

type FormulaComponentPayload = {
  tipo_componente: string;
  materia_prima_id?: number;
  produto_embalagem_id?: number;
  produto_id?: number;
  quantidade: number;
  unidade?: string;
  observacao?: string;
};

type OutputPayload = {
  tipo_produto: string;
  produto_embalagem_id?: number;
  produto_id?: number;
  quantidade: number;
  observacao?: string;
};

export async function createPcpFormulaAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#nova-formula");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const tipoReceita = field(formData, "tipo_receita") || "producao";
  const justificativa = field(formData, "justificativa");
  const componentes = parseFormulaComponents(formData);

  if (!produtoId || !Number.isInteger(produtoId) || produtoId <= 0 || !justificativa) {
    redirect("/pcp?result=missing_formula_required#nova-formula");
  }
  if (!ALLOWED_FORMULA_TYPES.has(tipoReceita)) {
    redirect("/pcp?result=invalid_formula_type#nova-formula");
  }
  if (tipoReceita === "producao" && componentes.length === 0) {
    redirect("/pcp?result=missing_formula_components#nova-formula");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_pcp_formula_versao", {
    p_componentes_jsonb: componentes,
    p_justificativa: justificativa,
    p_observacao: optionalField(formData, "observacao"),
    p_produto_id: produtoId,
    p_tipo_receita: tipoReceita
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#nova-formula`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=formula_created#formulas");
}

export async function activatePcpFormulaAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#formulas");
  }

  const formulaVersionId = optionalInteger(formData, "formula_versao_id");
  const motivo = field(formData, "motivo");
  if (!formulaVersionId || formulaVersionId <= 0 || !motivo) {
    redirect("/pcp?result=missing_activation_required#formulas");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "activate_pcp_formula_versao", {
    p_formula_versao_id: formulaVersionId,
    p_motivo: motivo
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#formulas`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=formula_activated#formulas");
}

export async function createPcpOpAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#nova-op");
  }

  const formulaVersionId = optionalInteger(formData, "formula_versao_id");
  const tipoOp = field(formData, "tipo_op") || "estoque";
  const quantidadePlanejada = optionalNumber(formData, "quantidade_planejada");

  if (!formulaVersionId || formulaVersionId <= 0) {
    redirect("/pcp?result=missing_op_required#nova-op");
  }
  if (!ALLOWED_OP_TYPES.has(tipoOp)) {
    redirect("/pcp?result=invalid_op_type#nova-op");
  }
  if (quantidadePlanejada !== null && (!Number.isFinite(quantidadePlanejada) || quantidadePlanejada <= 0)) {
    redirect("/pcp?result=invalid_positive_number#nova-op");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_pcp_op", {
    p_formula_versao_id: formulaVersionId,
    p_observacao: optionalField(formData, "observacao"),
    p_quantidade_planejada: quantidadePlanejada,
    p_tipo_op: tipoOp
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#nova-op`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=op_created#ops");
}

export async function reservePcpComponentAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#ops");
  }

  const opComponentId = optionalInteger(formData, "op_componente_id");
  const tipoComponente = field(formData, "tipo_componente").toUpperCase();
  const loteId = optionalInteger(formData, "lote_id");
  const quantidadeReservada = optionalNumber(formData, "quantidade_reservada");

  if (!opComponentId || opComponentId <= 0 || !loteId || loteId <= 0) {
    redirect("/pcp?result=missing_reservation_required#ops");
  }
  if (!ALLOWED_COMPONENT_TYPES.has(tipoComponente)) {
    redirect("/pcp?result=invalid_component_type#ops");
  }
  if (quantidadeReservada !== null && (!Number.isFinite(quantidadeReservada) || quantidadeReservada <= 0)) {
    redirect("/pcp?result=invalid_positive_number#ops");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "reservar_pcp_op_componente", {
    p_lote_mp_id: tipoComponente === "MP" ? loteId : null,
    p_lote_pa_id: tipoComponente === "PA" ? loteId : null,
    p_lote_pi_id: tipoComponente === "PI" ? loteId : null,
    p_observacao: optionalField(formData, "observacao"),
    p_op_componente_id: opComponentId,
    p_quantidade_reservada: quantidadeReservada
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#ops`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=component_reserved#ops");
}

export async function startPcpOpAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#ops");
  }

  const opId = optionalInteger(formData, "op_id");
  if (!opId || opId <= 0) {
    redirect("/pcp?result=missing_op_required#ops");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "iniciar_pcp_op", {
    p_observacao: optionalField(formData, "observacao"),
    p_op_id: opId
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#ops`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=op_started#ops");
}

export async function finishPcpOpAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#ops");
  }

  const opId = optionalInteger(formData, "op_id");
  const cqStatus = field(formData, "cq_status") || "aprovado";
  const ph = optionalNumber(formData, "ph");
  const densidade = optionalNumber(formData, "densidade_kg_l");
  const volume = optionalNumber(formData, "volume_l");
  const massa = optionalNumber(formData, "massa_kg");
  const temperatura = optionalNumber(formData, "temperatura_c");
  const separadorMp = field(formData, "separador_mp");
  const conferenteMp = field(formData, "conferente_mp");
  const formuladores = parsePeopleList(field(formData, "formuladores"));
  const outputs = parseOutputs(formData);

  if (!opId || opId <= 0 || !separadorMp || !conferenteMp || formuladores.length === 0) {
    redirect("/pcp?result=missing_finish_required#ops");
  }
  if (!ALLOWED_CQ_STATUS.has(cqStatus)) {
    redirect("/pcp?result=invalid_cq_status#ops");
  }
  if ([ph, densidade, volume, massa, temperatura].some((value) => value === null || !Number.isFinite(value))) {
    redirect("/pcp?result=missing_cq_numbers#ops");
  }
  if (outputs.length === 0) {
    redirect("/pcp?result=missing_outputs#ops");
  }

  const supabase = await createSupabaseServerClient();
  const correlationId = `pcp_op:${opId}:finish`;
  const { error } = await auditedRpc(supabase, "finalizar_pcp_op", {
    p_conferente_mp: conferenteMp,
    p_cq_status: cqStatus,
    p_densidade_kg_l: densidade,
    p_formuladores_jsonb: formuladores,
    p_massa_kg: massa,
    p_observacao: optionalField(formData, "observacao_finalizacao"),
    p_op_id: opId,
    p_outputs_jsonb: outputs,
    p_ph: ph,
    p_separador_mp: separadorMp,
    p_temperatura_c: temperatura,
    p_volume_l: volume
  }, {
    metadata: {
      action_key: "pcp.op.finish",
      axis: "movement_event",
      correlation_id: correlationId,
      domain: "pcp",
      entity: "pcp_ordens_producao",
      entity_id: opId,
      failure_action: "pcp.op_finish_failed"
    },
    origin: "apps/web/pcp.finish"
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#ops`);
  }

  revalidatePath("/pcp");
  revalidatePath("/relatorios");
  redirect("/pcp?result=op_finished#ops");
}

export async function cancelPcpOpAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/pcp?result=not_configured#ops");
  }

  const opId = optionalInteger(formData, "op_id");
  const motivo = field(formData, "motivo");
  if (!opId || opId <= 0 || !motivo) {
    redirect("/pcp?result=missing_cancel_required#ops");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "cancelar_pcp_op", {
    p_motivo: motivo,
    p_op_id: opId
  });

  if (error) {
    redirect(`/pcp?result=${encodeURIComponent(mapPcpError(error.message))}#ops`);
  }

  revalidatePath("/pcp");
  redirect("/pcp?result=op_cancelled#ops");
}

function parseFormulaComponents(formData: FormData): FormulaComponentPayload[] {
  const components: FormulaComponentPayload[] = [];
  for (let index = 1; index <= 6; index += 1) {
    const tipo = field(formData, `component_${index}_tipo`).toUpperCase();
    const targetId = optionalInteger(formData, `component_${index}_target_id`);
    const quantidade = optionalNumber(formData, `component_${index}_quantidade`);
    const unidade = optionalField(formData, `component_${index}_unidade`);
    const observacao = optionalField(formData, `component_${index}_observacao`);

    if (!tipo && !targetId && quantidade === null) {
      continue;
    }
    if (!ALLOWED_COMPONENT_TYPES.has(tipo) || !targetId || targetId <= 0 || quantidade === null || quantidade <= 0) {
      redirect("/pcp?result=invalid_component_row#nova-formula");
    }

    const payload: FormulaComponentPayload = {
      tipo_componente: tipo,
      quantidade
    };
    if (unidade) {
      payload.unidade = unidade;
    }
    if (observacao) {
      payload.observacao = observacao;
    }
    if (tipo === "MP") {
      payload.materia_prima_id = targetId;
    } else if (tipo === "PA") {
      payload.produto_embalagem_id = targetId;
    } else {
      payload.produto_id = targetId;
    }
    components.push(payload);
  }
  return components;
}

function parseOutputs(formData: FormData): OutputPayload[] {
  const outputs: OutputPayload[] = [];
  for (let index = 1; index <= 3; index += 1) {
    const tipo = field(formData, `output_${index}_tipo`).toUpperCase();
    const targetId = optionalInteger(formData, `output_${index}_target_id`);
    const quantidade = optionalNumber(formData, `output_${index}_quantidade`);
    const observacao = optionalField(formData, `output_${index}_observacao`);

    if (!tipo && !targetId && quantidade === null) {
      continue;
    }
    if (!ALLOWED_OUTPUT_TYPES.has(tipo) || !targetId || targetId <= 0 || quantidade === null || quantidade <= 0) {
      redirect("/pcp?result=invalid_output_row#ops");
    }

    const payload: OutputPayload = {
      tipo_produto: tipo,
      quantidade
    };
    if (observacao) {
      payload.observacao = observacao;
    }
    if (tipo === "PA") {
      payload.produto_embalagem_id = targetId;
    } else {
      payload.produto_id = targetId;
    }
    outputs.push(payload);
  }
  return outputs;
}

function parsePeopleList(value: string): string[] {
  return value
    .split(/[,\n;]/)
    .map((item) => item.trim())
    .filter(Boolean);
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

function mapPcpError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  if (normalized.includes("not found") || normalized.includes("foreign key")) {
    return "missing_related_record";
  }
  if (normalized.includes("production recipe requires")) {
    return "missing_formula_components";
  }
  if (normalized.includes("mapa documental op requires")) {
    return "invalid_mapa_formula";
  }
  if (normalized.includes("operational op requires")) {
    return "invalid_operational_formula";
  }
  if (normalized.includes("exceeds planned") || normalized.includes("reservations must match")) {
    return "reservation_mismatch";
  }
  if (normalized.includes("insufficient stock")) {
    return "insufficient_stock";
  }
  if (normalized.includes("without full active reservation")) {
    return "missing_full_reservation";
  }
  if (normalized.includes("already has cq")) {
    return "already_finished";
  }
  if (normalized.includes("status does not allow")) {
    return "invalid_status";
  }
  if (normalized.includes("required") || normalized.includes("must be")) {
    return "missing_required";
  }
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  return "save_failed";
}
