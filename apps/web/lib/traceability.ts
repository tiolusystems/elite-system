import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type TraceEdge = {
  sourceType: string;
  sourceId: number;
  sourceCode: string;
  targetType: string;
  targetId: number;
  targetCode: string;
  quantity: number | null;
  unit: string | null;
  occurredAt: string;
  event: string;
  active: boolean;
  depth: number;
};

export type RecallDestination = {
  finishedLotId: number;
  finishedLotCode: string;
  product: string;
  lotStatus: string;
  currentBalance: number | null;
  shipmentId: number;
  shipmentCode: string;
  orderId: number;
  orderCode: string;
  customerId: number;
  customerName: string;
  propertyName: string | null;
  quantity: number | null;
  shippedAt: string;
  fiscalReference: string | null;
  contacts: Array<{ name: string; role: string; phone: string | null; email: string | null }>;
};

export type TraceFilters = {
  type: string;
  code: string;
  customerId: number | null;
  customerQuery: string;
  orderId: number | null;
  orderQuery: string;
  shipmentId: number | null;
  shipmentQuery: string;
  fiscalReference: string;
  direction: string;
};

export async function getTraceability(filters: TraceFilters) {
  if (!hasTraceFilter(filters)) return { edges: [] as TraceEdge[], error: null, source: "empty" as const };
  if (!getRuntimeStatus().supabaseConfigured) return { edges: [] as TraceEdge[], error: "Banco de homologação indisponível.", source: "error" as const };
  const supabase = await createSupabaseServerClient();
  const [customer, order, shipment] = await Promise.all([
    filters.customerId ? Promise.resolve({ id: filters.customerId, error: null }) : resolvePresentedId(supabase, "cad_clientes", "nome", filters.customerQuery),
    filters.orderId ? Promise.resolve({ id: filters.orderId, error: null }) : resolvePresentedId(supabase, "com_pedidos", "codigo_pedido", filters.orderQuery),
    filters.shipmentId ? Promise.resolve({ id: filters.shipmentId, error: null }) : resolvePresentedId(supabase, "exp_romaneios", "codigo_romaneio", filters.shipmentQuery)
  ]);
  const resolutionError = customer.error ?? order.error ?? shipment.error;
  if (resolutionError) return { edges: [] as TraceEdge[], error: resolutionError, source: "error" as const };
  const { data, error } = await supabase.rpc("consultar_rel_rastreabilidade", {
    p_cliente_id: customer.id,
    p_codigo: filters.code || null,
    p_direcao: filters.direction || "ambas",
    p_limite: 500,
    p_pedido_id: order.id,
    p_referencia_fiscal: filters.fiscalReference || null,
    p_romaneio_id: shipment.id,
    p_tipo: filters.type || null
  });
  if (error) return { edges: [] as TraceEdge[], error: humanTraceError(error.message), source: "error" as const };
  return { edges: ((data ?? []) as Array<Record<string, unknown>>).map(mapEdge), error: null, source: "supabase" as const };
}

export async function getRecall(type: string, lotCode: string) {
  if (!type || !lotCode) return { destinations: [] as RecallDestination[], error: null };
  if (!getRuntimeStatus().supabaseConfigured) return { destinations: [] as RecallDestination[], error: "Banco de homologação indisponível." };
  const supabase = await createSupabaseServerClient();
  const lot = await resolveLotId(supabase, type, lotCode);
  if (lot.error) return { destinations: [] as RecallDestination[], error: lot.error };
  if (!lot.id) return { destinations: [] as RecallDestination[], error: "Lote não encontrado para a família informada." };
  const { data, error } = await supabase.rpc("simular_rel_recolhimento", { p_lote_id: lot.id, p_tipo_lote: type });
  if (error) return { destinations: [] as RecallDestination[], error: humanTraceError(error.message) };
  return { destinations: ((data ?? []) as Array<Record<string, unknown>>).map(mapRecall), error: null };
}

export function hasTraceFilter(filters: TraceFilters) {
  return Boolean(filters.type || filters.code || filters.customerId || filters.customerQuery || filters.orderId || filters.orderQuery || filters.shipmentId || filters.shipmentQuery || filters.fiscalReference);
}

async function resolvePresentedId(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  table: "cad_clientes" | "com_pedidos" | "exp_romaneios",
  column: "nome" | "codigo_pedido" | "codigo_romaneio",
  query: string
) {
  if (!query) return { id: null as number | null, error: null as string | null };
  const { data, error } = await supabase.from(table).select("id").ilike(column, `%${query}%`).limit(2);
  if (error) return { id: null, error: "Não foi possível localizar o registro informado." };
  if (!data?.length) return { id: null, error: "Nenhum registro corresponde ao filtro informado." };
  if (data.length > 1) return { id: null, error: "O filtro corresponde a mais de um registro; refine a busca." };
  return { id: Number(data[0].id), error: null };
}

async function resolveLotId(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  type: string,
  code: string
) {
  const table = type === "MP" || type === "EMBALAGEM" ? "est_lotes_mp" : type === "PI" ? "est_lotes_pi" : "est_lotes_pa";
  const { data, error } = await supabase.from(table).select("id").ilike("codigo_lote", `%${code}%`).limit(2);
  if (error) return { id: null as number | null, error: "Não foi possível localizar o lote informado." };
  if (!data?.length) return { id: null, error: null };
  if (data.length > 1) return { id: null, error: "O código corresponde a mais de um lote; refine a busca." };
  return { id: Number(data[0].id), error: null };
}

function mapEdge(row: Record<string, unknown>): TraceEdge {
  return {
    sourceType: String(row.origem_tipo), sourceId: Number(row.origem_id), sourceCode: String(row.origem_codigo),
    targetType: String(row.destino_tipo), targetId: Number(row.destino_id), targetCode: String(row.destino_codigo),
    quantity: row.quantidade == null ? null : Number(row.quantidade), unit: row.unidade == null ? null : String(row.unidade),
    occurredAt: String(row.evento_em), event: String(row.evento), active: Boolean(row.ativo), depth: Number(row.profundidade)
  };
}

function mapRecall(row: Record<string, unknown>): RecallDestination {
  return {
    finishedLotId: Number(row.lote_pa_id), finishedLotCode: String(row.codigo_lote),
    product: String(row.produto), lotStatus: String(row.status_lote), currentBalance: row.saldo_fisico == null ? null : Number(row.saldo_fisico),
    shipmentId: Number(row.romaneio_id), shipmentCode: String(row.codigo_romaneio),
    orderId: Number(row.pedido_id), orderCode: String(row.codigo_pedido),
    customerId: Number(row.cliente_id), customerName: String(row.cliente_nome),
    propertyName: row.propriedade_nome == null ? null : String(row.propriedade_nome),
    quantity: row.quantidade == null ? null : Number(row.quantidade), shippedAt: String(row.expedido_em),
    fiscalReference: row.referencia_fiscal == null ? null : String(row.referencia_fiscal),
    contacts: Array.isArray(row.contatos) ? row.contatos.map((contact) => {
      const value = contact as Record<string, unknown>;
      return {
        name: String(value.nome), role: String(value.papel),
        phone: value.telefone == null ? null : String(value.telefone),
        email: value.email == null ? null : String(value.email)
      };
    }) : []
  };
}

function humanTraceError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("not allowed") || normalized.includes("permission")) return "Você não possui alçada para esta consulta.";
  if (normalized.includes("filter")) return "Informe ao menos um filtro de rastreabilidade.";
  return "Não foi possível consultar a rastreabilidade. Nenhum dado foi alterado.";
}
