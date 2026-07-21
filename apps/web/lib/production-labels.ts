import type { PcpComponentType, PcpLookupOption } from "@/lib/pcp";

const UNIT_LABELS: Record<string, string> = {
  deg_c: "Graus Celsius (°C)",
  g: "Grama (g)",
  kg: "Quilograma (kg)",
  "kg/l": "Quilograma por litro (kg/L)",
  l: "Litro (L)",
  ml: "Mililitro (mL)",
  one: "Adimensional",
  percent: "Percentual (%)",
  sc: "Saca",
  t: "Tonelada (t)",
  un: "Unidade (un.)"
};

const COMPONENT_LABELS: Record<PcpComponentType, string> = {
  MP: "Matéria-prima",
  PA: "Produto acabado",
  PI: "Produto intermediário"
};

const STATUS_LABELS: Record<string, string> = {
  aprovado: "Aprovado",
  bloqueado: "Bloqueado",
  reprovado: "Reprovado",
  conforme: "Conforme",
  nao_conforme: "Não conforme",
  sem_referencia: "Sem referência",
  disponivel: "Disponível",
  reservado: "Reservado",
  consumido: "Consumido",
  cancelado: "Cancelado",
  completed: "Finalizada"
};

export function unitLabel(code: string | null | undefined): string {
  if (!code) return "-";
  return UNIT_LABELS[code.toLowerCase()] ?? code;
}

export function unitOptionLabel(option: PcpLookupOption): string {
  return unitLabel(option.label);
}

export function productionOptionLabel(option: PcpLookupOption): string {
  if (!option.detail) return option.label;

  const detail = option.detail
    .replace(/\bactive\b/gi, "Ativo")
    .replace(/\binactive\b/gi, "Inativo");

  return `${option.label} - ${detail}`;
}

export function componentTypeLabel(type: PcpComponentType): string {
  return COMPONENT_LABELS[type];
}

export function productionStatusLabel(status: string | null | undefined): string {
  if (!status) return "Não informado";
  return STATUS_LABELS[status] ?? status.replaceAll("_", " ");
}
