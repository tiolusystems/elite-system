import { NextResponse } from "next/server";

import { commissionRoleLabel } from "@/app/pedidos/financeiro/presenters";
import { getAuthStatus } from "@/lib/auth";
import { getBuildInfo } from "@/lib/build-info";
import { getCommissionReport, getFinanceAccess } from "@/lib/finance";
import { getRuntimeStatus } from "@/lib/runtime";
import {
  XLSX_MIME_TYPE,
  buildXlsxBytes,
  bytesToArrayBuffer,
  type XlsxRow,
} from "@/lib/tabular-export";

export async function GET(request: Request) {
  const access = await getFinanceAccess();
  if (!(access.commissionsView && access.commissionsExport)) {
    return NextResponse.json({ error: "Você não possui alçada para exportar este relatório." }, { status: 403 });
  }

  const url = new URL(request.url);
  const query = url.searchParams.get("q") ?? "";
  const role = url.searchParams.get("papel") ?? "";
  const cutoffDate = url.searchParams.get("corte") ?? new Date().toISOString().slice(0, 10);
  const onlyPositive = url.searchParams.get("saldo") !== "all";
  const format = url.searchParams.get("formato") === "csv" ? "csv" : "xlsx";
  const [reportResult, auth] = await Promise.all([
    getCommissionReport(query, role, cutoffDate, onlyPositive),
    getAuthStatus(),
  ]);

  if (reportResult.error) {
    return NextResponse.json({ error: reportResult.error }, { status: 503 });
  }

  const rows = reportResult.data;
  const build = getBuildInfo();
  const runtime = getRuntimeStatus();
  const generatedAt = new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date());
  const generatedBy = auth.profile?.displayName || auth.email || "Usuário autenticado";
  const version = `${build.version} · ${build.release}`;

  if (format === "csv") {
    const headers = [
      "Pessoa", "Papéis", "Previsto", "Liberado", "Pagamentos", "Estornos",
      "Ajustes", "Saldo", "Data de corte", "Ambiente", "Emitido por", "Gerado em", "Versão",
    ];
    const body = rows.map((row) => [
      row.personName,
      row.roles.map(commissionRoleLabel).join(", "),
      decimal(row.predicted),
      decimal(row.released),
      decimal(row.payments),
      decimal(row.reversals),
      decimal(row.adjustments),
      decimal(row.balance),
      cutoffDate,
      runtime.databaseLabel,
      generatedBy,
      generatedAt,
      version,
    ]);
    const csv = [headers, ...body].map((line) => line.map(csvCell).join(";")).join("\r\n");

    return new NextResponse(`\ufeff${csv}`, {
      headers: {
        "Cache-Control": "no-store",
        "Content-Disposition": `attachment; filename="comissoes-a-pagar-${cutoffDate}.csv"`,
        "Content-Type": "text/csv; charset=utf-8",
      },
    });
  }

  const xlsxRows: XlsxRow[] = rows.map((row) => ({
    pessoa: row.personName,
    papeis: row.roles.map(commissionRoleLabel).join(", "),
    previsto: row.predicted,
    liberado: row.released,
    pagamentos: row.payments,
    estornos: row.reversals,
    ajustes: row.adjustments,
    saldo: row.balance,
  }));
  const bytes = await buildXlsxBytes({
    title: "Relatório de comissões a pagar",
    sheetName: "Comissões a pagar",
    metadata: [
      { label: "Data de corte", value: cutoffDate.split("-").reverse().join("/") },
      { label: "Pessoa pesquisada", value: query || "Todas" },
      { label: "Papel", value: role ? commissionRoleLabel(role) : "Todos" },
      { label: "Saldo", value: onlyPositive ? "Somente a pagar" : "Todos" },
      { label: "Ambiente", value: runtime.databaseLabel },
      { label: "Emitido por", value: generatedBy },
      { label: "Gerado em", value: generatedAt },
      { label: "Versão", value: version },
    ],
    columns: [
      { key: "pessoa", header: "Pessoa", width: 30 },
      { key: "papeis", header: "Papéis", width: 24 },
      { key: "previsto", header: "Previsto", width: 16, format: "currency" },
      { key: "liberado", header: "Liberado", width: 16, format: "currency" },
      { key: "pagamentos", header: "Pagamentos", width: 16, format: "currency" },
      { key: "estornos", header: "Estornos", width: 16, format: "currency" },
      { key: "ajustes", header: "Ajustes", width: 16, format: "currency" },
      { key: "saldo", header: "Saldo", width: 16, format: "currency" },
    ],
    rows: xlsxRows,
  });

  return new NextResponse(bytesToArrayBuffer(bytes), {
    headers: {
      "Cache-Control": "no-store",
      "Content-Disposition": `attachment; filename="comissoes-a-pagar-${cutoffDate}.xlsx"`,
      "Content-Type": XLSX_MIME_TYPE,
    },
  });
}

function decimal(value: number) {
  return value.toFixed(2).replace(".", ",");
}

function csvCell(value: unknown) {
  return `"${String(value ?? "").replaceAll('"', '""')}"`;
}
