import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type KanbanColumnKey = "rascunho" | "aberto" | "bloqueado" | "concluido" | "cancelado";

export type KanbanOrder = {
  pedidoId: number;
  codigoPedido: string;
  status: string;
  colunaKanban: KanbanColumnKey;
  tipoPedido: string;
  dataPedido: string;
  previsaoEntrega: string | null;
  valorTotal: number;
  clienteId: number;
  clienteNome: string;
  propriedadeId: number | null;
  propriedadeNome: string | null;
  propriedadeCidade: string | null;
  propriedadeUf: string | null;
  sequenciaPropriedade: number | null;
  vendedorGeradorId: number | null;
  vendedorGeradorNome: string | null;
  gerenteVinculadoNome: string | null;
  areaNome: string | null;
  gerenteAreaNome: string | null;
  updatedAt: string;
};

export type KanbanColumn = {
  key: KanbanColumnKey;
  title: string;
  detail: string;
  orders: KanbanOrder[];
};

export type KanbanDashboard = {
  metrics: {
    total: number | null;
    rascunho: number | null;
    aberto: number | null;
    bloqueado: number | null;
    valorAberto: number | null;
  };
  columns: KanbanColumn[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const COLUMN_DEFS: Array<Omit<KanbanColumn, "orders">> = [
  { key: "rascunho", title: "Rascunho", detail: "Pedido ainda ajustavel, sem baixa de estoque." },
  { key: "aberto", title: "Aberto", detail: "Apto a credito, romaneio, faturamento e acompanhamento." },
  { key: "bloqueado", title: "Bloqueado", detail: "Retido por credito, cadastro ou regra operacional." },
  { key: "concluido", title: "Concluido", detail: "Atendido no fluxo operacional." },
  { key: "cancelado", title: "Cancelado", detail: "Encerrado sem prosseguir no fluxo." }
];

export async function getKanbanDashboard(): Promise<KanbanDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const rows = await supabase
      .from("com_pedidos_kanban")
      .select(
        "pedido_id,codigo_pedido,status,coluna_kanban,tipo_pedido,data_pedido,previsao_entrega,valor_total,cliente_id,cliente_nome,propriedade_id,propriedade_nome,propriedade_cidade,propriedade_uf,sequencia_propriedade,vendedor_gerador_id,vendedor_gerador_nome,gerente_vinculado_nome,area_nome,gerente_area_nome,updated_at"
      )
      .order("updated_at", { ascending: false })
      .limit(240);

    if (rows.error) {
      return emptyDashboard("error", rows.error.message);
    }

    const orders = ((rows.data ?? []) as Array<Record<string, unknown>>).map(mapOrder);

    return {
      metrics: {
        total: orders.length,
        rascunho: orders.filter((order) => order.colunaKanban === "rascunho").length,
        aberto: orders.filter((order) => order.colunaKanban === "aberto").length,
        bloqueado: orders.filter((order) => order.colunaKanban === "bloqueado").length,
        valorAberto: orders
          .filter((order) => order.colunaKanban === "aberto")
          .reduce((sum, order) => sum + order.valorTotal, 0)
      },
      columns: COLUMN_DEFS.map((column) => ({
        ...column,
        orders: orders.filter((order) => order.colunaKanban === column.key)
      })),
      source: "supabase",
      error: null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

function mapOrder(row: Record<string, unknown>): KanbanOrder {
  const column = String(row.coluna_kanban);
  return {
    pedidoId: Number(row.pedido_id),
    codigoPedido: String(row.codigo_pedido),
    status: String(row.status),
    colunaKanban: isKanbanColumn(column) ? column : "rascunho",
    tipoPedido: String(row.tipo_pedido),
    dataPedido: String(row.data_pedido),
    previsaoEntrega: nullableString(row.previsao_entrega),
    valorTotal: Number(row.valor_total ?? 0),
    clienteId: Number(row.cliente_id),
    clienteNome: String(row.cliente_nome),
    propriedadeId: nullableNumber(row.propriedade_id),
    propriedadeNome: nullableString(row.propriedade_nome),
    propriedadeCidade: nullableString(row.propriedade_cidade),
    propriedadeUf: nullableString(row.propriedade_uf),
    sequenciaPropriedade: nullableNumber(row.sequencia_propriedade),
    vendedorGeradorId: nullableNumber(row.vendedor_gerador_id),
    vendedorGeradorNome: nullableString(row.vendedor_gerador_nome),
    gerenteVinculadoNome: nullableString(row.gerente_vinculado_nome),
    areaNome: nullableString(row.area_nome),
    gerenteAreaNome: nullableString(row.gerente_area_nome),
    updatedAt: String(row.updated_at)
  };
}

function isKanbanColumn(value: string): value is KanbanColumnKey {
  return COLUMN_DEFS.some((column) => column.key === value);
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function emptyDashboard(source: KanbanDashboard["source"], error: string | null): KanbanDashboard {
  return {
    metrics: {
      total: null,
      rascunho: null,
      aberto: null,
      bloqueado: null,
      valorAberto: null
    },
    columns: COLUMN_DEFS.map((column) => ({ ...column, orders: [] })),
    source,
    error
  };
}
