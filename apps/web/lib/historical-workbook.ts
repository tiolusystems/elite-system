export type WorkbookMappingStatus = "defined" | "transform" | "pending" | "rejected" | "out_of_scope";

export type WorkbookReference = {
  sheetOrder: number;
  sourceKind: "structured_table" | "worksheet_outside_table";
  sheet: string;
  table: string;
  ref: string;
  columnPosition: number | null;
  excelColumn: string;
  outsideTableCells?: number;
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
  headers: string[];
  warnings: string[];
  mappings: WorkbookReference[];
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
    statusCounts: Record<WorkbookMappingStatus, number>;
    domainCounts: Record<string, number>;
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
