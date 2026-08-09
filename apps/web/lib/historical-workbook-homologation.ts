import type {
  HistoricalWorkbookAnalysis,
  WorkbookSourceClassificationName
} from "./historical-workbook";

export const EXPECTED_HISTORICAL_WORKBOOK_TABLES = 269;
export const WORKBOOK_HOMOLOGATION_ARTIFACT_TYPE = "elite_workbook_source_homologation";
export const WORKBOOK_HOMOLOGATION_ARTIFACT_VERSION = 1;

export const WORKBOOK_HOMOLOGATION_DECISIONS = [
  "importar_integralmente",
  "importar_apenas_metadados",
  "usar_somente_reconciliacao",
  "nao_importar",
  "adiar",
  "revisar"
] as const;

export type WorkbookHomologationDecision = (typeof WORKBOOK_HOMOLOGATION_DECISIONS)[number];
export type WorkbookHomologationStatus = "draft" | "homologated";

export const WORKBOOK_HOMOLOGATION_DECISION_LABELS: Record<WorkbookHomologationDecision, string> = {
  importar_integralmente: "Importar integralmente",
  importar_apenas_metadados: "Importar apenas metadados",
  usar_somente_reconciliacao: "Usar somente para reconciliacao",
  nao_importar: "Nao importar",
  adiar: "Adiar",
  revisar: "Revisar"
};

export type WorkbookHomologationRow = {
  sourceTableId: string;
  schemaFingerprint: string;
  sheetOrder: number;
  sheetName: string;
  tableName: string;
  range: string;
  rowCount: number;
  populatedRowCount: number;
  columnCount: number;
  mainColumns: string[];
  technicalClassification: WorkbookSourceClassificationName | null;
  ownerDomain: string | null;
  targetEntity: string | null;
  formulaCellCount: number;
  reportIndicator: boolean;
  derivedCalculationIndicator: boolean;
  duplicateRisk: "low" | "medium" | "high" | "unknown";
  technicalJustification: string;
  technicalReviewRequired: boolean;
  decision: WorkbookHomologationDecision | null;
  observation: string;
  updatedAt: string | null;
};

export type WorkbookHomologationRevisionChange = {
  revisionId: string;
  changedAt: string;
  previousDecision: WorkbookHomologationDecision | null;
  decision: WorkbookHomologationDecision | null;
  observation: string;
};

export type WorkbookHomologationArtifactEntry = WorkbookHomologationRow & {
  revisionHistory: WorkbookHomologationRevisionChange[];
};

export type WorkbookHomologationRevision = {
  revisionId: string;
  parentRevisionId: string | null;
  createdAt: string;
  status: WorkbookHomologationStatus;
  decidedTableCount: number;
};

export type WorkbookHomologationSummary = {
  total: number;
  withoutDecision: number;
  approvedForI2: number;
  excluded: number;
  pending: number;
  byDecision: Record<WorkbookHomologationDecision, number>;
};

export type WorkbookHomologationArtifact = {
  artifactType: typeof WORKBOOK_HOMOLOGATION_ARTIFACT_TYPE;
  artifactVersion: typeof WORKBOOK_HOMOLOGATION_ARTIFACT_VERSION;
  revisionId: string;
  parentRevisionId: string | null;
  createdAt: string;
  status: WorkbookHomologationStatus;
  workbook: {
    sha256: string;
    fileName: string;
    sheetCount: number;
    tableCount: number;
    technicalClassificationComplete: boolean;
    profileMatchesReference: boolean;
  };
  summary: WorkbookHomologationSummary;
  lists: {
    approvedForI2: string[];
    excluded: string[];
    pending: string[];
    metadataOnly: string[];
    reconciliationOnly: string[];
  };
  revisionTrail: WorkbookHomologationRevision[];
  entries: WorkbookHomologationArtifactEntry[];
};

type BuildArtifactOptions = {
  analysis: HistoricalWorkbookAnalysis;
  rows: WorkbookHomologationRow[];
  revisionId: string;
  createdAt: string;
  status: WorkbookHomologationStatus;
  previousArtifact?: WorkbookHomologationArtifact | null;
};

