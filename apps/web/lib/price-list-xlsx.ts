import { createHash } from "node:crypto";

import type { PriceListCatalogs } from "@/lib/price-lists";

export const PRICE_LIST_XLSX_MAX_BYTES = 10 * 1024 * 1024;
export const PRICE_LIST_XLSX_MAX_ROWS = 10_000;
export const PRICE_LIST_XLSX_FILENAME = "modelo_lista_precos_elite.xlsx";

const PRICE_LIST_XLSX_MAX_ARCHIVE_ENTRIES = 2_048;
const PRICE_LIST_XLSX_MAX_UNCOMPRESSED_BYTES = 96 * 1024 * 1024;
const PRICE_LIST_XLSX_MAX_ENTRY_BYTES = 32 * 1024 * 1024;
const PRICE_LIST_XLSX_MAX_COMPRESSION_RATIO = 200;
const PRICE_LIST_XLSX_MAX_SHEET_ROWS = 20_000;
const PRICE_LIST_XLSX_MAX_SHEET_COLUMNS = 64;

const SHEETS = ["INSTRUCOES", "LISTA", "PRECOS", "CATALOGOS"] as const;
const LIST_HEADERS = ["codigo_lista", "nome_lista", "vigencia_inicio", "vigencia_fim", "uf", "canal", "observacao"] as const;
const PRICE_HEADERS = [
  "codigo_produto", "nome_produto", "codigo_apresentacao", "nome_apresentacao",
  "unidade_precificacao", "fator_por_apresentacao", "pmp_min_dias", "pmp_max_dias",
  "preco_unitario", "observacao",
] as const;

type CellValue = string | number | boolean | Date | null;
type ExcelJsModule = typeof import("exceljs");
type ExcelJsLoader = Pick<ExcelJsModule, "Workbook">;

export type ParsedPriceListWorkbook = {
  workbookSha256: string;
  lista: Record<string, string | null>;
  linhas: Array<Record<string, unknown>>;
};

async function loadExcelJs(): Promise<ExcelJsLoader> {
  const excelJsModule = await import("exceljs");
  const compatible = excelJsModule as unknown as {
    Workbook?: ExcelJsModule["Workbook"];
    default?: { Workbook?: ExcelJsModule["Workbook"] };
  };
  const Workbook = compatible.Workbook ?? compatible.default?.Workbook;
  if (typeof Workbook !== "function") throw new Error("O processador XLSX nao esta disponivel.");
  return { Workbook };
}

