import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CorporateLookupBehavior = "selection" | "search";
export type CorporateLookupScope = "corporate" | "commercial" | "production";

export type CorporateLookupContract = {
  label: string;
  behavior: CorporateLookupBehavior;
  scope: CorporateLookupScope;
};

export const CORPORATE_LOOKUP_CONTRACTS = {
  clientes: { label: "Cliente", behavior: "selection", scope: "corporate" },
  "clientes-carteira": { label: "Cliente da carteira", behavior: "search", scope: "commercial" },
  pessoas: { label: "Pessoa", behavior: "selection", scope: "corporate" },
  produtos: { label: "Produto", behavior: "selection", scope: "corporate" },
  "materias-primas": { label: "Matéria-prima", behavior: "selection", scope: "corporate" },
  pedidos: { label: "Pedido", behavior: "selection", scope: "corporate" },
  "pedidos-comissionamento": { label: "Venda para comissionamento", behavior: "selection", scope: "commercial" },
  "pedidos-romaneio": { label: "Pedido com saldo", behavior: "selection", scope: "corporate" },
  romaneios: { label: "Romaneio", behavior: "selection", scope: "corporate" },
  "lotes-pa": { label: "Lote PA", behavior: "selection", scope: "corporate" },
  veiculos: { label: "Veículo", behavior: "selection", scope: "corporate" },
  propriedades: { label: "Propriedade", behavior: "selection", scope: "corporate" },
  "ops-producao": { label: "Ordem de produção", behavior: "search", scope: "production" },
  "ops-cq-fila": { label: "OP aguardando CQ", behavior: "search", scope: "production" },
  "ops-cq-historico": { label: "OP finalizada", behavior: "search", scope: "production" },
  "ordens-envase": { label: "Ordem de envase", behavior: "search", scope: "production" },
  "estoque-itens": { label: "Produto ou matéria-prima", behavior: "search", scope: "production" }
} as const satisfies Record<string, CorporateLookupContract>;

export type CorporateLookupEntity = keyof typeof CORPORATE_LOOKUP_CONTRACTS;

export const CORPORATE_LOOKUP_ENTITIES =
  Object.keys(CORPORATE_LOOKUP_CONTRACTS) as CorporateLookupEntity[];

export type CorporateLookupOption = {
  id: number;
  label: string;
  detail: string | null;
  status: string | null;
};

export type CorporateLookupPage = {
  options: CorporateLookupOption[];
  page: number;
  pageSize: number;
  total: number;
  hasMore: boolean;
};

type LookupInput = {
  entity: CorporateLookupEntity;
  query?: string;
  page?: number;
  pageSize?: number;
  contextId?: number | null;
};

export function isCorporateLookupEntity(value: string): value is CorporateLookupEntity {
  return CORPORATE_LOOKUP_ENTITIES.includes(value as CorporateLookupEntity);
}

