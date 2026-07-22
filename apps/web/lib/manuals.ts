export type RouteManual = {
  route: string;
  module: string;
  title: string;
  purpose: string;
  before: string[];
  steps: string[];
  after: string[];
  roles: string[];
  blockers: string[];
  records: string[];
};

export const ROUTE_MANUALS: RouteManual[] = [
  manual("/", "Nucleo", "Inicio", "Acompanhar o ambiente, os modulos liberados e os principais proximos passos."),
  manual("/modulos", "Nucleo", "Modulos", "Consultar disponibilidade, maturidade e dependencias dos modulos."),
  manual("/cadastros", "Cadastros", "Central de Cadastros", "Consultar e manter dados mestres usados pela operacao."),
  manual("/cadastros/materias-primas", "Cadastros", "Materias-primas", "Cadastrar e revisar insumos, unidades e classificacoes governadas."),
  manual("/cadastros/tipos-insumo", "Cadastros", "Tipos de insumo", "Manter o catalogo controlado de classificacao dos insumos."),
  manual("/cadastros/produtos", "Cadastros", "Produtos", "Manter produtos, apresentacoes e composicoes de embalagem."),
  manual("/cadastros/embalagens", "Cadastros", "Embalagens", "Manter embalagens e capacidades usadas no envase e na expedicao."),
  manual("/cadastros/unidades", "Cadastros", "Unidades e conversoes", "Manter unidades governadas e conversoes autorizadas."),
  manual("/cadastros/tecnicos", "Cadastros", "Cadastros tecnicos", "Consultar catalogos tecnicos usados em formulas e garantias."),
  manual("/pedidos", "Pedidos", "Pedidos", "Pesquisar clientes da carteira, criar pedidos e acompanhar aprovacao."),
  manual("/kanban", "Pedidos", "Kanban comercial", "Acompanhar pedidos por situacao e responsabilidade comercial."),
  manual("/producao", "Producao", "Producao", "Acompanhar a cadeia de formula, OP, reserva, CQ e lote."),
  manual("/producao/formulas", "Producao", "Formulas", "Criar e versionar formulas operacionais e documentais."),
  manual("/producao/garantias", "Producao", "Garantias", "Consultar garantias declaradas e calculadas por lote."),
  manual("/producao/ordens", "Producao", "Ordens de producao", "Abrir OP, reservar componentes e iniciar a producao."),
  manual("/producao/qualidade", "Producao", "CQ e finalizacao", "Registrar processo e CQ antes de finalizar a OP."),
  manual("/producao/envase", "Producao", "OP MAPA e envase", "Emitir a documentacao e controlar a transformacao de PI em PA."),
  manual("/producao/estoque", "Estoque", "Lotes e estoque", "Consultar saldos, reservas e rastreabilidade por lote."),
  manual("/producao/transformacoes", "Producao", "Transformacoes", "Acompanhar reprocessamentos e transformacoes de produto."),
  manual("/romaneios", "Expedicao", "Romaneios", "Separar itens de pedidos por lote e consolidar a baixa com a NF."),
  manual("/importacao-xml", "Importacao", "XML de materia-prima", "Conferir a NF-e e relacionar itens aos insumos cadastrados."),
  manual("/importacao-historica/mp", "Auditoria", "Excel historico", "Analisar e homologar fontes historicas antes da importacao."),
  manual("/relatorios", "Relatorios", "Relatorios", "Consultar vendas, estoque e rastreabilidade conforme as permissoes."),
  manual("/seguranca", "Seguranca", "Seguranca", "Administrar usuarios, convites e permissoes auditadas.")
];

export function manualForPath(pathname: string): RouteManual | null {
  return ROUTE_MANUALS
    .filter((manual) => pathname === manual.route || pathname.startsWith(`${manual.route}/`))
    .sort((left, right) => right.route.length - left.route.length)[0] ?? null;
}

function manual(route: string, module: string, title: string, purpose: string): RouteManual {
  return {
    route,
    module,
    title,
    purpose,
    before: ["Confirme o ambiente exibido no cabecalho.", "Tenha os dados e documentos necessarios para a operacao."],
    steps: ["Localize o registro ou processo.", "Revise os dados antes de confirmar.", "Execute somente a acao compatível com sua permissao."],
    after: ["Confira a mensagem de resultado.", "Consulte o historico ou a proxima etapa indicada pela tela."],
    roles: ["Usuarios autenticados com permissao para a area."],
    blockers: ["Cadastro incompleto, falta de permissao ou dependencia ainda nao liberada impedem a operacao."],
    records: ["Acoes de escrita geram historico e auditoria conforme o dominio proprietario."]
  };
}