export function createWorkbookHomologationRows(
  analysis: HistoricalWorkbookAnalysis
): WorkbookHomologationRow[] {
  return analysis.sheets.flatMap((sheet) =>
    sheet.tables.map((table) => {
      const technical = table.sourceClassification;
      const classification = technical?.classification ?? null;
      return {
        sourceTableId: technical?.sourceTableId ?? `unclassified:${sheet.order}:${table.name}:${table.ref}`,
        schemaFingerprint: technical?.schemaFingerprint ?? "",
        sheetOrder: sheet.order,
        sheetName: sheet.name,
        tableName: table.name,
        range: table.ref,
        rowCount: table.rowCount,
        populatedRowCount: table.populatedRowCount,
        columnCount: table.columnCount,
        mainColumns: table.headers.slice(0, 8),
        technicalClassification: classification,
        ownerDomain: technical?.ownerDomain ?? null,
        targetEntity: technical?.targetEntity ?? null,
        formulaCellCount: table.formulaCellCount,
        reportIndicator:
          classification === "reconciliation_report" ||
          classification === "dashboard_or_summary" ||
          technical?.useForReconciliation === true,
        derivedCalculationIndicator: classification === "derived_calculation",
        duplicateRisk: technical?.duplicateRisk ?? "unknown",
        technicalJustification: technical?.justification ?? "Classificacao tecnica pendente de revisao.",
        technicalReviewRequired: technical?.reviewRequired ?? true,
        decision: null,
        observation: "",
        updatedAt: null
      };
    })
  );
}

export function summarizeWorkbookHomologation(
  rows: WorkbookHomologationRow[]
): WorkbookHomologationSummary {
  const byDecision = Object.fromEntries(
    WORKBOOK_HOMOLOGATION_DECISIONS.map((decision) => [decision, 0])
  ) as Record<WorkbookHomologationDecision, number>;

  for (const row of rows) {
    if (row.decision) byDecision[row.decision] += 1;
  }

  return {
    total: rows.length,
    withoutDecision: rows.filter((row) => row.decision === null).length,
    approvedForI2: byDecision.importar_integralmente,
    excluded: byDecision.nao_importar,
    pending:
      rows.filter((row) => row.decision === null).length +
      byDecision.adiar +
      byDecision.revisar,
    byDecision
  };
}

export function isWorkbookHomologationReady(
  analysis: HistoricalWorkbookAnalysis,
  rows: WorkbookHomologationRow[]
): boolean {
  return (
    analysis.summary.tableCount === EXPECTED_HISTORICAL_WORKBOOK_TABLES &&
    rows.length === EXPECTED_HISTORICAL_WORKBOOK_TABLES &&
    analysis.summary.sourceClassificationComplete &&
    analysis.summary.schemaDriftTableCount === 0 &&
    rows.every((row) => row.decision !== null)
  );
}

