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

export type MasterDataClientDocument = { id: number; clienteId: number; propriedadeId: number | null; tipo: string; numero: string };
export type MasterDataClientContact = { id: number; clienteId: number; propriedadeId: number | null; nome: string; papel: string; telefone: string | null; email: string | null; status: string };
export type MasterDataClientCredit = { id: number; clienteId: number; limiteManual: number | null; limiteCalculado: number | null; limiteDisponivel: number; statusCredito: string; motivo: string | null; updatedAt: string };
export type MasterDataClientIdentification = { id: number; clienteId: number; tipoPessoa: string; razaoSocial: string | null; nomeFantasia: string | null; situacaoCadastral: string; dataAbertura: string | null; cnaePrincipal: string | null; regimeTributario: string | null; condicaoContribuinte: string | null; fonteInformacao: string; dataConsulta: string | null; updatedAt: string };
export type MasterDataClientEstablishment = { id: number; clienteId: number; nome: string; tipo: string; status: string };
export type MasterDataClientAddress = { id: number; clienteId: number; estabelecimentoId: number | null; propriedadeId: number | null; tipo: string; cep: string | null; logradouro: string; numero: string | null; complemento: string | null; bairro: string | null; cidade: string; uf: string; status: string };

export type MasterDataClientSeller = {
  id: number;
  clienteId: number;
  pessoaId: number;
  propriedadeId: number | null;
  status: string;
  vigenciaInicio: string | null;
  vigenciaFim: string | null;
};

export type MasterDataPerson = {
  id: number;
  userProfileId: string | null;
  codigoLegado: string | null;
  nome: string;
  tipoComercial: string | null;
  status: string;
  vendedorResponsavelId: number | null;
  apelidos: string[];
  grafiasIncorretas: string[];
};

export type MasterDataPersonRole = {
  pessoaId: number;
  papel: string;
  vigenciaInicio: string | null;
};

export type MasterDataCommercialArea = {
  id: number;
  nome: string;
  status: string;
};

