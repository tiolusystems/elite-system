import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type OrderLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type OrderLookups = {
  clientes: OrderLookupOption[];
  propriedades: OrderLookupOption[];
  itensVendaveis: OrderLookupOption[];
  pessoasComerciais: OrderLookupOption[];
  pedidos: OrderLookupOption[];
  pedidoItens: OrderLookupOption[];
};

export type RecentOrder = {
  id: number;
  codigoPedido: string;
  clienteId: number;
  propriedadeId: number | null;
  sequenciaPropriedade: number | null;
  vendedorGeradorId: number | null;
  tipoPedido: string;
  status: string;
  dataPedido: string;
  valorTotal: number;
  createdAt: string;
};

export type RecentCreditDecision = {
  id: number;
  pedidoId: number;
  decisao: string;
  statusAnterior: string;
  statusResultante: string;
  motivo: string | null;
  limiteDisponivelSnapshot: number | null;
  inadimplenciaSnapshot: number | null;
  createdAt: string;
};

export type RecentReceipt = {
  id: number;
  pedidoId: number;
  valorRecebido: number;
  dataRecebimento: string;
  formaRecebimento: string | null;
  createdAt: string;
};

export type RecentCommissionRelease = {
  id: number;
  recebimentoId: number;
  pedidoId: number;
  pessoaId: number;
  valorLiberado: number;
  percentualRecebidoSnapshot: number;
  status: string;
  createdAt: string;
};

