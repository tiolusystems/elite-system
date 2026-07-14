import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type TechnicalUnit = {
  id: number;
  code: string;
  name: string;
  symbol: string;
  dimension: string;
  status: string;
  source: string;
};

export type TechnicalNutrient = {
  id: number;
  name: string;
  symbol: string | null;
  status: string;
};

export type TechnicalMaterial = {
  id: number;
  legacyCode: string | null;
  sku: string;
  name: string;
  baseUnit: string;
  status: string;
  type: string | null;
  density: number | null;
  minimumStock: number | null;
  ncm: string | null;
  ibama: string | null;
  adsCode: string | null;
  source: string;
  updatedAt: string;
};

export type TechnicalConversion = {
  id: number;
  materialId: number;
  materialLabel: string;
  sourceUnit: string;
  targetUnit: string;
  factor: number;
  validFrom: string | null;
  validTo: string | null;
  reviewStatus: string;
};

export type TechnicalProduct = {
  id: number;
  code: string;
  name: string;
  status: string;
  group: string | null;
  density: number | null;
  shelfLifeMonths: number | null;
  mapaRegistration: string | null;
  ncm: string | null;
  ibama: string | null;
  ads: string | null;
  source: string;
};

export type TechnicalProductGroup = {
  id: number;
  code: string;
  name: string;
  status: string;
};

export type TechnicalPackage = {
  id: number;
  legacyCode: string | null;
  description: string;
  unit: string;
  volumeLiters: number | null;
  controlsStock: boolean;
  materialId: number | null;
  materialLabel: string | null;
  status: string;
  source: string;
};

export type TechnicalSaleItem = {
  id: number;
  code: string;
  productId: number;
  productLabel: string;
  packageId: number;
  packageLabel: string;
  status: string;
};