export async function buildPriceListTemplate(catalogs: PriceListCatalogs): Promise<Uint8Array> {
  const { Workbook } = await loadExcelJs();
  const workbook = new Workbook();
  workbook.creator = "Elite System";
  workbook.company = "Elite Agrociencias";
  workbook.created = new Date();

  const instructions = workbook.addWorksheet("INSTRUCOES");
  instructions.columns = [{ width: 24 }, { width: 88 }];
  const instructionRows = [
    ["etapa", "orientacao"],
    ["1", "Preencha uma unica linha na aba LISTA."],
    ["2", "Na aba PRECOS, use codigos existentes. Nomes servem apenas para conferencia."],
    ["3", "Informe o fator comercial explicito. Para L, ele deve ser igual a capacidade em litros da apresentacao."],
    ["4", "Para cada apresentacao, as faixas de PMP devem iniciar em 0 e continuar sem lacunas: 0-30, 31-60, 61-90."],
    ["5", "Precos devem ser celulas numericas positivas. Texto com R$ e formulas sao recusados."],
    ["6", "Baixar ou analisar nao publica. A publicacao exige confirmacao separada no Elite System."],
  ];
  instructions.addRows(instructionRows.map((row) => row.map(safeExportText)));
  styleHeader(instructions, 1, 2);
  instructions.addTable({ name: "tb_instrucoes", ref: "A1", headerRow: true, style: { theme: "TableStyleMedium2", showRowStripes: true }, columns: [{ name: "etapa" }, { name: "orientacao" }], rows: instructionRows.slice(1) });
  instructions.views = [{ state: "frozen", ySplit: 1 }];

  const list = workbook.addWorksheet("LISTA");
  list.columns = LIST_HEADERS.map((header) => ({ header, key: header, width: header.includes("observacao") ? 42 : 20 }));
  list.addRow({});
  list.addTable({ name: "tb_lista", ref: "A1", headerRow: true, style: { theme: "TableStyleMedium2", showRowStripes: true }, columns: LIST_HEADERS.map((name) => ({ name })), rows: [["", "", null, null, "", "", ""]] });
  list.views = [{ state: "frozen", ySplit: 1 }];
  list.autoFilter = "A1:G2";
  list.getColumn(3).numFmt = "dd/mm/yyyy";
  list.getColumn(4).numFmt = "dd/mm/yyyy";
  list.getCell("E2").dataValidation = { type: "list", allowBlank: true, formulae: ['"AC,AL,AP,AM,BA,CE,DF,ES,GO,MA,MT,MS,MG,PA,PB,PR,PE,PI,RJ,RN,RS,RO,RR,SC,SP,SE,TO"'] };
  if (catalogs.canais.length) list.getCell("F2").dataValidation = { type: "list", allowBlank: true, formulae: [`"${catalogs.canais.map((item) => item.codigo).join(",")}"`] };

  const prices = workbook.addWorksheet("PRECOS");
  prices.columns = PRICE_HEADERS.map((header) => ({ header, key: header, width: header.includes("nome") || header === "observacao" ? 34 : 22 }));
  prices.addTable({ name: "tb_precos", ref: "A1", headerRow: true, style: { theme: "TableStyleMedium2", showRowStripes: true }, columns: PRICE_HEADERS.map((name) => ({ name })), rows: [["", "", "", "", "", null, null, null, null, ""]] });
  prices.views = [{ state: "frozen", ySplit: 1 }];
  prices.autoFilter = "A1:J2";
  prices.getColumn(6).numFmt = "0.000000";
  prices.getColumn(7).numFmt = "0";
  prices.getColumn(8).numFmt = "0";
  prices.getColumn(9).numFmt = "R$ #,##0.00";
  if (catalogs.unidades.length) prices.getCell("E2").dataValidation = { type: "list", allowBlank: false, formulae: [`"${catalogs.unidades.map((item) => item.codigo).join(",")}"`] };

  const catalog = workbook.addWorksheet("CATALOGOS");
  catalog.columns = [{ width: 20 }, { width: 24 }, { width: 46 }, { width: 24 }, { width: 30 }];
  const catalogRows: string[][] = [
    ...catalogs.produtos.map((item) => ["PRODUTO", item.codigo, item.nome, "", ""]),
    ...catalogs.apresentacoes.map((item) => ["APRESENTACAO", item.codigo, item.nome, item.produto_codigo, item.volume_litros == null ? "" : `${item.volume_litros} L`]),
    ...catalogs.unidades.map((item) => ["UNIDADE", item.codigo, item.nome, "", item.simbolo]),
    ...catalogs.canais.map((item) => ["CANAL", item.codigo, item.nome, "", ""]),
    ...["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"].map((uf) => ["UF", uf, uf, "", ""]),
  ];
  catalog.addTable({ name: "tb_catalogos", ref: "A1", headerRow: true, style: { theme: "TableStyleMedium2", showRowStripes: true }, columns: ["tipo", "codigo", "nome", "codigo_produto", "detalhe"].map((name) => ({ name })), rows: catalogRows.map((row) => row.map(safeExportText)) });
  catalog.views = [{ state: "frozen", ySplit: 1 }];
  styleHeader(list, 1, LIST_HEADERS.length);
  styleHeader(prices, 1, PRICE_HEADERS.length);
  styleHeader(catalog, 1, 5);

  const buffer = await workbook.xlsx.writeBuffer();
  return new Uint8Array(buffer);
}

