export type WorkbookMappingStatus = "defined" | "transform" | "pending" | "rejected" | "out_of_scope";

export type WorkbookSourceClassificationName =
  | "source_master"
  | "source_transaction"
  | "source_formula"
  | "reconciliation_report"
  | "derived_calculation"
  | "duplicate_source"
  | "dashboard_or_summary"
  | "deferred"
  | "out_of_scope";

export type WorkbookSourceClassification = {
  sourceTableId: string;
  classification: WorkbookSourceClassificationName | null;
  ownerDomain: string | null;
  targetEntity: string | null;
  schemaFingerprint: string;
  schemaDriftDetected: boolean;
  reviewRequired: boolean;
  normalizationBlocked: boolean;
  identityHash?: string;
  sheetRef?: string;
  tableRef?: string;
  tableNumberInSheet?: number;
  baselineRange?: string;
  baselineRowCount?: number;
  baselineColumnCount?: number;
  canonicalHeaders?: string[];
  formulaCellCount?: number;
  calculatedValueCount?: number;
  equivalentPrimarySource?: string | null;
  preserveRows?: boolean;
  preserveMetadataOnly?: boolean;
  normalizeLater?: boolean;
  useForReconciliation?: boolean;
  justification?: string;
  duplicateRisk?: "low" | "medium" | "high" | "unknown";
  dependencies?: string[];
  qualityNotes?: string[];
  driftReason?: string | null;
};

export type WorkbookReference = {
  sheetOrder: number;
  sourceKind: "structured_table" | "worksheet_outside_table";
  sheet: string;
  table: string;
  ref: string;
  columnPosition: number | null;
  excelColumn: string;
  outsideTableCells?: number;
  sourceTableId: string;
  sourceClassification: WorkbookSourceClassificationName | null;
  sourceBindingKind: "structured_table" | "worksheet_metadata";
  sourceCode: string;
  status: WorkbookMappingStatus;
  domain: string;
  target: string;
  rule: string;
  warning: string | null;
};

export type WorkbookTableAnalysis = {
  name: string;
  ref: string;
  rowCount: number;
  populatedRowCount: number;
  columnCount: number;
  formulaCellCount: number;
  calculatedValueCount: number;
  headers: string[];
  warnings: string[];
  mappings: WorkbookReference[];
  sourceClassification?: WorkbookSourceClassification;
};

export type WorkbookSheetAnalysis = {
  order: number;
  name: string;
  state: string;
  dimension: string;
  nonemptyRows: number;
  nonemptyCells: number;
  formulaCells: number;
  errorCells: number;
  warnings: string[];
  tables: WorkbookTableAnalysis[];
  outsideColumns: WorkbookReference[];
};

export type HistoricalWorkbookAnalysis = {
  contractVersion: number;
  readOnly: true;
  notice: string;
  file: {
    name: string;
    sizeBytes: number;
    modifiedAt: string;
    sha256: string;
  };
  summary: {
    sheetCount: number;
    tableCount: number;
    namedRangeCount: number;
    tableRowCount: number;
    populatedTableRowCount: number;
    referenceCount: number;
    boundReferenceCount: number;
    unboundReferenceCount: number;
    classifiedTableCount: number;
    unclassifiedTableCount: number;
    schemaDriftTableCount: number;
    sourceClassificationComplete: boolean;
    tableClassificationCounts: Record<WorkbookSourceClassificationName, number>;
    statusCounts: Record<WorkbookMappingStatus, number>;
    domainCounts: Record<string, number>;
    structuralProfileMatchesReference: boolean;
    profileMatchesReference: boolean;
    profileWarnings: string[];
  };
  sheets: WorkbookSheetAnalysis[];
  reportRows: WorkbookReference[];
  analyzedAt: string;
};

export type HistoricalWorkbookActionResult =
  | { ok: true; analysis: HistoricalWorkbookAnalysis }
  | { ok: false; code: string; message: string };