export type OrdersDashboard = {
  metrics: {
    totalPedidos: number | null;
    rascunhos: number | null;
    abertos: number | null;
    bloqueados: number | null;
    faturamentoPrevisto: number | null;
    totalRecebido: number | null;
    comissaoLiberada: number | null;
  };
  lookups: OrderLookups;
  recentOrders: RecentOrder[];
  recentCreditDecisions: RecentCreditDecision[];
  recentReceipts: RecentReceipt[];
  recentCommissionReleases: RecentCommissionRelease[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_LOOKUPS: OrderLookups = {
  clientes: [],
  propriedades: [],
  itensVendaveis: [],
  pessoasComerciais: [],
  pedidos: [],
  pedidoItens: []
};

export async function getOrdersDashboard(): Promise<OrdersDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [
      totalPedidos,
      rascunhos,
      abertos,
      bloqueados,
      totals,
      receivedTotals,
      commissionTotals,
      recentOrders,
      creditDecisions,
      recentReceipts,
      commissionReleases,
      lookups
    ] = await Promise.all([
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "draft"),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "open"),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "blocked"),
      supabase.from("com_pedidos").select("valor_total,status").limit(1000),
      supabase.from("com_recebimentos").select("valor_recebido").limit(1000),
      supabase.from("com_comissao_liberacoes").select("valor_liberado,status").limit(1000),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,propriedade_id,sequencia_propriedade,vendedor_gerador_id,tipo_pedido,status,data_pedido,valor_total,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_pedido_credito_decisoes")
        .select("id,pedido_id,decisao,status_anterior,status_resultante,motivo,limite_disponivel_snapshot,inadimplencia_snapshot,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_recebimentos")
        .select("id,pedido_id,valor_recebido,data_recebimento,forma_recebimento,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_comissao_liberacoes")
        .select("id,recebimento_id,pedido_id,pessoa_id,valor_liberado,percentual_recebido_snapshot,status,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      getOrderLookups(supabase)
    ]);

    const totalRows = totals.error ? [] : ((totals.data ?? []) as Array<{ valor_total: number | string | null; status: string }>);
    const receivedRows = receivedTotals.error ? [] : ((receivedTotals.data ?? []) as Array<{ valor_recebido: number | string | null }>);
    const commissionRows = commissionTotals.error
      ? []
      : ((commissionTotals.data ?? []) as Array<{ valor_liberado: number | string | null; status: string }>);

    return {
      metrics: {
        totalPedidos: totalPedidos.count ?? null,
        rascunhos: rascunhos.count ?? null,
        abertos: abertos.count ?? null,
        bloqueados: bloqueados.count ?? null,
        faturamentoPrevisto: totalRows
          .filter((row) => row.status !== "cancelled")
          .reduce((sum, row) => sum + Number(row.valor_total ?? 0), 0),
        totalRecebido: receivedRows.reduce((sum, row) => sum + Number(row.valor_recebido ?? 0), 0),
        comissaoLiberada: commissionRows
          .filter((row) => row.status === "liberada")
          .reduce((sum, row) => sum + Number(row.valor_liberado ?? 0), 0)
      },
      lookups,
      recentOrders: recentOrders.error
        ? []
        : ((recentOrders.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            codigoPedido: String(row.codigo_pedido),
            clienteId: Number(row.cliente_id),
            propriedadeId: nullableNumber(row.propriedade_id),
            sequenciaPropriedade: nullableNumber(row.sequencia_propriedade),
            vendedorGeradorId: nullableNumber(row.vendedor_gerador_id),
            tipoPedido: String(row.tipo_pedido),
            status: String(row.status),
            dataPedido: String(row.data_pedido),
            valorTotal: Number(row.valor_total ?? 0),
            createdAt: String(row.created_at)
          })),
      recentCreditDecisions: creditDecisions.error
        ? []
        : ((creditDecisions.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            pedidoId: Number(row.pedido_id),
            decisao: String(row.decisao),
            statusAnterior: String(row.status_anterior),
            statusResultante: String(row.status_resultante),
            motivo: row.motivo === null ? null : String(row.motivo),
            limiteDisponivelSnapshot:
              row.limite_disponivel_snapshot === null ? null : Number(row.limite_disponivel_snapshot),
            inadimplenciaSnapshot: row.inadimplencia_snapshot === null ? null : Number(row.inadimplencia_snapshot),
            createdAt: String(row.created_at)
          })),
      recentReceipts: recentReceipts.error
        ? []
        : ((recentReceipts.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            pedidoId: Number(row.pedido_id),
            valorRecebido: Number(row.valor_recebido ?? 0),
            dataRecebimento: String(row.data_recebimento),
            formaRecebimento: row.forma_recebimento === null ? null : String(row.forma_recebimento),
            createdAt: String(row.created_at)
          })),
      recentCommissionReleases: commissionReleases.error
        ? []
        : ((commissionReleases.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            recebimentoId: Number(row.recebimento_id),
            pedidoId: Number(row.pedido_id),
            pessoaId: Number(row.pessoa_id),
            valorLiberado: Number(row.valor_liberado ?? 0),
            percentualRecebidoSnapshot: Number(row.percentual_recebido_snapshot ?? 0),
            status: String(row.status),
            createdAt: String(row.created_at)
          })),
      source: "supabase",
      error:
        totalPedidos.error?.message ??
        rascunhos.error?.message ??
        abertos.error?.message ??
        bloqueados.error?.message ??
        totals.error?.message ??
        receivedTotals.error?.message ??
        commissionTotals.error?.message ??
        recentOrders.error?.message ??
        creditDecisions.error?.message ??
        recentReceipts.error?.message ??
        commissionReleases.error?.message ??
        null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getOrderLookups(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<OrderLookups> {
  try {
    const [clientes, propriedades, itensVendaveis, pessoasComerciais, pedidos, pedidoItens] = await Promise.all([
      supabase
        .from("cad_clientes")
        .select("id,nome,cidade,uf,status")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_cliente_propriedades")
        .select("id,cliente_id,nome,cidade,uf,status")
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(200),
      supabase
        .from("cad_produto_embalagens")
        .select("id,codigo_item,status,produto_id,embalagem_id,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros,unidade)")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,tipo_pedido,status,valor_total")
        .in("status", ["draft", "open", "blocked"])
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("com_pedido_itens")
        .select("id,pedido_id,produto_embalagem_id,tipo_item,quantidade,status")
        .eq("status", "active")
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
      propriedades: propriedades.error
        ? []
        : ((propriedades.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `cliente ${item.cliente_id} / ${item.cidade ?? "sem cidade"} / ${item.uf ?? "sem UF"}`
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
          })),
      pedidos: pedidos.error
        ? []
        : ((pedidos.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.codigo_pedido),
            detail: `cliente ${item.cliente_id} / ${item.tipo_pedido} / ${item.status} / ${Number(item.valor_total ?? 0).toFixed(2)}`
          })),
      pedidoItens: pedidoItens.error
        ? []
        : ((pedidoItens.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: `pedido ${item.pedido_id} / item ${item.produto_embalagem_id}`,
            detail: `${item.tipo_item} / qtd ${Number(item.quantidade ?? 0).toFixed(4)} / ${item.status ?? "sem status"}`
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

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function emptyDashboard(source: OrdersDashboard["source"], error: string | null): OrdersDashboard {
  return {
    metrics: {
      totalPedidos: null,
      rascunhos: null,
      abertos: null,
      bloqueados: null,
      faturamentoPrevisto: null,
      totalRecebido: null,
      comissaoLiberada: null
    },
    lookups: EMPTY_LOOKUPS,
    recentOrders: [],
    recentCreditDecisions: [],
    recentReceipts: [],
    recentCommissionReleases: [],
    source,
    error
  };
}