export function buildWorkbookHomologationArtifact({
  analysis,
  rows,
  revisionId,
  createdAt,
  status,
  previousArtifact = null
}: BuildArtifactOptions): WorkbookHomologationArtifact {
  if (status === "homologated" && !isWorkbookHomologationReady(analysis, rows)) {
    throw new Error("A homologacao final exige decisao explicita para as 269 tabelas e classificacao tecnica integra.");
  }

  const previousById = new Map(
    previousArtifact?.entries.map((entry) => [entry.sourceTableId, entry]) ?? []
  );
  const entries = rows.map((row) => {
    const previous = previousById.get(row.sourceTableId);
    const changed =
      !previous ||
      previous.decision !== row.decision ||
      previous.observation !== row.observation;
    const revisionHistory = [...(previous?.revisionHistory ?? [])];
    if (changed) {
      revisionHistory.push({
        revisionId,
        changedAt: createdAt,
        previousDecision: previous?.decision ?? null,
        decision: row.decision,
        observation: row.observation
      });
    }
    return { ...row, revisionHistory };
  });
  const summary = summarizeWorkbookHomologation(rows);
  const parentRevisionId = previousArtifact?.revisionId ?? null;
  const revision: WorkbookHomologationRevision = {
    revisionId,
    parentRevisionId,
    createdAt,
    status,
    decidedTableCount: rows.length - summary.withoutDecision
  };

  return {
    artifactType: WORKBOOK_HOMOLOGATION_ARTIFACT_TYPE,
    artifactVersion: WORKBOOK_HOMOLOGATION_ARTIFACT_VERSION,
    revisionId,
    parentRevisionId,
    createdAt,
    status,
    workbook: {
      sha256: analysis.file.sha256,
      fileName: analysis.file.name,
      sheetCount: analysis.summary.sheetCount,
      tableCount: analysis.summary.tableCount,
      technicalClassificationComplete: analysis.summary.sourceClassificationComplete,
      profileMatchesReference: analysis.summary.profileMatchesReference
    },
    summary,
    lists: {
      approvedForI2: sourceIdsFor(rows, (row) => row.decision === "importar_integralmente"),
      excluded: sourceIdsFor(rows, (row) => row.decision === "nao_importar"),
      pending: sourceIdsFor(rows, (row) =>
        row.decision === null || row.decision === "adiar" || row.decision === "revisar"
      ),
      metadataOnly: sourceIdsFor(rows, (row) => row.decision === "importar_apenas_metadados"),
      reconciliationOnly: sourceIdsFor(rows, (row) => row.decision === "usar_somente_reconciliacao")
    },
    revisionTrail: [...(previousArtifact?.revisionTrail ?? []), revision],
    entries
  };
}

export function validateWorkbookHomologationArtifact(
  value: unknown,
  analysis: HistoricalWorkbookAnalysis,
  currentRows: WorkbookHomologationRow[]
): { ok: true; artifact: WorkbookHomologationArtifact } | { ok: false; message: string } {
  if (!isRecord(value)) return invalid("O arquivo de revisao nao contem um objeto JSON valido.");
  if (value.artifactType !== WORKBOOK_HOMOLOGATION_ARTIFACT_TYPE) return invalid("Tipo de artefato invalido.");
  if (value.artifactVersion !== WORKBOOK_HOMOLOGATION_ARTIFACT_VERSION) return invalid("Versao de artefato nao suportada.");
  if (typeof value.revisionId !== "string" || !value.revisionId.trim()) return invalid("Identificador de revisao ausente.");
  if (value.parentRevisionId !== null && typeof value.parentRevisionId !== "string") return invalid("Revisao pai invalida.");
  if (typeof value.createdAt !== "string" || Number.isNaN(Date.parse(value.createdAt))) return invalid("Data da revisao invalida.");
  if (value.status !== "draft" && value.status !== "homologated") return invalid("Status da revisao invalido.");
  if (!isRecord(value.workbook) || value.workbook.sha256 !== analysis.file.sha256) {
    return invalid("A revisao pertence a outro workbook (SHA256 diferente).");
  }
  if (value.workbook.tableCount !== currentRows.length) {
    return invalid("A quantidade de tabelas da revisao difere do workbook analisado.");
  }
  if (!Array.isArray(value.entries) || value.entries.length !== currentRows.length) {
    return invalid("A revisao nao contem exatamente as mesmas tabelas do workbook analisado.");
  }

  const currentById = new Map(currentRows.map((row) => [row.sourceTableId, row]));
  const seen = new Set<string>();
  for (const candidate of value.entries) {
    if (!isRecord(candidate) || typeof candidate.sourceTableId !== "string") {
      return invalid("A revisao contem uma tabela sem identificador valido.");
    }
    if (seen.has(candidate.sourceTableId)) return invalid("A revisao contem identificadores de tabela duplicados.");
    seen.add(candidate.sourceTableId);
    const current = currentById.get(candidate.sourceTableId);
    if (!current) return invalid("A revisao contem uma tabela que nao existe neste workbook.");
    if (candidate.schemaFingerprint !== current.schemaFingerprint) {
      return invalid(`A estrutura da tabela ${current.sourceTableId} mudou desde a revisao importada.`);
    }
    if (
      candidate.technicalClassification !== current.technicalClassification ||
      candidate.ownerDomain !== current.ownerDomain ||
      candidate.targetEntity !== current.targetEntity
    ) {
      return invalid(`A classificacao tecnica da tabela ${current.sourceTableId} mudou.`);
    }
    if (candidate.decision !== null && !isWorkbookHomologationDecision(candidate.decision)) {
      return invalid(`A tabela ${current.sourceTableId} contem uma decisao desconhecida.`);
    }
    if (
      typeof candidate.observation !== "string" ||
      candidate.observation.length > 1000 ||
      (candidate.updatedAt !== null && typeof candidate.updatedAt !== "string") ||
      !Array.isArray(candidate.revisionHistory) ||
      !candidate.revisionHistory.every(isRevisionChange)
    ) {
      return invalid(`A tabela ${current.sourceTableId} contem dados de revisao invalidos.`);
    }
  }

  if (!Array.isArray(value.revisionTrail) || !value.revisionTrail.every(isRevisionTrailEntry)) {
    return invalid("O historico de revisoes esta ausente ou invalido.");
  }
  if (value.status === "homologated" && value.entries.some((entry) => isRecord(entry) && entry.decision === null)) {
    return invalid("Uma homologacao final nao pode conter tabela sem decisao.");
  }
  return { ok: true, artifact: value as WorkbookHomologationArtifact };
}

