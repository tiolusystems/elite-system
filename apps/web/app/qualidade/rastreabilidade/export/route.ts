import { NextRequest, NextResponse } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  XLSX_MIME_TYPE,
  buildXlsxBytes,
  bytesToArrayBuffer,
  type XlsxRow,
} from "@/lib/tabular-export";

const columns = [
  { key: "ambiente", header: "Ambiente", width: 16 },
  { key: "usuario_id", header: "Usuário", width: 38 },
  { key: "exportado_em", header: "Exportado em", width: 20, format: "datetime" as const },
  { key: "filtros", header: "Filtros", width: 34 },
  { key: "origem_tipo", header: "Tipo de origem", width: 18 },
  { key: "origem_codigo", header: "Código de origem", width: 22 },
  { key: "destino_tipo", header: "Tipo de destino", width: 18 },
  { key: "destino_codigo", header: "Código de destino", width: 22 },
  { key: "quantidade", header: "Quantidade", width: 16, format: "decimal" as const },
  { key: "unidade", header: "Unidade", width: 12 },
  { key: "evento_em", header: "Evento em", width: 20, format: "datetime" as const },
  { key: "evento", header: "Evento", width: 24 },
  { key: "ativo", header: "Ativo", width: 12, format: "boolean" as const },
  { key: "profundidade", header: "Etapa", width: 10, format: "integer" as const },
  { key: "divergencia_origem", header: "Divergência na origem", width: 20, format: "boolean" as const },
  { key: "divergencia_destino", header: "Divergência no destino", width: 20, format: "boolean" as const },
];

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams;
  const format = query.get("formato") === "csv" ? "csv" : "xlsx";
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("exportar_rel_rastreabilidade", {
    p_cliente_id: integer(query.get("cliente")),
    p_codigo: text(query.get("codigo")),
    p_direcao: text(query.get("direcao")) ?? "ambas",
    p_pedido_id: integer(query.get("pedido")),
    p_referencia_fiscal: text(query.get("referencia")),
    p_romaneio_id: integer(query.get("romaneio")),
    p_tipo: text(query.get("tipo")),
  });

  if (error) {
    return NextResponse.json({ error: "Não foi possível exportar a rastreabilidade." }, { status: 403 });
  }

  const rows = (data ?? []) as Array<Record<string, unknown>>;
  const date = new Date().toISOString().slice(0, 10);

  if (format === "csv") {
    const headers = columns.map((column) => column.key);
    const csv = [
      headers.join(";"),
      ...rows.map((row) => headers.map((key) => csvCell(row[key])).join(";")),
    ].join("\r\n");
    return new NextResponse(`\ufeff${csv}`, {
      headers: {
        "Content-Disposition": `attachment; filename="rastreabilidade-${date}.csv"`,
        "Content-Type": "text/csv; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  }

  const xlsxRows: XlsxRow[] = rows.map((row) =>
    Object.fromEntries(columns.map((column) => [column.key, exportValue(row[column.key])]))
  );

  const bytes = await buildXlsxBytes({
    title: "Rastreabilidade total",
    sheetName: "Rastreabilidade",
    metadata: [
      { label: "Tipo pesquisado", value: query.get("tipo") || "Qualquer tipo" },
      { label: "Código", value: query.get("codigo") || "Não informado" },
      { label: "Direção", value: query.get("direcao") || "ambas" },
      {
        label: "Exportado em",
        value: new Intl.DateTimeFormat("pt-BR", {
          dateStyle: "short",
          timeStyle: "short",
        }).format(new Date()),
      },
    ],
    columns,
    rows: xlsxRows,
  });

  return new NextResponse(bytesToArrayBuffer(bytes), {
    headers: {
      "Content-Disposition": `attachment; filename="rastreabilidade-${date}.xlsx"`,
      "Content-Type": XLSX_MIME_TYPE,
      "Cache-Control": "no-store",
    },
  });
}

function text(raw: string | null) {
  return raw?.trim() || null;
}

function integer(raw: string | null) {
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : null;
}

function exportValue(value: unknown): string | number | boolean | null {
  if (value == null) return null;
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return value;
  return JSON.stringify(value);
}

function csvCell(value: unknown) {
  const textValue = value == null
    ? ""
    : typeof value === "object"
      ? JSON.stringify(value)
      : String(value);
  return `"${textValue.replaceAll('"', '""')}"`;
}
