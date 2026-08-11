"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CommissionChangeReview = {
  requestId: string;
  orderCode: string;
  personName: string;
  role: string;
  percentage: number;
  orderTotal: number;
  receivedValue: number;
  expectedValue: number;
  immediateRelease: number;
  justification: string;
};

export type FinanceActionState = {
  status: "idle" | "review" | "success" | "error";
  message: string;
  fieldErrors: Record<string, string>;
  resultId: string;
  review: CommissionChangeReview | null;
};

export const INITIAL_FINANCE_ACTION_STATE: FinanceActionState = {
  status: "idle",
  message: "",
  fieldErrors: {},
  resultId: "",
  review: null,
};

export async function assignOrderCommissionAction(
  _previous: FinanceActionState,
  formData: FormData
): Promise<FinanceActionState> {
  if (!configured()) return failure("O serviço financeiro está indisponível neste ambiente.");

  const idempotencyKey = uuid(formData, "idempotency_key");
  const orderId = positiveInteger(formData, "pedido_id");
  const personId = positiveInteger(formData, "pessoa_id");
  const percentage = positiveNumber(formData, "percentual_comissao");
  const role = field(formData, "papel_comissao");
  const reason = field(formData, "justificativa");
  const fieldErrors: Record<string, string> = {};

  if (!orderId) fieldErrors.pedido_id = "Selecione uma venda liberada.";
  if (!personId) fieldErrors.pessoa_id = "Selecione a pessoa comissionada.";
  if (!percentage || percentage > 100) fieldErrors.percentual_comissao = "Informe um percentual maior que zero e de até 100%.";
  if (!new Set(["vendedor", "agente", "gerente", "tecnico_campo", "outro"]).has(role)) {
    fieldErrors.papel_comissao = "Selecione um papel válido.";
  }
  if (reason.length < 10) fieldErrors.justificativa = "Explique a participação com pelo menos 10 caracteres.";
  if (!idempotencyKey) fieldErrors.idempotency_key = "Atualize a página e tente novamente.";
  if (Object.keys(fieldErrors).length) {
    return failure("Revise os campos destacados antes de preparar a alteração.", fieldErrors);
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await auditedRpc(supabase, "propor_com_pedido_comissao_idempotente", {
    p_request_key: idempotencyKey,
    p_pedido_id: orderId,
    p_pessoa_id: personId,
    p_papel_comissao: role,
    p_percentual_comissao: percentage,
    p_justificativa: reason,
  }, {
    metadata: {
      action_key: "financeiro.commissions.revision.request",
      axis: "change_type",
      domain: "financeiro",
      entity: "com_comissao_alteracao_solicitacoes",
      entity_id: String(orderId),
      failure_action: "financeiro.comissao_revisao_failed",
    },
  });
  if (error) return rpcFailure(error.message, "assignment");

  const payload = record(data);
  const preview = record(payload.preview);
  const requestId = String(payload.solicitacao_id ?? "");
  if (!requestId) return failure("A revisão foi preparada, mas o identificador da confirmação não foi retornado.");

  return reviewState("Revise o impacto antes da confirmação final.", {
    requestId,
    orderCode: String(preview.pedido_codigo ?? ""),
    personName: String(preview.pessoa_nome ?? ""),
    role: String(preview.papel_comissao ?? role),
    percentage: Number(preview.percentual_comissao ?? percentage),
    orderTotal: Number(preview.pedido_valor_total ?? 0),
    receivedValue: Number(preview.valor_recebido_ativo ?? 0),
    expectedValue: Number(preview.valor_previsto ?? 0),
    immediateRelease: Number(preview.valor_liberavel_imediato_estimado ?? 0),
    justification: String(preview.justificativa ?? reason),
  });
}

export async function confirmOrderCommissionAction(
  _previous: FinanceActionState,
  formData: FormData
): Promise<FinanceActionState> {
  if (!configured()) return failure("O serviço financeiro está indisponível neste ambiente.");

  const requestId = uuid(formData, "solicitacao_id");
  if (!requestId) return failure("A revisão não possui um identificador válido. Refazer a revisão.");

  const supabase = await createSupabaseServerClient();
  const { data, error } = await auditedRpc(supabase, "confirmar_com_pedido_comissao_idempotente", {
    p_solicitacao_id: requestId,
  }, {
    metadata: {
      action_key: "financeiro.commissions.revision.confirm",
      axis: "change_type",
      domain: "financeiro",
      entity: "com_comissao_alteracao_solicitacoes",
      entity_id: requestId,
      failure_action: "financeiro.comissao_confirmacao_failed",
    },
  });
  if (error) return rpcFailure(error.message, "assignment");

  const releases = Number(record(data).liberacoes_recebimentos_existentes ?? 0);
  revalidateFinance();
  return success(
    releases > 0
      ? "Alteração confirmada. O novo direito foi registrado e os recebimentos existentes foram considerados na liberação proporcional."
      : "Alteração confirmada. O novo direito de comissão foi registrado."
  );
}

export async function registerReceiptAction(
  _previous: FinanceActionState,
  formData: FormData
): Promise<FinanceActionState> {
  if (!configured()) return failure("O serviço financeiro está indisponível neste ambiente.");

  const idempotencyKey = uuid(formData, "idempotency_key");
  const orderId = positiveInteger(formData, "pedido_id");
  const value = positiveNumber(formData, "valor_recebido");
  const receiptDate = field(formData, "data_recebimento");
  const documentReference = field(formData, "referencia_documental");
  const fieldErrors: Record<string, string> = {};

  if (!orderId) fieldErrors.pedido_id = "Selecione o pedido que recebeu o pagamento.";
  if (!value) fieldErrors.valor_recebido = "Informe um valor recebido maior que zero.";
  if (!receiptDate) fieldErrors.data_recebimento = "Informe a data do recebimento.";
  if (documentReference.length < 3) fieldErrors.referencia_documental = "Informe a referência documental do recebimento.";
  if (!idempotencyKey) fieldErrors.idempotency_key = "Atualize a página e tente novamente.";
  if (Object.keys(fieldErrors).length) return failure("Revise os campos destacados antes de registrar o recebimento.", fieldErrors);

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_com_recebimento_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_pedido_id: orderId,
    p_valor_recebido: value,
    p_data_recebimento: receiptDate,
    p_forma_recebimento: optionalField(formData, "forma_recebimento"),
    p_observacao: optionalField(formData, "observacao"),
    p_referencia_documental: documentReference,
  }, {
    metadata: {
      action_key: "financeiro.receipts.register",
      axis: "financial_event",
      domain: "financeiro",
      entity: "com_recebimentos",
      entity_id: String(orderId),
      failure_action: "financeiro.recebimento_failed",
    },
  });
  if (error) return rpcFailure(error.message, "receipt");

  revalidateFinance();
  return success("Recebimento registrado. O saldo e a liberação proporcional foram atualizados.");
}

