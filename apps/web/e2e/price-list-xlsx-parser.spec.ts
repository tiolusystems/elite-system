import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";

import { expect, test } from "@playwright/test";
import ExcelJS from "exceljs";

import {
  buildPriceListTemplate,
  canonicalPriceListRowDocument,
  parsePriceListWorkbook,
  PRICE_LIST_XLSX_MAX_ROWS,
} from "../lib/price-list-xlsx";

test.beforeEach(({}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-1920", "resource parser contract runs once");
});

test("official template and 10,000 price rows are accepted", async () => {
  const workbook = await officialWorkbook();
  fillList(workbook);
  const prices = workbook.getWorksheet("PRECOS")!;
  for (let index = 0; index < PRICE_LIST_XLSX_MAX_ROWS; index += 1) fillPrice(prices.getRow(index + 2), index);
  const parsed = await parsePriceListWorkbook(Buffer.from(await workbook.xlsx.writeBuffer()));
  expect(parsed.linhas).toHaveLength(PRICE_LIST_XLSX_MAX_ROWS);
});

test("10,001 rows and excessive sheet dimensions are rejected before RPC", async () => {
  const rowOverflow = await officialWorkbook();
  fillList(rowOverflow);
  const prices = rowOverflow.getWorksheet("PRECOS")!;
  for (let index = 0; index <= PRICE_LIST_XLSX_MAX_ROWS; index += 1) fillPrice(prices.getRow(index + 2), index);
  await expect(parsePriceListWorkbook(Buffer.from(await rowOverflow.xlsx.writeBuffer())))
    .rejects.toThrow("A aba PRECOS aceita no maximo 10.000 linhas preenchidas.");

  const dimensionOverflow = await officialWorkbook();
  fillList(dimensionOverflow);
  fillPrice(dimensionOverflow.getWorksheet("PRECOS")!.getRow(2), 0);
  dimensionOverflow.getWorksheet("PRECOS")!.getCell("XFD2").value = "dimensao suspeita";
  await expect(parsePriceListWorkbook(Buffer.from(await dimensionOverflow.xlsx.writeBuffer())))
    .rejects.toThrow("possui dimensoes excessivas");
});

test("compressed workbook with excessive expansion is rejected before ExcelJS", async () => {
  const payload = Buffer.alloc(32 * 1024 * 1024 + 1, 65);
  const archive = singleEntryZip("xl/sharedStrings.xml", payload);
  expect(archive.byteLength).toBeLessThan(10 * 1024 * 1024);
  await expect(parsePriceListWorkbook(archive)).rejects.toThrow(/parte interna grande demais|taxa de compactacao suspeita/);
});

test("canonical row document ignores object field order and fixes numeric representation", () => {
  const row = canonicalRow();
  const reordered = Object.fromEntries(Object.entries(row).reverse());
  const document = canonicalPriceListRowDocument(row);
  expect(document).toBe(canonicalPriceListRowDocument(reordered));
  expect(createHash("sha256").update(document).digest("hex"))
    .toBe("1bdd9a313e3a4df12c9d4e45f25e4feed9539fa742fdee26ad81deb3186ad5c4");
  expect(document).toContain('"31.255"');
  expect(canonicalPriceListRowDocument({ ...row, preco_unitario: 1e-7 })).toContain('"0.0000001"');
});

async function officialWorkbook(): Promise<ExcelJS.Workbook> {
  const bytes = await buildPriceListTemplate({
    produtos: [{ codigo: "9137", nome: "Produto parser" }],
    apresentacoes: [{ codigo: "PLX137-20L", produto_codigo: "9137", nome: "Embalagem parser", volume_litros: 20 }],
    unidades: [{ codigo: "l", nome: "Litro", simbolo: "L" }],
    canais: [{ codigo: "direto_elite", nome: "Direto Elite" }],
  });
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(bytes as unknown as ArrayBuffer);
  return workbook;
}

function fillList(workbook: ExcelJS.Workbook): void {
  workbook.getWorksheet("LISTA")!.getRow(2).values = [
    "PARSER137", "Lista parser", new Date(2026, 7, 25), new Date(2026, 11, 31), "SP", "direto_elite", "teste parser",
  ];
}

function fillPrice(row: ExcelJS.Row, index: number): void {
  row.values = [
    "9137", "Produto parser", "PLX137-20L", "Embalagem parser", "l", 20,
    index, index, 31.255, `linha ${index}`,
  ];
}

function canonicalRow(): Record<string, unknown> {
  return {
    excel_row: 2,
    codigo_produto: "9137",
    nome_produto: "Produto parser",
    codigo_apresentacao: "PLX137-20L",
    nome_apresentacao: "Embalagem parser",
    unidade_precificacao: "l",
    fator_por_apresentacao: 20,
    pmp_min_dias: 0,
    pmp_max_dias: 30,
    preco_unitario: 31.255,
    observacao: null,
    source_payload: { A: "9137", B: "Produto parser", C: "PLX137-20L", D: "Embalagem parser", E: "l", F: 20, G: 0, H: 30, I: 31.255, J: null },
    formulas: {},
    celulas: {
      codigo_produto: "A2", nome_produto: "B2", codigo_apresentacao: "C2", nome_apresentacao: "D2",
      unidade_precificacao: "E2", fator_por_apresentacao: "F2", pmp_min_dias: "G2", pmp_max_dias: "H2",
      preco_unitario: "I2", observacao: "J2",
    },
  };
}

function singleEntryZip(name: string, payload: Buffer): Buffer {
  const compressed = deflateRawSync(payload);
  const nameBytes = Buffer.from(name, "utf8");
  const local = Buffer.alloc(30 + nameBytes.length);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt16LE(8, 8);
  local.writeUInt32LE(compressed.length, 18);
  local.writeUInt32LE(payload.length, 22);
  local.writeUInt16LE(nameBytes.length, 26);
  nameBytes.copy(local, 30);
  const central = Buffer.alloc(46 + nameBytes.length);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt16LE(8, 10);
  central.writeUInt32LE(compressed.length, 20);
  central.writeUInt32LE(payload.length, 24);
  central.writeUInt16LE(nameBytes.length, 28);
  nameBytes.copy(central, 46);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(1, 8);
  eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(central.length, 12);
  eocd.writeUInt32LE(local.length + compressed.length, 16);
  return Buffer.concat([local, compressed, central, eocd]);
}