export async function searchCorporateLookup(input: LookupInput): Promise<CorporateLookupPage> {
  const supabase = await createSupabaseServerClient();
  const page = Math.max(1, Math.trunc(input.page ?? 1));
  const pageSize = Math.min(25, Math.max(10, Math.trunc(input.pageSize ?? 20)));
  const offset = (page - 1) * pageSize;
  const query = input.query?.trim() ?? "";

  if (
    input.entity === "ops-producao"
    || input.entity === "ops-cq-fila"
    || input.entity === "ops-cq-historico"
  ) {
    let formulaIds: number[] = [];
    if (query) {
      const safeQuery = escapeFilter(query);
      const productResponse = await supabase
        .from("cad_produtos_base")
        .select("id")
        .or(`codigo_produto.ilike.%${safeQuery}%,nome.ilike.%${safeQuery}%`)
        .limit(500);
      if (productResponse.error) throw productResponse.error;

      const productIds = uniqueNumbers(records(productResponse.data).map((row) => row.id));
      if (productIds.length > 0) {
        const formulaResponse = await supabase
          .from("pcp_formula_versoes")
          .select("id")
          .in("produto_id", productIds)
          .limit(1000);
        if (formulaResponse.error) throw formulaResponse.error;
        formulaIds = uniqueNumbers(records(formulaResponse.data).map((row) => row.id));
      }
    }

    let builder = supabase
      .from("pcp_ordens_producao")
      .select("id,codigo_op,formula_versao_id,tipo_op,status", { count: "exact" });

    if (input.entity === "ops-cq-fila") {
      builder = builder.eq("status", "in_process");
    } else if (input.entity === "ops-cq-historico") {
      builder = builder.eq("status", "completed");
    }

    if (query) {
      const safeQuery = escapeFilter(query);
      builder = formulaIds.length > 0
        ? builder.or(`codigo_op.ilike.%${safeQuery}%,formula_versao_id.in.(${formulaIds.join(",")})`)
        : builder.ilike("codigo_op", `%${safeQuery}%`);
    }

    const response = await builder
      .order("id", { ascending: false })
      .range(offset, offset + pageSize - 1);
    if (response.error) throw response.error;

    const opRows = records(response.data);
    const returnedFormulaIds = uniqueNumbers(opRows.map((row) => row.formula_versao_id));
    const formulaMap = new Map<number, string>();

    if (returnedFormulaIds.length > 0) {
      const formulaResponse = await supabase
        .from("pcp_formula_versoes")
        .select("id,versao,produto_id,cad_produtos_base(codigo_produto,nome)")
        .in("id", returnedFormulaIds);
      if (formulaResponse.error) throw formulaResponse.error;

      for (const row of records(formulaResponse.data)) {
        const productCode = nestedLabel(row.cad_produtos_base, "codigo_produto");
        const productName = nestedLabel(row.cad_produtos_base, "nome");
        const productLabel = joinDetail([productCode, productName]) ?? "Produto não identificado";
        formulaMap.set(Number(row.id), `${productLabel} · fórmula v${Number(row.versao)}`);
      }
    }

    return pageResult(opRows.map((row) => ({
      id: Number(row.id),
      label: String(row.codigo_op),
      detail: joinDetail([
        formulaMap.get(Number(row.formula_versao_id)) ?? null,
        productionOpTypeLabel(row.tipo_op)
      ]),
      status: optional(row.status)
    })), page, pageSize, response.count ?? 0);
  }

  if (input.entity === "ordens-envase") {
    let builder = supabase
      .from("pcp_ordens_envase_dossie")
      .select("id,codigo_ordem,codigo_op_mapa,produto_nome,embalagem_descricao,status,emitida_em", { count: "exact" });

    if (query) {
      const safeQuery = escapeFilter(query);
      builder = builder.or(
        `codigo_ordem.ilike.%${safeQuery}%,codigo_op_mapa.ilike.%${safeQuery}%,produto_nome.ilike.%${safeQuery}%`
      );
    }

    const response = await builder
      .order("emitida_em", { ascending: false })
      .range(offset, offset + pageSize - 1);
    if (response.error) throw response.error;

    return pageResult(records(response.data).map((row) => ({
      id: Number(row.id),
      label: String(row.codigo_ordem),
      detail: joinDetail([
        optional(row.produto_nome),
        optional(row.embalagem_descricao),
        optional(row.codigo_op_mapa)
      ]),
      status: optional(row.status)
    })), page, pageSize, response.count ?? 0);
  }

  if (input.entity === "estoque-itens") {
    const safeQuery = escapeFilter(query);

    let productBuilder = supabase
      .from("cad_produtos_base")
      .select("id,codigo_produto,nome,status")
      .order("nome", { ascending: true })
      .limit(pageSize);
    let materialBuilder = supabase
      .from("cad_materias_primas")
      .select("id,sku_corrigido,nome,status")
      .order("nome", { ascending: true })
      .limit(pageSize);

    if (safeQuery) {
      productBuilder = productBuilder.or(
        `codigo_produto.ilike.%${safeQuery}%,nome.ilike.%${safeQuery}%`
      );
      materialBuilder = materialBuilder.or(
        `sku_corrigido.ilike.%${safeQuery}%,nome.ilike.%${safeQuery}%`
      );
    }

    const [productResponse, materialResponse] = await Promise.all([
      productBuilder,
      materialBuilder
    ]);
    if (productResponse.error) throw productResponse.error;
    if (materialResponse.error) throw materialResponse.error;

    const combined: CorporateLookupOption[] = [
      ...records(productResponse.data).map((row) => ({
        id: 1_000_000_000 + Number(row.id),
        label: String(row.nome),
        detail: joinDetail(["Produto", optional(row.codigo_produto)]),
        status: optional(row.status)
      })),
      ...records(materialResponse.data).map((row) => ({
        id: -Number(row.id),
        label: String(row.nome),
        detail: joinDetail(["MP", optional(row.sku_corrigido)]),
        status: optional(row.status)
      }))
    ];

    combined.sort((left, right) => left.label.localeCompare(right.label, "pt-BR"));
    const options = combined.slice(0, pageSize);
    return {
      options,
      page: 1,
      pageSize,
      total: options.length,
      hasMore: false
    };
  }

  if (input.entity === "clientes-carteira") {
    const response = await supabase.rpc("consultar_com_carteira_clientes_paginada", {
      p_busca: query || null,
      p_limite: pageSize + 1,
      p_offset: offset
    });
    if (response.error) throw response.error;

    const resultRows = records(response.data);
    const hasMore = resultRows.length > pageSize;
    const visibleRows = resultRows.slice(0, pageSize);
    const minimumTotal = offset + visibleRows.length + (hasMore ? 1 : 0);

    return {
      options: visibleRows.map((row) => ({
        id: Number(row.vinculo_id),
        label: String(row.cliente_nome),
        detail: joinDetail([
          optional(row.nome_fantasia) !== optional(row.cliente_nome) ? optional(row.nome_fantasia) : null,
          optional(row.documento_principal),
          joinDetail([optional(row.municipio), optional(row.uf)]),
          optional(row.vendedor_nome)
        ]),
        status: optional(row.situacao)
      })),
      page,
      pageSize,
      total: minimumTotal,
      hasMore
    };
  }

  if (input.entity === "clientes") {
    const { data, error } = await supabase.rpc("consultar_cad_clientes_paginada", {
      p_busca: query || null,
      p_situacao: null,
      p_ordenacao: "nome_asc",
      p_limite: pageSize,
      p_offset: offset
    });
    if (error) throw error;
    const rows = records(data);
    const total = Number(rows[0]?.total_registros ?? 0);
    return pageResult(rows.map((row) => ({
      id: Number(row.cliente_id),
      label: String(row.razao_social || row.nome),
      detail: joinDetail([optional(row.nome_fantasia), optional(row.documento_principal), location(row.cidade, row.uf)]),
      status: optional(row.situacao)
    })), page, pageSize, total);
  }

  if (input.entity === "pessoas") {
    let builder = supabase.from("cad_pessoas_comerciais").select("id,nome,papeis_json,status", { count: "exact" });
    if (query) builder = builder.or(`nome.ilike.%${escapeFilter(query)}%,nome_norm.ilike.%${escapeFilter(normalize(query))}%`);
    const { data, error, count } = await builder.order("nome", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({
      id: Number(row.id),
      label: String(row.nome),
      detail: roles(row.papeis_json),
      status: optional(row.status)
    })), page, pageSize, count ?? 0);
  }

  if (input.entity === "produtos") {
    let builder = supabase.from("cad_produtos_base").select("id,codigo_produto,nome,status", { count: "exact" });
    if (query) builder = builder.or(`codigo_produto.ilike.%${escapeFilter(query)}%,nome.ilike.%${escapeFilter(query)}%,nome_norm.ilike.%${escapeFilter(normalize(query))}%`);
    const { data, error, count } = await builder.order("nome", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.nome), detail: optional(row.codigo_produto), status: optional(row.status) })), page, pageSize, count ?? 0);
  }

  if (input.entity === "materias-primas") {
    let builder = supabase.from("cad_materias_primas").select("id,sku_corrigido,nome,status", { count: "exact" });
    if (query) builder = builder.or(`sku_corrigido.ilike.%${escapeFilter(query)}%,nome.ilike.%${escapeFilter(query)}%,nome_norm.ilike.%${escapeFilter(normalize(query))}%`);
    const { data, error, count } = await builder.order("nome", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.nome), detail: optional(row.sku_corrigido), status: optional(row.status) })), page, pageSize, count ?? 0);
  }

  if (input.entity === "pedidos-comissionamento") {
    const response = await supabase.rpc("buscar_fin_pedidos_comissionamento", {
      p_query: query || null,
      p_limit: pageSize,
      p_offset: offset,
    });
    if (response.error) throw response.error;
    const rows = records(response.data);
    return pageResult(rows.map((row) => ({
      id: Number(row.pedido_id),
      label: String(row.codigo_pedido),
      detail: joinDetail([optional(row.cliente_nome), "Venda liberada"]),
      status: optional(row.status),
    })), page, pageSize, Number(rows[0]?.total_count ?? 0));
  }

  if (input.entity === "pedidos" || input.entity === "pedidos-romaneio") {
    let builder = supabase.from("com_pedidos").select("id,codigo_pedido,data_pedido,status,cliente_id,cad_clientes(nome)", { count: "exact" });
    if (query) builder = builder.or(`codigo_pedido.ilike.%${escapeFilter(query)}%`);
    const { data, error, count } = await builder.order("data_pedido", { ascending: false }).order("id", { ascending: false }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    const orderRows = records(data);
    if (input.entity === "pedidos") {
      return pageResult(orderRows.map((row) => ({
        id: Number(row.id),
        label: String(row.codigo_pedido),
        detail: joinDetail([nestedLabel(row.cad_clientes, "nome"), formatDate(row.data_pedido)]),
        status: optional(row.status)
      })), page, pageSize, count ?? 0);
    }
    const orderIds = orderRows.map((row) => Number(row.id));
    const balanceResponse = orderIds.length
      ? await supabase
          .from("exp_pedido_item_romaneio_saldos")
          .select("pedido_id,quantidade_disponivel_romaneio")
          .in("pedido_id", orderIds)
          .gt("quantidade_disponivel_romaneio", 0)
      : { data: [], error: null };
    if (balanceResponse.error) throw balanceResponse.error;
    const availableItemsByOrder = new Map<number, number>();
    for (const balance of records(balanceResponse.data)) {
      const orderId = Number(balance.pedido_id);
      availableItemsByOrder.set(orderId, (availableItemsByOrder.get(orderId) ?? 0) + 1);
    }
    return pageResult(orderRows.map((row) => ({
      id: Number(row.id),
      label: String(row.codigo_pedido),
      detail: joinDetail([
        nestedLabel(row.cad_clientes, "nome"),
        formatDate(row.data_pedido),
        availableItemsLabel(availableItemsByOrder.get(Number(row.id)) ?? 0)
      ]),
      status: optional(row.status)
    })), page, pageSize, count ?? 0);
  }

  if (input.entity === "romaneios") {
    let builder = supabase.from("exp_romaneios").select("id,codigo_romaneio,data_romaneio,status,pedido_id", { count: "exact" });
    if (query) builder = builder.ilike("codigo_romaneio", `%${escapeFilter(query)}%`);
    const { data, error, count } = await builder.order("data_romaneio", { ascending: false }).order("id", { ascending: false }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.codigo_romaneio), detail: formatDate(row.data_romaneio), status: optional(row.status) })), page, pageSize, count ?? 0);
  }

  if (input.entity === "lotes-pa") {
    let builder = supabase.from("est_lotes_pa_saldos").select("lote_pa_id,codigo_lote,status,saldo_disponivel,produto_embalagem_id", { count: "exact" });
    if (query) builder = builder.ilike("codigo_lote", `%${escapeFilter(query)}%`);
    const { data, error, count } = await builder.order("codigo_lote", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({
      id: Number(row.lote_pa_id),
      label: String(row.codigo_lote),
      detail: `Saldo disponivel: ${number(row.saldo_disponivel)}`,
      status: optional(row.status)
    })), page, pageSize, count ?? 0);
  }

  if (input.entity === "veiculos") {
    let builder = supabase.from("cad_veiculos").select("id,descricao,placa,status", { count: "exact" });
    if (query) builder = builder.or(`descricao.ilike.%${escapeFilter(query)}%,placa.ilike.%${escapeFilter(query)}%,placa_norm.ilike.%${escapeFilter(normalize(query))}%`);
    const { data, error, count } = await builder.order("descricao", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.descricao), detail: optional(row.placa), status: optional(row.status) })), page, pageSize, count ?? 0);
  }

  let builder = supabase.from("cad_cliente_propriedades").select("id,nome,cidade,uf,status,cliente_id", { count: "exact" });
  if (input.contextId) builder = builder.eq("cliente_id", input.contextId);
  if (query) builder = builder.or(`nome.ilike.%${escapeFilter(query)}%,cidade.ilike.%${escapeFilter(query)}%`);
  const { data, error, count } = await builder.order("nome", { ascending: true }).range(offset, offset + pageSize - 1);
  if (error) throw error;
  return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.nome), detail: location(row.cidade, row.uf), status: optional(row.status) })), page, pageSize, count ?? 0);
}

