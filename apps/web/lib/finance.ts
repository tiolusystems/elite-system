import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type FinanceAccess = {
  dashboardView: boolean;
  commissionAssign: boolean;
  receiptsView: boolean;
  receiptsRegister: boolean;
  commissionsView: boolean;
  commissionsPay: boolean;
  commissionsAdjust: boolean;
  commissionsExport: boolean;
  any: boolean;
};

export type FinanceFilters = {
  startDate: string;
  endDate: string;
  cutoffDate: string;
};

export type FinanceOverview = {
  totals: {
    openReceivables: number | null;
    receivedPeriod: number | null;
    commissionBalance: number | null;
    ordersWithBalance: number | null;
  };
  receipts: Array<{
    id: number;
    clientName: string;
    value: number;
    date: string;
    method: string | null;
    documentReference: string | null;
  }>;
  error: string | null;
};

export type ReceiptOrder = {
  id: number;
  code: string;
  clientId: number;
  clientName: string;
  propertyName: string | null;
  total: number;
  received: number;
  open: number;
  status: string;
  fiscalReferences: Array<{ numero: string | null; tipo: string; status: string }>;
  previousReceipts: Array<{
    id: number;
    value: number;
    date: string;
    method: string | null;
    documentReference: string | null;
    status: string;
  }>;
  totalCount: number;
};

export type CommissionAssignment = {
  personId: number;
  personName: string;
  role: string;
  percentage: number;
  expectedValue: number;
  status: string;
  origin: string | null;
};

export type CommissionOrder = {
  id: number;
  code: string;
  clientName: string;
  total: number;
  status: string;
  assignments: CommissionAssignment[];
  totalPercentage: number;
  totalCount: number;
};

export type CommissionOrderDetail = CommissionOrder & {
  type: string;
  eligible: boolean;
  ineligibilityReason: string | null;
  received: number;
};

export type CommissionPerson = {
  id: number;
  name: string;
  roles: string[];
};

export type CommissionAccount = {
  personId: number;
  personName: string;
  roles: string[];
  status: string;
  predicted: number;
  released: number;
  payments: number;
  reversals: number;
  adjustments: number;
  balance: number;
  totalCount: number;
};

export type CommissionMovement = {
  id: number;
  type: string;
  value: number;
  reason: string | null;
  orderCode: string | null;
  reference: string | null;
  createdAt: string;
  createdBy: string | null;
};

export type FinanceQueryResult<T> = {
  data: T;
  error: string | null;
};

const ACTIONS = {
  dashboardView: "financeiro.dashboard.view",
  commissionAssign: "pedidos.commissions.assign",
  receiptsView: "financeiro.receipts.view",
  receiptsRegister: "financeiro.receipts.register",
  commissionsView: "financeiro.commissions.view",
  commissionsPay: "financeiro.commissions.pay",
  commissionsAdjust: "financeiro.commissions.adjust",
  commissionsExport: "financeiro.commissions.export",
} as const;

export async function getFinanceAccess(): Promise<FinanceAccess> {
  const denied = accessFrom({});
  if (!getRuntimeStatus().supabaseConfigured) return denied;

  try {
    const supabase = await createSupabaseServerClient();
    const entries = await Promise.all(
      Object.entries(ACTIONS).map(async ([key, actionKey]) => {
        const { data, error } = await supabase.rpc("can_current_user", { p_action_key: actionKey });
        return [key, !error && data === true] as const;
      })
    );
    return accessFrom(Object.fromEntries(entries));
  } catch {
    return denied;
  }
}

