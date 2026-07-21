import { NextRequest, NextResponse } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const productPackageId = Number(request.nextUrl.searchParams.get("produto_embalagem_id"));
  if (!Number.isInteger(productPackageId) || productPackageId <= 0) {
    return NextResponse.json({ error: "Produto inválido." }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("est_lotes_pa_saldos")
    .select("lote_pa_id,produto_embalagem_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,updated_at")
    .eq("produto_embalagem_id", productPackageId)
    .eq("status", "disponivel")
    .gt("saldo_disponivel", 0)
    .order("data_validade", { ascending: true, nullsFirst: false })
    .limit(200);
  if (error) {
    return NextResponse.json({ error: "Não foi possível consultar o estoque deste produto." }, { status: 500 });
  }

  return NextResponse.json({
    lots: (data ?? []).map((row) => ({
      id: Number(row.lote_pa_id),
      produtoEmbalagemId: Number(row.produto_embalagem_id),
      itemLabel: "Produto selecionado",
      codigoLote: String(row.codigo_lote),
      status: String(row.status),
      saldoFisico: Number(row.saldo_fisico),
      quantidadeReservada: Number(row.quantidade_reservada),
      saldoDisponivel: Number(row.saldo_disponivel),
      dataValidade: row.data_validade ? String(row.data_validade) : null,
      updatedAt: String(row.updated_at)
    }))
  });
}