function pageResult(options: CorporateLookupOption[], page: number, pageSize: number, total: number): CorporateLookupPage {
  return { options, page, pageSize, total, hasMore: page * pageSize < total };
}

function records(value: unknown): Array<Record<string, unknown>> {
  return Array.isArray(value) ? value as Array<Record<string, unknown>> : [];
}

function optional(value: unknown): string | null {
  const text = value == null ? "" : String(value).trim();
  return text || null;
}

function joinDetail(values: Array<string | null>): string | null {
  const present = values.filter((value): value is string => Boolean(value));
  return present.length ? present.join(" · ") : null;
}

function location(city: unknown, state: unknown): string | null {
  return joinDetail([optional(city), optional(state)]);
}

function roles(value: unknown): string | null {
  const parsed = Array.isArray(value) ? value : [];
  return parsed.map(String).filter(Boolean).join(" · ") || null;
}

function nestedLabel(value: unknown, key: string): string | null {
  const record = Array.isArray(value) ? value[0] : value;
  return record && typeof record === "object" ? optional((record as Record<string, unknown>)[key]) : null;
}

function normalize(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9]/g, "").toLocaleLowerCase("pt-BR");
}

function escapeFilter(value: string): string {
  return value.replace(/[,%()]/g, " ").trim();
}

function formatDate(value: unknown): string | null {
  const raw = optional(value);
  if (!raw) return null;
  const date = new Date(`${raw}T00:00:00`);
  return Number.isNaN(date.valueOf()) ? raw : new Intl.DateTimeFormat("pt-BR").format(date);
}

function number(value: unknown): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(Number(value ?? 0));
}

function availableItemsLabel(count: number): string {
  if (count === 0) return "Sem saldo a entregar";
  return `${count} ${count === 1 ? "item com saldo" : "itens com saldo"}`;
}

function uniqueNumbers(values: unknown[]): number[] {
  return Array.from(new Set(
    values
      .map(Number)
      .filter((value) => Number.isSafeInteger(value) && value > 0)
  ));
}

function productionOpTypeLabel(value: unknown): string | null {
  const key = optional(value);
  if (!key) return null;
  return ({
    estoque: "Produção para estoque",
    experimental: "Experimental",
    desenvolvimento: "Desenvolvimento",
    reprocessamento: "Reprocessamento",
    mapa_documental: "MAPA documental"
  } as Record<string, string>)[key] ?? key;
}
