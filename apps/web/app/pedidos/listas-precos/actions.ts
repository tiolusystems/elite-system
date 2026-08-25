"use server";

import { revalidatePath } from "next/cache";

import { parsePriceListWorkbook, PRICE_LIST_XLSX_MAX_BYTES } from "@/lib/price-list-xlsx";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type PriceListActionResult = {
  ok: boolean;
  code: string;
  message: string;
  analysisId?: number;
  publishedVersionId?: number;
};

export async function analyzePriceListWorkbookAction(formData: FormData): Promise<PriceListActionResult> {
  const file = formData.get("workbook");
  if (!(file instanceof File) || file.size === 0) return failure("missing_file", "Selecione a planilha XLSX preenchida.");
  if (!file.name.toLocaleLowerCase("pt-BR").endsWith(".xlsx")) return failure("invalid_extension", "Envie somente o modelo .xlsx, sem macros.");
  if (file.size > PRICE_LIST_XLSX_MAX_BYTES) return failure("file_too_large", "A planilha deve possuir no maximo 10 MB.");
  const reason = text(formData, "motivo");
  if (reason.length < 10) return failure("reason_required", "Informe um motivo com ao menos 10 caracteres.");
  let parsed;
  try {
    parsed = await parsePriceListWorkbook(Buffer.from(await file.arrayBuffer()));
  } catch (error) {
    return failure("invalid_workbook", error instanceof Error ? error.message : "Nao foi possivel analisar a planilha.");
  }
  const idempotencyKey = text(formData, "idempotency_key");
  if (!isUuid(idempotencyKey)) return failure("invalid_request", "Atualize a pagina e tente novamente.");
  const supabase = await createSupabaseServerClient();
  const { data, error } = await auditedRpc<Record<string, unknown>>(supabase, "analisar_com_lista_preco_xlsx_operacional_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_file_name: file.name,
    p_workbook_sha256: parsed.workbookSha256,
    p_size_bytes: file.size,
    p_lista: parsed.lista,
    p_linhas: parsed.linhas,
    p_motivo: reason,
  }, {
    origin: "apps/web/app/pedidos/listas-precos",
    metadata: {
      action_key: "pedidos.price_lists.import.stage",
      axis: "field_risk",
      domain: "pedidos",
      entity: "com_lista_preco_xlsx_analises",
      failure_action: "pedidos.price_list_xlsx_analysis_failed",
      correlation_id: idempotencyKey,
    },
  });
  if (error) return failure(mapError(error.message), userMessage(error.message));
  const analysisId = Number(data?.analise_id);
  if (!Number.isInteger(analysisId) || analysisId <= 0) return failure("invalid_response", "A analise nao retornou uma identificacao valida.");
  revalidatePath("/pedidos/listas-precos");
  return {
    ok: true,
    code: data?.workbook_repetido === true ? "workbook_repeated" : "analyzed",
    message: data?.workbook_repetido === true ? "Esta planilha ja foi importada. A analise existente foi aberta." : "Planilha analisada. Revise todos os avisos e erros.",
    analysisId,
  };
}

export async function publishPriceListAnalysisAction(formData: FormData): Promise<PriceListActionResult> {
  const analysisId = Number(text(formData, "analise_id"));
  const hash = text(formData, "canonical_payload_sha256").toLocaleLowerCase("pt-BR");
  const key = text(formData, "idempotency_key");
  const reason = text(formData, "motivo_publicacao");
  if (!Number.isInteger(analysisId) || analysisId <= 0 || !/^[0-9a-f]{64}$/.test(hash) || !isUuid(key)) return failure("invalid_request", "A analise mudou ou a solicitacao expirou. Atualize a pagina.");
  if (reason.length < 10) return failure("reason_required", "Informe um motivo de publicacao com ao menos 10 caracteres.");
  const supabase = await createSupabaseServerClient();
  const { data, error } = await auditedRpc<Record<string, unknown>>(supabase, "publicar_com_lista_preco_xlsx_operacional_idempotente", {
    p_idempotency_key: key,
    p_analise_id: analysisId,
    p_canonical_payload_sha256: hash,
    p_confirmar_avisos: formData.get("confirmar_avisos") === "on",
    p_motivo: reason,
  }, {
    origin: "apps/web/app/pedidos/listas-precos",
    metadata: {
      action_key: "pedidos.price_lists.publish",
      axis: "status_transition",
      domain: "pedidos",
      entity: "com_lista_preco_xlsx_publicacoes",
      failure_action: "pedidos.price_list_xlsx_publish_failed",
      correlation_id: key,
    },
  });
  if (error) return failure(mapError(error.message), userMessage(error.message));
  revalidatePath("/pedidos/listas-precos");
  return {
    ok: true,
    code: "published",
    message: "Nova versao publicada. A versao anterior foi preservada no historico.",
    analysisId,
    publishedVersionId: Number(data?.versao_id),
  };
}

function text(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function failure(code: string, message: string): PriceListActionResult {
  return { ok: false, code, message };
}

function mapError(message: string): string {
  const value = message.toLocaleLowerCase("pt-BR");
  if (value.includes("not allowed") || value.includes("permission")) return "permission_denied";
  if (value.includes("reutilizada") || value.includes("diverge")) return "stale_analysis";
  if (value.includes("avisos")) return "warnings_unconfirmed";
  if (value.includes("erros")) return "analysis_blocked";
  return "operation_failed";
}

function userMessage(message: string): string {
  const code = mapError(message);
  if (code === "permission_denied") return "Sua conta nao possui alcada para esta operacao.";
  if (code === "stale_analysis") return "O conteudo confirmado nao corresponde mais a analise. Atualize a pagina.";
  if (code === "warnings_unconfirmed") return "Confirme que revisou os avisos antes de publicar.";
  if (code === "analysis_blocked") return "Corrija todos os erros da planilha e gere uma nova analise.";
  return "Nao foi possivel concluir a operacao. Nenhuma versao parcial foi publicada.";
}
