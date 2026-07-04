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
  componentTargets: PcpLookupOption[];
  outputTargets: PcpLookupOption[];
  formulas: PcpLookupOption[];
  ops: PcpLookupOption[];
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
  status: string;
  createdAt: string;
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
  outputs: PcpOpOutput[];
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
};

export type PcpDashboard = {
  metrics: {
    formulasVersionadas: number | null;
    formulasAtivas: number | null;
    opsAbertas: number | null;
    opsEmProcesso: number | null;
    componentesPendentes: number | null;
    lotesBloqueados: number | null;
  };
  lookups: PcpLookups;
  activeFormulas: PcpActiveFormula[];
  formulaVersions: PcpFormulaVersion[];
  recentOps: PcpRecentOp[];
  availableLots: PcpAvailableLot[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_LOOKUPS: PcpLookups = {
  produtos: [],
  materiasPrimas: [],
  produtoEmbalagens: [],
  componentTargets: [],
  outputTargets: [],
  formulas: [],
  ops: []
};

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
      opOutputs,
      lotesMp,
      lotesPa,
      lotesPi
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
        .select("id,produto_id,tipo_receita,versao,justificativa,observacao,previous_hash,entry_hash,created_at")
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
        .from("pcp_op_produtos_gerados")
        .select(
          "id,op_id,tipo_produto,produto_embalagem_id,produto_id,lote_pa_id,lote_pi_id,quantidade,status_lote,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(400),
      supabase
        .from("est_lotes_mp_saldos")
        .select(
          "lote_mp_id,materia_prima_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("est_lotes_pa_saldos")
        .select(
          "lote_pa_id,produto_embalagem_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("est_lotes_pi_saldos")
        .select(
          "lote_pi_id,produto_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,origem_ref,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(300)
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
    const opOutputRows = rows(opOutputs);

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

    const reservationsByComponent = groupBy(
      opReservationRows.map((row) => mapReservation(row, lotMap)),
      (reservation) => reservation.opComponentId
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

    const recentOps = opRows.map((row) => {
      const id = Number(row.id);
      const formula = formulaById.get(Number(row.formula_versao_id));
      return {
        id,
        codigoOp: String(row.codigo_op),
        formulaVersionId: Number(row.formula_versao_id),
        formulaLabel: formula ? `${formula.produtoLabel} / ${formula.tipoReceita} v${formula.versao}` : `formula ${row.formula_versao_id}`,
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
        outputs: outputsByOp.get(id) ?? []
      } satisfies PcpRecentOp;
    });

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
      componentTargets: [
        ...materiaPrimaRows.map((row) => ({
          id: Number(row.id),
          label: `MP - ${materialLabel(row)}`,
          detail: `${row.unidade_base_estoque ?? "sem unidade"} / ${row.status ?? "sem status"}`
        })),
        ...produtoEmbalagemRows.map((row) => ({
          id: Number(row.id),
          label: `PA - ${packageLabel(row)}`,
          detail: `${row.status ?? "sem status"}`
        })),
        ...produtoRows.map((row) => ({
          id: Number(row.id),
          label: `PI - ${productLabel(row)}`,
          detail: `${row.status ?? "sem status"}`
        }))
      ],
      outputTargets: [
        ...produtoEmbalagemRows.map((row) => ({
          id: Number(row.id),
          label: `PA - ${packageLabel(row)}`,
          detail: `${row.status ?? "sem status"}`
        })),
        ...produtoRows.map((row) => ({
          id: Number(row.id),
          label: `PI - ${productLabel(row)}`,
          detail: `${row.status ?? "sem status"}`
        }))
      ],
      formulas: formulaVersions.map((formula) => ({
        id: formula.id,
        label: `${formula.produtoLabel} / ${formula.tipoReceita} v${formula.versao}`,
        detail: `${formula.isActive ? "ativa" : "versao"} / ${formula.components.length} componente(s)`
      })),
      ops: recentOps
        .filter((op) => ["draft", "planned", "in_process"].includes(op.status))
        .map((op) => ({
          id: op.id,
          label: `${op.codigoOp} - ${op.produtoLabel}`,
          detail: `${op.tipoOp} / ${op.status}`
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
      opOutputs,
      lotesMp,
      lotesPa,
      lotesPi
    ]);

    return {
      metrics: {
        formulasVersionadas: formulaVersions.length,
        formulasAtivas: active.length,
        opsAbertas: openOps.length,
        opsEmProcesso: recentOps.filter((op) => op.status === "in_process").length,
        componentesPendentes: openOps.flatMap((op) => op.components).filter((component) => component.status !== "reserved").length,
        lotesBloqueados: availableLots.filter((lot) => lot.status === "bloqueado").length
      },
      lookups,
      activeFormulas: active,
      formulaVersions,
      recentOps,
      availableLots,
      source: firstError ? "error" : "supabase",
      error: firstError
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
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

function mapReservation(row: Record<string, unknown>, lotMap: Map<string, string>): PcpOpReservation {
  const type = componentType(row.tipo_componente);
  const loteId =
    type === "MP" ? Number(row.lote_mp_id) : type === "PA" ? Number(row.lote_pa_id) : Number(row.lote_pi_id);
  return {
    id: Number(row.id),
    opComponentId: Number(row.op_componente_id),
    tipoComponente: type,
    loteId,
    loteLabel: lotMap.get(`${type}:${loteId}`) ?? `lote ${loteId}`,
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
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
    updatedAt: String(row.updated_at ?? "")
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

function emptyDashboard(source: PcpDashboard["source"], error: string | null): PcpDashboard {
  return {
    metrics: {
      formulasVersionadas: null,
      formulasAtivas: null,
      opsAbertas: null,
      opsEmProcesso: null,
      componentesPendentes: null,
      lotesBloqueados: null
    },
    lookups: EMPTY_LOOKUPS,
    activeFormulas: [],
    formulaVersions: [],
    recentOps: [],
    availableLots: [],
    source,
    error
  };
}