export async function getFinanceOverview(filters: FinanceFilters, access: FinanceAccess): Promise<FinanceOverview> {
  if (!getRuntimeStatus().supabaseConfigured) return emptyOverview("Banco de homologação não configurado.");
  if (!access.any) return emptyOverview("Usuário sem alçada para consultar o Financeiro.");

  try {
    const supabase = await createSupabaseServerClient();
    const dashboardResult = await supabase.rpc("consultar_fin_dashboard", {
      p_data_inicio: filters.startDate,
      p_data_fim: filters.endDate,
      p_data_corte: filters.cutoffDate,
    });

    const receiptResult = access.receiptsView || access.receiptsRegister
      ? await supabase
          .from("com_recebimentos")
          .select("id,cliente_id,valor_recebido,data_recebimento,forma_recebimento,referencia_documental")
          .eq("status", "active")
          .order("data_recebimento", { ascending: false })
          .order("id", { ascending: false })
          .limit(8)
      : { data: [], error: null };

    const clientIds = [...new Set((receiptResult.data ?? []).map((row) => Number(row.cliente_id)).filter((id) => id > 0))];
    const clientResult = clientIds.length
      ? await supabase.from("cad_clientes").select("id,nome").in("id", clientIds)
      : { data: [], error: null };

    const error = dashboardResult.error ?? receiptResult.error ?? clientResult.error;
    if (error) return emptyOverview(humanError(error.message));

    const raw = object(dashboardResult.data);
    const clients = new Map((clientResult.data ?? []).map((row) => [Number(row.id), String(row.nome)]));
    return {
      totals: {
        openReceivables: nullableNumber(raw.open_receivables),
        receivedPeriod: nullableNumber(raw.received_period),
        commissionBalance: nullableNumber(raw.commission_balance),
        ordersWithBalance: nullableNumber(raw.orders_with_balance),
      },
      receipts: (receiptResult.data ?? []).map((row) => ({
        id: Number(row.id),
        clientName: clients.get(Number(row.cliente_id)) ?? "Cliente não identificado",
        value: Number(row.valor_recebido ?? 0),
        date: String(row.data_recebimento),
        method: optionalString(row.forma_recebimento),
        documentReference: optionalString(row.referencia_documental),
      })),
      error: null,
    };
  } catch {
    return emptyOverview("Não foi possível consultar o Financeiro agora.");
  }
}

export async function searchReceiptOrders(query: string, page = 1): Promise<FinanceQueryResult<ReceiptOrder[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("buscar_fin_pedidos_recebimento", {
      p_query: query || null,
      p_limit: 20,
      p_offset: Math.max(page - 1, 0) * 20,
    });
    if (error) return queryFailure(humanError(error.message));
    return querySuccess(((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.pedido_id),
      code: String(row.codigo_pedido),
      clientId: Number(row.cliente_id),
      clientName: String(row.cliente_nome),
      propertyName: optionalString(row.propriedade_nome),
      total: Number(row.valor_total ?? 0),
      received: Number(row.valor_recebido ?? 0),
      open: Number(row.saldo_aberto ?? 0),
      status: String(row.status),
      fiscalReferences: array(row.referencias_fiscais).map((item) => {
        const value = object(item);
        return { numero: optionalString(value.numero), tipo: String(value.tipo), status: String(value.status) };
      }),
      previousReceipts: array(row.recebimentos_anteriores).map((item) => {
        const value = object(item);
        return {
          id: Number(value.id),
          value: Number(value.valor ?? 0),
          date: String(value.data),
          method: optionalString(value.forma),
          documentReference: optionalString(value.referencia_documental),
          status: String(value.status),
        };
      }),
      totalCount: Number(row.total_count ?? 0),
    })));
  } catch {
    return queryFailure("Não foi possível consultar os pedidos agora.");
  }
}

