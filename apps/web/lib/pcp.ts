import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type PcpComponentType = "MP" | "PA" | "PI";

export type PcpLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type PcpLookups = {
  produtos: PcpLookupOption[];
  materiasPrimas: PcpLookupOption[];
  produtoEmbalagens: PcpLookupOption[];
  pessoas: PcpLookupOption[];
  formulas: PcpLookupOption[];
  nutrientes: PcpLookupOption[];
  unidades: PcpLookupOption[];
};

export type PcpProductGuarantee = {
  id: number;
  produtoId: number;
  produtoLabel: string;
  nutriente: string;
  tipoLimite: string;
  valor: number;
  valorMaximo: number | null;
  unidade: string;
  fonte: string;
  vigenciaInicio: string | null;
  vigenciaFim: string | null;
  documentoReferencia: string | null;
  justificativa: string | null;
  createdAt: string;
};

export type PcpMpLotGuarantee = {
  id: number;
  materiaPrimaId: number;
  loteMpId: number;
  loteLabel: string;
  nutriente: string;
  valor: number;
  unidade: string;
  fonte: string;
  dataReferencia: string | null;
  documentoReferencia: string | null;
  justificativa: string | null;
  createdAt: string;
};

export type PcpMpLotParameters = {
  id: number;
  loteMpId: number;
  loteLabel: string;
  densidadeKgL: number;
  dataReferencia: string;
  fonte: string;
  documentoReferencia: string | null;
  justificativa: string;
  createdAt: string;
};

export type PcpHistoricalGuaranteeReview = {
  id: number;
  produtoLabel: string;
  descricaoOrigem: string;
  valorPpPercentualL: number | null;
  valorPvKgL: number | null;
  decisao: string;
  nutrienteLabel: string | null;
  unidadePp: string | null;
  unidadePv: string | null;
  justificativa: string | null;
  sourceBatchId: number;
  sourceRowId: number;
  linhaExcel: number | null;
};

export type PcpOpGuaranteeResult = {
  id: number;
  opId: number;
  produtoGeradoId: number;
  produtoId: number;
  produtoLabel: string;
  calculoVersao: number;
  nutriente: string;
  unidade: string;
  valorCalculado: number | null;
  tipoLimite: string | null;
  valorReferencia: number | null;
  valorMaximoReferencia: number | null;
  statusResultado: string;
  atende: boolean | null;
  justificativa: string;
  createdAt: string;
};

export type PcpFormulaComponent = {
  id: number;
  formulaVersionId: number;
  tipoComponente: PcpComponentType;
  targetId: number;
  targetLabel: string;
  quantidade: number;
  unidade: string | null;
  observacao: string | null;
};

export type PcpFormulaVersion = {
  id: number;
  produtoId: number;
  produtoLabel: string;
  tipoReceita: string;
  baseCalculo: string;
  versao: number;
  justificativa: string;
  observacao: string | null;
  previousHash: string | null;
  entryHash: string;
  createdAt: string;
  isActive: boolean;
  components: PcpFormulaComponent[];
};

export type PcpActiveFormula = {
  formulaVersionId: number;
  produtoId: number;
  produtoLabel: string;
  tipoReceita: string;
  versao: number;
  justificativa: string;
  motivoAtivacao: string;
  ativadaAt: string;
};

export type PcpOpReservation = {
  id: number;
  opComponentId: number;
  tipoComponente: PcpComponentType;
  loteId: number;
  loteLabel: string;
  quantidadeReservada: number;
  quantidadeUtilizada: number | null;
  status: string;
  createdAt: string;
};

export type PcpOpParticipant = {
  id: number;
  opId: number;
  pessoaId: number | null;
  papel: string;
  ordem: number;
  nome: string;
  registradoEm: string;
};

export type PcpOpComponent = {
  id: number;
  opId: number;
  tipoComponente: PcpComponentType;
  targetId: number;
  targetLabel: string;
  quantidadePlanejada: number;
  quantidadeReservada: number;
  unidade: string | null;
  status: string;
  reservations: PcpOpReservation[];
};

export type PcpOpOutput = {
  id: number;
  opId: number;
  tipoProduto: "PA" | "PI";
  targetLabel: string;
  loteId: number;
  loteLabel: string;
  quantidade: number;
  statusLote: string;
  createdAt: string;
};

export type PcpRecentOp = {
  id: number;
  codigoOp: string;
  formulaVersionId: number;
  formulaLabel: string;
  produtoId: number;
  produtoLabel: string;
  tipoOp: string;
  status: string;
  quantidadePlanejada: number | null;
  observacao: string | null;
  cqStatus: string | null;
  createdAt: string;
  startedAt: string | null;
  completedAt: string | null;
  components: PcpOpComponent[];
  participants: PcpOpParticipant[];
  outputs: PcpOpOutput[];
  guaranteeResults: PcpOpGuaranteeResult[];
};

export type PcpAvailableLot = {
  id: number;
  tipo: PcpComponentType;
  targetId: number;
  targetLabel: string;
  codigoLote: string;
  status: string;
  saldoFisico: number;
  quantidadeReservada: number;
  saldoDisponivel: number;
  dataValidade: string | null;
  origemRef: string | null;
  updatedAt: string;
  entryAt: string;
};