export async function parsePriceListWorkbook(bytes: Buffer): Promise<ParsedPriceListWorkbook> {
  if (bytes.byteLength === 0) throw new Error("O arquivo esta vazio.");
  if (bytes.byteLength > PRICE_LIST_XLSX_MAX_BYTES) throw new Error("O arquivo excede o limite de 10 MB.");
  inspectXlsxArchive(bytes);
  const { Workbook } = await loadExcelJs();
  const workbook = new Workbook();
  try {
    await workbook.xlsx.load(bytes as unknown as ArrayBuffer);
  } catch {
    throw new Error("O arquivo nao e um XLSX valido ou esta corrompido.");
  }
  const names = workbook.worksheets.map((sheet) => sheet.name.toLocaleUpperCase("pt-BR"));
  if (names.length !== SHEETS.length || SHEETS.some((name) => !names.includes(name))) {
    throw new Error("O workbook deve conter somente as abas INSTRUCOES, LISTA, PRECOS e CATALOGOS.");
  }
  const listSheet = workbook.getWorksheet("LISTA");
  const priceSheet = workbook.getWorksheet("PRECOS");
  if (!listSheet || !priceSheet) throw new Error("As abas LISTA e PRECOS sao obrigatorias.");
  for (const sheet of workbook.worksheets) validateWorksheetDimensions(sheet);
  if (priceSheet.rowCount > PRICE_LIST_XLSX_MAX_ROWS + 1 || priceSheet.actualRowCount > PRICE_LIST_XLSX_MAX_ROWS + 1) {
    throw new Error("A aba PRECOS aceita no maximo 10.000 linhas preenchidas.");
  }
  const listColumns = readHeader(listSheet, LIST_HEADERS);
  const priceColumns = readHeader(priceSheet, PRICE_HEADERS);
  const nonEmptyListRows = rowsWithValues(listSheet, 2, LIST_HEADERS.length);
  if (nonEmptyListRows.length !== 1) throw new Error("A aba LISTA deve possuir exatamente uma linha preenchida.");
  const listRow = nonEmptyListRows[0];
  const startDate = dateCell(listRow.getCell(listColumns.vigencia_inicio), "vigencia_inicio");
  const endDateCell = listRow.getCell(listColumns.vigencia_fim);
  const endDate = cellIsBlank(endDateCell.value) ? null : dateCell(endDateCell, "vigencia_fim");
  if (endDate && endDate < startDate) throw new Error("A vigencia final nao pode ser anterior a inicial.");
  const lista = {
    codigo_lista: requiredText(listRow.getCell(listColumns.codigo_lista), "codigo_lista").toLocaleUpperCase("pt-BR"),
    nome_lista: requiredText(listRow.getCell(listColumns.nome_lista), "nome_lista"),
    vigencia_inicio: startDate,
    vigencia_fim: endDate,
    uf: optionalText(listRow.getCell(listColumns.uf))?.toLocaleUpperCase("pt-BR") ?? null,
    canal: optionalText(listRow.getCell(listColumns.canal))?.toLocaleLowerCase("pt-BR") ?? null,
    observacao: optionalText(listRow.getCell(listColumns.observacao)),
  };

  const sourceRows = rowsWithValues(priceSheet, 2, PRICE_HEADERS.length);
  if (!sourceRows.length) throw new Error("A aba PRECOS deve possuir ao menos uma linha preenchida.");
  if (sourceRows.length > PRICE_LIST_XLSX_MAX_ROWS) throw new Error("A aba PRECOS aceita no maximo 10.000 linhas preenchidas.");
  const linhas = sourceRows.map((row) => {
    const sourcePayload: Record<string, CellValue> = {};
    const formulas: Record<string, string> = {};
    const cells: Record<string, string> = {};
    PRICE_HEADERS.forEach((header) => {
      const column = priceColumns[header];
      const cell = row.getCell(column);
      const letter = columnLetter(column);
      const formula = formulaFrom(cell.value);
      sourcePayload[letter] = serializableCellValue(cell.value);
      cells[header] = `${letter}${row.number}`;
      if (formula) formulas[letter] = formula;
    });
    const factor = numericCell(row.getCell(priceColumns.fator_por_apresentacao));
    const pmpMin = integerCell(row.getCell(priceColumns.pmp_min_dias));
    const pmpMax = integerCell(row.getCell(priceColumns.pmp_max_dias));
    const price = numericCell(row.getCell(priceColumns.preco_unitario));
    const canonical = {
      excel_row: row.number,
      codigo_produto: optionalText(row.getCell(priceColumns.codigo_produto)) ?? "",
      nome_produto: optionalText(row.getCell(priceColumns.nome_produto)),
      codigo_apresentacao: optionalText(row.getCell(priceColumns.codigo_apresentacao)) ?? "",
      nome_apresentacao: optionalText(row.getCell(priceColumns.nome_apresentacao)),
      unidade_precificacao: optionalText(row.getCell(priceColumns.unidade_precificacao)) ?? "",
      fator_por_apresentacao: factor,
      pmp_min_dias: pmpMin,
      pmp_max_dias: pmpMax,
      preco_unitario: price,
      observacao: optionalText(row.getCell(priceColumns.observacao)),
      source_payload: sourcePayload,
      formulas,
      celulas: cells,
    };
    return { ...canonical, row_sha256: sha256(canonicalPriceListRowDocument(canonical)) };
  });
  return { workbookSha256: sha256(bytes), lista, linhas };
}