export async function payCommissionAction(
  _previous: FinanceActionState,
  formData: FormData
): Promise<FinanceActionState> {
  if (!configured()) return failure("O serviço financeiro está indisponível neste ambiente.");

  const idempotencyKey = uuid(formData, "idempotency_key");
  const personId = positiveInteger(formData, "pessoa_id");
  const value = positiveNumber(formData, "valor_pago");
  const paymentDate = field(formData, "data_pagamento");
  const fieldErrors: Record<string, string> = {};

  if (!personId) fieldErrors.pessoa_id = "Selecione a pessoa que receberá o pagamento.";
  if (!value) fieldErrors.valor_pago = "Informe um valor pago maior que zero.";
  if (!paymentDate) fieldErrors.data_pagamento = "Informe a data do pagamento.";
  if (!idempotencyKey) fieldErrors.idempotency_key = "Atualize a página e tente novamente.";
  if (Object.keys(fieldErrors).length) return failure("Revise os campos destacados antes de registrar o pagamento.", fieldErrors);

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_fin_comissao_pagamento_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_pessoa_id: personId,
    p_valor_pago: value,
    p_data_pagamento: paymentDate,
    p_forma_pagamento: optionalField(formData, "forma_pagamento"),
    p_motivo: optionalField(formData, "referencia_pagamento"),
  }, {
    metadata: {
      action_key: "financeiro.commissions.pay",
      axis: "financial_event",
      domain: "financeiro",
      entity: "fin_comissao_movimentos",
      entity_id: String(personId),
      failure_action: "financeiro.comissao_pagamento_failed",
    },
  });
  if (error) return rpcFailure(error.message, "payment");

  revalidateFinance();
  return success("Pagamento registrado. O movimento original e o novo saldo permanecem auditáveis.");
}