export type PcpDashboard = {
  metrics: {
    formulasVersionadas: number | null;
    formulasAtivas: number | null;
    opsAbertas: number | null;
    opsEmProcesso: number | null;
    componentesPendentes: number | null;
    lotesBloqueados: number | null;
    garantiasVigentes: number | null;
    transformacoesAbertas: number | null;
  };
  lookups: PcpLookups;
  activeFormulas: PcpActiveFormula[];
  formulaVersions: PcpFormulaVersion[];
  recentOps: PcpRecentOp[];
  availableLots: PcpAvailableLot[];
  productGuarantees: PcpProductGuarantee[];
  mpLotGuarantees: PcpMpLotGuarantee[];
  mpLotParameters: PcpMpLotParameters[];
  historicalGuarantees: PcpHistoricalGuaranteeReview[];
  opGuaranteeResults: PcpOpGuaranteeResult[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export type PcpSupervisorDashboard = {
  metrics: {
    opsAguardando: number | null;
    opsEmProducao: number | null;
    componentesSemReserva: number | null;
    lotesBloqueados: number | null;
  };
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export type PcpOrderCapabilities = {
  canCreate: boolean;
  canReserve: boolean;
  canOverrideFifo: boolean;
  canStart: boolean;
  canCancel: boolean;
};

const EMPTY_LOOKUPS: PcpLookups = {
  produtos: [],
  materiasPrimas: [],
  produtoEmbalagens: [],
  pessoas: [],
  formulas: [],
  nutrientes: [],
  unidades: []
};

const PCP_ORDER_PERMISSION_KEYS = {
  canCreate: "pcp.op.create",
  canReserve: "pcp.op.reserve_components",
  canOverrideFifo: "pcp.op.reserve_override_fifo",
  canStart: "pcp.op.start",
  canCancel: "pcp.op.cancel"
} as const;

const EMPTY_ORDER_CAPABILITIES: PcpOrderCapabilities = {
  canCreate: false,
  canReserve: false,
  canOverrideFifo: false,
  canStart: false,
  canCancel: false
};

export async function getPcpOrderCapabilities(): Promise<PcpOrderCapabilities> {
  if (!getRuntimeStatus().supabaseConfigured) return EMPTY_ORDER_CAPABILITIES;

  try {
    const supabase = await createSupabaseServerClient();
    const entries = await Promise.all(
      Object.entries(PCP_ORDER_PERMISSION_KEYS).map(async ([capability, actionKey]) => {
        const { data, error } = await supabase.rpc("can_current_user", {
          p_action_key: actionKey
        });
        return [capability, !error && data === true] as const;
      })
    );
    return Object.fromEntries(entries) as PcpOrderCapabilities;
  } catch {
    return EMPTY_ORDER_CAPABILITIES;
  }
}

export async function canCurrentUserViewPcpDashboard(): Promise<boolean> {
  if (!getRuntimeStatus().supabaseConfigured) return false;

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("can_current_user", {
      p_action_key: "pcp.dashboard.view"
    });
    return !error && data === true;
  } catch {
    return false;
  }
}

export async function getPcpSupervisorDashboard(): Promise<PcpSupervisorDashboard> {
  if (!getRuntimeStatus().supabaseConfigured) {
    return emptySupervisorDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("get_pcp_supervisor_dashboard");
    if (error) return emptySupervisorDashboard("error", error.message);

    const row = data && typeof data === "object"
      ? data as Record<string, unknown>
      : {};

    return {
      metrics: {
        opsAguardando: nullableNumber(row.ops_aguardando),
        opsEmProducao: nullableNumber(row.ops_em_producao),
        componentesSemReserva: nullableNumber(row.componentes_sem_reserva),
        lotesBloqueados: nullableNumber(row.lotes_bloqueados)
      },
      source: "supabase",
      error: null
    };
  } catch (error) {
    return emptySupervisorDashboard(
      "error",
      error instanceof Error ? error.message : "Não foi possível carregar o painel supervisor."
    );
  }
}

export async function getPcpDashboard(): Promise<PcpDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [
      produtos,
      materiasPrimas,
      produtoEmbalagens,
      formulas,
      activeFormulas,
      formulaItems,
      ops,
      opComponents,
      opReservations,
      opConsumptions,
      opParticipants,
      opOutputs,
      lotesMp,
      lotesPa,
      lotesPi,
      pessoas,
      nutrientes,
      unidades,
      productGuarantees,
      mpLotGuarantees,
      mpLotParameters,
      historicalGuarantees,
      opGuaranteeResults
    ] = await Promise.all([
      supabase
        .from("cad_produtos_base")
        .select("id,codigo_produto,nome,status,prazo_validade_meses")
        .order("codigo_produto", { ascending: true })
        .limit(300),
      supabase
        .from("cad_materias_primas")
        .select("id,sku_corrigido,nome,unidade_base_estoque,status")
        .order("nome", { ascending: true })
        .limit(400),
      supabase
        .from("cad_produto_embalagens")
        .select(
          "id,codigo_item,status,produto_id,embalagem_id,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros,unidade)"
        )
        .order("codigo_item", { ascending: true })
        .limit(400),
      supabase
        .from("pcp_formula_versoes")
        .select("id,produto_id,tipo_receita,versao,base_calculo,justificativa,observacao,previous_hash,entry_hash,created_at")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("pcp_formula_ativa")
        .select("formula_versao_id,produto_id,tipo_receita,versao,justificativa,motivo_ativacao,ativada_at")
        .order("ativada_at", { ascending: false })
        .limit(120),
      supabase
        .from("pcp_formula_itens")
        .select(
          "id,formula_versao_id,tipo_componente,materia_prima_id,produto_embalagem_id,produto_id,quantidade,unidade,observacao"
        )
        .order("created_at", { ascending: false })
        .limit(800),
      supabase
        .from("pcp_ordens_producao")
        .select(
          "id,codigo_op,formula_versao_id,tipo_op,status,quantidade_planejada,observacao,cq_status,created_at,started_at,completed_at"
        )
        .order("created_at", { ascending: false })
        .limit(60),
      supabase
        .from("pcp_op_componentes_planejados")
        .select(
          "id,op_id,tipo_componente,materia_prima_id,produto_embalagem_id,produto_id,quantidade_planejada,unidade,status"
        )
        .order("created_at", { ascending: false })
        .limit(900),
      supabase
        .from("pcp_op_reservas_componentes")
        .select(
          "id,op_id,op_componente_id,tipo_componente,lote_mp_id,lote_pa_id,lote_pi_id,quantidade_reservada,status,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(900),
      supabase
        .from("pcp_op_consumos")
        .select("id,op_id,op_componente_id,reserva_id,quantidade_consumida,created_at")
        .order("created_at", { ascending: false })
        .limit(900),
      supabase
        .from("pcp_op_cq_participantes")
        .select("id,op_id,papel,ordem,nome_snapshot,pessoa_comercial_id,created_at")
        .order("created_at", { ascending: false })
        .limit(500),
      supabase
        .from("pcp_op_produtos_gerados")
        .select(
          "id,op_id,tipo_produto,produto_embalagem_id,produto_id,lote_pa_id,lote_pi_id,quantidade,status_lote,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(400),
      supabase
        .from("est_lotes_mp_saldos")
        .select(
          "lote_mp_id,materia_prima_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("est_lotes_pa_saldos")
        .select(
          "lote_pa_id,produto_embalagem_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("est_lotes_pi_saldos")
        .select(
          "lote_pi_id,produto_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .eq("status", "active")
        .order("nome", { ascending: true })
        .limit(300),
      supabase
        .from("cad_nutrientes")
        .select("id,nome,simbolo,status")
        .eq("status", "active")
        .order("nome", { ascending: true })
        .limit(300),
      supabase
        .from("cad_unidades_medida")
        .select("id,codigo,nome,simbolo,status")
        .eq("status", "active")
        .order("codigo", { ascending: true })
        .limit(300),
      supabase
        .from("cad_garantias_produto_mapa_atuais")
        .select(
          "id,produto_id,nutriente,tipo_limite,valor,valor_maximo,unidade,fonte,vigencia_inicio,vigencia_fim,documento_referencia,justificativa,created_at"
        )
        .order("produto_id", { ascending: true })
        .order("nutriente", { ascending: true })
        .limit(500),
      supabase
        .from("cad_garantias_lote_mp_atuais")
        .select(
          "id,materia_prima_id,lote_mp_id,nutriente,valor,unidade,fonte,data_referencia,documento_referencia,justificativa,created_at"
        )
        .order("data_referencia", { ascending: false })
        .limit(800),
      supabase
        .from("cad_lote_mp_parametros_tecnicos_atuais")
        .select("id,lote_mp_id,densidade_kg_l,data_referencia,fonte,documento_referencia,justificativa,created_at")
        .order("data_referencia", { ascending: false })
        .limit(800),
      supabase
        .from("pcp_garantias_historicas_conciliacao_atual")
        .select(
          "id,produto_id,codigo_produto,produto_nome,descricao_origem,valor_pp_percentual_l,valor_pv_kg_l,decisao,nutriente_nome,nutriente_simbolo,unidade_pp_codigo,unidade_pv_codigo,justificativa,source_batch_id,source_row_id,linha_excel"
        )
        .order("id", { ascending: false })
        .limit(500),
      supabase
        .from("pcp_op_garantia_resultados_atuais")
        .select(
          "id,op_id,produto_gerado_id,produto_id,calculo_versao,nutriente,unidade,valor_calculado,tipo_limite,valor_referencia,valor_maximo_referencia,status_resultado,atende,justificativa,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(800)
    ]);

    const produtoRows = rows(produtos);
    const materiaPrimaRows = rows(materiasPrimas);
    const produtoEmbalagemRows = rows(produtoEmbalagens);
    const formulaRows = rows(formulas);
    const activeFormulaRows = rows(activeFormulas);
    const formulaItemRows = rows(formulaItems);
    const opRows = rows(ops);
    const opComponentRows = rows(opComponents);
    const opReservationRows = rows(opReservations);
    const opConsumptionRows = rows(opConsumptions);
    const opParticipantRows = rows(opParticipants);
    const opOutputRows = rows(opOutputs);
    const personRows = rows(pessoas);
    const nutrientRows = rows(nutrientes);
    const unitRows = rows(unidades);
    const productGuaranteeRows = rows(productGuarantees);
    const mpLotGuaranteeRows = rows(mpLotGuarantees);
    const mpLotParameterRows = rows(mpLotParameters);
    const historicalGuaranteeRows = rows(historicalGuarantees);
    const opGuaranteeResultRows = rows(opGuaranteeResults);

    const produtoMap = new Map<number, string>(
      produtoRows.map((row) => [Number(row.id), productLabel(row)])
    );
    const materiaPrimaMap = new Map<number, string>(
      materiaPrimaRows.map((row) => [Number(row.id), materialLabel(row)])
    );
    const produtoEmbalagemMap = new Map<number, string>(
      produtoEmbalagemRows.map((row) => [Number(row.id), packageLabel(row)])
    );
    const formulaActiveIds = new Set(activeFormulaRows.map((row) => Number(row.formula_versao_id)));
    const lotMap = new Map<string, string>();
    const availableLots = [
      ...rows(lotesMp).map((row) => mapLot(row, "MP", Number(row.lote_mp_id), Number(row.materia_prima_id), materiaPrimaMap)),
      ...rows(lotesPa).map((row) =>
        mapLot(row, "PA", Number(row.lote_pa_id), Number(row.produto_embalagem_id), produtoEmbalagemMap)
      ),
      ...rows(lotesPi).map((row) => mapLot(row, "PI", Number(row.lote_pi_id), Number(row.produto_id), produtoMap))
    ].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

    for (const lot of availableLots) {
      lotMap.set(`${lot.tipo}:${lot.id}`, `${lot.codigoLote} - ${lot.targetLabel}`);
    }

    const formulaComponentsByVersion = groupBy(
      formulaItemRows.map((row) => mapFormulaComponent(row, materiaPrimaMap, produtoEmbalagemMap, produtoMap)),
      (component) => component.formulaVersionId
    );

    const formulaVersions = formulaRows.map((row) => {
      const id = Number(row.id);
      const produtoId = Number(row.produto_id);
      return {
        id,
        produtoId,
        produtoLabel: produtoMap.get(produtoId) ?? `produto ${produtoId}`,
        tipoReceita: String(row.tipo_receita),
        baseCalculo: String(row.base_calculo),
        versao: Number(row.versao),
        justificativa: String(row.justificativa),
        observacao: nullableString(row.observacao),
        previousHash: nullableString(row.previous_hash),
        entryHash: String(row.entry_hash),
        createdAt: String(row.created_at),
        isActive: formulaActiveIds.has(id),
        components: formulaComponentsByVersion.get(id) ?? []
      } satisfies PcpFormulaVersion;
    });

    const formulaById = new Map<number, PcpFormulaVersion>(formulaVersions.map((formula) => [formula.id, formula]));
    const active = activeFormulaRows.map((row) => {
      const produtoId = Number(row.produto_id);
      return {
        formulaVersionId: Number(row.formula_versao_id),
        produtoId,
        produtoLabel: produtoMap.get(produtoId) ?? `produto ${produtoId}`,
        tipoReceita: String(row.tipo_receita),
        versao: Number(row.versao),
        justificativa: String(row.justificativa),
        motivoAtivacao: String(row.motivo_ativacao),
        ativadaAt: String(row.ativada_at)
      } satisfies PcpActiveFormula;
    });

    const consumedByReservation = new Map<number, number>(
      opConsumptionRows.map((row) => [Number(row.reserva_id), Number(row.quantidade_consumida ?? 0)])
    );
    const reservationsByComponent = groupBy(
      opReservationRows.map((row) => mapReservation(row, lotMap, consumedByReservation)),
      (reservation) => reservation.opComponentId
    );
    const participantsByOp = groupBy(
      opParticipantRows.map((row) => ({
        id: Number(row.id),
        opId: Number(row.op_id),
        pessoaId: nullableNumber(row.pessoa_comercial_id),
        papel: String(row.papel),
        ordem: Number(row.ordem),
        nome: String(row.nome_snapshot),
        registradoEm: String(row.created_at)
      } satisfies PcpOpParticipant)),
      (participant) => participant.opId
    );

    const componentsByOp = groupBy(
      opComponentRows.map((row) => {
        const component = mapOpComponent(row, reservationsByComponent, materiaPrimaMap, produtoEmbalagemMap, produtoMap);
        return component;
      }),
      (component) => component.opId
    );

    const outputsByOp = groupBy(
      opOutputRows.map((row) => mapOutput(row, lotMap, produtoEmbalagemMap, produtoMap)),
      (output) => output.opId
    );

    const guaranteeResultsByOp = groupBy(
      opGuaranteeResultRows.map((row) => mapOpGuaranteeResult(row, produtoMap)),
      (result) => result.opId
    );

    const recentOps = opRows.map((row) => {
      const id = Number(row.id);
      const formula = formulaById.get(Number(row.formula_versao_id));
      return {
        id,
        codigoOp: String(row.codigo_op),
        formulaVersionId: Number(row.formula_versao_id),
        formulaLabel: formula ? `${formula.produtoLabel} / ${formula.tipoReceita} v${formula.versao}` : `formula ${row.formula_versao_id}`,
        produtoId: formula?.produtoId ?? 0,
        produtoLabel: formula?.produtoLabel ?? "produto nao carregado",
        tipoOp: String(row.tipo_op),
        status: String(row.status),
        quantidadePlanejada: nullableNumber(row.quantidade_planejada),
        observacao: nullableString(row.observacao),
        cqStatus: nullableString(row.cq_status),
        createdAt: String(row.created_at),
        startedAt: nullableString(row.started_at),
        completedAt: nullableString(row.completed_at),
        components: componentsByOp.get(id) ?? [],
        participants: participantsByOp.get(id) ?? [],
        outputs: outputsByOp.get(id) ?? [],
        guaranteeResults: guaranteeResultsByOp.get(id) ?? []
      } satisfies PcpRecentOp;
    });

    const currentProductGuarantees = productGuaranteeRows.map((row) => mapProductGuarantee(row, produtoMap));
    const currentMpLotGuarantees = mpLotGuaranteeRows.map((row) => mapMpLotGuarantee(row, lotMap));
    const currentMpLotParameters = mpLotParameterRows.map((row) => mapMpLotParameters(row, lotMap));

    const lookups: PcpLookups = {
      produtos: produtoRows.map((row) => ({
        id: Number(row.id),
        label: productLabel(row),
        detail: `status ${row.status ?? "sem status"} / validade ${row.prazo_validade_meses ?? "sem prazo"} mes(es)`
      })),
      materiasPrimas: materiaPrimaRows.map((row) => ({
        id: Number(row.id),
        label: materialLabel(row),
        detail: `${row.unidade_base_estoque ?? "sem unidade"} / ${row.status ?? "sem status"}`
      })),
      produtoEmbalagens: produtoEmbalagemRows.map((row) => ({
        id: Number(row.id),
        label: packageLabel(row),
        detail: `${row.status ?? "sem status"}`
      })),
      pessoas: personRows.map((row) => ({
        id: Number(row.id),
        label: String(row.nome),
        detail: `${row.tipo_comercial ?? "sem tipo"}`
      })),
      formulas: formulaVersions.map((formula) => ({
        id: formula.id,
        label: `${formula.produtoLabel} / ${formula.tipoReceita} v${formula.versao}`,
        detail: `${formula.isActive ? "ativa" : "versao"} / ${formula.components.length} componente(s)`
      })),
      nutrientes: nutrientRows.map((row) => ({
        id: Number(row.id),
        label: String(row.simbolo ?? row.nome),
        detail: String(row.nome)
      })),
      unidades: unitRows.map((row) => ({
        id: Number(row.id),
        label: String(row.codigo),
        detail: String(row.nome)
      }))
    };

    const openOps = recentOps.filter((op) => ["draft", "planned", "in_process"].includes(op.status));
    const firstError = firstResponseError([
      produtos,
      materiasPrimas,
      produtoEmbalagens,
      formulas,
      activeFormulas,
      formulaItems,
      ops,
      opComponents,
      opReservations,
      opConsumptions,
      opParticipants,
      opOutputs,
      lotesMp,
      lotesPa,
      lotesPi,
      pessoas,
      nutrientes,
      unidades,
      productGuarantees,
      mpLotGuarantees,
      mpLotParameters,
      historicalGuarantees,
      opGuaranteeResults
    ]);

    return {
      metrics: {
        formulasVersionadas: formulaVersions.length,
        formulasAtivas: active.length,
        opsAbertas: openOps.length,
        opsEmProcesso: recentOps.filter((op) => op.status === "in_process").length,
        componentesPendentes: openOps.flatMap((op) => op.components).filter((component) => component.status !== "reserved").length,
        lotesBloqueados: availableLots.filter((lot) => lot.status === "bloqueado").length,
        garantiasVigentes: currentProductGuarantees.length + currentMpLotGuarantees.length,
        transformacoesAbertas: openOps.filter((op) => op.tipoOp === "reprocessamento").length
      },
      lookups,
      activeFormulas: active,
      formulaVersions,
      recentOps,
      availableLots,
      productGuarantees: currentProductGuarantees,
      mpLotGuarantees: currentMpLotGuarantees,
      mpLotParameters: currentMpLotParameters,
      historicalGuarantees: historicalGuaranteeRows.map((row) => ({
        id: Number(row.id),
        produtoLabel: `${row.codigo_produto} - ${row.produto_nome}`,
        descricaoOrigem: String(row.descricao_origem),
        valorPpPercentualL: nullableNumber(row.valor_pp_percentual_l),
        valorPvKgL: nullableNumber(row.valor_pv_kg_l),
        decisao: String(row.decisao),
        nutrienteLabel: row.nutriente_id === null || row.nutriente_id === undefined
          ? null
          : String(row.nutriente_simbolo ?? row.nutriente_nome),
        unidadePp: nullableString(row.unidade_pp_codigo),
        unidadePv: nullableString(row.unidade_pv_codigo),
        justificativa: nullableString(row.justificativa),
        sourceBatchId: Number(row.source_batch_id),
        sourceRowId: Number(row.source_row_id),
        linhaExcel: nullableNumber(row.linha_excel)
      })),
      opGuaranteeResults: opGuaranteeResultRows.map((row) => mapOpGuaranteeResult(row, produtoMap)),
      source: firstError ? "error" : "supabase",
      error: firstError
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

export async function getPcpOrderPrintData(orderId: number): Promise<PcpRecentOp | null> {
  if (!Number.isInteger(orderId) || orderId <= 0 || !getRuntimeStatus().supabaseConfigured) {
    return null;
  }

  try {
    const supabase = await createSupabaseServerClient();
    const orderResponse = await supabase
      .from("pcp_ordens_producao")
      .select(
        "id,codigo_op,formula_versao_id,tipo_op,status,quantidade_planejada,observacao,cq_status,created_at,started_at,completed_at"
      )
      .eq("id", orderId)
      .limit(1);
    const order = rows(orderResponse)[0];
    if (orderResponse.error || !order) return null;

    const formulaVersionId = Number(order.formula_versao_id);
    const [formulaResponse, componentResponse, reservationResponse, consumptionResponse, participantResponse] =
      await Promise.all([
        supabase
          .from("pcp_formula_versoes")
          .select("id,produto_id,tipo_receita,versao")
          .eq("id", formulaVersionId)
          .limit(1),
        supabase
          .from("pcp_op_componentes_planejados")
          .select(
            "id,op_id,tipo_componente,materia_prima_id,produto_embalagem_id,produto_id,quantidade_planejada,unidade,status"
          )
          .eq("op_id", orderId)
          .order("id", { ascending: true }),
        supabase
          .from("pcp_op_reservas_componentes")
          .select(
            "id,op_id,op_componente_id,tipo_componente,lote_mp_id,lote_pa_id,lote_pi_id,quantidade_reservada,status,created_at"
          )
          .eq("op_id", orderId)
          .order("created_at", { ascending: true }),
        supabase
          .from("pcp_op_consumos")
          .select("id,op_id,op_componente_id,reserva_id,quantidade_consumida,created_at")
          .eq("op_id", orderId),
        supabase
          .from("pcp_op_cq_participantes")
          .select("id,op_id,papel,ordem,nome_snapshot,pessoa_comercial_id,created_at")
          .eq("op_id", orderId)
          .order("papel", { ascending: true })
          .order("ordem", { ascending: true })
      ]);
    if (firstResponseError([
      formulaResponse,
      componentResponse,
      reservationResponse,
      consumptionResponse,
      participantResponse
    ])) return null;

    const formula = rows(formulaResponse)[0];
    if (!formula) return null;

    const componentRows = rows(componentResponse);
    const reservationRows = rows(reservationResponse);
    const materiaPrimaIds = uniqueNumbers(componentRows.map((row) => row.materia_prima_id));
    const produtoEmbalagemIds = uniqueNumbers(componentRows.map((row) => row.produto_embalagem_id));
    const produtoIds = uniqueNumbers([formula.produto_id, ...componentRows.map((row) => row.produto_id)]);
    const loteMpIds = uniqueNumbers(reservationRows.map((row) => row.lote_mp_id));
    const lotePaIds = uniqueNumbers(reservationRows.map((row) => row.lote_pa_id));
    const lotePiIds = uniqueNumbers(reservationRows.map((row) => row.lote_pi_id));

    const [produtoResponse, materiaPrimaResponse, produtoEmbalagemResponse, loteMpResponse, lotePaResponse, lotePiResponse] =
      await Promise.all([
        supabase
          .from("cad_produtos_base")
          .select("id,codigo_produto,nome")
          .in("id", produtoIds.length > 0 ? produtoIds : [-1]),
        supabase
          .from("cad_materias_primas")
          .select("id,sku_corrigido,nome")
          .in("id", materiaPrimaIds.length > 0 ? materiaPrimaIds : [-1]),
        supabase
          .from("cad_produto_embalagens")
          .select("id,codigo_item,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros,unidade)")
          .in("id", produtoEmbalagemIds.length > 0 ? produtoEmbalagemIds : [-1]),
        supabase
          .from("est_lotes_mp_saldos")
          .select(
            "lote_mp_id,materia_prima_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
          )
          .in("lote_mp_id", loteMpIds.length > 0 ? loteMpIds : [-1]),
        supabase
          .from("est_lotes_pa_saldos")
          .select(
            "lote_pa_id,produto_embalagem_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
          )
          .in("lote_pa_id", lotePaIds.length > 0 ? lotePaIds : [-1]),
        supabase
          .from("est_lotes_pi_saldos")
          .select(
            "lote_pi_id,produto_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,created_at,updated_at"
          )
          .in("lote_pi_id", lotePiIds.length > 0 ? lotePiIds : [-1])
      ]);
    if (firstResponseError([
      produtoResponse,
      materiaPrimaResponse,
      produtoEmbalagemResponse,
      loteMpResponse,
      lotePaResponse,
      lotePiResponse
    ])) return null;

    const produtoMap = new Map<number, string>(
      rows(produtoResponse).map((row) => [Number(row.id), productLabel(row)])
    );
    const materiaPrimaMap = new Map<number, string>(
      rows(materiaPrimaResponse).map((row) => [Number(row.id), materialLabel(row)])
    );
    const produtoEmbalagemMap = new Map<number, string>(
      rows(produtoEmbalagemResponse).map((row) => [Number(row.id), packageLabel(row)])
    );
    const lotMap = new Map<string, string>();
    for (const row of rows(loteMpResponse)) {
      lotMap.set(`MP:${Number(row.lote_mp_id)}`, `${row.codigo_lote} - ${materiaPrimaMap.get(Number(row.materia_prima_id)) ?? "Matéria-prima"}`);
    }
    for (const row of rows(lotePaResponse)) {
      lotMap.set(`PA:${Number(row.lote_pa_id)}`, `${row.codigo_lote} - ${produtoEmbalagemMap.get(Number(row.produto_embalagem_id)) ?? "Produto acabado"}`);
    }
    for (const row of rows(lotePiResponse)) {
      lotMap.set(`PI:${Number(row.lote_pi_id)}`, `${row.codigo_lote} - ${produtoMap.get(Number(row.produto_id)) ?? "Produto intermediário"}`);
    }

    const consumedByReservation = new Map<number, number>(
      rows(consumptionResponse).map((row) => [Number(row.reserva_id), Number(row.quantidade_consumida ?? 0)])
    );
    const reservationsByComponent = groupBy(
      reservationRows.map((row) => mapReservation(row, lotMap, consumedByReservation)),
      (reservation) => reservation.opComponentId
    );
    const components = componentRows.map((row) =>
      mapOpComponent(row, reservationsByComponent, materiaPrimaMap, produtoEmbalagemMap, produtoMap)
    );
    const participants = rows(participantResponse).map((row) => ({
      id: Number(row.id),
      opId: Number(row.op_id),
      pessoaId: nullableNumber(row.pessoa_comercial_id),
      papel: String(row.papel),
      ordem: Number(row.ordem),
      nome: String(row.nome_snapshot),
      registradoEm: String(row.created_at)
    } satisfies PcpOpParticipant));
    const produtoId = Number(formula.produto_id);
    const produtoLabelValue = produtoMap.get(produtoId) ?? "Produto não carregado";

    return {
      id: Number(order.id),
      codigoOp: String(order.codigo_op),
      formulaVersionId,
      formulaLabel: `${produtoLabelValue} / ${String(formula.tipo_receita)} v${Number(formula.versao)}`,
      produtoId,
      produtoLabel: produtoLabelValue,
      tipoOp: String(order.tipo_op),
      status: String(order.status),
      quantidadePlanejada: nullableNumber(order.quantidade_planejada),
      observacao: nullableString(order.observacao),
      cqStatus: nullableString(order.cq_status),
      createdAt: String(order.created_at),
      startedAt: nullableString(order.started_at),
      completedAt: nullableString(order.completed_at),
      components,
      participants,
      outputs: [],
      guaranteeResults: []
    };
  } catch {
    return null;
  }
}

function mapProductGuarantee(
  row: Record<string, unknown>,
  produtoMap: Map<number, string>
): PcpProductGuarantee {
  const produtoId = Number(row.produto_id);
  return {
    id: Number(row.id),
    produtoId,
    produtoLabel: produtoMap.get(produtoId) ?? `produto ${produtoId}`,
    nutriente: String(row.nutriente),
    tipoLimite: String(row.tipo_limite),
    valor: Number(row.valor),
    valorMaximo: nullableNumber(row.valor_maximo),
    unidade: String(row.unidade),
    fonte: String(row.fonte),
    vigenciaInicio: nullableString(row.vigencia_inicio),
    vigenciaFim: nullableString(row.vigencia_fim),
    documentoReferencia: nullableString(row.documento_referencia),
    justificativa: nullableString(row.justificativa),
    createdAt: String(row.created_at)
  };
}

function mapMpLotGuarantee(row: Record<string, unknown>, lotMap: Map<string, string>): PcpMpLotGuarantee {
  const loteMpId = Number(row.lote_mp_id);
  return {
    id: Number(row.id),
    materiaPrimaId: Number(row.materia_prima_id),
    loteMpId,
    loteLabel: lotMap.get(`MP:${loteMpId}`) ?? `lote MP ${loteMpId}`,
    nutriente: String(row.nutriente),
    valor: Number(row.valor),
    unidade: String(row.unidade),
    fonte: String(row.fonte),
    dataReferencia: nullableString(row.data_referencia),
    documentoReferencia: nullableString(row.documento_referencia),
    justificativa: nullableString(row.justificativa),
    createdAt: String(row.created_at)
  };
}

function mapMpLotParameters(row: Record<string, unknown>, lotMap: Map<string, string>): PcpMpLotParameters {
  const loteMpId = Number(row.lote_mp_id);
  return {
    id: Number(row.id),
    loteMpId,
    loteLabel: lotMap.get(`MP:${loteMpId}`) ?? `lote MP ${loteMpId}`,
    densidadeKgL: Number(row.densidade_kg_l),
    dataReferencia: String(row.data_referencia),
    fonte: String(row.fonte),
    documentoReferencia: nullableString(row.documento_referencia),
    justificativa: String(row.justificativa),
    createdAt: String(row.created_at)
  };
}

function mapOpGuaranteeResult(
  row: Record<string, unknown>,
  produtoMap: Map<number, string>
): PcpOpGuaranteeResult {
  const produtoId = Number(row.produto_id);
  return {
    id: Number(row.id),
    opId: Number(row.op_id),
    produtoGeradoId: Number(row.produto_gerado_id),
    produtoId,
    produtoLabel: produtoMap.get(produtoId) ?? `produto ${produtoId}`,
    calculoVersao: Number(row.calculo_versao),
    nutriente: String(row.nutriente),
    unidade: String(row.unidade),
    valorCalculado: nullableNumber(row.valor_calculado),
    tipoLimite: nullableString(row.tipo_limite),
    valorReferencia: nullableNumber(row.valor_referencia),
    valorMaximoReferencia: nullableNumber(row.valor_maximo_referencia),
    statusResultado: String(row.status_resultado),
    atende: row.atende === null || row.atende === undefined ? null : Boolean(row.atende),
    justificativa: String(row.justificativa),
    createdAt: String(row.created_at)
  };
}

function mapFormulaComponent(
  row: Record<string, unknown>,
  materiaPrimaMap: Map<number, string>,
  produtoEmbalagemMap: Map<number, string>,
  produtoMap: Map<number, string>
): PcpFormulaComponent {
  const type = componentType(row.tipo_componente);
  const targetId = targetIdFor(type, row);
  return {
    id: Number(row.id),
    formulaVersionId: Number(row.formula_versao_id),
    tipoComponente: type,
    targetId,
    targetLabel: targetLabelFor(type, targetId, materiaPrimaMap, produtoEmbalagemMap, produtoMap),
    quantidade: Number(row.quantidade ?? 0),
    unidade: nullableString(row.unidade),
    observacao: nullableString(row.observacao)
  };
}

function mapOpComponent(
  row: Record<string, unknown>,
  reservationsByComponent: Map<number, PcpOpReservation[]>,
  materiaPrimaMap: Map<number, string>,
  produtoEmbalagemMap: Map<number, string>,
  produtoMap: Map<number, string>
): PcpOpComponent {
  const type = componentType(row.tipo_componente);
  const targetId = targetIdFor(type, row);
  const reservations = reservationsByComponent.get(Number(row.id)) ?? [];
  return {
    id: Number(row.id),
    opId: Number(row.op_id),
    tipoComponente: type,
    targetId,
    targetLabel: targetLabelFor(type, targetId, materiaPrimaMap, produtoEmbalagemMap, produtoMap),
    quantidadePlanejada: Number(row.quantidade_planejada ?? 0),
    quantidadeReservada: reservations
      .filter((reservation) => reservation.status === "ativa")
      .reduce((sum, reservation) => sum + reservation.quantidadeReservada, 0),
    unidade: nullableString(row.unidade),
    status: String(row.status),
    reservations
  };
}

function mapReservation(
  row: Record<string, unknown>,
  lotMap: Map<string, string>,
  consumedByReservation: Map<number, number>
): PcpOpReservation {
  const type = componentType(row.tipo_componente);
  const loteId =
    type === "MP" ? Number(row.lote_mp_id) : type === "PA" ? Number(row.lote_pa_id) : Number(row.lote_pi_id);
  const id = Number(row.id);
  return {
    id,
    opComponentId: Number(row.op_componente_id),
    tipoComponente: type,
    loteId,
    loteLabel: lotMap.get(`${type}:${loteId}`) ?? `lote ${loteId}`,
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    quantidadeUtilizada: consumedByReservation.has(id) ? consumedByReservation.get(id) ?? 0 : null,
    status: String(row.status),
    createdAt: String(row.created_at)
  };
}

function mapOutput(
  row: Record<string, unknown>,
  lotMap: Map<string, string>,
  produtoEmbalagemMap: Map<number, string>,
  produtoMap: Map<number, string>
): PcpOpOutput {
  const type = String(row.tipo_produto) === "PI" ? "PI" : "PA";
  const loteId = type === "PA" ? Number(row.lote_pa_id) : Number(row.lote_pi_id);
  const targetId = type === "PA" ? Number(row.produto_embalagem_id) : Number(row.produto_id);
  return {
    id: Number(row.id),
    opId: Number(row.op_id),
    tipoProduto: type,
    targetLabel: type === "PA" ? produtoEmbalagemMap.get(targetId) ?? `item ${targetId}` : produtoMap.get(targetId) ?? `produto ${targetId}`,
    loteId,
    loteLabel: lotMap.get(`${type}:${loteId}`) ?? `lote ${loteId}`,
    quantidade: Number(row.quantidade ?? 0),
    statusLote: String(row.status_lote),
    createdAt: String(row.created_at)
  };
}

function mapLot(
  row: Record<string, unknown>,
  tipo: PcpComponentType,
  id: number,
  targetId: number,
  targetMap: Map<number, string>
): PcpAvailableLot {
  return {
    id,
    tipo,
    targetId,
    targetLabel: targetMap.get(targetId) ?? `${tipo} ${targetId}`,
    codigoLote: String(row.codigo_lote),
    status: String(row.status),
    saldoFisico: Number(row.saldo_fisico ?? 0),
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    saldoDisponivel: Number(row.saldo_disponivel ?? 0),
    dataValidade: nullableString(row.data_validade),
    origemRef: nullableString(row.origem_ref),
    updatedAt: String(row.updated_at ?? ""),
    entryAt: String(row.created_at ?? "")
  };
}

function productLabel(row: Record<string, unknown>): string {
  return `${row.codigo_produto ?? "sem codigo"} - ${row.nome ?? "sem nome"}`;
}

function materialLabel(row: Record<string, unknown>): string {
  return `${row.sku_corrigido ?? "sem SKU"} - ${row.nome ?? "sem nome"}`;
}

function packageLabel(row: Record<string, unknown>): string {
  const produto = firstNested(row.cad_produtos_base);
  const embalagem = firstNested(row.cad_embalagens);
  const produtoLabel = produto ? `${produto.codigo_produto ?? ""} ${produto.nome ?? ""}`.trim() : `produto ${row.produto_id}`;
  const embalagemLabel = embalagem ? `${embalagem.descricao ?? ""}`.trim() : `embalagem ${row.embalagem_id}`;
  return `${row.codigo_item ?? "sem item"} - ${produtoLabel} / ${embalagemLabel}`;
}

function targetIdFor(type: PcpComponentType, row: Record<string, unknown>): number {
  if (type === "MP") {
    return Number(row.materia_prima_id);
  }
  if (type === "PA") {
    return Number(row.produto_embalagem_id);
  }
  return Number(row.produto_id);
}

function targetLabelFor(
  type: PcpComponentType,
  targetId: number,
  materiaPrimaMap: Map<number, string>,
  produtoEmbalagemMap: Map<number, string>,
  produtoMap: Map<number, string>
): string {
  if (type === "MP") {
    return materiaPrimaMap.get(targetId) ?? `MP ${targetId}`;
  }
  if (type === "PA") {
    return produtoEmbalagemMap.get(targetId) ?? `PA ${targetId}`;
  }
  return produtoMap.get(targetId) ?? `PI ${targetId}`;
}

function componentType(value: unknown): PcpComponentType {
  const normalized = String(value).toUpperCase();
  if (normalized === "PA" || normalized === "PI") {
    return normalized;
  }
  return "MP";
}

function rows(response: { data: unknown[] | null; error: { message: string } | null }): Array<Record<string, unknown>> {
  return response.error ? [] : ((response.data ?? []) as Array<Record<string, unknown>>);
}

function uniqueNumbers(values: unknown[]): number[] {
  return [...new Set(
    values
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value) && value > 0)
  )];
}

function firstResponseError(responses: Array<{ error: { message: string } | null }>): string | null {
  return responses.find((response) => response.error)?.error?.message ?? null;
}

function groupBy<T, K>(items: T[], keyFor: (item: T) => K): Map<K, T[]> {
  const grouped = new Map<K, T[]>();
  for (const item of items) {
    const key = keyFor(item);
    const existing = grouped.get(key) ?? [];
    existing.push(item);
    grouped.set(key, existing);
  }
  return grouped;
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

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function emptySupervisorDashboard(
  source: PcpSupervisorDashboard["source"],
  error: string | null
): PcpSupervisorDashboard {
  return {
    metrics: {
      opsAguardando: null,
      opsEmProducao: null,
      componentesSemReserva: null,
      lotesBloqueados: null
    },
    source,
    error
  };
}

function emptyDashboard(source: PcpDashboard["source"], error: string | null): PcpDashboard {
  return {
    metrics: {
      formulasVersionadas: null,
      formulasAtivas: null,
      opsAbertas: null,
      opsEmProcesso: null,
      componentesPendentes: null,
      lotesBloqueados: null,
      garantiasVigentes: null,
      transformacoesAbertas: null
    },
    lookups: EMPTY_LOOKUPS,
    activeFormulas: [],
    formulaVersions: [],
    recentOps: [],
    availableLots: [],
    productGuarantees: [],
    mpLotGuarantees: [],
    mpLotParameters: [],
    historicalGuarantees: [],
    opGuaranteeResults: [],
    source,
    error
  };
}