export async function searchCommissionOrders(query: string, page = 1): Promise<FinanceQueryResult<CommissionOrder[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("buscar_fin_pedidos_comissionamento", {
      p_query: query || null,
      p_limit: 20,
      p_offset: Math.max(page - 1, 0) * 20,
    });
    if (error) return queryFailure(humanError(error.message));
    return querySuccess(((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.pedido_id),
      code: String(row.codigo_pedido),
      clientName: String(row.cliente_nome),
      total: Number(row.valor_total ?? 0),
      status: String(row.status),
      assignments: array(row.comissionados).map((item) => {
        const value = object(item);
        return {
          personId: Number(value.pessoa_id),
          personName: String(value.pessoa_nome),
          role: String(value.papel),
          percentage: Number(value.percentual ?? 0),
          expectedValue: Number(value.valor_previsto ?? 0),
          status: String(value.status),
          origin: optionalString(value.origem),
        };
      }),
      totalPercentage: Number(row.total_percentual ?? 0),
      totalCount: Number(row.total_count ?? 0),
    })));
  } catch {
    return queryFailure("Não foi possível consultar os pedidos elegíveis agora.");
  }
}

export async function getCommissionOrderById(
  orderId: number
): Promise<FinanceQueryResult<CommissionOrderDetail | null>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  if (!Number.isInteger(orderId) || orderId <= 0) return querySuccess(null);

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_fin_pedido_comissionamento", {
      p_pedido_id: orderId,
    });
    if (error) return queryFailure(humanError(error.message));

    const row = ((data ?? []) as Array<Record<string, unknown>>)[0];
    if (!row) return querySuccess(null);

    return querySuccess({
      id: Number(row.pedido_id),
      code: String(row.codigo_pedido),
      clientName: String(row.cliente_nome),
      total: Number(row.valor_total ?? 0),
      status: String(row.status),
      type: String(row.tipo_pedido),
      eligible: row.elegivel === true,
      ineligibilityReason: optionalString(row.motivo_inelegibilidade),
      received: Number(row.valor_recebido ?? 0),
      assignments: array(row.comissionados).map((item) => {
        const value = object(item);
        return {
          personId: Number(value.pessoa_id),
          personName: String(value.pessoa_nome),
          role: String(value.papel),
          percentage: Number(value.percentual ?? 0),
          expectedValue: Number(value.valor_previsto ?? 0),
          status: String(value.status),
          origin: optionalString(value.origem),
        };
      }),
      totalPercentage: Number(row.total_percentual ?? 0),
      totalCount: 1,
    });
  } catch {
    return queryFailure("Não foi possível abrir os dados de comissionamento desta venda agora.");
  }
}

export async function getCommissionPeople(query = ""): Promise<FinanceQueryResult<CommissionPerson[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("buscar_fin_pessoas_comissionaveis", {
      p_query: query || null,
      p_limit: 100,
    });
    if (error) return queryFailure(humanError(error.message));
    return querySuccess(((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.pessoa_id),
      name: String(row.pessoa_nome),
      roles: stringArray(row.papeis),
    })));
  } catch {
    return queryFailure("Não foi possível consultar as pessoas comissionáveis agora.");
  }
}

export async function searchCommissionAccounts(
  query: string,
  status: string,
  cutoffDate: string,
  page = 1,
  role = ""
): Promise<FinanceQueryResult<CommissionAccount[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_fin_comissoes", {
      p_query: query || null,
      p_role: role || null,
      p_status: status,
      p_data_corte: cutoffDate,
      p_limit: 30,
      p_offset: Math.max(page - 1, 0) * 30,
    });
    if (error) return queryFailure(humanError(error.message));
    return querySuccess(((data ?? []) as Array<Record<string, unknown>>).map(mapCommissionAccount));
  } catch {
    return queryFailure("Não foi possível consultar as contas de comissão agora.");
  }
}