export async function adjustCommissionAction(
  _previous: FinanceActionState,
  formData: FormData
): Promise<FinanceActionState> {
  if (!configured()) return failure("O serviço financeiro está indisponível neste ambiente.");

  const idempotencyKey = uuid(formData, "idempotency_key");
  const personId = positiveInteger(formData, "pessoa_id");
  const value = signedNumber(formData, "valor_ajuste");
  const reason = field(formData, "motivo_codigo");
  const detail = optionalField(formData, "motivo_detalhe");
  const reasons = new Set(["correcao_calculo", "estorno_devolucao", "acordo_comercial", "compensacao_futura", "outro"]);
  const fieldErrors: Record<string, string> = {};

  if (!personId) fieldErrors.pessoa_id = "Selecione a pessoa cuja conta será ajustada.";
  if (!value) fieldErrors.valor_ajuste = "Informe um valor diferente de zero.";
  if (!reasons.has(reason)) fieldErrors.motivo_codigo = "Selecione um motivo válido.";
  if (!detail || detail.length < 10) fieldErrors.motivo_detalhe = "Detalhe o ajuste com pelo menos 10 caracteres.";
  if (!idempotencyKey) fieldErrors.idempotency_key = "Atualize a página e tente novamente.";
  if (Object.keys(fieldErrors).length) return failure("Revise os campos destacados antes de registrar o ajuste.", fieldErrors);

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "registrar_fin_comissao_ajuste_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_pessoa_id: personId,
    p_valor_ajuste: value,
    p_motivo: reason,
    p_referencia_json: { motivo_detalhe: detail },
  }, {
    metadata: {
      action_key: "financeiro.commissions.adjust",
      axis: "financial_event",
      domain: "financeiro",
      entity: "fin_comissao_movimentos",
      entity_id: String(personId),
      failure_action: "financeiro.comissao_ajuste_failed",
    },
  });
  if (error) return rpcFailure(error.message, "adjustment");

  revalidateFinance();
  return success("Ajuste excepcional registrado sem alterar os movimentos anteriores.");
}

function configured() {
  return getRuntimeStatus().supabaseConfigured;
}

function revalidateFinance() {
  revalidatePath("/pedidos/financeiro");
  revalidatePath("/pedidos/financeiro/comissionamento");
  revalidatePath("/pedidos/financeiro/recebimentos");
  revalidatePath("/pedidos/financeiro/comissoes");
  revalidatePath("/pedidos/financeiro/comissoes/relatorio");
}

function field(data: FormData, name: string) {
  return String(data.get(name) ?? "").trim();
}

function optionalField(data: FormData, name: string) {
  return field(data, name) || null;
}

function positiveInteger(data: FormData, name: string) {
  const value = Number(field(data, name));
  return Number.isInteger(value) && value > 0 ? value : null;
}

function positiveNumber(data: FormData, name: string) {
  const value = signedNumber(data, name);
  return value !== null && value > 0 ? value : null;
}

function signedNumber(data: FormData, name: string) {
  const value = Number(field(data, name).replace(",", "."));
  return Number.isFinite(value) && value !== 0 ? value : null;
}

function uuid(data: FormData, name: string) {
  const value = field(data, name);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null;
}

function success(message: string): FinanceActionState {
  return { status: "success", message, fieldErrors: {}, resultId: randomUUID(), review: null };
}

function reviewState(message: string, review: CommissionChangeReview): FinanceActionState {
  return { status: "review", message, fieldErrors: {}, resultId: randomUUID(), review };
}

