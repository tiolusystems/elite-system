import { createSupabaseServerClient } from "@/lib/supabase/server";

export const CORPORATE_LOOKUP_ENTITIES = [
  "clientes",
  "pessoas",
  "produtos",
  "materias-primas",
  "pedidos",
  "romaneios",
  "lotes-pa",
  "veiculos",
  "propriedades"
] as const;

export type CorporateLookupEntity = (typeof CORPORATE_LOOKUP_ENTITIES)[number];

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
    let builder = supabase.from("cad_materias_primas").select("id,sku,nome,status", { count: "exact" });
    if (query) builder = builder.or(`sku.ilike.%${escapeFilter(query)}%,nome.ilike.%${escapeFilter(query)}%,nome_norm.ilike.%${escapeFilter(normalize(query))}%`);
    const { data, error, count } = await builder.order("nome", { ascending: true }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({ id: Number(row.id), label: String(row.nome), detail: optional(row.sku), status: optional(row.status) })), page, pageSize, count ?? 0);
  }

  if (input.entity === "pedidos") {
    let builder = supabase.from("com_pedidos").select("id,codigo_pedido,data_pedido,status,cliente_id,cad_clientes(nome)", { count: "exact" });
    if (query) builder = builder.or(`codigo_pedido.ilike.%${escapeFilter(query)}%`);
    const { data, error, count } = await builder.order("data_pedido", { ascending: false }).order("id", { ascending: false }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    return pageResult(records(data).map((row) => ({
      id: Number(row.id),
      label: String(row.codigo_pedido),
      detail: joinDetail([nestedLabel(row.cad_clientes, "nome"), formatDate(row.data_pedido)]),
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
