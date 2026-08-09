import { NextRequest, NextResponse } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("exportar_rel_rastreabilidade", {
    p_cliente_id: integer(query.get("cliente")), p_codigo: text(query.get("codigo")),
    p_direcao: text(query.get("direcao")) ?? "ambas", p_pedido_id: integer(query.get("pedido")),
    p_referencia_fiscal: text(query.get("referencia")), p_romaneio_id: integer(query.get("romaneio")),
    p_tipo: text(query.get("tipo"))
  });
  if (error) return NextResponse.json({ error: "Não foi possível exportar a rastreabilidade." }, { status: 403 });
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  const headers = ["ambiente", "usuario_id", "exportado_em", "filtros", "origem_tipo", "origem_codigo", "destino_tipo", "destino_codigo", "quantidade", "unidade", "evento_em", "evento", "ativo", "profundidade", "divergencia_origem", "divergencia_destino"];
  const csv = [headers.join(";"), ...rows.map((row) => headers.map((key) => csvCell(row[key])).join(";"))].join("\r\n");
  return new NextResponse(`\ufeff${csv}`, { headers: { "Content-Disposition": `attachment; filename="rastreabilidade-${new Date().toISOString().slice(0, 10)}.csv"`, "Content-Type": "text/csv; charset=utf-8", "Cache-Control": "no-store" } });
}
function text(raw: string | null) { return raw?.trim() || null; }
function integer(raw: string | null) { const value = Number(raw); return Number.isInteger(value) && value > 0 ? value : null; }
function csvCell(value: unknown) { const textValue = value == null ? "" : String(value); return `"${textValue.replaceAll('"', '""')}"`; }
