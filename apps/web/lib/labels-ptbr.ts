const INTERNAL_VALUE_LABELS: Record<string, string> = {
  active: "Ativo",
  inactive: "Inativo",
  pending_review: "Em revisao",
  approved: "Aprovado",
  rejected: "Rejeitado",
  draft: "Rascunho",
  planned: "Planejada",
  in_process: "Em processo",
  completed: "Concluido",
  cancelled: "Cancelado",
  reversed: "Estornado",
  available: "Disponivel",
  blocked: "Bloqueado",
  read_only: "Somente leitura",
  read_write: "Leitura e gravacao",
  disabled: "Desativado",
  construction: "Em construcao",
  technical_validation: "Validacao tecnica",
  business_validation: "Validacao de negocio",
  open: "Aberto",
  fulfilled: "Atendido",
  reserved: "Reservado",
  consumed: "Consumido",
  pending: "Pendente",
  processing: "Em processamento",
  failed: "Falhou",
  success: "Concluido",
  ignored: "Ignorado",
  matched: "Conciliado",
  liberado: "Liberado",
  reduzido: "Reduzido",
  bloqueado: "Bloqueado",
  pendente_aprovacao: "Pendente de aprovacao",
  ativa: "Ativa",
  inativa: "Inativa",
  suspensa: "Suspensa",
  baixada: "Baixada",
  nao_verificada: "Nao verificada",
  aumento: "Aumento",
  reducao: "Reducao",
  bloqueio: "Bloqueio",
  liberacao: "Liberacao"
};

export function internalValueLabel(value: string | null | undefined): string {
  if (!value) return "Nao informado";
  return INTERNAL_VALUE_LABELS[value] ?? "Situacao nao reconhecida";
}

export function internalValueKnown(value: string | null | undefined): boolean {
  return Boolean(value && INTERNAL_VALUE_LABELS[value]);
}
