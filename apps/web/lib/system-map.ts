export const SYSTEM_MODULE_KEYS = [
  "core",
  "seguranca",
  "cadastros",
  "pedidos",
  "estoque",
  "pcp",
  "expedicao",
  "importacao",
  "faturamento",
  "financeiro",
  "metas",
  "relatorios",
  "auditoria"
] as const;

export type SystemModuleKey = (typeof SYSTEM_MODULE_KEYS)[number];
export type SystemMapLaneKey = "fundacao" | "operacao" | "saida" | "resultado" | "controle";

export type SystemModuleDependency = {
  moduleKey: SystemModuleKey;
  access: "read_only" | "read_write";
  required: boolean;
};

export type SystemModuleDetail = {
  moduleKey: SystemModuleKey;
  displayName: string;
  shortName: string;
  description: string;
  ownerDomain: string;
  isCore: boolean;
  sortOrder: number;
  lane: SystemMapLaneKey;
  primaryRoute: string | null;
  dependencies: readonly SystemModuleDependency[];
  capabilities: readonly string[];
};

export const SYSTEM_MODULE_CATALOG = [
  {
    moduleKey: "core",
    displayName: "Nucleo",
    shortName: "Nucleo",
    description: "Sessao, painel, configuracao, diagnostico e runtime modular.",
    ownerDomain: "sistema",
    isCore: true,
    sortOrder: 10,
    lane: "fundacao",
    primaryRoute: "/",
    dependencies: [],
    capabilities: ["Sessao e health-check", "Ambiente autoritativo", "Gate de rotas", "Rollout por modulo"]
  },
  {
    moduleKey: "seguranca",
    displayName: "Seguranca",
    shortName: "Seguranca",
    description: "Usuarios, convites, senhas, perfis, alcadas e auditoria de acesso.",
    ownerDomain: "seguranca",
    isCore: true,
    sortOrder: 20,
    lane: "fundacao",
    primaryRoute: "/seguranca",
    dependencies: [{ moduleKey: "core", access: "read_write", required: true }],
    capabilities: ["Login e sessao", "Convite por email", "Permissoes por check", "Action logs"]
  },
  {
    moduleKey: "cadastros",
    displayName: "Cadastros",
    shortName: "Cadastros",
    description: "Clientes, propriedades, pessoas, materias-primas, produtos e embalagens.",
    ownerDomain: "cadastros",
    isCore: false,
    sortOrder: 100,
    lane: "fundacao",
    primaryRoute: "/cadastros",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true }
    ],
    capabilities: ["Cliente e propriedades", "Pessoas e papeis", "MP, PA e PI", "Embalagens e conversoes"]
  },
  {
    moduleKey: "pedidos",
    displayName: "Pedidos",
    shortName: "Pedidos",
    description: "Pedido, credito, itens, comissionados, transicoes e Kanban comercial.",
    ownerDomain: "pedidos",
    isCore: false,
    sortOrder: 200,
    lane: "operacao",
    primaryRoute: "/pedidos",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_only", required: true }
    ],
    capabilities: ["Pedido por propriedade", "Credito e bloqueios", "Multiplos comissionados", "Kanban por vendedor"]
  },
  {
    moduleKey: "estoque",
    displayName: "Estoque",
    shortName: "Estoque",
    description: "Lotes, movimentos append-only, reservas, reversoes e saldos derivados.",
    ownerDomain: "estoque",
    isCore: false,
    sortOrder: 300,
    lane: "operacao",
    primaryRoute: "/producao",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_only", required: true }
    ],
    capabilities: ["Lotes MP, PA e PI", "Reserva por documento", "Movimentos imutaveis", "Saldo fisico e disponivel"]
  },
  {
    moduleKey: "pcp",
    displayName: "Producao, PCP e CQ",
    shortName: "Producao",
    description: "Formulas, ordens de producao, CQ, garantias e transformacoes.",
    ownerDomain: "pcp",
    isCore: false,
    sortOrder: 400,
    lane: "operacao",
    primaryRoute: "/producao",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_only", required: true },
      { moduleKey: "estoque", access: "read_write", required: true }
    ],
    capabilities: ["Formula versionada", "OP e reserva", "CQ e lote bloqueado", "PA/PI e reprocessamento"]
  },
  {
    moduleKey: "expedicao",
    displayName: "Romaneio e expedicao",
    shortName: "Romaneio",
    description: "Separacao parcial ou total, reserva multilote, confirmacao e estorno.",
    ownerDomain: "expedicao",
    isCore: false,
    sortOrder: 500,
    lane: "saida",
    primaryRoute: "/romaneios",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "pedidos", access: "read_write", required: true },
      { moduleKey: "estoque", access: "read_write", required: true }
    ],
    capabilities: ["Multi-item e multilote", "Separacao parcial", "Baixa de PA confirmada", "Estorno auditado"]
  },
  {
    moduleKey: "importacao",
    displayName: "Importacao XML",
    shortName: "XML de MP",
    description: "Staging, conferencia, conversao e entrada de materia-prima por NF-e XML.",
    ownerDomain: "importacao",
    isCore: false,
    sortOrder: 600,
    lane: "operacao",
    primaryRoute: "/importacao-xml",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_write", required: true },
      { moduleKey: "estoque", access: "read_write", required: true }
    ],
    capabilities: ["Leitura XML", "Escolha da MP", "Conversao de unidade", "Geracao auditada de lote"]
  },
  {
    moduleKey: "faturamento",
    displayName: "Faturamento",
    shortName: "Fiscal",
    description: "Documentos fiscais, remessas, complementos, devolucoes e eventos.",
    ownerDomain: "faturamento",
    isCore: false,
    sortOrder: 700,
    lane: "saida",
    primaryRoute: null,
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "pedidos", access: "read_write", required: true },
      { moduleKey: "expedicao", access: "read_only", required: true }
    ],
    capabilities: ["NF por pedido", "Simples faturamento", "Remessa vinculada", "Eventos fiscais imutaveis"]
  },
  {
    moduleKey: "financeiro",
    displayName: "Financeiro e comissoes",
    shortName: "Financeiro",
    description: "Recebimentos, alocacoes, liberacoes e conta corrente de comissao.",
    ownerDomain: "financeiro",
    isCore: false,
    sortOrder: 800,
    lane: "resultado",
    primaryRoute: "/pedidos",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "pedidos", access: "read_only", required: true },
      { moduleKey: "faturamento", access: "read_only", required: true }
    ],
    capabilities: ["Recebimento parcial", "Alocacao por NF", "Comissao proporcional", "Debitos e ajustes auditados"]
  },
  {
    moduleKey: "metas",
    displayName: "Metas comerciais",
    shortName: "Metas",
    description: "Periodos customizados e ledger de vendas, cancelamentos e devolucoes.",
    ownerDomain: "metas",
    isCore: false,
    sortOrder: 900,
    lane: "resultado",
    primaryRoute: null,
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "pedidos", access: "read_only", required: true }
    ],
    capabilities: ["Periodo customizado", "Venda aberta", "Abatimento por evento", "Base para faixas de comissao"]
  },
  {
    moduleKey: "relatorios",
    displayName: "Relatorios",
    shortName: "Relatorios",
    description: "Read models, reconciliacoes, indicadores e rastreabilidade transversal.",
    ownerDomain: "relatorios",
    isCore: false,
    sortOrder: 1000,
    lane: "controle",
    primaryRoute: "/relatorios",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_only", required: false },
      { moduleKey: "pedidos", access: "read_only", required: false },
      { moduleKey: "estoque", access: "read_only", required: false },
      { moduleKey: "pcp", access: "read_only", required: false },
      { moduleKey: "expedicao", access: "read_only", required: false },
      { moduleKey: "faturamento", access: "read_only", required: false },
      { moduleKey: "financeiro", access: "read_only", required: false },
      { moduleKey: "metas", access: "read_only", required: false }
    ],
    capabilities: ["Vendas e comissoes", "Saldos e vencimentos", "Rastreabilidade de lotes", "Reconciliacao com Excel"]
  },
  {
    moduleKey: "auditoria",
    displayName: "Auditoria e migracao",
    shortName: "Auditoria",
    description: "Fonte historica, batches, issues, reconciliacoes e evidencias.",
    ownerDomain: "auditoria",
    isCore: false,
    sortOrder: 1100,
    lane: "controle",
    primaryRoute: "/importacao-historica/mp",
    dependencies: [
      { moduleKey: "core", access: "read_write", required: true },
      { moduleKey: "seguranca", access: "read_only", required: true },
      { moduleKey: "cadastros", access: "read_only", required: false },
      { moduleKey: "pedidos", access: "read_only", required: false },
      { moduleKey: "estoque", access: "read_only", required: false },
      { moduleKey: "pcp", access: "read_only", required: false }
    ],
    capabilities: ["Fonte e hash", "Batch e linha original", "Historico MP e aliases", "Reconciliacao de valores"]
  }
] as const satisfies readonly SystemModuleDetail[];

