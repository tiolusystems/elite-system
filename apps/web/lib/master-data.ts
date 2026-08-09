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

export type MasterDataClientListItem = MasterDataClient & {
  razaoSocial: string | null;
  nomeFantasia: string | null;
  documentoPrincipal: string | null;
  propriedadesTotal: number;
};

export type MasterDataClientPage = {
  clientes: MasterDataClientListItem[];
  total: number;
  pagina: number;
  tamanhoPagina: number;
  erro: string | null;
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
export type MasterDataClientCreditEvent = { id: number; clienteId: number; tipoEvento: string; limiteAnterior: number | null; limiteNovo: number; statusAnterior: string | null; statusNovo: string; justificativa: string; createdAt: string };
export type MasterDataClientIdentification = { id: number; clienteId: number; tipoPessoa: string; razaoSocial: string | null; nomeFantasia: string | null; situacaoCadastral: string; dataAbertura: string | null; cnaePrincipal: string | null; regimeTributario: string | null; condicaoContribuinte: string | null; fonteInformacao: string; dataConsulta: string | null; updatedAt: string };
export type MasterDataClientEstablishment = { id: number; clienteId: number; nome: string; tipo: string; status: string };
export type MasterDataClientAddress = { id: number; clienteId: number; estabelecimentoId: number | null; propriedadeId: number | null; tipo: string; cep: string | null; logradouro: string; numero: string | null; complemento: string | null; bairro: string | null; cidade: string; uf: string; status: string };

export type MasterDataClientSeller = {
  id: number;
  clienteId: number;
  pessoaId: number;
  papelVinculoId: number;
  propriedadeId: number | null;
  status: string;
  vigenciaInicio: string | null;
  vigenciaFim: string | null;
};

export type MasterDataClientWorkspace = {
  pagina: MasterDataClientPage;
  cliente: MasterDataClient | null;
  propriedades: MasterDataProperty[];
  vinculos: MasterDataClientSeller[];
  linkRoles: MasterDataClientLinkRole[];
  pessoas: LookupOption[];
  documentos: MasterDataClientDocument[];
  contatos: MasterDataClientContact[];
  creditos: MasterDataClientCredit[];
  creditoEventos: MasterDataClientCreditEvent[];
  identificacoes: MasterDataClientIdentification[];
  estabelecimentos: MasterDataClientEstablishment[];
  enderecos: MasterDataClientAddress[];
  creditoGravacaoDisponivel: boolean;
  commercialLinksManageAvailable: boolean;
  erro: string | null;
};

export type MasterDataClientLinkRole = {
  id: number;
  code: string;
  name: string;
  grantsVisibility: boolean;
  status: string;
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

export type MasterDataVehicle = {
  id: number;
  legacyCode: string | null;
  description: string;
  plate: string | null;
  status: string;
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
  clienteCreditoEventos: MasterDataClientCreditEvent[];
  clienteIdentificacoes: MasterDataClientIdentification[];
  clienteEstabelecimentos: MasterDataClientEstablishment[];
  clienteEnderecos: MasterDataClientAddress[];
  clienteVendedores: MasterDataClientSeller[];
  clienteVinculoPapeis: MasterDataClientLinkRole[];
  pessoas: MasterDataPerson[];
  pessoaPapeis: MasterDataPersonRole[];
  areasComerciais: MasterDataCommercialArea[];
  pessoaAreas: MasterDataPersonArea[];
  vehicles: MasterDataVehicle[];
  creditoGravacaoDisponivel: boolean;
  clienteVinculosGravacaoDisponivel: boolean;
  vehicleCreateAvailable: boolean;
  vehicleStatusManageAvailable: boolean;
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
  },
  {
    key: "veiculos",
    title: "Veiculos",
    table: "cad_veiculos",
    owner: "Expedicao",
    requiredFields: ["descricao", "placa", "status"],
    audit: "Cadastro, situacao e uso em romaneios",
    status: "ready"
  }
];

export async function getMasterDataDashboard(
  options: { lightweight?: boolean } = {}
): Promise<MasterDataDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }
  if (options.lightweight) {
    return emptyDashboard("supabase", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [metrics, validationResult, lookups, peopleData, vehicleData] = await Promise.all([
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
      getPeopleMasterData(supabase),
      getVehicleMasterData(supabase)
    ]);

    return {
      modules: MASTER_DATA_MODULES,
      metrics,
      validationIssues: validationResult.error ? [] : ((validationResult.data ?? []) as ValidationIssue[]),
      lookups,
      clientes: [],
      propriedades: [],
      clienteDocumentos: [],
      clienteContatos: [],
      clienteCreditos: [],
      clienteCreditoEventos: [],
      clienteIdentificacoes: [],
      clienteEstabelecimentos: [],
      clienteEnderecos: [],
      clienteVendedores: [],
      clienteVinculoPapeis: [],
      pessoas: peopleData.pessoas,
      pessoaPapeis: peopleData.pessoaPapeis,
      areasComerciais: peopleData.areasComerciais,
      pessoaAreas: peopleData.pessoaAreas,
      vehicles: vehicleData.vehicles,
      creditoGravacaoDisponivel: false,
      clienteVinculosGravacaoDisponivel: false,
      vehicleCreateAvailable: vehicleData.vehicleCreateAvailable,
      vehicleStatusManageAvailable: vehicleData.vehicleStatusManageAvailable,
      source: "supabase",
      error: validationResult.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

async function getVehicleMasterData(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>
): Promise<Pick<MasterDataDashboard, "vehicles" | "vehicleCreateAvailable" | "vehicleStatusManageAvailable">> {
  const [vehiclesResult, createPermission, statusPermission] = await Promise.all([
    supabase
      .from("cad_veiculos")
      .select("id,codigo_legado,descricao,placa,status")
      .order("descricao", { ascending: true })
      .limit(250),
    supabase.rpc("can_current_user", { p_action_key: "cadastros.veiculos.create" }),
    supabase.rpc("can_current_user", { p_action_key: "cadastros.veiculos.status.manage" })
  ]);

  return {
    vehicles: vehiclesResult.error
      ? []
      : (vehiclesResult.data ?? []).map((item) => ({
          id: Number(item.id),
          legacyCode: item.codigo_legado,
          description: item.descricao,
          plate: item.placa,
          status: item.status
        })),
    vehicleCreateAvailable: !createPermission.error && createPermission.data === true,
    vehicleStatusManageAvailable: !statusPermission.error && statusPermission.data === true
  };
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

export async function getMasterDataClientWorkspace(input: {
  busca: string;
  situacao: string;
  ordenacao: string;
  pagina: number;
  clienteId: number | null;
  carregarLista: boolean;
}): Promise<MasterDataClientWorkspace> {
  const runtime = getRuntimeStatus();
  const tamanhoPagina = 25;
  const paginaSolicitada = Math.max(1, input.pagina);
  const empty = emptyClientWorkspace(paginaSolicitada, tamanhoPagina);
  if (!runtime.supabaseConfigured) {
    return { ...empty, erro: "Banco de homologacao indisponivel." };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const situacao = ["active", "inactive", "pending_review"].includes(input.situacao)
      ? input.situacao
      : "";
    const ordenacao = input.ordenacao === "nome_desc" ? "nome_desc" : "nome_asc";
    let pagina = paginaSolicitada;
    let pageRows: Array<Record<string, unknown>> = [];
    let pageError: string | null = null;

    if (input.carregarLista) {
      const loadPage = async (pageNumber: number) =>
        supabase.rpc("consultar_cad_clientes_paginada", {
          p_busca: input.busca.trim() || null,
          p_situacao: situacao || null,
          p_ordenacao: ordenacao,
          p_limite: tamanhoPagina,
          p_offset: (pageNumber - 1) * tamanhoPagina
        });
      let result = await loadPage(pagina);
      pageError = result.error?.message ?? null;
      pageRows = (result.data ?? []) as Array<Record<string, unknown>>;
      if (!pageError && pageRows.length === 0 && pagina > 1) {
        const firstPage = await loadPage(1);
        pageError = firstPage.error?.message ?? null;
        const firstRows = (firstPage.data ?? []) as Array<Record<string, unknown>>;
        const total = Number(firstRows[0]?.total_registros ?? 0);
        pagina = Math.max(1, Math.ceil(total / tamanhoPagina));
        result = pagina === 1 ? firstPage : await loadPage(pagina);
        pageError = result.error?.message ?? null;
        pageRows = (result.data ?? []) as Array<Record<string, unknown>>;
      }
    }

    const clientData = input.clienteId
      ? await getClientRecord(supabase, input.clienteId)
      : emptyClientRecord();
    const total = Number(pageRows[0]?.total_registros ?? 0);
    const paginaResult: MasterDataClientPage = {
      clientes: pageRows.map(mapClientListItem),
      total,
      pagina,
      tamanhoPagina,
      erro: pageError ? "Nao foi possivel consultar os clientes agora." : null
    };

    return {
      pagina: paginaResult,
      ...clientData,
      erro: pageError
        ? "Nao foi possivel consultar os clientes agora."
        : clientData.erro
    };
  } catch {
    return { ...empty, erro: "Nao foi possivel carregar os clientes agora." };
  }
}

async function getClientRecord(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  clienteId: number
): Promise<Omit<MasterDataClientWorkspace, "pagina">> {
  const [
    clientResult,
    propertiesResult,
    sellersResult,
    linkRolesResult,
    peopleResult,
    documentsResult,
    contactsResult,
    creditsResult,
    creditEventsResult,
    identificationsResult,
    establishmentsResult,
    addressesResult,
    creditPermission,
    commercialLinksPermission
  ] = await Promise.all([
    supabase
      .from("cad_clientes")
      .select("id,codigo_legado,nome,cidade,uf,status,apelidos_json,valor_total_compras")
      .eq("id", clienteId)
      .maybeSingle(),
    supabase
      .from("cad_cliente_propriedades")
      .select("id,cliente_id,nome,cnpj,cidade,uf,status")
      .eq("cliente_id", clienteId)
      .order("nome", { ascending: true }),
    supabase
      .from("cad_cliente_vendedores")
      .select("id,cliente_id,pessoa_id,papel_vinculo_id,propriedade_id,status,vigencia_inicio,vigencia_fim")
      .eq("cliente_id", clienteId)
      .order("vigencia_inicio", { ascending: false }),
    supabase
      .from("cad_cliente_vinculo_papeis")
      .select("id,codigo_norm,nome,concede_visibilidade,status")
      .order("nome", { ascending: true }),
    supabase
      .from("cad_pessoas_comerciais")
      .select("id,nome,tipo_comercial,status")
      .eq("status", "active")
      .order("nome", { ascending: true })
      .limit(250),
    supabase
      .from("cad_cliente_documentos")
      .select("id,cliente_id,propriedade_id,tipo,numero")
      .eq("cliente_id", clienteId)
      .order("id", { ascending: false }),
    supabase
      .from("cad_cliente_contatos")
      .select("id,cliente_id,propriedade_id,nome,papel,telefone,email,status")
      .eq("cliente_id", clienteId)
      .order("id", { ascending: false }),
    supabase
      .from("cad_limites_credito_cliente")
      .select("id,cliente_id,limite_manual,limite_calculado,limite_disponivel,status_credito,motivo,updated_at")
      .eq("cliente_id", clienteId)
      .order("updated_at", { ascending: false }),
    supabase
      .from("cad_limite_credito_eventos")
      .select("id,cliente_id,tipo_evento,limite_anterior,limite_novo,status_anterior,status_novo,justificativa,created_at")
      .eq("cliente_id", clienteId)
      .order("created_at", { ascending: false }),
    supabase
      .from("cad_cliente_identificacoes")
      .select("id,cliente_id,tipo_pessoa,razao_social,nome_fantasia,situacao_cadastral,data_abertura,cnae_principal,regime_tributario,condicao_contribuinte,fonte_informacao,data_consulta,updated_at")
      .eq("cliente_id", clienteId),
    supabase
      .from("cad_cliente_estabelecimentos")
      .select("id,cliente_id,nome,tipo,status")
      .eq("cliente_id", clienteId)
      .order("nome"),
    supabase
      .from("cad_cliente_enderecos")
      .select("id,cliente_id,estabelecimento_id,propriedade_id,tipo,cep,logradouro,numero,complemento,bairro,cidade,uf,status")
      .eq("cliente_id", clienteId)
      .order("id", { ascending: false }),
    supabase.rpc("can_current_user", { p_action_key: "financeiro.credit_limits.adjust" }),
    supabase.rpc("can_current_user", { p_action_key: "cadastros.clientes.commercial_links.manage" })
  ]);

  const errors = [
    clientResult.error,
    propertiesResult.error,
    sellersResult.error,
    linkRolesResult.error,
    peopleResult.error,
    documentsResult.error,
    contactsResult.error,
    creditsResult.error,
    creditEventsResult.error,
    identificationsResult.error,
    establishmentsResult.error,
    addressesResult.error
  ].filter(Boolean);
  const row = clientResult.data;

  return {
    cliente: row
      ? {
          id: Number(row.id),
          codigoLegado: row.codigo_legado,
          nome: row.nome,
          cidade: row.cidade,
          uf: row.uf,
          status: row.status,
          apelidos: stringArray(row.apelidos_json),
          valorTotalCompras: row.valor_total_compras === null ? null : Number(row.valor_total_compras)
        }
      : null,
    propriedades: (propertiesResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      nome: item.nome,
      cnpj: item.cnpj,
      cidade: item.cidade,
      uf: item.uf,
      status: item.status
    })),
    vinculos: (sellersResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      pessoaId: Number(item.pessoa_id),
      papelVinculoId: Number(item.papel_vinculo_id),
      propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id),
      status: item.status,
      vigenciaInicio: item.vigencia_inicio,
      vigenciaFim: item.vigencia_fim
    })),
    linkRoles: (linkRolesResult.data ?? []).map((item) => ({
      id: Number(item.id),
      code: item.codigo_norm,
      name: item.nome,
      grantsVisibility: Boolean(item.concede_visibilidade),
      status: item.status
    })),
    pessoas: (peopleResult.data ?? []).map((item) => ({
      id: Number(item.id),
      label: item.nome,
      detail: item.tipo_comercial
    })),
    documentos: (documentsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id),
      tipo: item.tipo,
      numero: item.numero
    })),
    contatos: (contactsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id),
      nome: item.nome,
      papel: item.papel,
      telefone: item.telefone,
      email: item.email,
      status: item.status
    })),
    creditos: (creditsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      limiteManual: item.limite_manual === null ? null : Number(item.limite_manual),
      limiteCalculado: item.limite_calculado === null ? null : Number(item.limite_calculado),
      limiteDisponivel: Number(item.limite_disponivel),
      statusCredito: item.status_credito,
      motivo: item.motivo,
      updatedAt: item.updated_at
    })),
    creditoEventos: (creditEventsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      tipoEvento: item.tipo_evento,
      limiteAnterior: item.limite_anterior === null ? null : Number(item.limite_anterior),
      limiteNovo: Number(item.limite_novo),
      statusAnterior: item.status_anterior,
      statusNovo: item.status_novo,
      justificativa: item.justificativa,
      createdAt: item.created_at
    })),
    identificacoes: (identificationsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      tipoPessoa: item.tipo_pessoa,
      razaoSocial: item.razao_social,
      nomeFantasia: item.nome_fantasia,
      situacaoCadastral: item.situacao_cadastral,
      dataAbertura: item.data_abertura,
      cnaePrincipal: item.cnae_principal,
      regimeTributario: item.regime_tributario,
      condicaoContribuinte: item.condicao_contribuinte,
      fonteInformacao: item.fonte_informacao,
      dataConsulta: item.data_consulta,
      updatedAt: item.updated_at
    })),
    estabelecimentos: (establishmentsResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      nome: item.nome,
      tipo: item.tipo,
      status: item.status
    })),
    enderecos: (addressesResult.data ?? []).map((item) => ({
      id: Number(item.id),
      clienteId: Number(item.cliente_id),
      estabelecimentoId: item.estabelecimento_id === null ? null : Number(item.estabelecimento_id),
      propriedadeId: item.propriedade_id === null ? null : Number(item.propriedade_id),
      tipo: item.tipo,
      cep: item.cep,
      logradouro: item.logradouro,
      numero: item.numero,
      complemento: item.complemento,
      bairro: item.bairro,
      cidade: item.cidade,
      uf: item.uf,
      status: item.status
    })),
    creditoGravacaoDisponivel: !creditPermission.error && creditPermission.data === true,
    commercialLinksManageAvailable:
      !commercialLinksPermission.error && commercialLinksPermission.data === true,
    erro: errors.length ? "Nao foi possivel carregar toda a ficha do cliente." : null
  };
}

