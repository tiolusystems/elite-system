import { NextResponse } from "next/server";

import { buildPriceListTemplate, PRICE_LIST_XLSX_FILENAME } from "@/lib/price-list-xlsx";
import { getPriceListAccess, getPriceListWorkspace } from "@/lib/price-lists";
import { XLSX_MIME_TYPE } from "@/lib/tabular-export";

export async function GET() {
  const access = await getPriceListAccess();
  if (!(access.view && access.analyze)) return NextResponse.json({ error: "Acesso nao autorizado." }, { status: 403 });
  const workspace = await getPriceListWorkspace();
  if (!workspace.data) return NextResponse.json({ error: workspace.error }, { status: 503 });
  const bytes = await buildPriceListTemplate(workspace.data.catalogos);
  return new NextResponse(bytes as BodyInit, {
    headers: {
      "Content-Disposition": `attachment; filename="${PRICE_LIST_XLSX_FILENAME}"`,
      "Content-Type": XLSX_MIME_TYPE,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
