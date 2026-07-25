import type { PcpComponentType, PcpLookupOption } from "@/lib/pcp";
import { internalValueKnown, internalValueLabel } from "@/lib/labels-ptbr";

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

const FORMULA_PURPOSE_LABELS: Record<string, string> = {
  producao: "Produção operacional",
  mapa: "Documentação MAPA"
};

const FORMULA_BASIS_LABELS: Record<string, string> = {
  por_litro: "Base de 1 L",
  documental_mapa: "Composição documental",
  legado_nao_comprovado: "Revisão por litro necessária"
};

const ORDER_STATUS_LABELS: Record<string, string> = {
  draft: "Rascunho",
  planned: "Planejada",
  in_process: "Em processo",
  completed: "Finalizada",
  cancelled: "Cancelada"
};

const ORDER_TYPE_LABELS: Record<string, string> = {
  estoque: "Produção para estoque",
  experimental: "Experimental",
  desenvolvimento: "Desenvolvimento",
  reprocessamento: "Reprocessamento",
  mapa_documental: "MAPA documental"
};

const COMPONENT_STATUS_LABELS: Record<string, string> = {
  pending: "Pendente",
  partial: "Parcial",
  reserved: "Reservado",
  consumed: "Consumido"
};

const STATUS_LABELS: Record<string, string> = {
  aprovado: "Aprovado",
  bloqueado: "Bloqueado",
  reprovado: "Reprovado",
  conforme: "Conforme",
  nao_conforme: "Não conforme",
  sem_referencia: "Sem referência",
  sem_referencia_mapa: "Sem referência MAPA",
  sem_dados_lote: "Sem garantia do lote",
  unidade_incompativel: "Unidade incompatível",
  base_incompleta: "Base física incompleta",
  atende: "Atende",
  nao_atende: "Não atende",
  informativo: "Informativo",
  ativa: "Ativa",
  disponivel: "Disponível",
  reservado: "Reservado",
  consumido: "Consumido",
  cancelado: "Cancelado",
  cancelada: "Cancelada",
  completed: "Finalizada"
};

export function unitLabel(code: string | null | undefined): string {
  if (!code) return "-";
  return UNIT_LABELS[code.toLowerCase()] ?? code;
}

export function unitOptionLabel(option: PcpLookupOption): string {
  const governedFormulaUnits: Record<string, string> = {
    kg_l_produzido: "kg/L produzido",
    l_l_produzido: "L/L produzido",
    un_l_produzido: "UN/L produzido"
  };
  if (governedFormulaUnits[option.label]) return governedFormulaUnits[option.label];
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

export function formulaPurposeLabel(value: string): string {
  return FORMULA_PURPOSE_LABELS[value] ?? "Finalidade não reconhecida";
}

export function formulaBasisLabel(value: string): string {
  return FORMULA_BASIS_LABELS[value] ?? "Base não reconhecida";
}

export function orderStatusLabel(value: string): string {
  return ORDER_STATUS_LABELS[value] ?? "Situação não reconhecida";
}

export function orderTypeLabel(value: string): string {
  return ORDER_TYPE_LABELS[value] ?? "Tipo não reconhecido";
}

export function componentStatusLabel(value: string): string {
  return COMPONENT_STATUS_LABELS[value] ?? "Situação não reconhecida";
}

export function productionStatusLabel(status: string | null | undefined): string {
  if (!status) return "Não informado";
  if (STATUS_LABELS[status]) return STATUS_LABELS[status];
  return internalValueKnown(status) ? internalValueLabel(status) : "Situação não reconhecida";
}
