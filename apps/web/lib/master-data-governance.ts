export const CADASTRO_STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "pending_review", label: "Em revisão" },
  { value: "inactive", label: "Inativo" }
] as const;

export const UF_OPTIONS = [
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG",
  "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"
] as const;

const STATUS_LABELS: Record<string, string> = Object.fromEntries(
  CADASTRO_STATUS_OPTIONS.map((option) => [option.value, option.label])
);

export function cadastroStatusLabel(value: string | null | undefined) {
  return value ? STATUS_LABELS[value] ?? "Situação não reconhecida" : "Não informado";
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
