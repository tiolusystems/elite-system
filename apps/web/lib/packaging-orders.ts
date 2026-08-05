import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type PackagingLookup = { id: number; label: string; detail: string | null; targetId?: number };
export type PackagingReservation = {
  id: number;
  plannedComponentId: number | null;
  lotId: number;
  lotLabel: string;
  quantity: number;
  status: string;
};
export type PackagingComponent = {
  id: number;
  materialId: number;
  materialLabel: string;
  unitLabel: string;
  quantityPerLiter: number;
  plannedQuantity: number;
  reservedQuantity: number;
  reservations: PackagingReservation[];
};
export type PackagingOutput = { id: number; lotId: number; lotLabel: string; quantity: number };
export type PackagingOrder = {
  id: number;
  code: string;
  mapaOpId: number;
  mapaOpCode: string;
  formulaVersion: number;
  piLotId: number;
  piLotCode: string;
  saleItemId: number;
  saleItemCode: string;
  productName: string;
  packageName: string;
  plannedVolume: number;
  plannedFinishedPackages: number;
  status: string;
  issuerName: string;
  terminal: string;
  issuedAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  observation: string | null;
  components: PackagingComponent[];
  outputs: PackagingOutput[];
};
export type PackagingOrdersData = {
  orders: PackagingOrder[];
  formulas: PackagingLookup[];
  piLots: PackagingLookup[];
  presentations: PackagingLookup[];
  mpLots: PackagingLookup[];
  pagination: { page: number; pageSize: number; total: number; totalPages: number };
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export async function getPackagingOrdersData(input: {
  page?: number;
  pageSize?: number;
  query?: string | null;
  status?: string | null;
} = {}): Promise<PackagingOrdersData> {
  if (!getRuntimeStatus().supabaseConfigured) return emptyData("not_configured", null);
  try {
    const supabase = await createSupabaseServerClient();
    const pageSize = Math.min(50, Math.max(10, input.pageSize ?? 20));
    const page = Math.max(1, input.page ?? 1);
    const from = (page - 1) * pageSize;
    let ordersQuery = supabase.from("pcp_ordens_envase_dossie").select("*", { count: "exact" });
    if (input.query?.trim()) ordersQuery = ordersQuery.ilike("codigo_ordem", `%${input.query.trim()}%`);
    if (input.status && input.status !== "all") ordersQuery = ordersQuery.eq("status", input.status);
    const orderPage = await ordersQuery.order("emitida_em", { ascending: false }).range(from, from + pageSize - 1);
    const orderIds = rows(orderPage).map((row) => Number(row.id));
    const orderFilter = orderIds.length > 0 ? orderIds : [-1];
    const [orders, components, reservations, outputs, formulas, products, piLots, presentations, materials, units, mpLots] =
      await Promise.all([
        Promise.resolve(orderPage),
        supabase.from("pcp_ordem_envase_embalagens").select("*").in("ordem_envase_id", orderFilter).order("id", { ascending: true }),
        supabase.from("pcp_ordem_envase_reservas").select("*").in("ordem_envase_id", orderFilter).order("id", { ascending: true }),
        supabase.from("pcp_ordem_envase_lotes_pa").select("*").in("ordem_envase_id", orderFilter).order("id", { ascending: true }),
        supabase.from("pcp_formula_ativa").select("formula_versao_id,produto_id,tipo_receita,versao").eq("tipo_receita", "mapa").limit(300),
        supabase.from("cad_produtos_base").select("id,codigo_produto,nome,status").limit(400),
        supabase.from("est_lotes_pi_saldos").select("lote_pi_id,produto_id,codigo_lote,status,saldo_disponivel").eq("status", "disponivel").gt("saldo_disponivel", 0).limit(400),
        supabase.from("cad_produto_embalagens").select("id,codigo_item,produto_id,status,cad_produtos_base(nome),cad_embalagens(descricao)").eq("status", "active").limit(400),
        supabase.from("cad_materias_primas").select("id,sku_corrigido,nome").limit(500),
        supabase.from("cad_unidades_medida").select("id,codigo,simbolo").limit(300),
        supabase.from("est_lotes_mp_saldos").select("lote_mp_id,materia_prima_id,codigo_lote,status,saldo_disponivel").eq("status", "disponivel").gt("saldo_disponivel", 0).limit(600)
      ]);
    const queryError = [orders, components, reservations, outputs, formulas, products, piLots, presentations, materials, units, mpLots]
      .find((result) => result.error)?.error;
    if (queryError) return emptyData("error", humanDatabaseError(queryError.message));

    const productMap = new Map(rows(products).map((row) => [Number(row.id), `${row.codigo_produto} - ${row.nome}`]));
    const materialMap = new Map(rows(materials).map((row) => [Number(row.id), `${row.sku_corrigido} - ${row.nome}`]));
    const unitMap = new Map(rows(units).map((row) => [Number(row.id), String(row.simbolo ?? row.codigo)]));
    const mpLotMap = new Map(rows(mpLots).map((row) => [Number(row.lote_mp_id), String(row.codigo_lote)]));
    const piLotMap = new Map(rows(piLots).map((row) => [Number(row.lote_pi_id), String(row.codigo_lote)]));
    const outputLotIds = rows(outputs).map((row) => Number(row.lote_pa_id));
    const paLotResult = outputLotIds.length
      ? await supabase.from("est_lotes_pa").select("id,codigo_lote").in("id", outputLotIds)
      : { data: [], error: null };
    if (paLotResult.error) return emptyData("error", humanDatabaseError(paLotResult.error.message));
    const paLotMap = new Map(rows(paLotResult).map((row) => [Number(row.id), String(row.codigo_lote)]));

    const reservationRows = rows(reservations).map((row) => ({
      id: Number(row.id),
      orderId: Number(row.ordem_envase_id),
      type: String(row.tipo_reserva),
      plannedComponentId: nullableNumber(row.embalagem_planejada_id),
      lotId: Number(row.lote_mp_id ?? row.lote_pi_id),
      lotLabel: String(row.tipo_reserva) === "PI"
        ? piLotMap.get(Number(row.lote_pi_id)) ?? `Lote PI ${row.lote_pi_id}`
        : mpLotMap.get(Number(row.lote_mp_id)) ?? `Lote MP ${row.lote_mp_id}`,
      quantity: Number(row.quantidade_reservada),
      status: String(row.status)
    }));
    const reservationsByPlan = groupBy(
      reservationRows.filter((item) => item.plannedComponentId !== null),
      (item) => item.plannedComponentId as number
    );
    const componentsByOrder = groupBy(rows(components).map((row) => {
      const componentReservations = reservationsByPlan.get(Number(row.id)) ?? [];
      return {
        id: Number(row.id),
        orderId: Number(row.ordem_envase_id),
        materialId: Number(row.materia_prima_id),
        materialLabel: materialMap.get(Number(row.materia_prima_id)) ?? `MP ${row.materia_prima_id}`,
        unitLabel: unitMap.get(Number(row.unidade_id)) ?? `Unidade ${row.unidade_id}`,
        quantityPerLiter: Number(row.quantidade_un_l),
        plannedQuantity: Number(row.quantidade_planejada),
        reservedQuantity: componentReservations.filter((item) => item.status === "ativa").reduce((sum, item) => sum + item.quantity, 0),
        reservations: componentReservations
      };
    }), (item) => item.orderId);
    const outputsByOrder = groupBy(rows(outputs).map((row) => ({
      id: Number(row.id),
      orderId: Number(row.ordem_envase_id),
      lotId: Number(row.lote_pa_id),
      lotLabel: paLotMap.get(Number(row.lote_pa_id)) ?? `Lote PA ${row.lote_pa_id}`,
      quantity: Number(row.quantidade)
    })), (item) => item.orderId);

    return {
      orders: rows(orders).map((row) => ({
        id: Number(row.id), code: String(row.codigo_ordem), mapaOpId: Number(row.op_mapa_id),
        mapaOpCode: String(row.codigo_op_mapa), formulaVersion: Number(row.formula_mapa_versao),
        piLotId: Number(row.lote_pi_origem_id), piLotCode: String(row.lote_pi_origem),
        saleItemId: Number(row.produto_embalagem_id), saleItemCode: String(row.codigo_item),
        productName: String(row.produto_nome), packageName: String(row.embalagem_descricao),
        plannedVolume: Number(row.volume_planejado_l), plannedFinishedPackages: Number(row.quantidade_pa_planejada),
        status: String(row.status), issuerName: String(row.emissor_nome), terminal: String(row.terminal_emissor),
        issuedAt: String(row.emitida_em), startedAt: nullableString(row.iniciada_em), finishedAt: nullableString(row.finalizada_em),
        observation: nullableString(row.observacao), components: componentsByOrder.get(Number(row.id)) ?? [],
        outputs: outputsByOrder.get(Number(row.id)) ?? []
      })),
      formulas: rows(formulas).map((row) => ({
        id: Number(row.formula_versao_id),
        label: `${productMap.get(Number(row.produto_id)) ?? `Produto ${row.produto_id}`} / MAPA v${row.versao}`,
        detail: "Fórmula MAPA ativa", targetId: Number(row.produto_id)
      })),
      piLots: rows(piLots).map((row) => ({
        id: Number(row.lote_pi_id), label: String(row.codigo_lote),
        detail: `${productMap.get(Number(row.produto_id)) ?? `Produto ${row.produto_id}`} / disponível ${formatNumber(Number(row.saldo_disponivel))} L`,
        targetId: Number(row.produto_id)
      })),
      presentations: rows(presentations).map((row) => ({
        id: Number(row.id), label: `${row.codigo_item} - ${relationName(row.cad_produtos_base)} / ${relationName(row.cad_embalagens)}`,
        detail: "Apresentação ativa", targetId: Number(row.produto_id)
      })),
      mpLots: rows(mpLots).map((row) => ({
        id: Number(row.lote_mp_id), label: String(row.codigo_lote),
        detail: `${materialMap.get(Number(row.materia_prima_id)) ?? `MP ${row.materia_prima_id}`} / disponível ${formatNumber(Number(row.saldo_disponivel))}`,
        targetId: Number(row.materia_prima_id)
      })),
      pagination: {
        page,
        pageSize,
        total: orders.count ?? 0,
        totalPages: Math.max(1, Math.ceil((orders.count ?? 0) / pageSize))
      },
      source: "supabase", error: null
    };
  } catch {
    return emptyData("error", "Não foi possível carregar as ordens de envase.");
  }
}

function rows(result: { data?: unknown[] | null }): Array<Record<string, unknown>> {
  return (result.data ?? []) as Array<Record<string, unknown>>;
}
function nullableNumber(value: unknown): number | null { return value == null ? null : Number(value); }
function nullableString(value: unknown): string | null { return value == null ? null : String(value); }
function relationName(value: unknown): string {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object") return "Cadastro não carregado";
  const record = relation as Record<string, unknown>;
  return String(record.nome ?? record.descricao ?? "Cadastro não carregado");
}
function groupBy<T>(items: T[], key: (item: T) => number): Map<number, T[]> {
  const groups = new Map<number, T[]>();
  for (const item of items) groups.set(key(item), [...(groups.get(key(item)) ?? []), item]);
  return groups;
}
function formatNumber(value: number): string { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value); }
function humanDatabaseError(message: string): string {
  return message.toLowerCase().includes("does not exist")
    ? "O contrato de Envase ainda não foi instalado neste ambiente."
    : "Não foi possível consultar o fluxo de Envase.";
}
function emptyData(source: "not_configured" | "error", error: string | null): PackagingOrdersData {
  return { orders: [], formulas: [], piLots: [], presentations: [], mpLots: [], pagination: { page: 1, pageSize: 20, total: 0, totalPages: 1 }, source, error };
}