export function workbookHomologationCsv(rows: WorkbookHomologationRow[]): string {
  const headers = [
    "source_table_id",
    "schema_fingerprint",
    "ordem_aba",
    "aba",
    "tabela",
    "intervalo",
    "quantidade_linhas",
    "linhas_preenchidas",
    "quantidade_colunas",
    "principais_colunas",
    "classificacao_tecnica_sugerida",
    "dominio_previsto",
    "destino_previsto",
    "presenca_formulas",
    "quantidade_formulas",
    "indicio_relatorio",
    "indicio_calculo_derivado",
    "risco_duplicidade",
    "justificativa_tecnica",
    "decisao_final_luciano",
    "observacao_luciano"
  ];
  const data = rows.map((row) => [
    row.sourceTableId,
    row.schemaFingerprint,
    row.sheetOrder,
    row.sheetName,
    row.tableName,
    row.range,
    row.rowCount,
    row.populatedRowCount,
    row.columnCount,
    row.mainColumns.join(" | "),
    row.technicalClassification ?? "sem_classificacao_tecnica",
    row.ownerDomain ?? "sem_dominio",
    row.targetEntity ?? "sem_destino",
    row.formulaCellCount > 0 ? "sim" : "nao",
    row.formulaCellCount,
    row.reportIndicator ? "sim" : "nao",
    row.derivedCalculationIndicator ? "sim" : "nao",
    row.duplicateRisk,
    row.technicalJustification,
    row.decision ?? "sem_decisao",
    row.observation
  ]);
  return `\uFEFF${[headers, ...data].map((row) => row.map(csvCell).join(";")).join("\r\n")}`;
}

export function isWorkbookHomologationDecision(value: unknown): value is WorkbookHomologationDecision {
  return typeof value === "string" && WORKBOOK_HOMOLOGATION_DECISIONS.includes(value as WorkbookHomologationDecision);
}

function sourceIdsFor(
  rows: WorkbookHomologationRow[],
  predicate: (row: WorkbookHomologationRow) => boolean
): string[] {
  return rows.filter(predicate).map((row) => row.sourceTableId);
}

function csvCell(value: string | number): string {
  let text = String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isRevisionChange(value: unknown): boolean {
  return (
    isRecord(value) &&
    typeof value.revisionId === "string" &&
    typeof value.changedAt === "string" &&
    (value.previousDecision === null || isWorkbookHomologationDecision(value.previousDecision)) &&
    (value.decision === null || isWorkbookHomologationDecision(value.decision)) &&
    typeof value.observation === "string"
  );
}

function isRevisionTrailEntry(value: unknown): boolean {
  return (
    isRecord(value) &&
    typeof value.revisionId === "string" &&
    (value.parentRevisionId === null || typeof value.parentRevisionId === "string") &&
    typeof value.createdAt === "string" &&
    (value.status === "draft" || value.status === "homologated") &&
    typeof value.decidedTableCount === "number"
  );
}

function invalid(message: string): { ok: false; message: string } {
  return { ok: false, message };
}
