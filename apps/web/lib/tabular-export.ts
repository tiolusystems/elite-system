export const XLSX_MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

export type XlsxCellFormat =
  | "text"
  | "integer"
  | "decimal"
  | "currency"
  | "date"
  | "datetime"
  | "boolean";

export type XlsxColumn = {
  key: string;
  header: string;
  width?: number;
  format?: XlsxCellFormat;
};

export type XlsxCellValue = string | number | boolean | Date | null | undefined;
export type XlsxRow = Record<string, XlsxCellValue>;

export type XlsxDocument = {
  title: string;
  sheetName: string;
  columns: XlsxColumn[];
  rows: XlsxRow[];
  metadata?: Array<{ label: string; value: string | number | boolean | null | undefined }>;
};

export async function buildXlsxBytes(document: XlsxDocument): Promise<Uint8Array> {
  if (!document.columns.length) throw new Error("A exportação precisa possuir ao menos uma coluna.");

  const { Workbook } = await import("exceljs");
  const workbook = new Workbook();
  workbook.creator = "Elite System";
  workbook.company = "Elite Agrociências";
  workbook.created = new Date();

  const worksheet = workbook.addWorksheet(safeSheetName(document.sheetName));
  let cursor = 1;

  const titleRow = worksheet.getRow(cursor);
  titleRow.getCell(1).value = document.title;
  titleRow.getCell(1).font = { bold: true, size: 14 };
  if (document.columns.length > 1) worksheet.mergeCells(cursor, 1, cursor, document.columns.length);
  cursor += 2;

  for (const item of document.metadata ?? []) {
    const row = worksheet.getRow(cursor);
    row.getCell(1).value = item.label;
    row.getCell(1).font = { bold: true };
    row.getCell(2).value = String(item.value ?? "");
    if (document.columns.length > 2) worksheet.mergeCells(cursor, 2, cursor, document.columns.length);
    cursor += 1;
  }

  if (document.metadata?.length) cursor += 1;

  const headerRowNumber = cursor;
  const headerRow = worksheet.getRow(headerRowNumber);
  document.columns.forEach((column, index) => {
    const cell = headerRow.getCell(index + 1);
    cell.value = column.header;
    cell.font = { bold: true };
    cell.alignment = { vertical: "middle", wrapText: true };
    worksheet.getColumn(index + 1).width = column.width ?? 18;
  });

  document.rows.forEach((source, rowIndex) => {
    const row = worksheet.getRow(headerRowNumber + rowIndex + 1);
    document.columns.forEach((column, columnIndex) => {
      const cell = row.getCell(columnIndex + 1);
      cell.value = normalizeCellValue(source[column.key], column.format ?? "text");
      cell.alignment = { vertical: "top", wrapText: column.format === "text" };
      const numberFormat = excelNumberFormat(column.format ?? "text");
      if (numberFormat) cell.numFmt = numberFormat;
    });
  });

  worksheet.autoFilter = {
    from: { row: headerRowNumber, column: 1 },
    to: { row: headerRowNumber, column: document.columns.length },
  };
  worksheet.views = [{ state: "frozen", ySplit: headerRowNumber }];

  const buffer = await workbook.xlsx.writeBuffer();
  return new Uint8Array(buffer);
}

export function downloadBytes(bytes: Uint8Array, filename: string, mimeType: string): void {
  const arrayBuffer = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength
  ) as ArrayBuffer;
  const url = URL.createObjectURL(new Blob([arrayBuffer], { type: mimeType }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength
  ) as ArrayBuffer;
}

function normalizeCellValue(
  value: XlsxCellValue,
  format: XlsxCellFormat
): string | number | boolean | Date | null {
  if (value == null) return null;
  if (format === "text") return String(value);
  if (format === "boolean") return Boolean(value);
  if (format === "date") return normalizeDate(value, false);
  if (format === "datetime") return normalizeDate(value, true);
  if (format === "integer" || format === "decimal" || format === "currency") {
    const numeric = typeof value === "number" ? value : Number(value);
    return Number.isFinite(numeric) ? numeric : String(value);
  }
  return value instanceof Date ? value : String(value);
}

function normalizeDate(value: XlsxCellValue, includeTime: boolean): Date | string {
  if (value instanceof Date) return value;
  const text = String(value);
  const isoDate = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (isoDate && !includeTime) {
    return new Date(Number(isoDate[1]), Number(isoDate[2]) - 1, Number(isoDate[3]), 12, 0, 0);
  }
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? text : parsed;
}

function excelNumberFormat(format: XlsxCellFormat): string | null {
  if (format === "integer") return "0";
  if (format === "decimal") return "0.00";
  if (format === "currency") return 'R$ #,##0.00';
  if (format === "date") return "dd/mm/yyyy";
  if (format === "datetime") return "dd/mm/yyyy hh:mm";
  return null;
}

function safeSheetName(value: string): string {
  const cleaned = value.replace(/[:\\/?*\[\]]/g, " ").trim() || "Exportação";
  return cleaned.slice(0, 31);
}
