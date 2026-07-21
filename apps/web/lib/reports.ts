import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type ReportCatalogItem = {
  id: number;
  codigo: string;
  modulo: string;
  nome: string;
  descricao: string;
  fontePrincipal: string;
  status: string;
  sortOrder: number;
};

export type ValidityLotRow = {
  tipoLote: string;
  loteId: number;
  codigoLote: string;
  codigoCadastro: string;
  nomeCadastro: string;
  embalagem: string | null;
  status: string;
  saldoFisico: number;
  quantidadeReservada: number;
  saldoDisponivel: number;
  dataFabricacao: string | null;
  dataValidade: string | null;
  prazoValidadeMeses: number | null;
  diasParaVencer: number | null;
  statusVencimento: string;
  origemRef: string | null;
  observacao: string | null;
};

export type ReprocessamentoRow = ValidityLotRow & {
  prioridadeReprocessamento: string;
};

export type PaStockPositionRow = {
  lotePaId: number; produtoEmbalagemId: number; codigoLote: string;
  saldoFisico: number; saldoEmpenhado: number; saldoDisponivel: number;
  litrosFisicos: number; volumesFisicos: number | null;
  litrosEmpenhados: number; volumesEmpenhados: number | null;
};

export type ReportsDashboard = {
  metrics: {
    catalogados: number | null;
    ativos: number | null;
    lotesNoRelatorio: number | null;
    vencidosComSaldo: number | null;
    vencendo30Dias: number | null;
    candidatosReprocessamento: number | null;
    candidatosAlta: number | null;
  };
  catalog: ReportCatalogItem[];
  validityRows: ValidityLotRow[];
  reprocessamentoRows: ReprocessamentoRow[];
  paStockPositionRows: PaStockPositionRow[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export async function getReportsDashboard(dataCorte = new Date().toISOString().slice(0, 10)): Promise<ReportsDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [catalog, validityRows, reprocessamentoRows, paStockPosition] = await Promise.all([
      supabase
        .from("relatorio_catalogo")
        .select("id,codigo,modulo,nome,descricao,fonte_principal,status,sort_order")
        .order("sort_order", { ascending: true })
        .limit(100),
      supabase
        .from("rel_estoque_lotes_vencimento")
        .select(
          "tipo_lote,lote_id,codigo_lote,codigo_cadastro,nome_cadastro,embalagem,status,saldo_fisico,quantidade_reservada,saldo_disponivel,data_fabricacao,data_validade,prazo_validade_meses,dias_para_vencer,status_vencimento,origem_ref,observacao"
        )
        .order("data_validade", { ascending: true })
        .limit(200),
      supabase
        .from("rel_estoque_reprocessamento_candidatos")
        .select(
          "tipo_lote,lote_id,codigo_lote,codigo_cadastro,nome_cadastro,embalagem,status,saldo_fisico,quantidade_reservada,saldo_disponivel,data_fabricacao,data_validade,dias_para_vencer,status_vencimento,prioridade_reprocessamento,origem_ref,observacao"
        )
        .order("prioridade_reprocessamento", { ascending: true })
        .limit(80),
      supabase.rpc("consultar_est_estoque_pa_posicao", { p_data_corte: dataCorte })
    ]);

    const mappedCatalog = catalog.error ? [] : ((catalog.data ?? []) as Array<Record<string, unknown>>).map(mapCatalog);
    const mappedValidityRows = validityRows.error
      ? []
      : ((validityRows.data ?? []) as Array<Record<string, unknown>>).map(mapValidityLot);
    const mappedReprocessamentoRows = reprocessamentoRows.error
      ? []
      : ((reprocessamentoRows.data ?? []) as Array<Record<string, unknown>>).map(mapReprocessamento);

    return {
      metrics: {
        catalogados: mappedCatalog.length,
        ativos: mappedCatalog.filter((item) => item.status === "ativo").length,
        lotesNoRelatorio: mappedValidityRows.length,
        vencidosComSaldo: mappedValidityRows.filter((row) => row.statusVencimento === "vencido_com_saldo").length,
        vencendo30Dias: mappedValidityRows.filter((row) => row.statusVencimento === "vence_30_dias").length,
        candidatosReprocessamento: mappedReprocessamentoRows.length,
        candidatosAlta: mappedReprocessamentoRows.filter((row) => row.prioridadeReprocessamento === "alta").length
      },
      catalog: mappedCatalog,
      validityRows: mappedValidityRows,
      reprocessamentoRows: mappedReprocessamentoRows,
      paStockPositionRows: paStockPosition.error ? [] : ((paStockPosition.data ?? []) as Array<Record<string, unknown>>).map(mapPaStockPosition),
      source: "supabase",
      error: catalog.error?.message ?? validityRows.error?.message ?? reprocessamentoRows.error?.message ?? paStockPosition.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

function mapCatalog(row: Record<string, unknown>): ReportCatalogItem {
  return {
    id: Number(row.id),
    codigo: String(row.codigo),
    modulo: String(row.modulo),
    nome: String(row.nome),
    descricao: String(row.descricao),
    fontePrincipal: String(row.fonte_principal),
    status: String(row.status),
    sortOrder: Number(row.sort_order ?? 0)
  };
}

function mapValidityLot(row: Record<string, unknown>): ValidityLotRow {
  return {
    tipoLote: String(row.tipo_lote),
    loteId: Number(row.lote_id),
    codigoLote: String(row.codigo_lote),
    codigoCadastro: String(row.codigo_cadastro),
    nomeCadastro: String(row.nome_cadastro),
    embalagem: nullableString(row.embalagem),
    status: String(row.status),
    saldoFisico: Number(row.saldo_fisico ?? 0),
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    saldoDisponivel: Number(row.saldo_disponivel ?? 0),
    dataFabricacao: nullableString(row.data_fabricacao),
    dataValidade: nullableString(row.data_validade),
    prazoValidadeMeses: nullableNumber(row.prazo_validade_meses),
    diasParaVencer: nullableNumber(row.dias_para_vencer),
    statusVencimento: String(row.status_vencimento),
    origemRef: nullableString(row.origem_ref),
    observacao: nullableString(row.observacao)
  };
}

function mapReprocessamento(row: Record<string, unknown>): ReprocessamentoRow {
  return {
    ...mapValidityLot(row),
    prioridadeReprocessamento: String(row.prioridade_reprocessamento)
  };
}

function mapPaStockPosition(row: Record<string, unknown>): PaStockPositionRow {
  return {
    lotePaId: Number(row.lote_pa_id), produtoEmbalagemId: Number(row.produto_embalagem_id), codigoLote: String(row.codigo_lote),
    saldoFisico: Number(row.saldo_fisico ?? 0), saldoEmpenhado: Number(row.saldo_empenhado ?? 0), saldoDisponivel: Number(row.saldo_disponivel ?? 0),
    litrosFisicos: Number(row.litros_fisicos ?? 0), volumesFisicos: nullableNumber(row.volumes_fisicos),
    litrosEmpenhados: Number(row.litros_empenhados ?? 0), volumesEmpenhados: nullableNumber(row.volumes_empenhados)
  };
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function emptyDashboard(source: "not_configured" | "error", error: string | null): ReportsDashboard {
  return {
    metrics: {
      catalogados: null,
      ativos: null,
      lotesNoRelatorio: null,
      vencidosComSaldo: null,
      vencendo30Dias: null,
      candidatosReprocessamento: null,
      candidatosAlta: null
    },
    catalog: [],
    validityRows: [],
    reprocessamentoRows: [],
    paStockPositionRows: [],
    source,
    error
  };
}