export type MasterDataPersonArea = {
  id: number;
  pessoaId: number;
  areaId: number;
  papelArea: string;
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
  clienteDocumentos: MasterDataClientDocument[];
  clienteContatos: MasterDataClientContact[];
  clienteCreditos: MasterDataClientCredit[];
  clienteIdentificacoes: MasterDataClientIdentification[];
  clienteEstabelecimentos: MasterDataClientEstablishment[];
  clienteEnderecos: MasterDataClientAddress[];
  clienteVendedores: MasterDataClientSeller[];
  pessoas: MasterDataPerson[];
  pessoaPapeis: MasterDataPersonRole[];
  areasComerciais: MasterDataCommercialArea[];
  pessoaAreas: MasterDataPersonArea[];
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
    const [metrics, validationResult, lookups, clientData, peopleData] = await Promise.all([
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
      getClientMasterData(supabase),
      getPeopleMasterData(supabase)
    ]);

    return {
      modules: MASTER_DATA_MODULES,
      metrics,
      validationIssues: validationResult.error ? [] : ((validationResult.data ?? []) as ValidationIssue[]),
      lookups,
      clientes: clientData.clientes,
      propriedades: clientData.propriedades,
      clienteDocumentos: clientData.clienteDocumentos,
      clienteContatos: clientData.clienteContatos,
      clienteCreditos: clientData.clienteCreditos,
      clienteIdentificacoes: clientData.clienteIdentificacoes,
      clienteEstabelecimentos: clientData.clienteEstabelecimentos,
      clienteEnderecos: clientData.clienteEnderecos,
      clienteVendedores: clientData.clienteVendedores,
      pessoas: peopleData.pessoas,
      pessoaPapeis: peopleData.pessoaPapeis,
      areasComerciais: peopleData.areasComerciais,
      pessoaAreas: peopleData.pessoaAreas,
      source: "supabase",
      error: validationResult.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getPeopleMasterData(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<Pick<MasterDataDashboard, "pessoas" | "pessoaPapeis" | "areasComerciais" | "pessoaAreas">> {
  const [peopleResult, rolesResult, areasResult, membershipsResult] = await Promise.all([
    supabase
      .from("cad_pessoas_comerciais")
      .select("id,user_profile_id,codigo_legado,nome,tipo_comercial,status,vendedor_responsavel_id,apelidos_json,grafias_incorretas_json")
      .order("nome", { ascending: true })
      .limit(250),
    supabase
      .from("cad_pessoas_comerciais_papeis_ativos")
      .select("pessoa_id,papel,vigencia_inicio")
      .order("pessoa_id", { ascending: true })
      .limit(1000),
    supabase
      .from("cad_areas_comerciais")
      .select("id,nome,status")
      .order("nome", { ascending: true })
      .limit(250),
    supabase
      .from("cad_pessoa_areas_comerciais")
      .select("id,pessoa_id,area_id,papel_area,status,vigencia_inicio,vigencia_fim")
      .order("vigencia_inicio", { ascending: false })
      .limit(1000)
  ]);

  return {
    pessoas: peopleResult.error
      ? []
      : (peopleResult.data ?? []).map((item) => ({
          id: Number(item.id),
          userProfileId: item.user_profile_id,
          codigoLegado: item.codigo_legado,
          nome: item.nome,
          tipoComercial: item.tipo_comercial,
          status: item.status,
          vendedorResponsavelId: item.vendedor_responsavel_id === null ? null : Number(item.vendedor_responsavel_id),
          apelidos: stringArray(item.apelidos_json),
          grafiasIncorretas: stringArray(item.grafias_incorretas_json)
        })),
    pessoaPapeis: rolesResult.error
      ? []
      : (rolesResult.data ?? []).map((item) => ({
          pessoaId: Number(item.pessoa_id),
          papel: item.papel,
          vigenciaInicio: item.vigencia_inicio
        })),
    areasComerciais: areasResult.error
      ? []
      : (areasResult.data ?? []).map((item) => ({
          id: Number(item.id),
          nome: item.nome,
          status: item.status
        })),
    pessoaAreas: membershipsResult.error
      ? []
      : (membershipsResult.data ?? []).map((item) => ({
          id: Number(item.id),
          pessoaId: Number(item.pessoa_id),
          areaId: Number(item.area_id),
          papelArea: item.papel_area,
          status: item.status,
          vigenciaInicio: item.vigencia_inicio,
          vigenciaFim: item.vigencia_fim
        }))
  };
}

async function getClientMasterData(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<Pick<MasterDataDashboard, "clientes" | "propriedades" | "clienteVendedores" | "clienteDocumentos" | "clienteContatos" | "clienteCreditos" | "clienteIdentificacoes" | "clienteEstabelecimentos" | "clienteEnderecos">> {
  const [clientsResult, propertiesResult, sellersResult, documentsResult, contactsResult, creditsResult, identificationsResult, establishmentsResult, addressesResult] = await Promise.all([
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
      .limit(500),
    supabase.from("cad_cliente_documentos").select("id,cliente_id,propriedade_id,tipo,numero").order("id", { ascending: false }).limit(1000),
    supabase.from("cad_cliente_contatos").select("id,cliente_id,propriedade_id,nome,papel,telefone,email,status").order("id", { ascending: false }).limit(1000),
    supabase.from("cad_limites_credito_cliente").select("id,cliente_id,limite_manual,limite_calculado,limite_disponivel,status_credito,motivo,updated_at").order("updated_at", { ascending: false }).limit(1000),
    supabase.from("cad_cliente_identificacoes").select("id,cliente_id,tipo_pessoa,razao_social,nome_fantasia,situacao_cadastral,data_abertura,cnae_principal,regime_tributario,condicao_contribuinte,fonte_informacao,data_consulta,updated_at").limit(500),
    supabase.from("cad_cliente_estabelecimentos").select("id,cliente_id,nome,tipo,status").order("nome").limit(1000),
    supabase.from("cad_cliente_enderecos").select("id,cliente_id,estabelecimento_id,propriedade_id,tipo,cep,logradouro,numero,complemento,bairro,cidade,uf,status").order("id", { ascending: false }).limit(1500)
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
        })),
    clienteDocumentos: documentsResult.error ? [] : (documentsResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id), tipo: item.tipo, numero: item.numero })),
    clienteContatos: contactsResult.error ? [] : (contactsResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id), nome: item.nome, papel: item.papel, telefone: item.telefone, email: item.email, status: item.status })),
    clienteCreditos: creditsResult.error ? [] : (creditsResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), limiteManual: item.limite_manual === null ? null : Number(item.limite_manual), limiteCalculado: item.limite_calculado === null ? null : Number(item.limite_calculado), limiteDisponivel: Number(item.limite_disponivel), statusCredito: item.status_credito, motivo: item.motivo, updatedAt: item.updated_at })),
    clienteIdentificacoes: identificationsResult.error ? [] : (identificationsResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), tipoPessoa: item.tipo_pessoa, razaoSocial: item.razao_social, nomeFantasia: item.nome_fantasia, situacaoCadastral: item.situacao_cadastral, dataAbertura: item.data_abertura, cnaePrincipal: item.cnae_principal, regimeTributario: item.regime_tributario, condicaoContribuinte: item.condicao_contribuinte, fonteInformacao: item.fonte_informacao, dataConsulta: item.data_consulta, updatedAt: item.updated_at })),
    clienteEstabelecimentos: establishmentsResult.error ? [] : (establishmentsResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), nome: item.nome, tipo: item.tipo, status: item.status })),
    clienteEnderecos: addressesResult.error ? [] : (addressesResult.data ?? []).map((item) => ({ id: Number(item.id), clienteId: Number(item.cliente_id), estabelecimentoId: item.estabelecimento_id === null ? null : Number(item.estabelecimento_id), propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id), tipo: item.tipo, cep: item.cep, logradouro: item.logradouro, numero: item.numero, complemento: item.complemento, bairro: item.bairro, cidade: item.cidade, uf: item.uf, status: item.status }))
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
    clienteDocumentos: [],
    clienteContatos: [],
    clienteCreditos: [],
    clienteIdentificacoes: [],
    clienteEstabelecimentos: [],
    clienteEnderecos: [],
    clienteVendedores: [],
    pessoas: [],
    pessoaPapeis: [],
    areasComerciais: [],
    pessoaAreas: [],
    source,
    error
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}
