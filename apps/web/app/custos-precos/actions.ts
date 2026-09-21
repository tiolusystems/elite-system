"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";

import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { validateCalculation, validatePolicy, validateReview, validateScenario, type PricingFieldErrors, type PricingValidation } from "./pricing-form-validation";
import type { PricingActionState } from "./pricing-action-state";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function createPricingPolicyAction(_previous: PricingActionState, formData: FormData): Promise<PricingActionState> {
  const validation = validatePolicy(formData);
  const rejected = rejectedInput(formData, validation);
  if (rejected) return rejected;
  return call("salvar_prc_politica_versao_v2_idempotente", "precificacao.policy.manage", "prc_politica_versoes", {
    p_key: key(formData), ...validation.payload!,
  }, "policy", values(formData));
}

export async function reviewPricingPolicyAction(_previous: PricingActionState, formData: FormData): Promise<PricingActionState> {
  const validation = validateReview(formData, "versao_id");
  const rejected = rejectedInput(formData, validation);
  if (rejected) return rejected;
  return call("decidir_prc_politica_versao_idempotente", "precificacao.policy.review", "prc_politica_revisoes", {
    p_key: key(formData), p_versao_id: validation.payload!.id, p_decisao: validation.payload!.decisao, p_justificativa: validation.payload!.justificativa,
  }, "policy-review", values(formData));
}

export async function createPricingScenarioAction(_previous: PricingActionState, formData: FormData): Promise<PricingActionState> {
  const validation = validateScenario(formData);
  const rejected = rejectedInput(formData, validation);
  if (rejected) return rejected;
  return call("criar_prc_cenario_idempotente", "precificacao.scenario.manage", "prc_cenarios", {
    p_key: key(formData), ...validation.payload!,
  }, "scenario", values(formData));
}

export async function calculatePricingScenarioAction(_previous: PricingActionState, formData: FormData): Promise<PricingActionState> {
  const validation = validateCalculation(formData);
  const rejected = rejectedInput(formData, validation);
  if (rejected) return rejected;
  return call("calcular_prc_cenario_idempotente", "precificacao.calculate", "prc_calculos", {
    p_key: key(formData), ...validation.payload!,
  }, "calculation", values(formData));
}

export async function reviewPricingCalculationAction(_previous: PricingActionState, formData: FormData): Promise<PricingActionState> {
  const validation = validateReview(formData, "calculo_id");
  const rejected = rejectedInput(formData, validation);
  if (rejected) return rejected;
  return call("decidir_prc_calculo_idempotente", "precificacao.calculation.review", "prc_calculo_decisoes", {
    p_key: key(formData), p_calculo_id: validation.payload!.id, p_decisao: validation.payload!.decisao, p_justificativa: validation.payload!.justificativa,
  }, "calculation-review", values(formData));
}

async function call(functionName: string, actionKey: string, entity: string, args: Record<string, unknown>, result: string, inputValues: Record<string, string>): Promise<PricingActionState> {
  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await auditedRpc(supabase, functionName, args, {
      origin: "apps/web/app/custos-precos",
      metadata: { action_key: actionKey, axis: "field_risk", domain: "precificacao", entity, failure_action: `precificacao.${result}.failed`, correlation_id: String(args.p_key) },
    });
    if (error) return rpcFailure(error.message, inputValues);
  } catch {
    return failure("Nao foi possivel concluir a operacao.", inputValues, {}, randomUUID());
  }
  revalidatePath("/custos-precos");
  return success(successMessage(result));
}

function rejectedInput<T>(formData: FormData, validation: PricingValidation<T>) {
  const fieldErrors = { ...validation.fieldErrors };
  if (!UUID.test(key(formData))) fieldErrors.idempotency_key = "Atualize a pagina e tente novamente.";
  return Object.keys(fieldErrors).length ? failure("Revise os campos destacados antes de continuar.", values(formData), fieldErrors) : null;
}

function rpcFailure(message: string, inputValues: Record<string, string>) {
  const value = message.toLocaleLowerCase("pt-BR");
  if (value.includes("prc_politica_versoes_check") || value.includes("margem") || value.includes("markup")) {
    return failure("O metodo escolhido aceita somente o percentual aplicavel.", inputValues, { metodo: "Para Margem liquida, Markup nao se aplica. Para Markup, Lucro minimo nao se aplica." });
  }
  if (value.includes("not allowed") || value.includes("permission")) return failure("Sua conta nao possui alcada para esta etapa.", inputValues);
  if (value.includes("denominador")) return failure("O conjunto de taxas torna o denominador invalido.", inputValues);
  if (value.includes("componente") || value.includes("fonte")) return failure("Todos os componentes e suas fontes precisam estar resolvidos.", inputValues);
  if (value.includes("criador")) return failure("A mesma pessoa nao pode criar e aprovar este fato.", inputValues);
  if (value.includes("idempotencia")) return failure("A solicitacao foi reutilizada com conteudo diferente.", inputValues);
  return failure("Nao foi possivel concluir a operacao.", inputValues, {}, randomUUID());
}

function success(message: string): PricingActionState {
  return { status: "success", message, fieldErrors: {}, values: {}, resultId: randomUUID(), occurrenceId: null };
}

function failure(message: string, inputValues: Record<string, string>, fieldErrors: PricingFieldErrors = {}, occurrenceId: string | null = null): PricingActionState {
  return { status: "error", message, fieldErrors, values: inputValues, resultId: randomUUID(), occurrenceId };
}

function successMessage(result: string) {
  return ({ policy: "Versao de politica criada e enviada para revisao.", "policy-review": "Decisao da politica registrada.", scenario: "Cenario e fontes congelados.", calculation: "Memoria de calculo registrada com 18 prazos.", "calculation-review": "Decisao do calculo registrada." } as Record<string, string>)[result] ?? "Operacao concluida.";
}

function values(formData: FormData) {
  const inputValues: Record<string, string> = {};
  for (const [name, value] of formData.entries()) if (name !== "idempotency_key") inputValues[name] = String(value);
  return inputValues;
}

function key(formData: FormData) {
  return String(formData.get("idempotency_key") ?? "").trim();
}