export type TechnicalCatalog = {
  units: TechnicalUnit[];
  nutrients: TechnicalNutrient[];
  materials: TechnicalMaterial[];
  conversions: TechnicalConversion[];
  products: TechnicalProduct[];
  productGroups: TechnicalProductGroup[];
  packages: TechnicalPackage[];
  saleItems: TechnicalSaleItem[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_CATALOG: Omit<TechnicalCatalog, "source" | "error"> = {
  units: [],
  nutrients: [],
  materials: [],
  conversions: [],
  products: [],
  productGroups: [],
  packages: [],
  saleItems: []
};

export async function getTechnicalCatalog(): Promise<TechnicalCatalog> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return { ...EMPTY_CATALOG, source: "not_configured", error: null };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [units, nutrients, materials, conversions, products, productGroups, packages, saleItems] = await Promise.all([
      supabase
        .from("cad_unidades_medida")
        .select("id,codigo,nome,simbolo,dimensao,status,origem_dados")
        .order("codigo", { ascending: true })
        .limit(300),
      supabase
        .from("cad_nutrientes")
        .select("id,nome,simbolo,status")
        .order("nome", { ascending: true })
        .limit(300),
      supabase
        .from("cad_materias_primas")
        .select(
          "id,codigo_legado,sku_corrigido,nome,unidade_base_estoque,status,tipo,densidade,estoque_minimo,ncm,ibama,codigo_ads,origem_dados,updated_at"
        )
        .order("nome", { ascending: true })
        .limit(800),
      supabase
        .from("cad_conversoes_unidade_mp")
        .select(
          "id,materia_prima_id,unidade_origem,unidade_destino,fator,vigencia_inicio,vigencia_fim,review_status"
        )
        .order("materia_prima_id", { ascending: true })
        .limit(800),
      supabase
        .from("cad_produtos_base")
        .select(
          "id,codigo_produto,nome,status,grupo,densidade_kg_l,prazo_validade_meses,reg_mapa,ncm,ibama,ads,origem_dados"
        )
        .order("codigo_produto", { ascending: true })
        .limit(800),
      supabase
        .from("cad_grupos_produto")
        .select("id,codigo,nome,status")
        .order("nome", { ascending: true })
        .limit(300),
      supabase
        .from("cad_embalagens")
        .select(
          "id,codigo_legado,descricao,unidade,volume_litros,controla_estoque,materia_prima_id,status,origem_dados"
        )
        .order("descricao", { ascending: true })
        .limit(800),
      supabase
        .from("cad_produto_embalagens")
        .select("id,codigo_item,produto_id,embalagem_id,status")
        .order("codigo_item", { ascending: true })
        .limit(1000)
    ]);

    const firstError = [units, nutrients, materials, conversions, products, productGroups, packages, saleItems].find(
      (result) => result.error
    )?.error;
    if (firstError) {
      return { ...EMPTY_CATALOG, source: "error", error: firstError.message };
    }

    const materialRows = materials.data ?? [];
    const productRows = products.data ?? [];
    const packageRows = packages.data ?? [];
    const materialLabels = new Map(
      materialRows.map((item) => [Number(item.id), `${item.sku_corrigido} - ${item.nome}`])
    );
    const productLabels = new Map(
      productRows.map((item) => [Number(item.id), `${item.codigo_produto} - ${item.nome}`])
    );
    const packageLabels = new Map(packageRows.map((item) => [Number(item.id), String(item.descricao)]));

    return {
      units: (units.data ?? []).map((item) => ({
        id: Number(item.id),
        code: String(item.codigo),
        name: String(item.nome),
        symbol: String(item.simbolo),
        dimension: String(item.dimensao),
        status: String(item.status),
        source: String(item.origem_dados)
      })),
      nutrients: (nutrients.data ?? []).map((item) => ({
        id: Number(item.id),
        name: String(item.nome),
        symbol: item.simbolo ? String(item.simbolo) : null,
        status: String(item.status)
      })),
      materials: materialRows.map((item) => ({
        id: Number(item.id),
        legacyCode: item.codigo_legado ? String(item.codigo_legado) : null,
        sku: String(item.sku_corrigido),
        name: String(item.nome),
        baseUnit: String(item.unidade_base_estoque),
        status: String(item.status),
        type: item.tipo ? String(item.tipo) : null,
        density: toNullableNumber(item.densidade),
        minimumStock: toNullableNumber(item.estoque_minimo),
        ncm: item.ncm ? String(item.ncm) : null,
        ibama: item.ibama ? String(item.ibama) : null,
        adsCode: item.codigo_ads ? String(item.codigo_ads) : null,
        source: String(item.origem_dados ?? "sistema"),
        updatedAt: String(item.updated_at)
      })),
      conversions: (conversions.data ?? []).map((item) => ({
        id: Number(item.id),
        materialId: Number(item.materia_prima_id),
        materialLabel: materialLabels.get(Number(item.materia_prima_id)) ?? `MP #${item.materia_prima_id}`,
        sourceUnit: String(item.unidade_origem),
        targetUnit: String(item.unidade_destino),
        factor: Number(item.fator),
        validFrom: item.vigencia_inicio ? String(item.vigencia_inicio) : null,
        validTo: item.vigencia_fim ? String(item.vigencia_fim) : null,
        reviewStatus: String(item.review_status ?? "approved")
      })),
      products: productRows.map((item) => ({
        id: Number(item.id),
        code: String(item.codigo_produto),
        name: String(item.nome),
        status: String(item.status),
        group: item.grupo ? String(item.grupo) : null,
        density: toNullableNumber(item.densidade_kg_l),
        shelfLifeMonths: toNullableNumber(item.prazo_validade_meses),
        mapaRegistration: item.reg_mapa ? String(item.reg_mapa) : null,
        ncm: item.ncm ? String(item.ncm) : null,
        ibama: item.ibama ? String(item.ibama) : null,
        ads: item.ads ? String(item.ads) : null,
        source: String(item.origem_dados ?? "sistema")
      })),
      productGroups: (productGroups.data ?? []).map((item) => ({
        id: Number(item.id),
        code: String(item.codigo),
        name: String(item.nome),
        status: String(item.status)
      })),
      packages: packageRows.map((item) => ({
        id: Number(item.id),
        legacyCode: item.codigo_legado ? String(item.codigo_legado) : null,
        description: String(item.descricao),
        unit: String(item.unidade),
        volumeLiters: toNullableNumber(item.volume_litros),
        controlsStock: Boolean(item.controla_estoque),
        materialId: item.materia_prima_id === null ? null : Number(item.materia_prima_id),
        materialLabel:
          item.materia_prima_id === null
            ? null
            : materialLabels.get(Number(item.materia_prima_id)) ?? `MP #${item.materia_prima_id}`,
        status: String(item.status),
        source: String(item.origem_dados ?? "sistema")
      })),
      saleItems: (saleItems.data ?? []).map((item) => ({
        id: Number(item.id),
        code: String(item.codigo_item),
        productId: Number(item.produto_id),
        productLabel: productLabels.get(Number(item.produto_id)) ?? `Produto #${item.produto_id}`,
        packageId: Number(item.embalagem_id),
        packageLabel: packageLabels.get(Number(item.embalagem_id)) ?? `Embalagem #${item.embalagem_id}`,
        status: String(item.status)
      })),
      source: "supabase",
      error: null
    };
  } catch (error) {
    return {
      ...EMPTY_CATALOG,
      source: "error",
      error: error instanceof Error ? error.message : "Erro desconhecido"
    };
  }
}

function toNullableNumber(value: unknown): number | null {
  return value === null || value === undefined || value === "" ? null : Number(value);
}
