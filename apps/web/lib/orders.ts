import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type OrderLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type OrderLookups = {
  clientes: OrderLookupOption[];
  propriedades: OrderLookupOption[];
  itensVendaveis: OrderLookupOption[];
  pessoasComerciais: OrderLookupOption[];
  pedidos: OrderLookupOption[];
  pedidoItens: OrderLookupOption[];
};

export type RecentOrder = {
  id: number;
  codigoPedido: string;
  clienteId: number;
  propriedadeId: number | null;
  sequenciaPropriedade: number | null;
  vendedorGeradorId: number | null;
  tipoPedido: string;
  status: string;
  dataPedido: string;
  valorTotal: number;
  createdAt: string;
};

export type RecentCreditDecision = {
  id: number;
  pedidoId: number;
  decisao: string;
  statusAnterior: string;
  statusResultante: string;
  motivo: string | null;
  limiteDisponivelSnapshot: number | null;
  inadimplenciaSnapshot: number | null;
  createdAt: string;
};

export type RecentReceipt = {
  id: number;
  pedidoId: number;
  valorRecebido: number;
  dataRecebimento: string;
  formaRecebimento: string | null;
  createdAt: string;
};

export type RecentCommissionRelease = {
  id: number;
  recebimentoId: number;
  pedidoId: number;
  pessoaId: number;
  valorLiberado: number;
  percentualRecebidoSnapshot: number;
  status: string;
  createdAt: string;
};

