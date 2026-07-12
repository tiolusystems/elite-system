import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type HistoricalMpMapping = {
  stagingItemId: number;
  batchId: number;
  sourceRowId: number;
  codigoLegado: string | null;
  nomeLegado: string | null;
  unidadeOrigem: string | null;
  mappingStatus: string;
  materiaPrimaId: number | null;
  materiaPrimaSku: string | null;
  materiaPrimaNome: string | null;
  matchMethod: string;
  confidence: number | null;
  matchCount: number;
};

export type HistoricalMpPrice = {
  acquisitionValueId: number;
  materiaPrimaId: number;
  sku: string;
  materiaPrimaNome: string;
  codigoLote: string;
  codigoLoteLegado: string | null;
  dataDocumento: string | null;
  documentoRef: string | null;
  ufEmitente: string | null;
  quantidadeOrigem: number;
  unidadeOrigem: string;
  quantidadeBase: number;
  valorMateriaPrima: number;
  frete: number;
  difalIcms: number;
  outrasDespesas: number;
  custoAquisicaoTotal: number;
  custoUnitarioBase: number;
};

export type HistoricalMpDashboard = {
  metrics: {
    batchId: number | null;
    totalItems: number | null;
    pendingItems: number | null;
    suggestedItems: number | null;
    approvedItems: number | null;
    conflictItems: number | null;
    acquisitionRecords: number | null;
    valorMateriaPrima: number | null;
    frete: number | null;
    difalIcms: number | null;
    outrasDespesas: number | null;
    custoAquisicaoTotal: number | null;
  };
  mappings: HistoricalMpMapping[];
  prices: HistoricalMpPrice[];
  canView: boolean;
  source: "supabase" | "not_configured" | "denied" | "error";
  error: string | null;
};

const EMPTY_METRICS: HistoricalMpDashboard["metrics"] = {
  batchId: null,
  totalItems: null,
  pendingItems: null,
  suggestedItems: null,
  approvedItems: null,
  conflictItems: null,
  acquisitionRecords: null,
  valorMateriaPrima: null,
  frete: null,
  difalIcms: null,
  outrasDespesas: null,
  custoAquisicaoTotal: null
};