export function canonicalPriceListRowDocument(row: Record<string, unknown>): string {
  const sourcePayload = objectValue(row.source_payload);
  const formulas = objectValue(row.formulas);
  const cells = objectValue(row.celulas);
  const sourceColumns = PRICE_HEADERS.map((_, index) => canonicalSourceValue(sourcePayload[columnLetter(index + 1)]));
  const formulaColumns = PRICE_HEADERS.map((_, index) => stringOrNull(formulas[columnLetter(index + 1)]));
  const cellColumns = PRICE_HEADERS.map((header) => stringOrNull(cells[header]));
  return postgresJsonArray([
    "price-list-row-v1",
    integerOrNull(row.excel_row),
    stringOrNull(row.codigo_produto),
    stringOrNull(row.nome_produto),
    stringOrNull(row.codigo_apresentacao),
    stringOrNull(row.nome_apresentacao),
    stringOrNull(row.unidade_precificacao),
    decimalOrNull(row.fator_por_apresentacao),
    integerOrNull(row.pmp_min_dias),
    integerOrNull(row.pmp_max_dias),
    decimalOrNull(row.preco_unitario),
    stringOrNull(row.observacao),
    sourceColumns,
    formulaColumns,
    cellColumns,
  ]);
}

function inspectXlsxArchive(bytes: Buffer): void {
  if (bytes.length < 22 || bytes.readUInt32LE(0) !== 0x04034b50) {
    throw new Error("O arquivo nao e um XLSX valido ou esta corrompido.");
  }
  const minimumEocd = Math.max(0, bytes.length - 65_557);
  let eocd = -1;
  for (let offset = bytes.length - 22; offset >= minimumEocd; offset -= 1) {
    if (bytes.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break; }
  }
  if (eocd < 0) throw new Error("O arquivo XLSX possui estrutura ZIP invalida.");
  const disk = bytes.readUInt16LE(eocd + 4);
  const centralDisk = bytes.readUInt16LE(eocd + 6);
  const entriesOnDisk = bytes.readUInt16LE(eocd + 8);
  const entries = bytes.readUInt16LE(eocd + 10);
  const centralSize = bytes.readUInt32LE(eocd + 12);
  const centralOffset = bytes.readUInt32LE(eocd + 16);
  if (disk !== 0 || centralDisk !== 0 || entriesOnDisk !== entries || entries === 0 || entries > PRICE_LIST_XLSX_MAX_ARCHIVE_ENTRIES) {
    throw new Error("O arquivo XLSX usa um formato ZIP nao suportado.");
  }
  if (entries === 0xffff || centralSize === 0xffffffff || centralOffset === 0xffffffff || centralOffset + centralSize > eocd) {
    throw new Error("O arquivo XLSX usa um formato ZIP nao suportado.");
  }
  let offset = centralOffset;
  let totalUncompressed = 0;
  for (let index = 0; index < entries; index += 1) {
    if (offset + 46 > eocd || bytes.readUInt32LE(offset) !== 0x02014b50) throw new Error("O arquivo XLSX possui estrutura ZIP invalida.");
    const flags = bytes.readUInt16LE(offset + 8);
    const method = bytes.readUInt16LE(offset + 10);
    const compressed = bytes.readUInt32LE(offset + 20);
    const uncompressed = bytes.readUInt32LE(offset + 24);
    const nameLength = bytes.readUInt16LE(offset + 28);
    const extraLength = bytes.readUInt16LE(offset + 30);
    const commentLength = bytes.readUInt16LE(offset + 32);
    const next = offset + 46 + nameLength + extraLength + commentLength;
    if (next > eocd) throw new Error("O arquivo XLSX possui estrutura ZIP invalida.");
    const name = bytes.toString("utf8", offset + 46, offset + 46 + nameLength);
    if ((flags & 0x1) !== 0) throw new Error("Planilhas XLSX criptografadas nao sao aceitas.");
    if (method !== 0 && method !== 8) throw new Error("O arquivo XLSX usa compactacao nao suportada.");
    if (/vbaProject\.bin$/i.test(name) || /EncryptedPackage$/i.test(name)) throw new Error("Planilhas com macro ou criptografia nao sao aceitas.");
    if (uncompressed > PRICE_LIST_XLSX_MAX_ENTRY_BYTES) throw new Error("O arquivo XLSX possui uma parte interna grande demais.");
    totalUncompressed += uncompressed;
    if (totalUncompressed > PRICE_LIST_XLSX_MAX_UNCOMPRESSED_BYTES) throw new Error("O arquivo XLSX expandido excede o limite de seguranca.");
    if (uncompressed > 0 && (compressed === 0 || uncompressed / compressed > PRICE_LIST_XLSX_MAX_COMPRESSION_RATIO)) {
      throw new Error("O arquivo XLSX possui taxa de compactacao suspeita.");
    }
    offset = next;
  }
  if (offset !== centralOffset + centralSize) throw new Error("O arquivo XLSX possui estrutura ZIP inconsistente.");
}