export type OrdersDashboard = {
  metrics: {
    totalPedidos: number | null;
    rascunhos: number | null;
    abertos: number | null;
    bloqueados: number | null;
    faturamentoPrevisto: number | null;
    totalRecebido: number | null;
    comissaoLiberada: number | null;
  };
  lookups: OrderLookups;
  recentOrders: RecentOrder[];
  recentCreditDecisions: RecentCreditDecision[];
  recentReceipts: RecentReceipt[];
  recentCommissionReleases: RecentCommissionRelease[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export type PortfolioClient = {
  linkId: number;
  clientId: number;
  clientName: string;
  propertyId: number | null;
  propertyName: string | null;
  sellerName: string;
  availableLimit: number | null;
  creditStatus: string;
};

export type ScopedOrder = {
  id: number;
  code: string;
  clientId: number;
  clientName: string;
  propertyName: string | null;
  sellerId: number | null;
  sellerName: string | null;
  status: string;
  type: string;
  orderDate: string;
  total: number;
};

export type ApprovalOrder = {
  id: number;
  code: string;
  clientId: number;
  clientName: string;
  sellerId: number;
  sellerName: string;
  orderDate: string;
  total: number;
  availableLimit: number | null;
  creditStatus: string;
};

export type SalesItem = { id: number; label: string };

export type ExchangeSourceItem = {
  id: number;
  orderId: number;
  orderCode: string;
  clientId: number;
  productPackagingId: number;
  label: string;
  quantity: number;
};

export type OrderContractItem = {
  id: number;
  product: string;
  packaging: string;
  quantity: number;
  unitPrice: number;
  total: number;
  volumeLiters: number | null;
  logisticVolumes: number | null;
  grossWeightKg: number | null;
};

export type OrderContract = {
  id: number;
  code: string;
  status: string;
  type: string;
  orderDate: string;
  deliveryDate: string | null;
  paymentTerms: string | null;
  observation: string | null;
  total: number;
  totalVolumeLiters: number | null;
  totalLogisticVolumes: number | null;
  totalGrossWeightKg: number | null;
  client: {
    name: string;
    city: string;
    state: string;
    propertyName: string | null;
    propertyCity: string | null;
    propertyState: string | null;
    documents: Array<{ type: string; number: string }>;
    contacts: Array<{ name: string; role: string; phone: string | null; email: string | null }>;
  };
  sellerName: string | null;
  approvedAt: string | null;
  approvedBy: string | null;
  items: OrderContractItem[];
};

export async function getOrderWorkspace(search: string | null) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return { clients: [] as PortfolioClient[], orders: [] as ScopedOrder[], approvals: [] as ApprovalOrder[], items: [] as SalesItem[], exchangeItems: [] as ExchangeSourceItem[], error: "Banco de homologação indisponível." };
  }
  try {
    const supabase = await createSupabaseServerClient();
    const normalizedSearch = search?.trim() ?? "";
    const [clients, orders, approvals, items] = await Promise.all([
      normalizedSearch.length >= 2
        ? supabase.rpc("consultar_com_carteira_clientes", { p_busca: normalizedSearch })
        : Promise.resolve({ data: [], error: null }),
      supabase.rpc("consultar_com_pedidos_escopo", { p_limite: 120 }),
      supabase.rpc("consultar_com_pedidos_aprovacao"),
      supabase.from("cad_produto_embalagens")
        .select("id,codigo_item,status,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros)")
        .eq("status", "active").order("codigo_item").limit(250)
    ]);
    const scopedOrders = (orders.data ?? []) as Array<Record<string, unknown>>;
    const orderIds = scopedOrders.map((row) => Number(row.pedido_id)).filter((id) => Number.isInteger(id) && id > 0);
    const exchangeSource = orderIds.length
      ? await supabase
          .from("com_pedido_itens")
          .select("id,pedido_id,produto_embalagem_id,quantidade,status,cad_produto_embalagens(codigo_item,cad_produtos_base(nome),cad_embalagens(descricao))")
          .in("pedido_id", orderIds)
          .eq("status", "active")
          .order("created_at", { ascending: false })
          .limit(300)
      : { data: [], error: null };
    const orderById = new Map(scopedOrders.map((row) => [Number(row.pedido_id), row]));
    const error = clients.error?.message ?? orders.error?.message ?? approvals.error?.message ?? items.error?.message ?? exchangeSource.error?.message ?? null;
    return {
      clients: ((clients.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
        linkId: Number(row.vinculo_id), clientId: Number(row.cliente_id), clientName: String(row.cliente_nome),
        propertyId: nullableNumber(row.propriedade_id), propertyName: row.propriedade_nome ? String(row.propriedade_nome) : null,
        sellerName: String(row.vendedor_nome), availableLimit: nullableNumber(row.limite_disponivel), creditStatus: String(row.status_credito)
      })),
      orders: scopedOrders.map((row) => ({
        id: Number(row.pedido_id), code: String(row.codigo_pedido), clientId: Number(row.cliente_id), clientName: String(row.cliente_nome),
        propertyName: row.propriedade_nome ? String(row.propriedade_nome) : null, sellerId: nullableNumber(row.vendedor_id),
        sellerName: row.vendedor_nome ? String(row.vendedor_nome) : null, status: String(row.status), type: String(row.tipo_pedido),
        orderDate: String(row.data_pedido), total: Number(row.valor_total ?? 0)
      })),
      approvals: ((approvals.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
        id: Number(row.pedido_id), code: String(row.codigo_pedido), clientId: Number(row.cliente_id), clientName: String(row.cliente_nome),
        sellerId: Number(row.vendedor_id), sellerName: String(row.vendedor_nome), orderDate: String(row.data_pedido),
        total: Number(row.valor_total ?? 0), availableLimit: nullableNumber(row.limite_disponivel), creditStatus: String(row.status_credito)
      })),
      items: ((items.data ?? []) as Array<Record<string, unknown>>).map((row) => {
        const product = firstNested(row.cad_produtos_base); const pack = firstNested(row.cad_embalagens);
        return { id: Number(row.id), label: `${row.codigo_item} - ${product?.nome ?? "Produto"} - ${pack?.descricao ?? "Embalagem"}` };
      }),
      exchangeItems: ((exchangeSource.data ?? []) as Array<Record<string, unknown>>).map((row) => {
        const order = orderById.get(Number(row.pedido_id));
        const presentation = firstNested(row.cad_produto_embalagens);
        const product = firstNested(presentation?.cad_produtos_base);
        const pack = firstNested(presentation?.cad_embalagens);
        return {
          id: Number(row.id),
          orderId: Number(row.pedido_id),
          orderCode: String(order?.codigo_pedido ?? `Pedido ${row.pedido_id}`),
          clientId: Number(order?.cliente_id ?? 0),
          productPackagingId: Number(row.produto_embalagem_id),
          label: `${presentation?.codigo_item ?? "Item"} - ${product?.nome ?? "Produto"} - ${pack?.descricao ?? "Apresentação"}`,
          quantity: Number(row.quantidade ?? 0)
        };
      }),
      error
    };
  } catch {
    return { clients: [] as PortfolioClient[], orders: [] as ScopedOrder[], approvals: [] as ApprovalOrder[], items: [] as SalesItem[], exchangeItems: [] as ExchangeSourceItem[], error: "Não foi possível carregar Pedidos agora." };
  }
}

