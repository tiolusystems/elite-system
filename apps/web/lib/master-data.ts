import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type MasterDataModule = {
  key: string;
  title: string;
  table: string;
  owner: string;
  requiredFields: string[];
  audit: string;
  status: "ready" | "building" | "blocked";
};

export type ValidationIssue = {
  id: number;
  entity: string;
  entity_key: string | null;
  severity: "error" | "warning";
  code: string;
  message: string;
  field: string | null;
  created_at: string;
};

export type MasterDataMetric = {
  moduleKey: string;
  table: string;
  count: number | null;
  error: string | null;
};

export type LookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type MasterDataLookups = {
  materiasPrimas: LookupOption[];
  produtos: LookupOption[];
  embalagens: LookupOption[];
  pessoasComerciais: LookupOption[];
};

export type MasterDataClient = {
  id: number;
  codigoLegado: string | null;
  nome: string;
  cidade: string;
  uf: string;
  status: string;
  apelidos: string[];
  valorTotalCompras: number | null;
};

export type MasterDataProperty = {
  id: number;
  clienteId: number;
  nome: string;
  cnpj: string | null;
  cidade: string | null;
  uf: string | null;
  status: string;
};

export type MasterDataClientSeller = {
  id: number;
  clienteId: number;
  pessoaId: number;
  propriedadeId: number | null;
  status: string;
  vigenciaInicio: string | null;
  vigenciaFim: string | null;
};

