import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type OrderLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type OrderLookups = {
  clientes: OrderLookupOption[];
  itensVendaveis: OrderLookupOption[];
  pessoasComerciais: OrderLookupOption[];
};

export type RecentOrder = {
  id: number;
  codigoPedido: string;
  clienteId: number;
  tipoPedido: string;
  status: string;
  dataPedido: string;
  valorTotal: number;
  createdAt: string;
};

export type OrdersDashboard = {
  metrics: {
    totalPedidos: number | null;
    rascunhos: number | null;
    abertos: number | null;
    faturamentoPrevisto: number | null;
  };
  lookups: OrderLookups;
  recentOrders: RecentOrder[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_LOOKUPS: OrderLookups = {
  clientes: [],
  itensVendaveis: [],
  pessoasComerciais: []
};

export async function getOrdersDashboard(): Promise<OrdersDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [totalPedidos, rascunhos, abertos, totals, recentOrders, lookups] = await Promise.all([
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "draft"),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "open"),
      supabase.from("com_pedidos").select("valor_total,status").limit(1000),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,tipo_pedido,status,data_pedido,valor_total,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      getOrderLookups(supabase)
    ]);

    const totalRows = totals.error ? [] : ((totals.data ?? []) as Array<{ valor_total: number | string | null; status: string }>);

    return {
      metrics: {
        totalPedidos: totalPedidos.count ?? null,
        rascunhos: rascunhos.count ?? null,
        abertos: abertos.count ?? null,
        faturamentoPrevisto: totalRows
          .filter((row) => row.status !== "cancelled")
          .reduce((sum, row) => sum + Number(row.valor_total ?? 0), 0)
      },
      lookups,
      recentOrders: recentOrders.error
        ? []
        : ((recentOrders.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            codigoPedido: String(row.codigo_pedido),
            clienteId: Number(row.cliente_id),
            tipoPedido: String(row.tipo_pedido),
            status: String(row.status),
            dataPedido: String(row.data_pedido),
            valorTotal: Number(row.valor_total ?? 0),
            createdAt: String(row.created_at)
          })),
      source: "supabase",
      error: totalPedidos.error?.message ?? rascunhos.error?.message ?? abertos.error?.message ?? totals.error?.message ?? recentOrders.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getOrderLookups(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<OrderLookups> {
  try {
    const [clientes, itensVendaveis, pessoasComerciais] = await Promise.all([
      supabase
        .from("cad_clientes")
        .select("id,nome,cidade,uf,status")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_produto_embalagens")
        .select("id,codigo_item,status,produto_id,embalagem_id,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros,unidade)")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .order("created_at", { ascending: false })
        .limit(120)
    ]);

    return {
      clientes: clientes.error
        ? []
        : ((clientes.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `${item.cidade ?? "sem cidade"} / ${item.uf ?? "sem UF"} / ${item.status ?? "sem status"}`
          })),
      itensVendaveis: itensVendaveis.error
        ? []
        : ((itensVendaveis.data ?? []) as Array<Record<string, unknown>>).map((item) => {
            const produto = firstNested(item.cad_produtos_base);
            const embalagem = firstNested(item.cad_embalagens);
            const produtoLabel = produto ? `${produto.codigo_produto ?? ""} ${produto.nome ?? ""}`.trim() : `produto ${item.produto_id}`;
            const embalagemLabel = embalagem ? `${embalagem.descricao ?? ""}`.trim() : `embalagem ${item.embalagem_id}`;
            return {
              id: Number(item.id),
              label: `${item.codigo_item} - ${produtoLabel}`,
              detail: `${embalagemLabel} / ${item.status ?? "sem status"}`
            };
          }),
      pessoasComerciais: pessoasComerciais.error
        ? []
        : ((pessoasComerciais.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `${item.tipo_comercial ?? "sem tipo"} / ${item.status ?? "sem status"}`
          }))
    };
  } catch {
    return EMPTY_LOOKUPS;
  }
}

function firstNested(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    return (value[0] as Record<string, unknown> | undefined) ?? null;
  }
  if (value && typeof value === "object") {
    return value as Record<string, unknown>;
  }
  return null;
}

function emptyDashboard(source: OrdersDashboard["source"], error: string | null): OrdersDashboard {
  return {
    metrics: {
      totalPedidos: null,
      rascunhos: null,
      abertos: null,
      faturamentoPrevisto: null
    },
    lookups: EMPTY_LOOKUPS,
    recentOrders: [],
    source,
    error
  };
}
