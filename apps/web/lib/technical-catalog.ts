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
  baseUnitId: number;
  status: string;
  inputTypeId: number | null;
  inputTypeName: string;
  inputTypeStatus: string | null;
  inputTypeReviewStatus: string;
  density: number | null;
  minimumStock: number | null;
  ncm: string | null;
  ibama: string | null;
  adsCode: string | null;
  source: string;
  updatedAt: string;
};

export type TechnicalInputType = {
  id: number;
  code: string;
  name: string;
  description: string | null;
  status: string;
  displayOrder: number;
  updatedAt: string;
};

export type TechnicalInputTypeSummary = {
  totalMaterials: number;
  classified: number;
  unclassified: number;
  governedSource: number;
  manualSource: number;
  inferred: number;
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

export type TechnicalPackageVersion = {
  id: number;
  packageId: number;
  version: number;
  validFrom: string | null;
  validTo: string | null;
  tareKg: number | null;
  cubicMeters: number | null;
  unitsPerLiter: number | null;
  justification: string | null;
  reviewStatus: string;
  active: boolean;
};

export type TechnicalPackageComponent = {
  id: number;
  packageVersionId: number;
  materialId: number;
  materialLabel: string;
  quantityUnL: number | null;
  reviewStatus: string;
  status: string;
};

export type TechnicalCatalog = {
  units: TechnicalUnit[];
  nutrients: TechnicalNutrient[];
  materials: TechnicalMaterial[];
  inputTypes: TechnicalInputType[];
  inputTypeSummary: TechnicalInputTypeSummary;
  conversions: TechnicalConversion[];
  products: TechnicalProduct[];
  productGroups: TechnicalProductGroup[];
  packages: TechnicalPackage[];
  saleItems: TechnicalSaleItem[];
  packageVersions: TechnicalPackageVersion[];
  packageComponents: TechnicalPackageComponent[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_CATALOG: Omit<TechnicalCatalog, "source" | "error"> = {
  units: [],
  nutrients: [],
  materials: [],
  inputTypes: [],
  inputTypeSummary: {
    totalMaterials: 0,
    classified: 0,
    unclassified: 0,
    governedSource: 0,
    manualSource: 0,
    inferred: 0
  },
  conversions: [],
  products: [],
  productGroups: [],
  packages: [],
  saleItems: [],
  packageVersions: [],
  packageComponents: []
};

export async function getTechnicalCatalog(): Promise<TechnicalCatalog> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return { ...EMPTY_CATALOG, source: "not_configured", error: null };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [units, nutrients, materials, inputTypes, inputTypeSummary, conversions, products, productGroups, packages, saleItems, packageVersions, packageComponents, packageActivations, packageReviews, packageComponentEvents] = await Promise.all([
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
          "id,codigo_legado,sku_corrigido,nome,unidade_base_estoque,unidade_base_estoque_id,status,tipo_insumo_id,tipo_insumo_review_status,densidade,estoque_minimo,ncm,ibama,codigo_ads,origem_dados,updated_at,cad_tipos_insumo(nome,status)"
        )
        .order("nome", { ascending: true })
        .limit(800),
      supabase
        .from("cad_tipos_insumo")
        .select("id,codigo,nome,descricao,status,ordem_exibicao,updated_at")
        .order("ordem_exibicao", { ascending: true })
        .order("nome", { ascending: true })
        .limit(300),
      supabase
        .from("cad_materias_primas_tipos_resumo")
        .select("total_materias_primas,total_classificadas,total_sem_classificacao,classificadas_fonte_governada,classificadas_manual_governado,classificadas_por_inferencia")
        .maybeSingle(),
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
        .limit(1000),
      supabase
        .from("cad_embalagem_versoes")
        .select("id,embalagem_id,versao,vigencia_inicio,vigencia_fim,peso_tara_kg,cubagem_m3,unidades_embalagem_por_litro,justificativa,review_status")
        .order("embalagem_id", { ascending: true })
        .order("versao", { ascending: false })
        .limit(1000),
      supabase
        .from("cad_embalagem_componentes")
        .select("id,embalagem_versao_id,materia_prima_id,quantidade_un_l,review_status,status")
        .order("embalagem_versao_id", { ascending: true })
        .limit(2000),
      supabase
        .from("cad_embalagem_versao_ativacoes")
        .select("id,embalagem_versao_id,tipo_evento,created_at")
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(1000),
      supabase
        .from("cad_embalagem_versao_revisoes")
        .select("id,embalagem_versao_id,decisao,created_at")
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(1000),
      supabase
        .from("cad_embalagem_componente_eventos")
        .select("id,embalagem_componente_id,tipo_evento,created_at")
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(1000)
    ]);

    const firstError = [units, nutrients, materials, inputTypes, inputTypeSummary, conversions, products, productGroups, packages, saleItems, packageVersions, packageComponents, packageActivations, packageReviews, packageComponentEvents].find(
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
    const versionPackageIds = new Map(
      (packageVersions.data ?? []).map((item) => [Number(item.id), Number(item.embalagem_id)])
    );
    const latestActivationByPackage = new Map<number, { versionId: number; type: string }>();
    const reviewByVersion = new Map<number, string>();
    const removedComponentIds = new Set<number>();
    for (const activation of packageActivations.data ?? []) {
      const packageId = versionPackageIds.get(Number(activation.embalagem_versao_id));
      if (packageId !== undefined && !latestActivationByPackage.has(packageId)) {
        latestActivationByPackage.set(packageId, {
          versionId: Number(activation.embalagem_versao_id),
          type: String(activation.tipo_evento)
        });
      }
    }
    for (const review of packageReviews.data ?? []) {
      const versionId = Number(review.embalagem_versao_id);
      if (!reviewByVersion.has(versionId)) reviewByVersion.set(versionId, String(review.decisao));
    }
    for (const event of packageComponentEvents.data ?? []) {
      if (String(event.tipo_evento) === "remocao") {
        removedComponentIds.add(Number(event.embalagem_componente_id));
      }
    }

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
        baseUnitId: Number(item.unidade_base_estoque_id),
        status: String(item.status),
        inputTypeId: item.tipo_insumo_id === null ? null : Number(item.tipo_insumo_id),
        inputTypeName: relationName(item.cad_tipos_insumo) ?? "Tipo de insumo não definido",
        inputTypeStatus: relationStatus(item.cad_tipos_insumo),
        inputTypeReviewStatus: String(item.tipo_insumo_review_status ?? "pending_review"),
        density: toNullableNumber(item.densidade),
        minimumStock: toNullableNumber(item.estoque_minimo),
        ncm: item.ncm ? String(item.ncm) : null,
        ibama: item.ibama ? String(item.ibama) : null,
        adsCode: item.codigo_ads ? String(item.codigo_ads) : null,
        source: String(item.origem_dados ?? "sistema"),
        updatedAt: String(item.updated_at)
      })),
      inputTypes: (inputTypes.data ?? []).map((item) => ({
        id: Number(item.id),
        code: String(item.codigo),
        name: String(item.nome),
        description: item.descricao ? String(item.descricao) : null,
        status: String(item.status),
        displayOrder: Number(item.ordem_exibicao),
        updatedAt: String(item.updated_at)
      })),
      inputTypeSummary: {
        totalMaterials: Number(inputTypeSummary.data?.total_materias_primas ?? 0),
        classified: Number(inputTypeSummary.data?.total_classificadas ?? 0),
        unclassified: Number(inputTypeSummary.data?.total_sem_classificacao ?? 0),
        governedSource: Number(inputTypeSummary.data?.classificadas_fonte_governada ?? 0),
        manualSource: Number(inputTypeSummary.data?.classificadas_manual_governado ?? 0),
        inferred: Number(inputTypeSummary.data?.classificadas_por_inferencia ?? 0)
      },
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
      packageVersions: (packageVersions.data ?? []).map((item) => {
        const current = latestActivationByPackage.get(Number(item.embalagem_id));
        return {
          id: Number(item.id),
          packageId: Number(item.embalagem_id),
          version: Number(item.versao),
          validFrom: item.vigencia_inicio ? String(item.vigencia_inicio) : null,
          validTo: item.vigencia_fim ? String(item.vigencia_fim) : null,
          tareKg: toNullableNumber(item.peso_tara_kg),
          cubicMeters: toNullableNumber(item.cubagem_m3),
          unitsPerLiter: toNullableNumber(item.unidades_embalagem_por_litro),
          justification: item.justificativa ? String(item.justificativa) : null,
          reviewStatus: reviewByVersion.get(Number(item.id)) ?? String(item.review_status),
          active: current?.type === "ativacao" && current.versionId === Number(item.id)
        };
      }),
      packageComponents: (packageComponents.data ?? []).map((item) => ({
        id: Number(item.id),
        packageVersionId: Number(item.embalagem_versao_id),
        materialId: Number(item.materia_prima_id),
        materialLabel: materialLabels.get(Number(item.materia_prima_id)) ?? `MP #${item.materia_prima_id}`,
        quantityUnL: toNullableNumber(item.quantidade_un_l),
        reviewStatus:
          reviewByVersion.get(Number(item.embalagem_versao_id)) ?? String(item.review_status),
        status: removedComponentIds.has(Number(item.id)) ? "removed" : "active"
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

function relationName(value: unknown): string | null {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object" || !("nome" in relation)) return null;
  const name = (relation as { nome?: unknown }).nome;
  return name ? String(name) : null;
}

function relationStatus(value: unknown): string | null {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object" || !("status" in relation)) return null;
  const status = (relation as { status?: unknown }).status;
  return status ? String(status) : null;
}

function toNullableNumber(value: unknown): number | null {
  return value === null || value === undefined || value === "" ? null : Number(value);
}