function mapClientListItem(row: Record<string, unknown>): MasterDataClientListItem {
  return {
    id: Number(row.cliente_id),
    codigoLegado: nullableString(row.codigo_legado),
    nome: String(row.nome),
    cidade: String(row.cidade),
    uf: String(row.uf),
    status: String(row.situacao),
    apelidos: stringArray(row.apelidos_json),
    valorTotalCompras: nullableNumber(row.valor_total_compras),
    razaoSocial: nullableString(row.razao_social),
    nomeFantasia: nullableString(row.nome_fantasia),
    documentoPrincipal: nullableString(row.documento_principal),
    propriedadesTotal: Number(row.propriedades_total ?? 0)
  };
}

function emptyClientRecord(): Omit<MasterDataClientWorkspace, "pagina"> {
  return {
    cliente: null,
    propriedades: [],
    vinculos: [],
    linkRoles: [],
    pessoas: [],
    documentos: [],
    contatos: [],
    creditos: [],
    creditoEventos: [],
    identificacoes: [],
    estabelecimentos: [],
    enderecos: [],
    creditoGravacaoDisponivel: false,
    commercialLinksManageAvailable: false,
    erro: null
  };
}

function emptyClientWorkspace(pagina: number, tamanhoPagina: number): MasterDataClientWorkspace {
  return {
    pagina: { clientes: [], total: 0, pagina, tamanhoPagina, erro: null },
    ...emptyClientRecord()
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
    clienteCreditoEventos: [],
    clienteIdentificacoes: [],
    clienteEstabelecimentos: [],
    clienteEnderecos: [],
    clienteVendedores: [],
    clienteVinculoPapeis: [],
    pessoas: [],
    pessoaPapeis: [],
    areasComerciais: [],
    pessoaAreas: [],
    vehicles: [],
    creditoGravacaoDisponivel: false,
    clienteVinculosGravacaoDisponivel: false,
    vehicleCreateAvailable: false,
    vehicleStatusManageAvailable: false,
    source,
    error
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}
