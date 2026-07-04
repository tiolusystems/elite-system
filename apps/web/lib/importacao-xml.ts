import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type XmlLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type NfeXmlSummary = {
  nfeId: number;
  chaveAcesso: string;
  numero: string | null;
  serie: string | null;
  emitenteNome: string | null;
  emitenteCnpj: string | null;
  dataEmissao: string | null;
  status: string;
  totalItens: number;
  itensPendentesMatch: number;
  itensConfirmados: number;
  itensComLoteMp: number;
  itensIgnorados: number;
  valorTotalXml: number;
  updatedAt: string;
};

export type PendingXmlItem = {
  itemId: number;
  nfeId: number;
  chaveAcesso: string;
  nfeNumero: string | null;
  emitenteNome: string | null;
  numeroItem: number;
  codigoFornecedor: string | null;
  descricaoFornecedor: string;
  ncm: string | null;
  cfop: string | null;
  unidadeXml: string;
  quantidadeXml: number;
  valorTotal: number;
  status: string;
  materiaPrimaSugeridaId: number | null;
  materiaPrimaSugeridaSku: string | null;
  materiaPrimaSugeridaNome: string | null;
  melhorScore: number | null;
  melhorMotivo: string | null;
  totalCandidatos: number;
  updatedAt: string;
};

export type ImportacaoXmlDashboard = {
  metrics: {
    notasXml: number | null;
    itensPendentes: number | null;
    itensConfirmados: number | null;
    lotesMpGerados: number | null;
    valorXml: number | null;
  };
  nfeOptions: XmlLookupOption[];
  materiasPrimas: XmlLookupOption[];
  summaries: NfeXmlSummary[];
  pendingItems: PendingXmlItem[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_DASHBOARD: ImportacaoXmlDashboard = {
  metrics: {
    notasXml: null,
    itensPendentes: null,
    itensConfirmados: null,
    lotesMpGerados: null,
    valorXml: null
  },
  nfeOptions: [],
  materiasPrimas: [],
  summaries: [],
  pendingItems: [],
  source: "not_configured",
  error: null
};

export async function getImportacaoXmlDashboard(): Promise<ImportacaoXmlDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return EMPTY_DASHBOARD;
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [summaries, pendingItems, materiasPrimas] = await Promise.all([
      supabase
        .from("imp_nfe_xml_resumo")
        .select(
          "nfe_id,chave_acesso_norm,numero,serie,emitente_nome,emitente_cnpj_norm,data_emissao,status,total_itens,itens_pendentes_match,itens_confirmados,itens_com_lote_mp,itens_ignorados,valor_total_xml,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(30),
      supabase
        .from("imp_nfe_xml_itens_pendentes_match")
        .select(
          "item_id,nfe_id,chave_acesso_norm,nfe_numero,emitente_nome,numero_item,codigo_fornecedor,descricao_fornecedor,ncm,cfop,unidade_xml,quantidade_xml,valor_total,status,materia_prima_sugerida_id,materia_prima_sugerida_sku,materia_prima_sugerida_nome,melhor_score,melhor_motivo,total_candidatos,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(80),
      supabase
        .from("cad_materias_primas")
        .select("id,sku_corrigido,nome,unidade_base_estoque,status")
        .eq("status", "active")
        .order("nome", { ascending: true })
        .limit(300)
    ]);

    const mappedSummaries = summaries.error
      ? []
      : ((summaries.data ?? []) as Array<Record<string, unknown>>).map(mapSummary);
    const mappedPending = pendingItems.error
      ? []
      : ((pendingItems.data ?? []) as Array<Record<string, unknown>>).map(mapPendingItem);
    const mappedMps = materiasPrimas.error
      ? []
      : ((materiasPrimas.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
          id: Number(row.id),
          label: `${row.sku_corrigido ?? "sem SKU"} - ${row.nome ?? "sem nome"}`,
          detail: `${row.unidade_base_estoque ?? "sem unidade"} / ${row.status ?? "sem status"}`
        }));

    return {
      metrics: {
        notasXml: mappedSummaries.length,
        itensPendentes: mappedSummaries.reduce((sum, item) => sum + item.itensPendentesMatch, 0),
        itensConfirmados: mappedSummaries.reduce((sum, item) => sum + item.itensConfirmados, 0),
        lotesMpGerados: mappedSummaries.reduce((sum, item) => sum + item.itensComLoteMp, 0),
        valorXml: mappedSummaries.reduce((sum, item) => sum + item.valorTotalXml, 0)
      },
      nfeOptions: mappedSummaries.map((item) => ({
        id: item.nfeId,
        label: `${item.numero ?? "sem numero"} - ${item.emitenteNome ?? item.chaveAcesso}`,
        detail: `${item.status} / ${item.totalItens} item(ns)`
      })),
      materiasPrimas: mappedMps,
      summaries: mappedSummaries,
      pendingItems: mappedPending,
      source: "supabase",
      error: summaries.error?.message ?? pendingItems.error?.message ?? materiasPrimas.error?.message ?? null
    };
  } catch (error) {
    return {
      ...EMPTY_DASHBOARD,
      source: "error",
      error: error instanceof Error ? error.message : "Erro desconhecido"
    };
  }
}

function mapSummary(row: Record<string, unknown>): NfeXmlSummary {
  return {
    nfeId: Number(row.nfe_id),
    chaveAcesso: String(row.chave_acesso_norm),
    numero: nullableString(row.numero),
    serie: nullableString(row.serie),
    emitenteNome: nullableString(row.emitente_nome),
    emitenteCnpj: nullableString(row.emitente_cnpj_norm),
    dataEmissao: nullableString(row.data_emissao),
    status: String(row.status),
    totalItens: Number(row.total_itens ?? 0),
    itensPendentesMatch: Number(row.itens_pendentes_match ?? 0),
    itensConfirmados: Number(row.itens_confirmados ?? 0),
    itensComLoteMp: Number(row.itens_com_lote_mp ?? 0),
    itensIgnorados: Number(row.itens_ignorados ?? 0),
    valorTotalXml: Number(row.valor_total_xml ?? 0),
    updatedAt: String(row.updated_at)
  };
}

function mapPendingItem(row: Record<string, unknown>): PendingXmlItem {
  return {
    itemId: Number(row.item_id),
    nfeId: Number(row.nfe_id),
    chaveAcesso: String(row.chave_acesso_norm),
    nfeNumero: nullableString(row.nfe_numero),
    emitenteNome: nullableString(row.emitente_nome),
    numeroItem: Number(row.numero_item),
    codigoFornecedor: nullableString(row.codigo_fornecedor),
    descricaoFornecedor: String(row.descricao_fornecedor),
    ncm: nullableString(row.ncm),
    cfop: nullableString(row.cfop),
    unidadeXml: String(row.unidade_xml),
    quantidadeXml: Number(row.quantidade_xml ?? 0),
    valorTotal: Number(row.valor_total ?? 0),
    status: String(row.status),
    materiaPrimaSugeridaId: nullableNumber(row.materia_prima_sugerida_id),
    materiaPrimaSugeridaSku: nullableString(row.materia_prima_sugerida_sku),
    materiaPrimaSugeridaNome: nullableString(row.materia_prima_sugerida_nome),
    melhorScore: nullableNumber(row.melhor_score),
    melhorMotivo: nullableString(row.melhor_motivo),
    totalCandidatos: Number(row.total_candidatos ?? 0),
    updatedAt: String(row.updated_at)
  };
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}