export async function getOrderContract(orderId: number): Promise<OrderContract | null> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured || !Number.isInteger(orderId) || orderId <= 0) return null;

  const supabase = await createSupabaseServerClient();
  const orderResult = await supabase
    .from("com_pedidos")
    .select("id,codigo_pedido,cliente_id,propriedade_id,vendedor_gerador_id,tipo_pedido,status,data_pedido,previsao_entrega,condicao_pagamento,valor_total,observacao")
    .eq("id", orderId)
    .maybeSingle();
  if (orderResult.error || !orderResult.data || !["open", "fulfilled"].includes(String(orderResult.data.status))) return null;

  const order = orderResult.data as Record<string, unknown>;
  const clientId = Number(order.cliente_id);
  const propertyId = nullableNumber(order.propriedade_id);
  const sellerId = nullableNumber(order.vendedor_gerador_id);
  const [clientResult, propertyResult, documentsResult, contactsResult, sellerResult, itemsResult, approvalResult] = await Promise.all([
    supabase.from("cad_clientes").select("id,nome,cidade,uf").eq("id", clientId).maybeSingle(),
    propertyId
      ? supabase.from("cad_cliente_propriedades").select("id,nome,cidade,uf").eq("id", propertyId).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    supabase.from("cad_cliente_documentos").select("tipo,numero").eq("cliente_id", clientId).order("id"),
    supabase.from("cad_cliente_contatos").select("nome,papel,telefone,email").eq("cliente_id", clientId).eq("status", "active").order("id"),
    sellerId
      ? supabase.from("cad_pessoas_comerciais").select("nome").eq("id", sellerId).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    supabase.from("com_pedido_itens")
      .select("id,quantidade,valor_unitario,valor_total,status,cad_produto_embalagens(codigo_item,embalagem_id,unidades_por_volume_logistico,cad_produtos_base(nome,densidade_kg_l),cad_embalagens(descricao,volume_litros,unidade))")
      .eq("pedido_id", orderId).eq("status", "active").order("id"),
    supabase.from("com_pedido_credito_decisoes")
      .select("created_at,created_by").eq("pedido_id", orderId).eq("decisao", "liberado").order("created_at", { ascending: false }).limit(1).maybeSingle()
  ]);
  if (clientResult.error || !clientResult.data || itemsResult.error) return null;

  const itemRows = (itemsResult.data ?? []) as Array<Record<string, unknown>>;
  const packagingIds = [...new Set(itemRows.map((row) => nullableNumber(firstNested(row.cad_produto_embalagens)?.embalagem_id)).filter((id): id is number => id !== null))];
  const packagingConfigResult = packagingIds.length
    ? await supabase.from("cad_embalagem_configuracoes_atuais").select("embalagem_id,peso_tara_kg").in("embalagem_id", packagingIds)
    : { data: [], error: null };
  const tareByPackagingId = new Map(
    ((packagingConfigResult.data ?? []) as Array<Record<string, unknown>>).map((row) => [Number(row.embalagem_id), nullableNumber(row.peso_tara_kg)])
  );
  const contractItems: OrderContractItem[] = itemRows.map((row) => {
    const presentation = firstNested(row.cad_produto_embalagens);
    const product = firstNested(presentation?.cad_produtos_base);
    const packaging = firstNested(presentation?.cad_embalagens);
    const quantity = Number(row.quantidade ?? 0);
    const unitVolume = nullableNumber(packaging?.volume_litros);
    const unitsPerVolume = nullableNumber(presentation?.unidades_por_volume_logistico);
    const density = nullableNumber(product?.densidade_kg_l);
    const tare = tareByPackagingId.get(Number(presentation?.embalagem_id)) ?? null;
    const volumeLiters = unitVolume === null ? null : quantity * unitVolume;
    const logisticVolumes = unitsPerVolume === null ? null : Math.ceil(quantity / unitsPerVolume);
    const grossWeightKg = volumeLiters === null || logisticVolumes === null || density === null || tare === null
      ? null
      : volumeLiters * density + logisticVolumes * tare;
    return {
      id: Number(row.id),
      product: String(product?.nome ?? presentation?.codigo_item ?? "Produto"),
      packaging: packagingLabel(packaging),
      quantity,
      unitPrice: Number(row.valor_unitario ?? 0),
      total: Number(row.valor_total ?? 0),
      volumeLiters,
      logisticVolumes,
      grossWeightKg
    };
  });

  const approvalActorId = approvalResult.data?.created_by ? String(approvalResult.data.created_by) : null;
  const approvalActor = approvalActorId
    ? await supabase.from("user_profiles").select("display_name").eq("id", approvalActorId).maybeSingle()
    : { data: null };

  return {
    id: Number(order.id),
    code: String(order.codigo_pedido),
    status: String(order.status),
    type: String(order.tipo_pedido),
    orderDate: String(order.data_pedido),
    deliveryDate: nullableString(order.previsao_entrega),
    paymentTerms: nullableString(order.condicao_pagamento),
    observation: nullableString(order.observacao),
    total: Number(order.valor_total ?? 0),
    totalVolumeLiters: sumComplete(contractItems.map((item) => item.volumeLiters)),
    totalLogisticVolumes: sumComplete(contractItems.map((item) => item.logisticVolumes)),
    totalGrossWeightKg: sumComplete(contractItems.map((item) => item.grossWeightKg)),
    client: {
      name: String(clientResult.data.nome),
      city: String(clientResult.data.cidade),
      state: String(clientResult.data.uf),
      propertyName: propertyResult.data?.nome ? String(propertyResult.data.nome) : null,
      propertyCity: propertyResult.data?.cidade ? String(propertyResult.data.cidade) : null,
      propertyState: propertyResult.data?.uf ? String(propertyResult.data.uf) : null,
      documents: ((documentsResult.data ?? []) as Array<Record<string, unknown>>).map((row) => ({ type: String(row.tipo), number: String(row.numero) })),
      contacts: ((contactsResult.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
        name: String(row.nome), role: String(row.papel), phone: nullableString(row.telefone), email: nullableString(row.email)
      }))
    },
    sellerName: sellerResult.data?.nome ? String(sellerResult.data.nome) : null,
    approvedAt: approvalResult.data?.created_at ? String(approvalResult.data.created_at) : null,
    approvedBy: approvalActor.data?.display_name ? String(approvalActor.data.display_name) : null,
    items: contractItems
  };
}

