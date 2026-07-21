"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_FORMULA_TYPES = new Set(["producao", "mapa"]);
const ALLOWED_COMPONENT_TYPES = new Set(["MP", "PA", "PI"]);
const ALLOWED_OP_TYPES = new Set(["estoque", "experimental", "desenvolvimento", "reprocessamento"]);
const ALLOWED_CQ_STATUS = new Set(["aprovado", "bloqueado", "reprovado"]);
const ALLOWED_OUTPUT_TYPES = new Set(["PA", "PI"]);
const ALLOWED_GUARANTEE_LIMITS = new Set(["minimo", "maximo", "faixa", "declarado"]);
const ALLOWED_GUARANTEE_SOURCES = new Set(["mapa", "manual", "laboratorio", "fornecedor", "calculado"]);

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

type OpReturnTarget = {
  path: "/producao/ordens" | "/producao/transformacoes";
  createAnchor: "nova-op" | "nova-transformacao";
  queueAnchor: "ops" | "transformacoes";
};

export async function createPcpFormulaAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/formulas?result=not_configured#nova-formula");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const tipoReceita = field(formData, "tipo_receita") || "producao";
  const justificativa = field(formData, "justificativa");
  const componentes = parseFormulaComponents(formData);

  if (!produtoId || !Number.isInteger(produtoId) || produtoId <= 0 || !justificativa) {
    redirect("/producao/formulas?result=missing_formula_required#nova-formula");
  }
  if (!ALLOWED_FORMULA_TYPES.has(tipoReceita)) {
    redirect("/producao/formulas?result=invalid_formula_type#nova-formula");
  }
  if (tipoReceita === "producao" && componentes.length === 0) {
    redirect("/producao/formulas?result=missing_formula_components#nova-formula");
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
    redirect(`/producao/formulas?result=${encodeURIComponent(mapPcpError(error.message))}#nova-formula`);
  }

  revalidatePath("/pcp");
  redirect("/producao/formulas?result=formula_created#formulas");
}

export async function activatePcpFormulaAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/formulas?result=not_configured#formulas");
  }

  const formulaVersionId = optionalInteger(formData, "formula_versao_id");
  const motivo = field(formData, "motivo");
  if (!formulaVersionId || formulaVersionId <= 0 || !motivo) {
    redirect("/producao/formulas?result=missing_activation_required#formulas");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "activate_pcp_formula_versao", {
    p_formula_versao_id: formulaVersionId,
    p_motivo: motivo
  });

  if (error) {
    redirect(`/producao/formulas?result=${encodeURIComponent(mapPcpError(error.message))}#formulas`);
  }

  revalidatePath("/pcp");
  redirect("/producao/formulas?result=formula_activated#formulas");
}

export async function createPcpOpAction(formData: FormData) {
  const returnTarget = opReturnTarget(formData);
  if (!getRuntimeStatus().supabaseConfigured) {
    redirectWithResult(returnTarget.path, "not_configured", returnTarget.createAnchor);
  }

  const formulaVersionId = optionalInteger(formData, "formula_versao_id");
  const tipoOp = field(formData, "tipo_op") || "estoque";
  const quantidadePlanejada = optionalNumber(formData, "quantidade_planejada");

  if (!formulaVersionId || formulaVersionId <= 0) {
    redirectWithResult(returnTarget.path, "missing_op_required", returnTarget.createAnchor);
  }
  if (!ALLOWED_OP_TYPES.has(tipoOp)) {
    redirectWithResult(returnTarget.path, "invalid_op_type", returnTarget.createAnchor);
  }
  if (quantidadePlanejada !== null && (!Number.isFinite(quantidadePlanejada) || quantidadePlanejada <= 0)) {
    redirectWithResult(returnTarget.path, "invalid_positive_number", returnTarget.createAnchor);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_pcp_op", {
    p_formula_versao_id: formulaVersionId,
    p_observacao: optionalField(formData, "observacao"),
    p_quantidade_planejada: quantidadePlanejada,
    p_tipo_op: tipoOp
  });

  if (error) {
    redirectWithResult(returnTarget.path, mapPcpError(error.message), returnTarget.createAnchor);
  }

  revalidateProductionPaths();
  redirectWithResult(returnTarget.path, "op_created", returnTarget.queueAnchor);
}