export const SYSTEM_MAP_LANES: ReadonlyArray<{
  laneKey: SystemMapLaneKey;
  label: string;
  description: string;
  moduleKeys: readonly SystemModuleKey[];
}> = [
  {
    laneKey: "fundacao",
    label: "1. Fundacao",
    description: "Identidade, regras centrais e dados mestres.",
    moduleKeys: ["core", "seguranca", "cadastros"]
  },
  {
    laneKey: "operacao",
    label: "2. Operacao",
    description: "Venda, materiais e transformacao fisica.",
    moduleKeys: ["pedidos", "estoque", "pcp", "importacao"]
  },
  {
    laneKey: "saida",
    label: "3. Saida",
    description: "Separacao, entrega e documento fiscal.",
    moduleKeys: ["expedicao", "faturamento"]
  },
  {
    laneKey: "resultado",
    label: "4. Resultado",
    description: "Dinheiro recebido, comissoes e metas.",
    moduleKeys: ["financeiro", "metas"]
  },
  {
    laneKey: "controle",
    label: "5. Controle",
    description: "Visibilidade, rastreabilidade e preservacao historica.",
    moduleKeys: ["relatorios", "auditoria"]
  }
];

export const SYSTEM_FLOWS: ReadonlyArray<{
  flowKey: string;
  title: string;
  description: string;
  moduleKeys: readonly SystemModuleKey[];
}> = [
  {
    flowKey: "venda",
    title: "Venda ate recebimento",
    description: "Do cadastro do cliente ao resultado comercial.",
    moduleKeys: ["cadastros", "pedidos", "expedicao", "faturamento", "financeiro", "metas", "relatorios"]
  },
  {
    flowKey: "producao",
    title: "Producao e transformacao",
    description: "Formula, reserva, CQ, consumo e novo lote.",
    moduleKeys: ["cadastros", "estoque", "pcp", "estoque", "relatorios"]
  },
  {
    flowKey: "entrada_mp",
    title: "Entrada de materia-prima",
    description: "NF-e conferida antes de virar lote e saldo.",
    moduleKeys: ["importacao", "cadastros", "estoque", "pcp"]
  },
  {
    flowKey: "historico",
    title: "Migracao historica",
    description: "Fonte preservada, normalizacao e reconciliacao.",
    moduleKeys: ["auditoria", "cadastros", "pedidos", "estoque", "relatorios"]
  }
];

export function getSystemModuleDetail(moduleKey: string): SystemModuleDetail | null {
  return SYSTEM_MODULE_CATALOG.find((module) => module.moduleKey === moduleKey) ?? null;
}

export function moduleMaturityPercent(lifecycle: string | null): number {
  const values: Record<string, number> = {
    construction: 15,
    technical_validation: 40,
    business_validation: 60,
    pilot: 80,
    operational: 100,
    suspended: 0
  };
  return lifecycle ? values[lifecycle] ?? 0 : 0;
}
