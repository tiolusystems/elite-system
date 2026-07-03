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

export type MasterDataDashboard = {
  modules: MasterDataModule[];
  metrics: MasterDataMetric[];
  validationIssues: ValidationIssue[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
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
    const metrics = await Promise.all(
      MASTER_DATA_MODULES.map(async (module) => {
        const { count, error } = await supabase.from(module.table).select("*", { count: "exact", head: true });
        return {
          moduleKey: module.key,
          table: module.table,
          count: count ?? null,
          error: error?.message ?? null
        };
      })
    );
    const { data, error } = await supabase
      .from("cadastro_validation_issues")
      .select("id,entity,entity_key,severity,code,message,field,created_at")
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .limit(8);

    return {
      modules: MASTER_DATA_MODULES,
      metrics,
      validationIssues: error ? [] : ((data ?? []) as ValidationIssue[]),
      source: "supabase",
      error: error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
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
    source,
    error
  };
}