export async function reservePcpComponentAction(formData: FormData) {
  const returnTarget = opReturnTarget(formData);
  if (!getRuntimeStatus().supabaseConfigured) {
    redirectWithResult(returnTarget.path, "not_configured", returnTarget.queueAnchor);
  }

  const opComponentId = optionalInteger(formData, "op_componente_id");
  const tipoComponente = field(formData, "tipo_componente").toUpperCase();
  const loteId = optionalInteger(formData, "lote_id");
  const quantidadeReservada = optionalNumber(formData, "quantidade_reservada");

  if (!opComponentId || opComponentId <= 0 || !loteId || loteId <= 0) {
    redirectWithResult(returnTarget.path, "missing_reservation_required", returnTarget.queueAnchor);
  }
  if (!ALLOWED_COMPONENT_TYPES.has(tipoComponente)) {
    redirectWithResult(returnTarget.path, "invalid_component_type", returnTarget.queueAnchor);
  }
  if (quantidadeReservada !== null && (!Number.isFinite(quantidadeReservada) || quantidadeReservada <= 0)) {
    redirectWithResult(returnTarget.path, "invalid_positive_number", returnTarget.queueAnchor);
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
    redirectWithResult(returnTarget.path, mapPcpError(error.message), returnTarget.queueAnchor);
  }

  revalidateProductionPaths();
  redirectWithResult(returnTarget.path, "component_reserved", returnTarget.queueAnchor);
}

export async function startPcpOpAction(formData: FormData) {
  const returnTarget = opReturnTarget(formData);
  if (!getRuntimeStatus().supabaseConfigured) {
    redirectWithResult(returnTarget.path, "not_configured", returnTarget.queueAnchor);
  }

  const opId = optionalInteger(formData, "op_id");
  if (!opId || opId <= 0) {
    redirectWithResult(returnTarget.path, "missing_op_required", returnTarget.queueAnchor);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "iniciar_pcp_op", {
    p_observacao: optionalField(formData, "observacao"),
    p_op_id: opId
  });

  if (error) {
    redirectWithResult(returnTarget.path, mapPcpError(error.message), returnTarget.queueAnchor);
  }

  revalidateProductionPaths();
  redirectWithResult(returnTarget.path, "op_started", returnTarget.queueAnchor);
}

export async function finishPcpOpAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/qualidade?result=not_configured#cq-pendente");
  }

  const opId = optionalInteger(formData, "op_id");
  const cqStatus = field(formData, "cq_status") || "aprovado";
  const ph = optionalNumber(formData, "ph");
  const densidade = optionalNumber(formData, "densidade_kg_l");
  const volume = optionalNumber(formData, "volume_l");
  const massa = optionalNumber(formData, "massa_kg");
  const temperatura = optionalNumber(formData, "temperatura_c");
  const separadorPessoaId = optionalInteger(formData, "separador_pessoa_id");
  const conferentePessoaId = optionalInteger(formData, "conferente_pessoa_id");
  const formuladorIds = Array.from({ length: 3 }, (_, index) =>
    optionalInteger(formData, `formulador_${index + 1}_pessoa_id`)
  ).filter((value): value is number => value !== null);
  const outputs = parseOutputs(formData);

  if (!opId || opId <= 0 || !separadorPessoaId || !conferentePessoaId || formuladorIds.length === 0) {
    redirect("/producao/qualidade?result=missing_finish_required#cq-pendente");
  }
  if (!ALLOWED_CQ_STATUS.has(cqStatus)) {
    redirect("/producao/qualidade?result=invalid_cq_status#cq-pendente");
  }
  if ([ph, densidade, volume, massa, temperatura].some((value) => value === null || !Number.isFinite(value))) {
    redirect("/producao/qualidade?result=missing_cq_numbers#cq-pendente");
  }
  if (outputs.length === 0) {
    redirect("/producao/qualidade?result=missing_outputs#cq-pendente");
  }

  const supabase = await createSupabaseServerClient();
  const participantIds = [...new Set([separadorPessoaId, conferentePessoaId, ...formuladorIds])];
  const participants = await supabase
    .from("cad_pessoas_comerciais")
    .select("id,nome,status")
    .in("id", participantIds)
    .eq("status", "active");
  if (participants.error || (participants.data ?? []).length !== participantIds.length) {
    redirect("/producao/qualidade?result=invalid_participants#cq-pendente");
  }
  const participantNames = new Map((participants.data ?? []).map((person) => [Number(person.id), String(person.nome)]));
  const separadorMp = participantNames.get(separadorPessoaId);
  const conferenteMp = participantNames.get(conferentePessoaId);
  const formuladores = formuladorIds.map((id) => participantNames.get(id)).filter((name): name is string => Boolean(name));
  if (!separadorMp || !conferenteMp || formuladores.length !== formuladorIds.length) {
    redirect("/producao/qualidade?result=invalid_participants#cq-pendente");
  }
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
    redirect(`/producao/qualidade?result=${encodeURIComponent(mapPcpError(error.message))}#cq-pendente`);
  }

  revalidatePath("/pcp");
  revalidatePath("/producao");
  revalidatePath("/producao/ordens");
  revalidatePath("/producao/qualidade");
  revalidatePath("/relatorios");
  redirect("/producao/qualidade?result=op_finished#historico-cq");
}

