export function money(value: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

export function date(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

export function dateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

export function orderStatusLabel(value: string) {
  return ({ open: "Liberado", fulfilled: "Atendido", blocked: "Bloqueado", draft: "Rascunho", cancelled: "Cancelado" } as Record<string, string>)[value] ?? "Situação não reconhecida";
}

export function personStatusLabel(value: string) {
  return ({ active: "Ativa", inactive: "Inativa", pending_review: "Em revisão" } as Record<string, string>)[value] ?? "Situação não reconhecida";
}

export function commissionRoleLabel(value: string) {
  return ({ vendedor: "Vendedor", agente: "Agente", gerente: "Gerente", tecnico_campo: "Técnico de campo", campanha: "Campanha", outro: "Outro" } as Record<string, string>)[value] ?? "Papel não reconhecido";
}

export function commissionMovementLabel(value: string) {
  return ({ credito_liberacao: "Comissão liberada", debito_pagamento: "Pagamento", debito_estorno: "Estorno", compensacao_futura: "Compensação futura", ajuste_manual: "Ajuste manual" } as Record<string, string>)[value] ?? "Movimento financeiro";
}

export function fiscalReferenceTypeLabel(value: string) {
  return ({ simples_faturamento: "NF de simples faturamento", remessa_total: "NF de remessa", remessa_vinculada: "NF de remessa vinculada", complementar: "Referência complementar" } as Record<string, string>)[value] ?? "Referência fiscal externa";
}

export function receiptMethodLabel(value: string) {
  return ({
    pix: "Pix",
    transferencia: "Transferência",
    boleto: "Boleto",
    dinheiro: "Dinheiro",
    cheque: "Cheque",
    cartao: "Cartão",
    outro: "Outra forma",
  } as Record<string, string>)[value] ?? "Forma não reconhecida";
}

export function financeDateDefaults() {
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const today = now.toISOString().slice(0, 10);
  return { startDate: start.toISOString().slice(0, 10), endDate: today, cutoffDate: today };
}