export async function getCommissionReport(
  query: string,
  role: string,
  cutoffDate: string,
  onlyPositive: boolean
): Promise<FinanceQueryResult<CommissionAccount[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  try {
    const supabase = await createSupabaseServerClient();
    const rows: CommissionAccount[] = [];
    let offset = 0;
    while (true) {
      const { data, error } = await supabase.rpc("consultar_fin_comissoes", {
        p_query: query || null,
        p_role: role || null,
        p_status: onlyPositive ? "positive" : "all",
        p_data_corte: cutoffDate,
        p_limit: 100,
        p_offset: offset,
      });
      if (error) return queryFailure(humanError(error.message));
      const batch = ((data ?? []) as Array<Record<string, unknown>>).map(mapCommissionAccount);
      rows.push(...batch);
      if (batch.length < 100) break;
      offset += 100;
    }
    return querySuccess(rows);
  } catch {
    return queryFailure("Não foi possível gerar o relatório de comissões agora.");
  }
}

export async function getCommissionMovements(
  personId: number,
  startDate?: string,
  endDate?: string
): Promise<FinanceQueryResult<CommissionMovement[]>> {
  if (!getRuntimeStatus().supabaseConfigured) return queryFailure("Banco de homologação não configurado.");
  if (!personId) return querySuccess([]);
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_fin_comissao_movimentos", {
      p_pessoa_id: personId,
      p_data_inicio: startDate || null,
      p_data_fim: endDate || null,
      p_limit: 200,
    });
    if (error) return queryFailure(humanError(error.message));
    return querySuccess(((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.movimento_id),
      type: String(row.tipo_movimento),
      value: Number(row.valor ?? 0),
      reason: optionalString(row.motivo),
      orderCode: optionalString(row.pedido_codigo),
      reference: optionalString(row.referencia),
      createdAt: String(row.criado_em),
      createdBy: optionalString(row.criado_por),
    })));
  } catch {
    return queryFailure("Não foi possível consultar o histórico de comissões agora.");
  }
}

function accessFrom(values: Partial<Record<keyof Omit<FinanceAccess, "any">, boolean>>): FinanceAccess {
  const access = {
    dashboardView: values.dashboardView === true,
    commissionAssign: values.commissionAssign === true,
    receiptsView: values.receiptsView === true,
    receiptsRegister: values.receiptsRegister === true,
    commissionsView: values.commissionsView === true,
    commissionsPay: values.commissionsPay === true,
    commissionsAdjust: values.commissionsAdjust === true,
    commissionsExport: values.commissionsExport === true,
  };
  return {
    ...access,
    any:
      access.dashboardView
      || access.commissionAssign
      || access.receiptsView
      || access.receiptsRegister
      || access.commissionsView
      || access.commissionsPay
      || access.commissionsAdjust,
  };
}

function emptyOverview(error: string): FinanceOverview {
  return {
    totals: { openReceivables: null, receivedPeriod: null, commissionBalance: null, ordersWithBalance: null },
    receipts: [],
    error,
  };
}

function humanError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("permission") || normalized.includes("not allowed") || normalized.includes("module unavailable")) {
    return "Usuário sem alçada para consultar estes dados financeiros.";
  }
  if (normalized.includes("period")) return "O período informado é inválido.";
  return "Não foi possível carregar os dados financeiros.";
}

function querySuccess<T>(data: T): FinanceQueryResult<T> {
  return { data, error: null };
}

function queryFailure<T>(error: string): FinanceQueryResult<T> {
  return { data: [] as T, error };
}

function nullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalString(value: unknown): string | null {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  return String(value);
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringArray(value: unknown): string[] {
  return array(value).map(String);
}

function mapCommissionAccount(row: Record<string, unknown>): CommissionAccount {
  return {
    personId: Number(row.pessoa_id),
    personName: String(row.pessoa_nome),
    roles: stringArray(row.papeis),
    status: String(row.situacao),
    predicted: Number(row.comissoes_previstas ?? 0),
    released: Number(row.creditos_liberados ?? 0),
    payments: Number(row.pagamentos ?? 0),
    reversals: Number(row.estornos ?? 0),
    adjustments: Number(row.ajustes ?? 0),
    balance: Number(row.saldo ?? 0),
    totalCount: Number(row.total_count ?? 0),
  };
}