export async function cancelPcpOpAction(formData: FormData) {
  const returnTarget = opReturnTarget(formData);
  if (!getRuntimeStatus().supabaseConfigured) {
    redirectWithResult(returnTarget.path, "not_configured", returnTarget.queueAnchor);
  }

  const opId = optionalInteger(formData, "op_id");
  const motivo = field(formData, "motivo");
  if (!opId || opId <= 0 || !motivo) {
    redirectWithResult(returnTarget.path, "missing_cancel_required", returnTarget.queueAnchor);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "cancelar_pcp_op", {
    p_motivo: motivo,
    p_op_id: opId
  });

  if (error) {
    redirectWithResult(returnTarget.path, mapPcpError(error.message), returnTarget.queueAnchor);
  }

  revalidateProductionPaths();
  redirectWithResult(returnTarget.path, "op_cancelled", returnTarget.queueAnchor);
}

export async function registerProductGuaranteeAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/garantias?result=not_configured");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const tipoLimite = field(formData, "tipo_limite").toLowerCase();
  const valor = optionalNumber(formData, "valor");
  const valorMaximo = optionalNumber(formData, "valor_maximo");
  const fonte = field(formData, "fonte").toLowerCase() || "mapa";
  const justificativa = field(formData, "justificativa");
  const documentoReferencia = optionalField(formData, "documento_referencia");

  if (!produtoId || !field(formData, "nutriente") || valor === null || valor < 0 || !field(formData, "unidade") || !justificativa) {
    redirect("/producao/garantias?result=missing_guarantee_required");
  }
  if (!ALLOWED_GUARANTEE_LIMITS.has(tipoLimite) || !ALLOWED_GUARANTEE_SOURCES.has(fonte)) {
    redirect("/producao/garantias?result=invalid_guarantee_type");
  }
  if ((fonte === "laboratorio" || fonte === "fornecedor") && !documentoReferencia) {
    redirect("/producao/garantias?result=missing_guarantee_document");
  }
  if (tipoLimite === "faixa" ? valorMaximo === null || valorMaximo < valor : valorMaximo !== null) {
    redirect("/producao/garantias?result=invalid_guarantee_range");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_pcp_garantia_produto", {
    p_documento_referencia: documentoReferencia,
    p_fonte: fonte,
    p_justificativa: justificativa,
    p_nutriente: field(formData, "nutriente"),
    p_produto_id: produtoId,
    p_tipo_limite: tipoLimite,
    p_unidade: field(formData, "unidade"),
    p_valor: valor,
    p_valor_maximo: valorMaximo,
    p_vigencia_fim: optionalField(formData, "vigencia_fim"),
    p_vigencia_inicio: optionalField(formData, "vigencia_inicio")
  });

  if (error) {
    redirect(`/producao/garantias?result=${encodeURIComponent(mapPcpError(error.message))}`);
  }

  revalidateProductionPaths();
  redirect("/producao/garantias?result=product_guarantee_registered");
}

export async function registerMpLotGuaranteeAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/garantias?result=not_configured");
  }

  const loteMpId = optionalInteger(formData, "lote_mp_id");
  const valor = optionalNumber(formData, "valor");
  const fonte = field(formData, "fonte").toLowerCase();
  const justificativa = field(formData, "justificativa");
  const documentoReferencia = optionalField(formData, "documento_referencia");
  if (!loteMpId || !field(formData, "nutriente") || valor === null || valor < 0 || !field(formData, "unidade") || !fonte || !field(formData, "data_referencia") || !justificativa) {
    redirect("/producao/garantias?result=missing_guarantee_required");
  }
  if (!ALLOWED_GUARANTEE_SOURCES.has(fonte)) {
    redirect("/producao/garantias?result=invalid_guarantee_type");
  }
  if ((fonte === "laboratorio" || fonte === "fornecedor") && !documentoReferencia) {
    redirect("/producao/garantias?result=missing_guarantee_document");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_pcp_garantia_lote_mp", {
    p_data_referencia: field(formData, "data_referencia"),
    p_documento_referencia: documentoReferencia,
    p_fonte: fonte,
    p_justificativa: justificativa,
    p_lote_mp_id: loteMpId,
    p_nutriente: field(formData, "nutriente"),
    p_unidade: field(formData, "unidade"),
    p_valor: valor
  });

  if (error) {
    redirect(`/producao/garantias?result=${encodeURIComponent(mapPcpError(error.message))}`);
  }

  revalidateProductionPaths();
  redirect("/producao/garantias?result=mp_lot_guarantee_registered");
}

export async function calculateOpGuaranteesAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/qualidade?result=not_configured#historico-cq");
  }

  const opId = optionalInteger(formData, "op_id");
  const justificativa = field(formData, "justificativa");
  if (!opId || !justificativa) {
    redirect("/producao/qualidade?result=missing_guarantee_calculation#historico-cq");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "calcular_pcp_garantias_op", {
    p_justificativa: justificativa,
    p_op_id: opId
  });
  if (error) {
    redirect(`/producao/qualidade?result=${encodeURIComponent(mapPcpError(error.message))}#historico-cq`);
  }

  revalidateProductionPaths();
  revalidatePath("/producao/qualidade");
  redirect("/producao/qualidade?result=guarantees_calculated#historico-cq");
}

export async function releaseBlockedLotAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/producao/estoque?result=not_configured#lotes");
  }

  const tipoLote = field(formData, "tipo_lote").toUpperCase();
  const loteId = optionalInteger(formData, "lote_id");
  const motivo = field(formData, "motivo");
  if (!ALLOWED_OUTPUT_TYPES.has(tipoLote) || !loteId || !motivo) {
    redirect("/producao/estoque?result=missing_release_required#lotes");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "liberar_pcp_lote_bloqueado", {
    p_lote_id: loteId,
    p_motivo: motivo,
    p_tipo_lote: tipoLote
  });
  if (error) {
    redirect(`/producao/estoque?result=${encodeURIComponent(mapPcpError(error.message))}#lotes`);
  }

  revalidateProductionPaths();
  redirect("/producao/estoque?result=blocked_lot_released#lotes");
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
      redirect("/producao/formulas?result=invalid_component_row#nova-formula");
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
      redirect("/producao/qualidade?result=invalid_output_row#cq-pendente");
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
  return Number.isSafeInteger(parsed) && String(parsed) === value ? parsed : null;
}

function revalidateProductionPaths() {
  revalidatePath("/pcp");
  revalidatePath("/producao");
  revalidatePath("/producao/formulas");
  revalidatePath("/producao/garantias");
  revalidatePath("/producao/ordens");
  revalidatePath("/producao/qualidade");
  revalidatePath("/producao/estoque");
  revalidatePath("/producao/transformacoes");
  revalidatePath("/relatorios");
}

function opReturnTarget(formData: FormData): OpReturnTarget {
  if (field(formData, "return_to") === "transformacoes") {
    return {
      path: "/producao/transformacoes",
      createAnchor: "nova-transformacao",
      queueAnchor: "transformacoes"
    };
  }
  return {
    path: "/producao/ordens",
    createAnchor: "nova-op",
    queueAnchor: "ops"
  };
}

function redirectWithResult(path: OpReturnTarget["path"], result: string, anchor: string): never {
  redirect(`${path}?result=${encodeURIComponent(result)}#${anchor}`);
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
  if (normalized.includes("completed operational op") || normalized.includes("generated product")) {
    return "invalid_guarantee_op";
  }
  if (normalized.includes("guarantee") || normalized.includes("garantia")) {
    return "invalid_guarantee";
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
