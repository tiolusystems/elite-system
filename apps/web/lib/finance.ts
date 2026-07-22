import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type FinanceOrderBalance = {
  id: number;
  code: string;
  clientName: string;
  total: number;
  received: number;
  open: number;
};

export type CommissionBalance = { personId: number; personName: string; balance: number };
export type FinanceReceipt = { id: number; orderId: number | null; value: number; date: string; method: string | null; status: string };
export type CommissionMovement = { id: number; personId: number; type: string; value: number; reason: string | null; createdAt: string };

export type FinanceDashboard = {
  orders: FinanceOrderBalance[];
  commissions: CommissionBalance[];
  receipts: FinanceReceipt[];
  movements: CommissionMovement[];
  totals: { openReceivables: number; received: number; commissionBalance: number };
  error: string | null;
  source: "supabase" | "not_configured" | "error";
};

export async function getFinanceDashboard(): Promise<FinanceDashboard> {
  if (!getRuntimeStatus().supabaseConfigured) return empty("not_configured", "Banco de homologacao nao configurado.");

  try {
    const supabase = await createSupabaseServerClient();
    const [balanceResult, orderResult, clientResult, commissionResult, receiptResult, movementResult] = await Promise.all([
      supabase.from("fin_recebimento_saldos_pedido").select("pedido_id,valor_total,valor_recebido_alocado,saldo_aberto").gt("saldo_aberto", 0).order("pedido_id", { ascending: false }).limit(200),
      supabase.from("com_pedidos").select("id,codigo_pedido,cliente_id,tipo_pedido,status").eq("tipo_pedido", "venda").in("status", ["open", "fulfilled"]).limit(300),
      supabase.from("cad_clientes").select("id,nome").limit(500),
      supabase.from("fin_comissao_saldos").select("pessoa_id,pessoa_nome,saldo_comissao").order("pessoa_nome").limit(300),
      supabase.from("com_recebimentos").select("id,pedido_id,valor_recebido,data_recebimento,forma_recebimento,status").order("id", { ascending: false }).limit(80),
      supabase.from("fin_comissao_movimentos").select("id,pessoa_id,tipo_movimento,valor,motivo,created_at").order("id", { ascending: false }).limit(100),
    ]);

    const error = balanceResult.error ?? orderResult.error ?? clientResult.error ?? commissionResult.error ?? receiptResult.error ?? movementResult.error;
    if (error) return empty("error", humanError(error.message));

    const ordersById = new Map((orderResult.data ?? []).map((row) => [Number(row.id), row]));
    const clientsById = new Map((clientResult.data ?? []).map((row) => [Number(row.id), String(row.nome)]));
    const orders = (balanceResult.data ?? []).flatMap((row) => {
      const order = ordersById.get(Number(row.pedido_id));
      if (!order) return [];
      return [{
        id: Number(row.pedido_id),
        code: String(order.codigo_pedido),
        clientName: clientsById.get(Number(order.cliente_id)) ?? "Cliente nao identificado",
        total: Number(row.valor_total ?? 0),
        received: Number(row.valor_recebido_alocado ?? 0),
        open: Number(row.saldo_aberto ?? 0),
      }];
    });
    const commissions = (commissionResult.data ?? []).map((row) => ({ personId: Number(row.pessoa_id), personName: String(row.pessoa_nome), balance: Number(row.saldo_comissao ?? 0) }));
    const receipts = (receiptResult.data ?? []).map((row) => ({ id: Number(row.id), orderId: row.pedido_id === null ? null : Number(row.pedido_id), value: Number(row.valor_recebido), date: String(row.data_recebimento), method: row.forma_recebimento ? String(row.forma_recebimento) : null, status: String(row.status ?? "active") }));
    const movements = (movementResult.data ?? []).map((row) => ({ id: Number(row.id), personId: Number(row.pessoa_id), type: String(row.tipo_movimento), value: Number(row.valor), reason: row.motivo ? String(row.motivo) : null, createdAt: String(row.created_at) }));

    return {
      orders,
      commissions,
      receipts,
      movements,
      totals: {
        openReceivables: orders.reduce((sum, row) => sum + row.open, 0),
        received: receipts.filter((row) => row.status === "active").reduce((sum, row) => sum + row.value, 0),
        commissionBalance: commissions.reduce((sum, row) => sum + row.balance, 0),
      },
      error: null,
      source: "supabase",
    };
  } catch {
    return empty("error", "Nao foi possivel consultar o financeiro agora.");
  }
}

function empty(source: FinanceDashboard["source"], error: string): FinanceDashboard {
  return { orders: [], commissions: [], receipts: [], movements: [], totals: { openReceivables: 0, received: 0, commissionBalance: 0 }, error, source };
}

function humanError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("permission") || normalized.includes("not allowed")) return "Seu perfil nao possui acesso aos dados financeiros.";
  return "Nao foi possivel carregar os dados financeiros.";
}
