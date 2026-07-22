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

type ManualGuide = Partial<Pick<RouteManual, "before" | "steps" | "after" | "roles" | "blockers" | "records">>;

export const ROUTE_MANUALS: RouteManual[] = [
  manual("/", "Nucleo", "Inicio", "Acompanhar o ambiente, os modulos liberados e os principais proximos passos."),
  manual("/modulos", "Nucleo", "Modulos", "Consultar disponibilidade, maturidade e dependencias dos modulos."),
  manual("/cadastros", "Cadastros", "Central de Cadastros", "Consultar e manter dados mestres usados pela operacao."),
  manual("/cadastros/materias-primas", "Cadastros", "Materias-primas", "Cadastrar e revisar insumos, unidades e classificacoes governadas.", {
    before: ["Tenha SKU, nome, tipo de insumo e unidade de estoque.", "Confirme se ja existe material com nome ou codigo semelhante."],
    steps: ["Pesquise o material antes de criar.", "Abra Novo insumo e preencha identidade, unidade e classificacao.", "Revise os candidatos a duplicidade.", "Confirme e justifique somente quando for um cadastro realmente distinto."],
    after: ["O insumo fica disponivel para lotes, formulas e XML conforme sua situacao.", "Dados tecnicos ou regulatorios pendentes continuam sinalizados."],
    blockers: ["SKU repetido e unidade invalida bloqueiam a gravacao.", "Possivel duplicidade exige revisao e justificativa."],
  }),
  manual("/cadastros/tipos-insumo", "Cadastros", "Tipos de insumo", "Manter o catalogo controlado de classificacao dos insumos."),
  manual("/cadastros/produtos", "Cadastros", "Produtos", "Manter produtos, apresentacoes e composicoes de embalagem.", {
    before: ["Cadastre o produto base antes da apresentacao.", "Tenha capacidade, unidade, itens da embalagem, tara e unidades por volume logistico."],
    steps: ["Pesquise o produto pelo codigo ou nome.", "Crie ou edite o produto base.", "Vincule uma embalagem para formar a apresentacao vendavel.", "Revise e ative a composicao da embalagem.", "Informe unidades por volume logistico para calculos de carga."],
    after: ["A apresentacao ativa pode ser usada em pedidos, envase, estoque PA e romaneio.", "Alteracoes futuras criam nova versao sem apagar o historico."],
    blockers: ["Codigo, capacidade ou relacionamento invalido bloqueiam a gravacao.", "Composicao nao revisada nao pode ser ativada."],
  }),
  manual("/cadastros/grupos-produto", "Cadastros", "Grupos de produto", "Organizar produtos PA e PI em famílias comerciais e gerenciais governadas.", {
    before: ["Pesquise o grupo para evitar duplicidade de código ou nome.", "Defina um nome estável e uma descrição que explique seu uso."],
    steps: ["Pesquise por código ou nome.", "Crie o grupo e defina sua ordem de exibição.", "Abra um grupo para editar ou consultar os produtos vinculados.", "Justifique alterações, inativação ou reativação."],
    after: ["Grupos ativos podem ser selecionados em novos produtos.", "Ao inativar, produtos históricos mantêm o vínculo e nenhuma fórmula, pedido ou OP é alterada."],
    roles: ["Usuários autenticados com permissão específica de consulta ou manutenção de grupos."],
    blockers: ["Código ou nome duplicado é recusado.", "Grupo inativo não pode ser atribuído a novo produto."],
    records: ["Criação, edição, inativação e reativação são auditadas com estado anterior, posterior e justificativa."],
  }),
  manual("/cadastros/embalagens", "Cadastros", "Embalagens", "Manter embalagens e capacidades usadas no envase e na expedicao."),
  manual("/cadastros/unidades", "Cadastros", "Unidades e conversoes", "Manter unidades governadas e conversoes autorizadas."),
  manual("/cadastros/tecnicos", "Cadastros", "Cadastros tecnicos", "Consultar catalogos tecnicos usados em formulas e garantias."),
  manual("/pedidos", "Pedidos", "Pedidos", "Pesquisar clientes da carteira, criar pedidos e acompanhar aprovacao.", {
    before: ["O cliente deve estar vinculado a carteira do vendedor.", "As apresentacoes precisam estar ativas e os precos devem ser conferidos."],
    steps: ["Pesquise e selecione o cliente.", "Confira limite e situacao de credito.", "Escolha Venda, Bonificacao, Mostruario ou Troca no mesmo formulario.", "Adicione os itens e envie para liberacao.", "O gerente aprova ou reprova com justificativa.", "Depois da aprovacao, use Exportar PDF para imprimir ou salvar o contrato."],
    after: ["Todo pedido nasce bloqueado.", "Pedido liberado pode seguir para impressao, romaneio e faturamento.", "O PDF calcula litros, volumes e peso bruto a partir dos cadastros logisticos."],
    roles: ["Vendedor cria e acompanha pedidos de sua carteira.", "Gerente consulta sua equipe, ajusta limite autorizado e decide a liberacao; repeticoes da mesma solicitacao nao duplicam o evento financeiro."],
    blockers: ["Cliente fora da carteira, item inativo ou dados obrigatorios impedem o envio.", "Bonificacao exige justificativa e nao gera comissao.", "PDF permanece indisponivel enquanto o pedido estiver bloqueado."],
    records: ["Pedido, itens, decisao gerencial, justificativa, limite e auditoria ficam registrados."],
  }),
  manual("/kanban", "Pedidos", "Kanban comercial", "Acompanhar pedidos por situacao e responsabilidade comercial."),
  manual("/producao", "Producao", "Producao", "Acompanhar a cadeia de formula, OP, reserva, CQ e lote."),
  manual("/producao/formulas", "Producao", "Formulas", "Criar e versionar formulas operacionais e documentais.", {
    before: ["Produto e materias-primas devem estar ativos.", "A formula operacional usa base de 1 litro; a formula MAPA e documental."],
    steps: ["Selecione o produto.", "Crie uma versao e informe os componentes por litro; repetir a mesma solicitacao nao cria outra versao.", "Revise o rendimento e as etapas.", "Ative somente a versao conferida."],
    after: ["A versao ativa pode abrir OP.", "Nova alteracao gera outra versao e preserva a anterior."],
  }),
  manual("/producao/garantias", "Producao", "Garantias", "Consultar garantias declaradas e calculadas por lote.", {
    before: ["Cadastre nutrientes, unidades e garantias das materias-primas.", "A garantia final depende dos lotes realmente consumidos e do CQ."],
    steps: ["Selecione produto, formula, OP ou lote.", "Compare garantia declarada e resultado calculado.", "Abra as pendencias quando faltar densidade, unidade ou garantia de lote."],
    after: ["O resultado fica vinculado aos insumos consumidos e ao lote produzido."],
    blockers: ["Dados tecnicos ausentes geram resultado pendente; o sistema nao estima valores."],
  }),
  manual("/producao/ordens", "Producao", "Ordens de producao", "Abrir OP, reservar componentes e iniciar a producao.", {
    before: ["Use formula operacional ativa e informe o volume planejado.", "Confira os lotes de MP e seus saldos."],
    steps: ["Crie a OP para um unico produto; repeticoes da mesma solicitacao nao abrem outra OP.", "Revise os componentes calculados.", "Reserve lotes por FIFO ou justifique escolha manual autorizada.", "Confirme as reservas e inicie a producao."],
    after: ["As reservas comprometem o saldo sem consumi-lo.", "O consumo ocorre na finalizacao da OP."],
    blockers: ["Saldo insuficiente, formula inativa ou reserva incompleta impedem o inicio."],
  }),
  manual("/producao/qualidade", "Producao", "CQ e finalizacao", "Registrar processo e CQ antes de finalizar a OP.", {
    before: ["A OP deve estar em producao e possuir reservas validas.", "Tenha volume produzido, perdas e resultados de CQ."],
    steps: ["Selecione a OP.", "Registre processo, volume obtido, perdas e CQ.", "Revise o resultado.", "Finalize para consumir MP e criar um unico lote PI."],
    after: ["CQ aprovado libera o PI para envase; reprovado preserva o lote bloqueado.", "Perdas ficam registradas separadamente do consumo normal."],
  }),
  manual("/producao/envase", "Producao", "OP MAPA e envase", "Emitir a documentacao e controlar a transformacao de PI em PA.", {
    before: ["O lote PI precisa estar liberado.", "Apresentacao e composicao de embalagens devem estar ativas."],
    steps: ["Selecione o lote PI e a apresentacao destino.", "Informe o volume de envase.", "Emita conjuntamente a OP MAPA e a Ordem de Envase.", "Imprima para assinaturas fisicas dos operadores.", "Finalize para baixar PI e embalagens e gerar o lote PA."],
    after: ["O lote PA gerado alimenta estoque e romaneios.", "A OP MAPA permanece documental e nao baixa MP."],
  }),
  manual("/producao/estoque", "Estoque", "Lotes e estoque", "Consultar saldos, reservas e rastreabilidade por lote.", {
    before: ["Escolha primeiro a familia MP, PI ou PA e filtre o produto."],
    steps: ["Pesquise o produto.", "Abra a apresentacao quando aplicavel.", "Consulte os lotes e seus saldos fisico, reservado e disponivel.", "Abra a rastreabilidade para conferir os movimentos."],
    after: ["A consulta nao altera saldo.", "Correcoes de estoque exigem novo movimento auditado."],
  }),
  manual("/producao/transformacoes", "Producao", "Transformacoes", "Acompanhar reprocessamentos e transformacoes de produto."),
  manual("/romaneios", "Expedicao", "Romaneios", "Separar itens de pedidos por lote e consolidar a baixa com a NF.", {
    before: ["O pedido deve estar liberado e possuir saldo a entregar.", "Produtos PA precisam ter lotes disponiveis e configuracao logistica."],
    steps: ["Abra a lista de pedidos com saldo.", "Selecione o pedido e os itens da entrega parcial ou total.", "Informe a quantidade de cada produto.", "Consulte e reserve os lotes do produto selecionado.", "Grave o romaneio.", "Informe NF, entregador e veiculo antes de confirmar a baixa."],
    after: ["A reserva reduz o disponivel sem baixar o fisico.", "A NF emitida e a confirmacao consolidam a saida de estoque.", "O romaneio pode ser impresso apos a reserva ou depois da NF."],
    blockers: ["Quantidade acima do saldo do pedido ou do lote e recusada.", "Falta de NF, entregador, veiculo ou dados logisticos impede a baixa final."],
  }),
  manual("/pedidos/financeiro", "Financeiro", "Recebimentos e comissoes", "Registrar dinheiro recebido e controlar a conta corrente de comissoes.", {
    before: ["O pedido de venda deve estar liberado ou atendido e possuir saldo financeiro aberto.", "Pagamentos e ajustes de comissao exigem permissao financeira especifica."],
    steps: ["Em venda aprovada e ainda sem recebimento, defina vendedor, agente ou gerente com percentual e justificativa.", "Selecione um pedido com saldo e registre o recebimento.", "Confira a liberacao proporcional gerada para os comissionados do pedido.", "Consulte o saldo por pessoa.", "Registre pagamento ou ajuste manual somente com documento e motivo adequados."],
    after: ["Cada recebimento libera somente a fracao correspondente da comissao prevista.", "Recebimentos, liberacoes, pagamentos e ajustes permanecem em ledgers imutaveis e auditados."],
    roles: ["Financeiro registra recebimentos e pagamentos.", "Gestores autorizados podem executar ajustes manuais justificados.", "Consulta depende das politicas de leitura do dominio."],
    blockers: ["Valor acima do saldo do pedido e recusado.", "O mesmo recebimento nao libera comissao duas vezes.", "Pagamento acima do saldo de comissao e ajuste sem motivo valido sao recusados."],
    records: ["Recebimento, alocacao, liberacao proporcional e movimentos da conta corrente de comissao ficam registrados."],
  }),
  manual("/importacao-xml", "Importacao", "XML de materia-prima", "Conferir a NF-e e relacionar itens aos insumos cadastrados."),
  manual("/importacao-historica/mp", "Auditoria", "Excel historico", "Analisar e homologar fontes historicas antes da importacao."),
  manual("/relatorios", "Relatorios", "Relatorios", "Consultar vendas, estoque e rastreabilidade conforme as permissoes."),
  manual("/seguranca", "Seguranca", "Seguranca", "Administrar usuarios, convites e permissoes auditadas."),
];

export function manualForPath(pathname: string): RouteManual | null {
  return ROUTE_MANUALS
    .filter((entry) => pathname === entry.route || pathname.startsWith(`${entry.route}/`))
    .sort((left, right) => right.route.length - left.route.length)[0] ?? null;
}

function manual(route: string, module: string, title: string, purpose: string, guide: ManualGuide = {}): RouteManual {
  return {
    route,
    module,
    title,
    purpose,
    before: guide.before ?? ["Confirme o ambiente exibido no cabecalho.", "Tenha os dados e documentos necessarios para a operacao."],
    steps: guide.steps ?? ["Localize o registro ou processo.", "Revise os dados antes de confirmar.", "Execute somente a acao compativel com sua permissao."],
    after: guide.after ?? ["Confira a mensagem de resultado.", "Consulte o historico ou a proxima etapa indicada pela tela."],
    roles: guide.roles ?? ["Usuarios autenticados com permissao para a area."],
    blockers: guide.blockers ?? ["Cadastro incompleto, falta de permissao ou dependencia ainda nao liberada impedem a operacao."],
    records: guide.records ?? ["Acoes de escrita geram historico e auditoria conforme o dominio proprietario."],
  };
}