function failure(message: string, fieldErrors: Record<string, string> = {}): FinanceActionState {
  return { status: "error", message, fieldErrors, resultId: randomUUID(), review: null };
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function rpcFailure(
  message: string,
  operation: "assignment" | "receipt" | "payment" | "adjustment"
): FinanceActionState {
  const value = message.toLowerCase();
  if (value.includes("not allowed") || value.includes("permission") || value.includes("module unavailable")) {
    return failure("Usuário sem alçada para esta operação.");
  }
  if (value.includes("receipt document reference")) {
    return failure("Referência documental obrigatória.", { referencia_documental: "Informe o documento que comprova o recebimento." });
  }
  if (value.includes("receipt exceeds order balance")) {
    return failure("Valor acima do saldo do pedido.", { valor_recebido: "Reduza o valor para não ultrapassar o saldo aberto." });
  }
  if (value.includes("valor_recebido must be greater")) {
    return failure("Valor de recebimento inválido.", { valor_recebido: "Informe um valor maior que zero." });
  }
  if (value.includes("data_recebimento is required")) {
    return failure("Data do recebimento obrigatória.", { data_recebimento: "Informe a data em que o valor foi recebido." });
  }
  if (value.includes("commission payment exceeds available balance")) {
    return failure("Pagamento acima do saldo da comissão.", { valor_pago: "Reduza o pagamento para o saldo disponível." });
  }
  if (value.includes("valor_pago must be greater")) {
    return failure("Valor de pagamento inválido.", { valor_pago: "Informe um valor maior que zero." });
  }
  if (value.includes("data_pagamento is required")) {
    return failure("Data do pagamento obrigatória.", { data_pagamento: "Informe a data em que a comissão foi paga." });
  }
  if (value.includes("idempotency key reused")) {
    return failure("Esta tentativa já foi usada com dados diferentes. Atualize a página antes de reenviar.");
  }
  if (value.includes("could not serialize") || value.includes("concurrent") || value.includes("lock timeout")) {
    return failure("O registro foi alterado durante esta operação. Atualize a página, confira os valores e tente novamente.");
  }
  if (value.includes("duplicate key") || value.includes("unique constraint")) {
    if (operation === "assignment") return failure("Esta pessoa já está definida neste papel para o pedido.");
    if (operation === "receipt") return failure("Este recebimento já foi processado. Nenhum valor foi duplicado.");
    return failure("Esta operação já foi registrada. Atualize a página para consultar o resultado.");
  }
  if (value.includes("already") || value.includes("ja_liberada")) {
    return failure("A operação já foi processada. Nenhum valor foi duplicado.");
  }
  if (value.includes("commission context changed after review")) {
    return failure("Os dados da venda mudaram desde a revisão. Refazer a revisão antes de confirmar.");
  }
  if (value.includes("commission change request expired")) {
    return failure("A revisão expirou. Refazer a revisão antes de confirmar.");
  }
  if (value.includes("only sale orders generate commission")) {
    return failure("Somente pedidos de venda podem gerar comissão.");
  }
  if (value.includes("commission request key reused")) {
    return failure("A tentativa anterior foi alterada. Refazer a revisão com uma nova solicitação.");
  }
  if (value.includes("commission participant already exists")) {
    return failure("Esta pessoa já participa da comissão neste papel.");
  }
  if (value.includes("commission percentage")) {
    return failure("Percentual de comissão inválido.", { percentual_comissao: "Informe um percentual maior que zero e de até 100%." });
  }
  if (value.includes("commission person") || value.includes("pessoa not found") || value.includes("pessoa is inactive")) {
    return failure("Pessoa não elegível para comissionamento.", { pessoa_id: "Selecione uma pessoa ativa e autorizada." });
  }
  if (
    value.includes("pedido status")
    || value.includes("pedido does not allow receipt")
    || value.includes("pedido not found")
    || value.includes("order must be approved")
  ) {
    return failure("O pedido ainda não está em uma situação que permita esta operação.");
  }
  return failure("Não foi possível concluir a operação. Os dados informados permanecem na tela para revisão.");
}