function sumComplete(values: Array<number | null>): number | null {
  return values.some((value) => value === null) ? null : values.reduce<number>((sum, value) => sum + (value ?? 0), 0);
}

const EMPTY_LOOKUPS: OrderLookups = {
  clientes: [],
  propriedades: [],
  itensVendaveis: [],
  pessoasComerciais: [],
  pedidos: [],
  pedidoItens: []
};

export async function getOrdersDashboard(): Promise<OrdersDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [
      totalPedidos,
      rascunhos,
      abertos,
      bloqueados,
      totals,
      receivedTotals,
      commissionTotals,
      recentOrders,
      creditDecisions,
      recentReceipts,
      commissionReleases,
      lookups
    ] = await Promise.all([
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "draft"),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "open"),
      supabase.from("com_pedidos").select("*", { count: "exact", head: true }).eq("status", "blocked"),
      supabase.from("com_pedidos").select("valor_total,status").limit(1000),
      supabase.from("com_recebimentos").select("valor_recebido").limit(1000),
      supabase.from("com_comissao_liberacoes").select("valor_liberado,status").limit(1000),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,propriedade_id,sequencia_propriedade,vendedor_gerador_id,tipo_pedido,status,data_pedido,valor_total,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_pedido_credito_decisoes")
        .select("id,pedido_id,decisao,status_anterior,status_resultante,motivo,limite_disponivel_snapshot,inadimplencia_snapshot,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_recebimentos")
        .select("id,pedido_id,valor_recebido,data_recebimento,forma_recebimento,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      supabase
        .from("com_comissao_liberacoes")
        .select("id,recebimento_id,pedido_id,pessoa_id,valor_liberado,percentual_recebido_snapshot,status,created_at")
        .order("created_at", { ascending: false })
        .limit(8),
      getOrderLookups(supabase)
    ]);

    const totalRows = totals.error ? [] : ((totals.data ?? []) as Array<{ valor_total: number | string | null; status: string }>);
    const receivedRows = receivedTotals.error ? [] : ((receivedTotals.data ?? []) as Array<{ valor_recebido: number | string | null }>);
    const commissionRows = commissionTotals.error
      ? []
      : ((commissionTotals.data ?? []) as Array<{ valor_liberado: number | string | null; status: string }>);

    return {
      metrics: {
        totalPedidos: totalPedidos.count ?? null,
        rascunhos: rascunhos.count ?? null,
        abertos: abertos.count ?? null,
        bloqueados: bloqueados.count ?? null,
        faturamentoPrevisto: totalRows
          .filter((row) => row.status !== "cancelled")
          .reduce((sum, row) => sum + Number(row.valor_total ?? 0), 0),
        totalRecebido: receivedRows.reduce((sum, row) => sum + Number(row.valor_recebido ?? 0), 0),
        comissaoLiberada: commissionRows
          .filter((row) => row.status === "liberada")
          .reduce((sum, row) => sum + Number(row.valor_liberado ?? 0), 0)
      },
      lookups,
      recentOrders: recentOrders.error
        ? []
        : ((recentOrders.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            codigoPedido: String(row.codigo_pedido),
            clienteId: Number(row.cliente_id),
            propriedadeId: nullableNumber(row.propriedade_id),
            sequenciaPropriedade: nullableNumber(row.sequencia_propriedade),
            vendedorGeradorId: nullableNumber(row.vendedor_gerador_id),
            tipoPedido: String(row.tipo_pedido),
            status: String(row.status),
            dataPedido: String(row.data_pedido),
            valorTotal: Number(row.valor_total ?? 0),
            createdAt: String(row.created_at)
          })),
      recentCreditDecisions: creditDecisions.error
        ? []
        : ((creditDecisions.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            pedidoId: Number(row.pedido_id),
            decisao: String(row.decisao),
            statusAnterior: String(row.status_anterior),
            statusResultante: String(row.status_resultante),
            motivo: row.motivo === null ? null : String(row.motivo),
            limiteDisponivelSnapshot:
              row.limite_disponivel_snapshot === null ? null : Number(row.limite_disponivel_snapshot),
            inadimplenciaSnapshot: row.inadimplencia_snapshot === null ? null : Number(row.inadimplencia_snapshot),
            createdAt: String(row.created_at)
          })),
      recentReceipts: recentReceipts.error
        ? []
        : ((recentReceipts.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            pedidoId: Number(row.pedido_id),
            valorRecebido: Number(row.valor_recebido ?? 0),
            dataRecebimento: String(row.data_recebimento),
            formaRecebimento: row.forma_recebimento === null ? null : String(row.forma_recebimento),
            createdAt: String(row.created_at)
          })),
      recentCommissionReleases: commissionReleases.error
        ? []
        : ((commissionReleases.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
            id: Number(row.id),
            recebimentoId: Number(row.recebimento_id),
            pedidoId: Number(row.pedido_id),
            pessoaId: Number(row.pessoa_id),
            valorLiberado: Number(row.valor_liberado ?? 0),
            percentualRecebidoSnapshot: Number(row.percentual_recebido_snapshot ?? 0),
            status: String(row.status),
            createdAt: String(row.created_at)
          })),
      source: "supabase",
      error:
        totalPedidos.error?.message ??
        rascunhos.error?.message ??
        abertos.error?.message ??
        bloqueados.error?.message ??
        totals.error?.message ??
        receivedTotals.error?.message ??
        commissionTotals.error?.message ??
        recentOrders.error?.message ??
        creditDecisions.error?.message ??
        recentReceipts.error?.message ??
        commissionReleases.error?.message ??
        null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getOrderLookups(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<OrderLookups> {
  try {
    const [clientes, propriedades, itensVendaveis, pessoasComerciais, pedidos, pedidoItens] = await Promise.all([
      supabase
        .from("cad_clientes")
        .select("id,nome,cidade,uf,status")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_cliente_propriedades")
        .select("id,cliente_id,nome,cidade,uf,status")
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(200),
      supabase
        .from("cad_produto_embalagens")
        .select("id,codigo_item,status,produto_id,embalagem_id,cad_produtos_base(codigo_produto,nome),cad_embalagens(descricao,volume_litros,unidade)")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,tipo_pedido,status,valor_total")
        .in("status", ["draft", "open", "blocked"])
        .order("created_at", { ascending: false })
        .limit(120),
      supabase
        .from("com_pedido_itens")
        .select("id,pedido_id,produto_embalagem_id,tipo_item,quantidade,status")
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(120)
    ]);

    return {
      clientes: clientes.error
        ? []
        : ((clientes.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `${item.cidade ?? "sem cidade"} / ${item.uf ?? "sem UF"} / ${item.status ?? "sem status"}`
          })),
      propriedades: propriedades.error
        ? []
        : ((propriedades.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `cliente ${item.cliente_id} / ${item.cidade ?? "sem cidade"} / ${item.uf ?? "sem UF"}`
          })),
      itensVendaveis: itensVendaveis.error
        ? []
        : ((itensVendaveis.data ?? []) as Array<Record<string, unknown>>).map((item) => {
            const produto = firstNested(item.cad_produtos_base);
            const embalagem = firstNested(item.cad_embalagens);
            const produtoLabel = produto ? `${produto.codigo_produto ?? ""} ${produto.nome ?? ""}`.trim() : `produto ${item.produto_id}`;
            const embalagemLabel = embalagem ? `${embalagem.descricao ?? ""}`.trim() : `embalagem ${item.embalagem_id}`;
            return {
              id: Number(item.id),
              label: `${item.codigo_item} - ${produtoLabel}`,
              detail: `${embalagemLabel} / ${item.status ?? "sem status"}`
            };
          }),
      pessoasComerciais: pessoasComerciais.error
        ? []
        : ((pessoasComerciais.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.nome),
            detail: `${item.tipo_comercial ?? "sem tipo"} / ${item.status ?? "sem status"}`
          })),
      pedidos: pedidos.error
        ? []
        : ((pedidos.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: String(item.codigo_pedido),
            detail: `cliente ${item.cliente_id} / ${item.tipo_pedido} / ${item.status} / ${Number(item.valor_total ?? 0).toFixed(2)}`
          })),
      pedidoItens: pedidoItens.error
        ? []
        : ((pedidoItens.data ?? []) as Array<Record<string, unknown>>).map((item) => ({
            id: Number(item.id),
            label: `pedido ${item.pedido_id} / item ${item.produto_embalagem_id}`,
            detail: `${item.tipo_item} / qtd ${Number(item.quantidade ?? 0).toFixed(4)} / ${item.status ?? "sem status"}`
          }))
    };
  } catch {
    return EMPTY_LOOKUPS;
  }
}

function firstNested(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    return (value[0] as Record<string, unknown> | undefined) ?? null;
  }
  if (value && typeof value === "object") {
    return value as Record<string, unknown>;
  }
  return null;
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined || String(value).trim() === "" ? null : String(value);
}

function packagingLabel(packaging: Record<string, unknown> | null): string {
  if (!packaging) return "Embalagem não informada";
  const description = nullableString(packaging.descricao) ?? "Embalagem";
  const volume = nullableNumber(packaging.volume_litros);
  const unit = nullableString(packaging.unidade);
  const capacity = volume === null ? null : `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(volume)} L`;
  return [description, capacity, unit].filter(Boolean).join(" - ");
}

function emptyDashboard(source: OrdersDashboard["source"], error: string | null): OrdersDashboard {
  return {
    metrics: {
      totalPedidos: null,
      rascunhos: null,
      abertos: null,
      bloqueados: null,
      faturamentoPrevisto: null,
      totalRecebido: null,
      comissaoLiberada: null
    },
    lookups: EMPTY_LOOKUPS,
    recentOrders: [],
    recentCreditDecisions: [],
    recentReceipts: [],
    recentCommissionReleases: [],
    source,
    error
  };
}