function validateWorksheetDimensions(worksheet: import("exceljs").Worksheet): void {
  if (worksheet.rowCount > PRICE_LIST_XLSX_MAX_SHEET_ROWS || worksheet.actualRowCount > PRICE_LIST_XLSX_MAX_SHEET_ROWS
      || worksheet.columnCount > PRICE_LIST_XLSX_MAX_SHEET_COLUMNS || worksheet.actualColumnCount > PRICE_LIST_XLSX_MAX_SHEET_COLUMNS) {
    throw new Error(`A aba ${worksheet.name} possui dimensoes excessivas.`);
  }
}

function objectValue(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function integerOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function decimalOrNull(value: unknown): string | null {
  return typeof value === "number" && Number.isFinite(value) ? canonicalDecimal(value) : null;
}

function canonicalSourceValue(value: unknown): unknown[] {
  if (value === null || value === undefined) return ["null", null];
  if (typeof value === "number" && Number.isFinite(value)) return ["number", canonicalDecimal(value)];
  if (typeof value === "string") return ["string", value];
  if (typeof value === "boolean") return ["boolean", value ? "true" : "false"];
  return ["unsupported", String(value)];
}

function canonicalDecimal(value: number): string {
  if (Object.is(value, -0)) return "0";
  const raw = value.toString().toLowerCase();
  if (!raw.includes("e")) return raw;
  const [coefficient, exponentText] = raw.split("e");
  const exponent = Number(exponentText);
  const negative = coefficient.startsWith("-");
  const digits = coefficient.replace("-", "").replace(".", "");
  const decimalPosition = coefficient.replace("-", "").indexOf(".");
  const integerDigits = decimalPosition < 0 ? digits.length : decimalPosition;
  const target = integerDigits + exponent;
  const expanded = target <= 0
    ? `0.${"0".repeat(-target)}${digits}`
    : target >= digits.length
      ? `${digits}${"0".repeat(target - digits.length)}`
      : `${digits.slice(0, target)}.${digits.slice(target)}`;
  return negative ? `-${expanded}` : expanded;
}

function postgresJsonArray(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(postgresJsonArray).join(", ")}]`;
  return JSON.stringify(value);
}

function readHeader<T extends readonly string[]>(worksheet: import("exceljs").Worksheet, expected: T): Record<T[number], number> {
  const headers = new Map<string, number>();
  worksheet.getRow(1).eachCell({ includeEmpty: false }, (cell, column) => {
    const value = String(cell.value ?? "").trim().toLocaleLowerCase("pt-BR");
    if (!value) return;
    if (headers.has(value)) throw new Error(`Cabecalho duplicado na aba ${worksheet.name}: ${value}.`);
    headers.set(value, column);
  });
  const missing = expected.filter((header) => !headers.has(header));
  const unknown = [...headers.keys()].filter((header) => !expected.includes(header as T[number]));
  if (missing.length || unknown.length) throw new Error(`Estrutura invalida na aba ${worksheet.name}. Ausentes: ${missing.join(", ") || "nenhum"}. Desconhecidos: ${unknown.join(", ") || "nenhum"}.`);
  return Object.fromEntries(expected.map((header) => [header, headers.get(header)!])) as Record<T[number], number>;
}

function rowsWithValues(worksheet: import("exceljs").Worksheet, start: number, columns: number): import("exceljs").Row[] {
  const rows: import("exceljs").Row[] = [];
  for (let index = start; index <= worksheet.actualRowCount; index += 1) {
    const row = worksheet.getRow(index);
    if (Array.from({ length: columns }, (_, offset) => row.getCell(offset + 1)).some((cell) => !cellIsBlank(cell.value))) rows.push(row);
  }
  return rows;
}

function requiredText(cell: import("exceljs").Cell, label: string): string {
  const value = optionalText(cell);
  if (!value) throw new Error(`${label} e obrigatorio.`);
  return value;
}

function optionalText(cell: import("exceljs").Cell): string | null {
  if (formulaFrom(cell.value)) return null;
  const value = cell.value;
  if (cellIsBlank(value)) return null;
  if (typeof value === "object" && value && "text" in value) return String(value.text).trim() || null;
  return String(value).trim() || null;
}

function numericCell(cell: import("exceljs").Cell): number | null {
  if (formulaFrom(cell.value) || typeof cell.value !== "number" || !Number.isFinite(cell.value)) return null;
  return cell.value;
}

function integerCell(cell: import("exceljs").Cell): number | null {
  const value = numericCell(cell);
  return value !== null && Number.isInteger(value) ? value : null;
}

function dateCell(cell: import("exceljs").Cell, label: string): string {
  if (!(cell.value instanceof Date) || Number.isNaN(cell.value.getTime())) throw new Error(`${label} deve ser uma celula de data valida.`);
  const year = cell.value.getFullYear();
  const month = String(cell.value.getMonth() + 1).padStart(2, "0");
  const day = String(cell.value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formulaFrom(value: import("exceljs").CellValue): string | null {
  return typeof value === "object" && value !== null && "formula" in value ? String(value.formula) : null;
}

function serializableCellValue(value: import("exceljs").CellValue): CellValue {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return value;
  if (typeof value === "object" && "result" in value) return serializableCellValue(value.result as import("exceljs").CellValue);
  if (typeof value === "object" && "text" in value) return String(value.text);
  return String(value);
}

function cellIsBlank(value: import("exceljs").CellValue): boolean {
  return value == null || (typeof value === "string" && value.trim() === "");
}

function columnLetter(column: number): string {
  let value = column;
  let result = "";
  while (value > 0) {
    value -= 1;
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = Math.floor(value / 26);
  }
  return result;
}

function sha256(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

function safeExportText(value: string): string {
  return /^[=+\-@]/.test(value) ? `'${value}` : value;
}

function styleHeader(worksheet: import("exceljs").Worksheet, row: number, columns: number): void {
  const header = worksheet.getRow(row);
  for (let column = 1; column <= columns; column += 1) {
    header.getCell(column).font = { bold: true, color: { argb: "FFFFFFFF" } };
    header.getCell(column).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1E5A46" } };
    header.getCell(column).alignment = { vertical: "middle", wrapText: true };
  }
}