export async function getHistoricalMpDashboard(): Promise<HistoricalMpDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const permission = await supabase.rpc("can_current_user", { p_action_key: "migration.mp.view" });
    if (permission.error) {
      return emptyDashboard("error", permission.error.message);
    }
    if (!permission.data) {
      return emptyDashboard("denied", "Seu perfil nao possui a alcada migration.mp.view.");
    }

    const summaryResult = await supabase
      .from("migration_mp_batch_summary")
      .select(
        "batch_id,total_items,pending_items,suggested_items,approved_items,conflict_items,acquisition_records,valor_materia_prima,frete,difal_icms,outras_despesas,custo_aquisicao_total"
      )
      .order("batch_id", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (summaryResult.error) {
      return emptyDashboard("error", summaryResult.error.message);
    }

    const summary = summaryResult.data as Record<string, unknown> | null;
    if (!summary) {
      return {
        ...emptyDashboard("supabase", null),
        canView: true,
        metrics: zeroMetrics()
      };
    }

    const batchId = Number(summary.batch_id);
    const [mappingsResult, pricesResult] = await Promise.all([
      supabase
        .from("migration_mp_mapping_dashboard")
        .select(
          "staging_item_id,batch_id,source_row_id,codigo_legado,nome_legado,unidade_origem,mapping_status,materia_prima_id,materia_prima_sku,materia_prima_nome,match_method,confidence,match_count"
        )
        .eq("batch_id", batchId)
        .order("staging_item_id", { ascending: true })
        .limit(200),
      supabase
        .from("est_mp_historico_precos")
        .select(
          "acquisition_value_id,materia_prima_id,sku_corrigido,materia_prima_nome,codigo_lote,codigo_lote_legado,data_documento,documento_ref,uf_emitente,quantidade_origem,unidade_origem,quantidade_base,valor_materia_prima,frete,difal_icms,outras_despesas,custo_aquisicao_total,custo_unitario_base"
        )
        .eq("source_batch_id", batchId)
        .order("data_documento", { ascending: false, nullsFirst: false })
        .limit(200)
    ]);

    return {
      metrics: mapMetrics(summary),
      mappings: mappingsResult.error
        ? []
        : ((mappingsResult.data ?? []) as Array<Record<string, unknown>>).map(mapMapping),
      prices: pricesResult.error
        ? []
        : ((pricesResult.data ?? []) as Array<Record<string, unknown>>).map(mapPrice),
      canView: true,
      source: "supabase",
      error: mappingsResult.error?.message ?? pricesResult.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

function emptyDashboard(source: HistoricalMpDashboard["source"], error: string | null): HistoricalMpDashboard {
  return {
    metrics: EMPTY_METRICS,
    mappings: [],
    prices: [],
    canView: false,
    source,
    error
  };
}

function zeroMetrics(): HistoricalMpDashboard["metrics"] {
  return {
    batchId: null,
    totalItems: 0,
    pendingItems: 0,
    suggestedItems: 0,
    approvedItems: 0,
    conflictItems: 0,
    acquisitionRecords: 0,
    valorMateriaPrima: 0,
    frete: 0,
    difalIcms: 0,
    outrasDespesas: 0,
    custoAquisicaoTotal: 0
  };
}

function mapMetrics(row: Record<string, unknown>): HistoricalMpDashboard["metrics"] {
  return {
    batchId: Number(row.batch_id),
    totalItems: Number(row.total_items ?? 0),
    pendingItems: Number(row.pending_items ?? 0),
    suggestedItems: Number(row.suggested_items ?? 0),
    approvedItems: Number(row.approved_items ?? 0),
    conflictItems: Number(row.conflict_items ?? 0),
    acquisitionRecords: Number(row.acquisition_records ?? 0),
    valorMateriaPrima: Number(row.valor_materia_prima ?? 0),
    frete: Number(row.frete ?? 0),
    difalIcms: Number(row.difal_icms ?? 0),
    outrasDespesas: Number(row.outras_despesas ?? 0),
    custoAquisicaoTotal: Number(row.custo_aquisicao_total ?? 0)
  };
}

function mapMapping(row: Record<string, unknown>): HistoricalMpMapping {
  return {
    stagingItemId: Number(row.staging_item_id),
    batchId: Number(row.batch_id),
    sourceRowId: Number(row.source_row_id),
    codigoLegado: nullableString(row.codigo_legado),
    nomeLegado: nullableString(row.nome_legado),
    unidadeOrigem: nullableString(row.unidade_origem),
    mappingStatus: String(row.mapping_status),
    materiaPrimaId: nullableNumber(row.materia_prima_id),
    materiaPrimaSku: nullableString(row.materia_prima_sku),
    materiaPrimaNome: nullableString(row.materia_prima_nome),
    matchMethod: String(row.match_method),
    confidence: nullableNumber(row.confidence),
    matchCount: Number(row.match_count ?? 0)
  };
}

function mapPrice(row: Record<string, unknown>): HistoricalMpPrice {
  return {
    acquisitionValueId: Number(row.acquisition_value_id),
    materiaPrimaId: Number(row.materia_prima_id),
    sku: String(row.sku_corrigido),
    materiaPrimaNome: String(row.materia_prima_nome),
    codigoLote: String(row.codigo_lote),
    codigoLoteLegado: nullableString(row.codigo_lote_legado),
    dataDocumento: nullableString(row.data_documento),
    documentoRef: nullableString(row.documento_ref),
    ufEmitente: nullableString(row.uf_emitente),
    quantidadeOrigem: Number(row.quantidade_origem),
    unidadeOrigem: String(row.unidade_origem),
    quantidadeBase: Number(row.quantidade_base),
    valorMateriaPrima: Number(row.valor_materia_prima),
    frete: Number(row.frete),
    difalIcms: Number(row.difal_icms),
    outrasDespesas: Number(row.outras_despesas),
    custoAquisicaoTotal: Number(row.custo_aquisicao_total),
    custoUnitarioBase: Number(row.custo_unitario_base)
  };
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}
