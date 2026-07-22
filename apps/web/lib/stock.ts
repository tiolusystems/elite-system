import type { PcpAvailableLot } from "@/lib/pcp";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type StockQuery = { search: string; family: string; status: string; validity: string; page: number };
export type StockWorkspace = { lots: PcpAvailableLot[]; total: number; page: number; pageSize: number; source: "supabase" | "error" | "not_configured"; error: string | null };
export type StockProduct = { family: string; id: number; code: string; name: string; presentations: number; lots: number };
export type StockPresentation = { id: number; code: string; description: string; lots: number; available: number };

export async function getStockProducts(search: string, family: string): Promise<StockProduct[]> {
  if (!search.trim() || !getRuntimeStatus().supabaseConfigured) return [];
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("consultar_est_estoque_produtos", { p_busca: search, p_familia: family, p_limite: 30 });
  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    family: String(row.familia), id: Number(row.produto_id), code: String(row.codigo), name: String(row.nome),
    presentations: Number(row.apresentacoes), lots: Number(row.lotes_disponiveis)
  }));
}

export async function getStockPresentations(productId: number): Promise<StockPresentation[]> {
  if (!productId || !getRuntimeStatus().supabaseConfigured) return [];
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("consultar_est_estoque_apresentacoes", { p_produto_id: productId });
  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    id: Number(row.apresentacao_id), code: String(row.codigo), description: String(row.descricao),
    lots: Number(row.lotes_disponiveis), available: Number(row.saldo_disponivel)
  }));
}

export async function getTargetStockLots(family: string, targetId: number, page: number): Promise<StockWorkspace> {
  const pageSize = 24;
  if (!targetId || !getRuntimeStatus().supabaseConfigured) return { lots: [], total: 0, page: 1, pageSize, source: "supabase", error: null };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("consultar_est_estoque_lotes_alvo", {
    p_alvo_id: targetId, p_familia: family, p_limite: pageSize, p_offset: (page - 1) * pageSize
  });
  if (error) return { lots: [], total: 0, page, pageSize, source: "error", error: "Nao foi possivel consultar os lotes." };
  return mapStockRows((data ?? []) as Array<Record<string, unknown>>, page, pageSize);
}

export async function getStockWorkspace(query: StockQuery): Promise<StockWorkspace> {
  const pageSize = 24;
  if (!getRuntimeStatus().supabaseConfigured) return { lots: [], total: 0, page: 1, pageSize, source: "not_configured", error: "Banco de dados nao configurado." };
  if (!query.search.trim()) return { lots: [], total: 0, page: 1, pageSize, source: "supabase", error: null };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("consultar_est_estoque_lotes", {
    p_busca: query.search,
    p_familia: query.family,
    p_limite: pageSize,
    p_offset: (query.page - 1) * pageSize,
    p_status: query.status,
    p_validade: query.validity
  });
  if (error) return { lots: [], total: 0, page: query.page, pageSize, source: "error", error: "Nao foi possivel consultar os lotes." };
  return mapStockRows((data ?? []) as Array<Record<string, unknown>>, query.page, pageSize);
}

function mapStockRows(rows: Array<Record<string, unknown>>, page: number, pageSize: number): StockWorkspace {
  return {
    lots: rows.map((row) => ({
      id: Number(row.lote_id), tipo: String(row.familia) as PcpAvailableLot["tipo"], targetId: Number(row.alvo_id),
      targetLabel: String(row.alvo_label), codigoLote: String(row.codigo_lote), status: String(row.status),
      saldoFisico: Number(row.saldo_fisico), quantidadeReservada: Number(row.quantidade_reservada), saldoDisponivel: Number(row.saldo_disponivel),
      dataValidade: row.data_validade ? String(row.data_validade) : null, origemRef: row.origem_ref ? String(row.origem_ref) : null,
      updatedAt: String(row.updated_at), entryAt: String(row.created_at)
    })),
    total: rows.length ? Number(rows[0].total_count) : 0,
    page,
    pageSize,
    source: "supabase",
    error: null
  };
}
