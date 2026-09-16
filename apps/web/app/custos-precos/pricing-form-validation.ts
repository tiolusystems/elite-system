export type PricingFieldErrors = Record<string, string>;

export type PricingValidation<T> = {
  fieldErrors: PricingFieldErrors;
  payload: T | null;
};

export const PRICING_COMPONENTS = [
  ["materia_prima", "BRL_L"], ["embalagem", "BRL_L"], ["custo_pontuacao_vendedor", "BRL_L"],
  ["custo_pontuacao_revenda", "BRL_L"], ["premiacao_revenda", "BRL_L"], ["premio_producao", "BRL_L"],
  ["frete", "BRL_L"], ["comissao", "FRACAO"], ["risco", "FRACAO"], ["marketing", "FRACAO"], ["tributacao", "FRACAO"],
] as const;

const DECIMAL = /^\d+(?:[,.]\d+)?$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export function field(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

export function parseHumanNumber(raw: string): number | null {
  const value = raw.trim();
  if (!DECIMAL.test(value) || (value.includes(",") && value.includes("."))) return null;
  const parsed = Number(value.replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

export function parsePercentage(raw: string): number | null {
  const source = raw.trim();
  const value = parseHumanNumber(source.endsWith("%") ? source.slice(0, -1).trim() : source);
  return value === null ? null : value / 100;
}

export function percentageWarning(raw: string) {
  const source = raw.trim();
  const rawNumber = source.endsWith("%") ? source.slice(0, -1).trim() : source;
  const value = parseHumanNumber(rawNumber);
  const display = rawNumber.replace(".", ",");
  return value !== null && value > 0 && value < 1 ? `${display} significa ${display}%. Para 20%, digite 20.` : null;
}

export function validatePolicy(formData: FormData): PricingValidation<{
  p_politica_id: number | null; p_nome: string | null; p_metodo: string; p_lucro_minimo: number | null; p_markup: number | null; p_juros_mensais: number; p_motivo: string;
}> {
  const errors: PricingFieldErrors = {};
  const politicaIdRaw = field(formData, "politica_id");
  const politicaId = politicaIdRaw ? positiveInteger(politicaIdRaw) : null;
  const nome = field(formData, "nome");
  const metodo = field(formData, "metodo");
  const motivo = field(formData, "motivo");
  const juros = parsePercentage(field(formData, "juros_mensais"));
  const lucro = parsePercentage(field(formData, "lucro_minimo"));
  const markup = parsePercentage(field(formData, "markup"));

  if (politicaIdRaw && !politicaId) errors.politica_id = "Selecione uma politica valida.";
  if (!politicaId && !nome) errors.nome = "Informe o nome da nova politica.";
  if (metodo !== "margem_liquida" && metodo !== "markup") errors.metodo = "Selecione um metodo valido.";
  if (juros === null || juros < 0) errors.juros_mensais = "Informe um percentual numerico igual ou maior que zero.";
  if (motivo.length < 10) errors.motivo = "Explique a finalidade desta versao com pelo menos 10 caracteres.";
  if (metodo === "margem_liquida") {
    if (lucro === null) errors.lucro_minimo = "Informe o lucro minimo.";
    else if (lucro < 0 || lucro >= 1) errors.lucro_minimo = "A margem liquida deve ser maior ou igual a 0% e menor que 100%.";
  }
  if (metodo === "markup" && (markup === null || markup < 0)) errors.markup = "Informe um markup numerico igual ou maior que zero.";

  return result(errors, {
    p_politica_id: politicaId, p_nome: politicaId ? null : nome, p_metodo: metodo,
    p_lucro_minimo: metodo === "margem_liquida" ? lucro : null,
    p_markup: metodo === "markup" ? markup : null,
    p_juros_mensais: juros ?? Number.NaN, p_motivo: motivo,
  });
}

export function validateScenario(formData: FormData): PricingValidation<{
  p_politica_versao_id: number; p_produto_embalagem_id: number; p_nome: string; p_motivo: string;
  p_componentes: Array<{ campo: string; unidade: string; valor: number; source_kind: string; source_reference: string; source_effective_date: string; reason: string }>;
}> {
  const errors: PricingFieldErrors = {};
  const politicaId = positiveInteger(field(formData, "politica_versao_id"));
  const produtoId = positiveInteger(field(formData, "produto_embalagem_id"));
  const nome = field(formData, "nome");
  const motivo = field(formData, "motivo");
  const sourceKind = field(formData, "source_kind");
  const sourceReference = field(formData, "source_reference");
  const sourceDate = field(formData, "source_effective_date");
  const sourceReason = field(formData, "source_reason");

  if (!politicaId) errors.politica_versao_id = "Selecione uma politica aprovada.";
  if (!produtoId) errors.produto_embalagem_id = "Selecione o produto e a apresentacao.";
  if (!nome) errors.nome = "Informe o nome do cenario.";
  if (motivo.length < 10) errors.motivo = "Informe o motivo do cenario com pelo menos 10 caracteres.";
  if (sourceKind !== "substituicao_manual") errors.source_kind = "Use uma substituicao manual enquanto a origem de sistema ainda nao estiver disponivel.";
  if (!sourceReference) errors.source_reference = "Informe a referencia da origem.";
  if (!validDate(sourceDate)) errors.source_effective_date = "Informe uma data valida.";
  if (sourceReason.length < 10) errors.source_reason = "Explique a origem com pelo menos 10 caracteres.";

  const componentes = PRICING_COMPONENTS.map(([campo, unidade]) => {
    const value = unidade === "FRACAO" ? parsePercentage(field(formData, campo)) : parseHumanNumber(field(formData, campo));
    if (value === null || value < 0) errors[campo] = "Informe um valor numerico igual ou maior que zero.";
    return { campo, unidade, valor: value ?? Number.NaN, source_kind: sourceKind, source_reference: sourceReference, source_effective_date: sourceDate, reason: sourceReason };
  });

  return result(errors, {
    p_politica_versao_id: politicaId ?? 0, p_produto_embalagem_id: produtoId ?? 0,
    p_nome: nome, p_motivo: motivo, p_componentes: componentes,
  });
}

export function validateCalculation(formData: FormData): PricingValidation<{ p_cenario_id: number; p_motivo: string }> {
  const errors: PricingFieldErrors = {};
  const cenarioId = positiveInteger(field(formData, "cenario_id"));
  const motivo = field(formData, "motivo");
  if (!cenarioId) errors.cenario_id = "O cenario selecionado nao e valido.";
  if (motivo.length < 10) errors.motivo = "Explique o calculo com pelo menos 10 caracteres.";
  return result(errors, { p_cenario_id: cenarioId ?? 0, p_motivo: motivo });
}

export function validateReview(formData: FormData, idName: "versao_id" | "calculo_id"): PricingValidation<{ id: number; decisao: string; justificativa: string }> {
  const errors: PricingFieldErrors = {};
  const id = positiveInteger(field(formData, idName));
  const decisao = field(formData, "decisao");
  const justificativa = field(formData, "justificativa");
  if (!id) errors[idName] = "O registro selecionado nao e valido.";
  if (!new Set(["APPROVED", "REJECTED"]).has(decisao)) errors.decisao = "Selecione uma decisao valida.";
  if (justificativa.length < 10) errors.justificativa = "Informe a justificativa com pelo menos 10 caracteres.";
  return result(errors, { id: id ?? 0, decisao, justificativa });
}

function result<T>(fieldErrors: PricingFieldErrors, payload: T): PricingValidation<T> {
  return { fieldErrors, payload: Object.keys(fieldErrors).length ? null : payload };
}

function positiveInteger(value: string) {
  return /^[1-9]\d*$/.test(value) ? Number(value) : null;
}

function validDate(value: string) {
  if (!DATE.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