export type MasterDataDashboard = {
  modules: MasterDataModule[];
  metrics: MasterDataMetric[];
  validationIssues: ValidationIssue[];
  lookups: MasterDataLookups;
  clientes: MasterDataClient[];
  propriedades: MasterDataProperty[];
  clienteVendedores: MasterDataClientSeller[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_LOOKUPS: MasterDataLookups = {
  materiasPrimas: [],
  produtos: [],
  embalagens: [],
  pessoasComerciais: []
};

export const MASTER_DATA_MODULES: MasterDataModule[] = [
  {
    key: "clientes",
    title: "Clientes",
    table: "cad_clientes",
    owner: "Comercial",
    requiredFields: ["nome", "cidade", "uf", "status"],
    audit: "Duplicidade, unificacao, vendedor e credito",
    status: "ready"
  },
  {
    key: "pessoas",
    title: "Pessoas comerciais",
    table: "cad_pessoas_comerciais",
    owner: "Comercial",
    requiredFields: ["nome", "papeis", "status"],
    audit: "Alias, grafias, agentes, gerente e comissionado",
    status: "ready"
  },
  {
    key: "materias-primas",
    title: "Materias-primas",
    table: "cad_materias_primas",
    owner: "Estoque",
    requiredFields: ["sku_corrigido", "nome", "unidade_base_estoque"],
    audit: "SKU legado, unidade, conversao e garantias",
    status: "ready"
  },
  {
    key: "produtos",
    title: "Produtos",
    table: "cad_produtos_base",
    owner: "Producao",
    requiredFields: ["codigo_produto", "nome", "status"],
    audit: "Produto, embalagem, PI/PA e garantias MAPA",
    status: "ready"
  },
  {
    key: "embalagens",
    title: "Embalagens",
    table: "cad_embalagens",
    owner: "Estoque",
    requiredFields: ["descricao", "unidade", "status"],
    audit: "Volume, estoque de insumo e transformacoes",
    status: "ready"
  },
  {
    key: "produto-embalagens",
    title: "Itens vendaveis",
    table: "cad_produto_embalagens",
    owner: "Comercial",
    requiredFields: ["produto_id", "embalagem_id", "codigo_item"],
    audit: "Produto + embalagem usado no pedido, estoque PA e faturamento",
    status: "ready"
  },
  {
    key: "conversoes-mp",
    title: "Conversoes de MP",
    table: "cad_conversoes_unidade_mp",
    owner: "Estoque",
    requiredFields: ["materia_prima_id", "unidade_origem", "unidade_destino", "fator"],
    audit: "XML/NF em saca, ton, t ou unidade convertida para estoque base",
    status: "ready"
  },
  {
    key: "credito",
    title: "Credito do cliente",
    table: "cad_limites_credito_cliente",
    owner: "Financeiro",
    requiredFields: ["cliente_id", "limite_disponivel", "status_credito"],
    audit: "Snapshot de limite, inadimplencia e aprovacao",
    status: "ready"
  }
];

export async function getMasterDataDashboard(): Promise<MasterDataDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [metrics, validationResult, lookups, clientData] = await Promise.all([
      Promise.all(
        MASTER_DATA_MODULES.map(async (module) => {
          const { count, error } = await supabase.from(module.table).select("*", { count: "exact", head: true });
          return {
            moduleKey: module.key,
            table: module.table,
            count: count ?? null,
            error: error?.message ?? null
          };
        })
      ),
      supabase
        .from("cadastro_validation_issues")
        .select("id,entity,entity_key,severity,code,message,field,created_at")
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(8),
      getMasterDataLookups(supabase),
      getClientMasterData(supabase)
    ]);

    return {
      modules: MASTER_DATA_MODULES,
      metrics,
      validationIssues: validationResult.error ? [] : ((validationResult.data ?? []) as ValidationIssue[]),
      lookups,
      clientes: clientData.clientes,
      propriedades: clientData.propriedades,
      clienteVendedores: clientData.clienteVendedores,
      source: "supabase",
      error: validationResult.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getClientMasterData(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<Pick<MasterDataDashboard, "clientes" | "propriedades" | "clienteVendedores">> {
  const [clientsResult, propertiesResult, sellersResult] = await Promise.all([
    supabase
      .from("cad_clientes")
      .select("id,codigo_legado,nome,cidade,uf,status,apelidos_json,valor_total_compras")
      .order("nome", { ascending: true })
      .limit(250),
    supabase
      .from("cad_cliente_propriedades")
      .select("id,cliente_id,nome,cnpj,cidade,uf,status")
      .order("nome", { ascending: true })
      .limit(500),
    supabase
      .from("cad_cliente_vendedores")
      .select("id,cliente_id,pessoa_id,propriedade_id,status,vigencia_inicio,vigencia_fim")
      .order("vigencia_inicio", { ascending: false })
      .limit(500)
  ]);

  return {
    clientes: clientsResult.error
      ? []
      : (clientsResult.data ?? []).map((item) => ({
          id: Number(item.id),
          codigoLegado: item.codigo_legado,
          nome: item.nome,
          cidade: item.cidade,
          uf: item.uf,
          status: item.status,
          apelidos: Array.isArray(item.apelidos_json)
            ? item.apelidos_json.filter((value): value is string => typeof value === "string")
            : [],
          valorTotalCompras: item.valor_total_compras === null ? null : Number(item.valor_total_compras)
        })),
    propriedades: propertiesResult.error
      ? []
      : (propertiesResult.data ?? []).map((item) => ({
          id: Number(item.id),
          clienteId: Number(item.cliente_id),
          nome: item.nome,
          cnpj: item.cnpj,
          cidade: item.cidade,
          uf: item.uf,
          status: item.status
        })),
    clienteVendedores: sellersResult.error
      ? []
      : (sellersResult.data ?? []).map((item) => ({
          id: Number(item.id),
          clienteId: Number(item.cliente_id),
          pessoaId: Number(item.pessoa_id),
          propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id),
          status: item.status,
          vigenciaInicio: item.vigencia_inicio,
          vigenciaFim: item.vigencia_fim
        }))
  };
}

async function getMasterDataLookups(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<MasterDataLookups> {
  try {
    const [materiasPrimas, produtos, embalagens, pessoasComerciais] = await Promise.all([
      supabase
        .from("cad_materias_primas")
        .select("id,sku_corrigido,nome,unidade_base_estoque,status")
        .order("created_at", { ascending: false })
        .limit(80),
      supabase
        .from("cad_produtos_base")
        .select("id,codigo_produto,nome,status,prazo_validade_meses")
        .order("created_at", { ascending: false })
        .limit(80),
      supabase
        .from("cad_embalagens")
        .select("id,descricao,unidade,volume_litros,status")
        .order("created_at", { ascending: false })
        .limit(80),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .order("created_at", { ascending: false })
        .limit(80)
    ]);

    return {
      materiasPrimas: materiasPrimas.error
        ? []
        : (materiasPrimas.data ?? []).map((item) => ({
            id: Number(item.id),
            label: `${item.sku_corrigido} - ${item.nome}`,
            detail: `${item.unidade_base_estoque} / ${item.status}`
          })),
      produtos: produtos.error
        ? []
        : (produtos.data ?? []).map((item) => ({
            id: Number(item.id),
            label: `${item.codigo_produto} - ${item.nome}`,
            detail: `${item.status}${item.prazo_validade_meses ? ` / validade ${item.prazo_validade_meses} meses` : ""}`
          })),
      embalagens: embalagens.error
        ? []
        : (embalagens.data ?? []).map((item) => ({
            id: Number(item.id),
            label: item.descricao,
            detail: `${item.unidade}${item.volume_litros ? ` / ${item.volume_litros} L` : ""} / ${item.status}`
          })),
      pessoasComerciais: pessoasComerciais.error
        ? []
        : (pessoasComerciais.data ?? []).map((item) => ({
            id: Number(item.id),
            label: item.nome,
            detail: `${item.tipo_comercial ?? "sem tipo"} / ${item.status}`
          }))
    };
  } catch {
    return EMPTY_LOOKUPS;
  }
}

function emptyDashboard(source: MasterDataDashboard["source"], error: string | null): MasterDataDashboard {
  return {
    modules: MASTER_DATA_MODULES,
    metrics: MASTER_DATA_MODULES.map((module) => ({
      moduleKey: module.key,
      table: module.table,
      count: null,
      error: null
    })),
    validationIssues: [],
    lookups: EMPTY_LOOKUPS,
    clientes: [],
    propriedades: [],
    clienteVendedores: [],
    source,
    error
  };
}
