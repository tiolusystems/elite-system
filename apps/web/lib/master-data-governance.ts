export const CADASTRO_STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "pending_review", label: "Em revisão" },
  { value: "inactive", label: "Inativo" }
] as const;

export const UF_OPTIONS = [
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG",
  "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"
] as const;

export const TIPO_COMERCIAL_OPTIONS = [
  { value: "funcionario_elite", label: "Funcionário Elite" },
  { value: "agente_vinculado", label: "Agente externo" },
  { value: "agente_direto_elite", label: "Agente direto Elite" },
  { value: "vendedor_direto_elite", label: "Vendedor direto Elite" },
  { value: "tecnico_campo", label: "Técnico de campo" },
  { value: "entregador", label: "Entregador" },
  { value: "gerente", label: "Gerente" },
  { value: "vendedor_gerente", label: "Vendedor e gerente" }
] as const;

export const PAPEL_COMERCIAL_OPTIONS = [
  { value: "funcionario", label: "Funcionário" },
  { value: "vendedor", label: "Vendedor" },
  { value: "agente", label: "Agente" },
  { value: "tecnico_campo", label: "Técnico de campo" },
  { value: "entregador", label: "Entregador" },
  { value: "gerente", label: "Gerente" },
  { value: "comissionado", label: "Comissionado" }
] as const;

export const MOTIVO_PAPEL_OPTIONS = [
  { value: "promocao", label: "Promoção" },
  { value: "correcao_cadastro", label: "Correção de cadastro" },
  { value: "transferencia_carteira", label: "Transferência de carteira" },
  { value: "desligamento_funcao", label: "Desligamento da função" },
  { value: "mudanca_comissao", label: "Mudança de comissão" },
  { value: "outro", label: "Outro" }
] as const;

export const PAPEL_AREA_OPTIONS = [
  { value: "vendedor", label: "Vendedor" },
  { value: "gerente", label: "Gerente" },
  { value: "supervisor", label: "Supervisor" },
  { value: "apoio", label: "Apoio" }
] as const;

const STATUS_LABELS: Record<string, string> = Object.fromEntries(
  CADASTRO_STATUS_OPTIONS.map((option) => [option.value, option.label])
);
const TIPO_COMERCIAL_LABELS: Record<string, string> = Object.fromEntries(
  TIPO_COMERCIAL_OPTIONS.map((option) => [option.value, option.label])
);
const PAPEL_COMERCIAL_LABELS: Record<string, string> = Object.fromEntries(
  PAPEL_COMERCIAL_OPTIONS.map((option) => [option.value, option.label])
);
const PAPEL_AREA_LABELS: Record<string, string> = Object.fromEntries(
  PAPEL_AREA_OPTIONS.map((option) => [option.value, option.label])
);
const DUPLICATE_REASON_LABELS: Record<string, string> = {
  same_legacy_code: "Mesmo código legado",
  same_normalized_name: "Mesmo nome normalizado",
  name_matches_existing_alias: "Nome corresponde a apelido existente",
  input_alias_matches_existing_name: "Apelido corresponde ao nome existente",
  same_historical_spelling: "Mesma grafia histórica"
};
const DATA_ORIGIN_LABELS: Record<string, string> = {
  sistema: "Sistema",
  excel_legado: "Excel legado"
};

export function cadastroStatusLabel(value: string | null | undefined) {
  return value ? STATUS_LABELS[value] ?? "Situação não reconhecida" : "Não informado";
}

export function tipoComercialLabel(value: string | null | undefined) {
  return value ? TIPO_COMERCIAL_LABELS[value] ?? "Tipo não reconhecido" : "Tipo não informado";
}

export function papelComercialLabel(value: string | null | undefined) {
  return value ? PAPEL_COMERCIAL_LABELS[value] ?? "Papel não reconhecido" : "Papel não informado";
}

export function papelAreaLabel(value: string | null | undefined) {
  return value ? PAPEL_AREA_LABELS[value] ?? "Papel não reconhecido" : "Papel não informado";
}

export function duplicateReasonLabel(value: string) {
  return DUPLICATE_REASON_LABELS[value] ?? "Semelhança cadastral";
}

export function dataOriginLabel(value: string | null | undefined) {
  return value ? DATA_ORIGIN_LABELS[value] ?? "Origem não reconhecida" : "Origem não informada";
}

export function formatLegacyCode(value: string | null | undefined) {
  return value?.trim() || "Sem código legado";
}

export function formatLocation(city: string | null | undefined, uf: string | null | undefined) {
  const normalizedCity = city?.trim();
  const normalizedUf = uf?.trim().toUpperCase();
  if (normalizedCity && normalizedUf) return `${normalizedCity} / ${normalizedUf}`;
  return normalizedCity || normalizedUf || "Localização não informada";
}
