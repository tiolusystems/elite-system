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
  manual("/modulo-indisponivel", "Nucleo", "Modulo indisponivel", "Entender por que uma area permanece protegida e acessar os modulos ja liberados.", {
    before: ["Confira o ambiente e o nome da area apresentados na tela."],
    steps: ["Leia o motivo da indisponibilidade.", "Use Ver modulos disponiveis para consultar as areas liberadas.", "Volte ao inicio para continuar uma operacao disponivel."],
    after: ["Nenhum dado e alterado nesta tela.", "A liberacao futura do modulo depende do rollout governado do ambiente."],
    blockers: ["Modulo suspenso, dependencia indisponivel ou rollout ainda nao autorizado impedem o acesso."],
  }),
  manual("/cadastros", "Cadastros", "Central de Cadastros", "Consultar e manter dados mestres usados pela operacao.", {
    before: ["Pesquise o cadastro antes de criar um novo registro.", "Confirme se possui a alcada individual exigida pela operacao."],
    steps: ["Escolha a area do cadastro.", "Use a busca para localizar registros existentes.", "Abra a acao de criacao ou manutencao.", "Revise a mensagem de confirmacao e o historico quando disponivel."],
    after: ["Cadastros ativos passam a alimentar os respectivos fluxos operacionais.", "Veiculos ativos ficam disponiveis para atribuicao no Romaneio."],
    blockers: ["Duplicidades e dados obrigatorios impedem a gravacao.", "Sem alcada, a consulta pode permanecer disponivel, mas os controles de escrita nao sao exibidos."],
    records: ["Criacoes e mudancas de situacao governadas registram usuario, data e estado anterior ou posterior."]
  }),
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
    steps: ["Pesquise e selecione o cliente.", "Confira limite e situacao de credito.", "Escolha Venda, Bonificacao, Mostruario ou Troca no mesmo formulario.", "Adicione os itens e envie para liberacao.", "O responsavel com alcada de revisao aprova ou reprova com justificativa.", "Depois da aprovacao, use Exportar PDF para imprimir ou salvar o contrato."],
    after: ["Todo pedido nasce bloqueado.", "Pedido liberado pode seguir para impressao, romaneio e faturamento.", "O PDF calcula litros, volumes e peso bruto a partir dos cadastros logisticos."],
    roles: ["Vendedor cria e acompanha pedidos de sua carteira.", "Gerente pode consultar sua equipe e revisar pedidos quando possuir a alcada correspondente.", "Alterar o limite cadastral exige uma permissao financeira individual e independente do papel organizacional."],
    blockers: ["Cliente fora da carteira, item inativo ou dados obrigatorios impedem o envio.", "Bonificacao exige justificativa e nao gera comissao.", "PDF permanece indisponivel enquanto o pedido estiver bloqueado."],
    records: ["Pedido, itens, decisao de credito e justificativa ficam registrados.", "Uma aprovacao excepcional do pedido nao altera o limite cadastral do cliente."],
  }),
  manual("/kanban", "Pedidos", "Kanban comercial", "Acompanhar pedidos por situacao e responsabilidade comercial."),
  manual("/producao", "Producao", "Producao", "Acompanhar a cadeia de formula, OP, reserva, CQ e lote."),
  manual("/producao/formulas", "Producao", "Formulas", "Criar e versionar formulas operacionais e documentais.", {
    before: ["Produto e materias-primas devem estar ativos.", "A formula operacional usa base de 1 litro; a formula MAPA e documental."],
    steps: ["Consulte as referencias vigentes ou use os filtros para abrir o historico.", "Selecione Nova formula ou use uma versao anterior como base.", "Informe produto, finalidade e componentes por litro; repetir a mesma solicitacao nao cria outra versao.", "Registre a justificativa, salve e confira os detalhes da nova versao.", "Ative somente a versao conferida e informe o motivo da ativacao."],
    after: ["A versao operacional ativa e revisada pode abrir OP.", "A formula MAPA permanece documental e nao movimenta estoque.", "Nova alteracao gera outra versao e preserva a anterior."],
    blockers: ["Formula operacional sem componente ou unidade por litro e recusada.", "Versao historica sem base por litro comprovada precisa ser copiada e revisada antes de abrir OP.", "Sem alcada, a criacao ou ativacao e negada pelo banco."],
    records: ["Produto, finalidade, componentes, justificativa, versao e ativacao permanecem auditaveis.", "A formula nao reserva nem baixa estoque; isso ocorre no fluxo da OP."]
  }),
  manual("/producao/garantias", "Producao", "Garantias", "Consultar garantias declaradas e calculadas por lote.", {
    before: ["Cadastre nutrientes, unidades e garantias das materias-primas.", "A garantia final depende dos lotes realmente consumidos e do CQ."],
    steps: ["Consulte a garantia declarada do produto, sem confundi-la com análise de lote.", "Registre a garantia analisada e a densidade do lote de matéria-prima com fonte, documento e justificativa.", "Compare a base física dos lotes consumidos com o resultado calculado da OP.", "Abra as pendências quando faltar densidade, unidade ou garantia de lote."],
    after: ["A declaração permanece a referência documental do produto.", "A análise de MP permanece vinculada ao lote e à sua fonte.", "O cálculo fica vinculado aos insumos consumidos, ao CQ e ao lote produzido."],
    roles: ["Consulta depende da alçada de leitura de Produção.", "Registro e revisão dependem das alçadas atômicas do domínio."],
    blockers: ["Dados técnicos ausentes geram resultado pendente; o sistema nao estima valores.", "Histórico e fontes anteriores são somente leitura."],
    records: ["Garantias declaradas, análises de lote, parâmetros técnicos, cálculos e pendências permanecem versionados e auditáveis."]
  }),
  manual("/producao/ordens", "Producao", "Ordens e reservas", "Consultar OPs, planejar a produção e reservar lotes antes do consumo.", {
    before: ["Use uma fórmula operacional vigente, revisada e com base de 1 litro.", "Confira o volume planejado e mantenha lotes disponíveis para cada componente."],
    steps: ["Consulte a fila por situação, finalidade, código ou produto.", "Use Abrir OP somente para iniciar um novo planejamento.", "Selecione a fórmula vigente e informe o volume; repetir a mesma solicitação não cria outra OP.", "Abra a OP na fila e confira as quantidades necessárias, reservadas e pendentes.", "Consulte os lotes somente dentro do componente que será separado.", "Reserve automaticamente por FIFO; se houver alçada para exceção, escolha outro lote e justifique.", "Use Imprimir OP para gerar a receita operacional com quantidades totais e separação por lote.", "Inicie somente depois que todos os componentes estiverem integralmente reservados."],
    after: ["As reservas comprometem o saldo disponível sem baixar o saldo físico.", "O consumo acontece na finalização da OP, depois da execução e do CQ.", "Cancelamento governado trata as reservas sem apagar o histórico."],
    roles: ["Consulta, criação, reserva, exceção ao FIFO, início e cancelamento são alçadas independentes.", "Nenhuma ação é liberada automaticamente pelo cargo do usuário."],
    blockers: ["Fórmula inativa ou histórica sem base por litro não abre OP.", "Saldo insuficiente, lote bloqueado ou reserva incompleta impedem o início.", "Lote fora da prioridade FIFO exige alçada específica e justificativa com pelo menos 10 caracteres."],
    records: ["A OP preserva fórmula, produto, volume, componentes e estados.", "A impressão mostra somente totais da OP, lotes separados, uso, desvio e rubrica; a base por litro e a validade continuam nos controles internos.", "Cada reserva registra lote, quantidade, prioridade FIFO, usuário e data.", "Início, cancelamento e exceções permanecem auditáveis."]
  }),
  manual("/producao/qualidade", "Produção", "CQ e finalização", "Registrar processo e CQ antes de finalizar a OP.", {
    before: ["A OP deve estar em produção e possuir reservas válidas.", "Tenha volume produzido, perdas e resultados de CQ."],
    steps: ["Selecione a OP em processo.", "Selecione as pessoas cadastradas que separaram, conferiram e formularam.", "Selecione também o responsável pelo CQ e o responsável pela liberação ou bloqueio.", "Registre pH, densidade, volume, massa e temperatura.", "Informe o resultado do CQ e revise a quantidade produzida.", "Finalize para consumir MP, liberar reservas excedentes e criar um único lote PI."],
    after: ["CQ aprovado libera o PI para envase; reprovado preserva o lote bloqueado.", "Perdas ficam registradas separadamente do consumo normal."],
    blockers: ["Sem todos os participantes digitais, dados de processo, CQ ou saída única a OP não finaliza.", "Pessoa inativa não pode ser vinculada a um novo fato.", "Assinatura física não substitui o vínculo digital.", "A transação inteira é recusada quando houver inconsistência; não existe finalização parcial silenciosa."],
    records: ["Processo, participantes por pessoa e função, nomes históricos, CQ, consumo real, perdas, reservas liberadas, lote PI e auditoria ficam registrados."],
  }),
  manual("/producao/envase", "Producao", "OP MAPA e envase", "Emitir a documentacao e controlar a transformacao de PI em PA.", {
    before: ["O lote PI precisa estar liberado.", "Apresentacao e composicao de embalagens devem estar ativas."],
    steps: ["Selecione o lote PI e a apresentação destino.", "Informe o volume planejado.", "Emita conjuntamente o registro interno da OP MAPA e a Ordem de Envase.", "Reserve cada lote de embalagem previsto.", "Imprima a ordem para as assinaturas físicas dos operadores.", "Finalize para baixar PI e embalagens e gerar o lote PA."],
    after: ["O lote PA gerado alimenta estoque e romaneios.", "A OP MAPA permanece documental e nao baixa MP."],
    blockers: ["Sem PI liberado, embalagem reservada ou distribuição completa a ordem não finaliza.", "O envase gera exatamente um lote PA por ordem."],
    records: ["PI de origem, embalagens, quantidades, ordem MAPA, ordem de envase, lote PA, custos e auditoria ficam vinculados."],
  }),
  manual("/producao/estoque", "Estoque", "Lotes e estoque", "Registrar entradas valorizadas e consultar saldos e reservas por lote.", {
    before: ["Escolha primeiro a familia MP, PI ou PA e filtre o produto."],
    steps: ["Pesquise o produto antes de consultar lotes.", "Para MP, abra Registrar entrada e custo e informe lote, documento, quantidade e componentes do custo.", "Abra a apresentação quando aplicável.", "Consulte os lotes e seus saldos físico, reservado e disponível.", "Abra a rastreabilidade para conferir os movimentos, bloqueios e liberações."],
    after: ["A consulta nao altera saldo.", "A entrada cria lote, movimento fisico e camada de custo na mesma transacao.", "Correcoes de estoque exigem novo movimento auditado."],
  }),
  manual("/producao/transformacoes", "Producao", "Transformacoes", "Acompanhar reprocessamentos e transformacoes de produto.", {
    before: ["Tenha lote de origem liberado, fórmula compatível e justificativa operacional."],
    steps: ["Consulte as transformações abertas e históricas.", "Selecione o lote de origem e informe a quantidade planejada.", "Escolha a finalidade operacional: PA para PI, PI para PA, reenvasamento ou reprocessamento.", "Reserve a origem e registre processo, CQ, perdas e lote de destino.", "Finalize somente quando origem, destino e quantidades estiverem conciliados."],
    after: ["Cada transformação cria novos eventos de movimento, sem editar o fato de origem.", "O lote de destino permanece relacionado ao lote de origem para rastreabilidade."],
    roles: ["Consulta, criação, reserva, início, finalização e revisão dependem de alçadas específicas; cargo não concede acesso automaticamente."],
    blockers: ["Lote bloqueado, reserva insuficiente, CQ pendente ou distribuição incompleta impedem a conclusão."],
    records: ["Origem, destino, quantidade, unidade, perdas, justificativa, CQ, usuário e auditoria permanecem registrados."],
  }),
  manual("/romaneios", "Expedicao", "Romaneios", "Separar itens de pedidos por lote, registrar referência fiscal externa e confirmar a baixa física.", {
    before: ["O pedido deve estar liberado e possuir saldo a entregar.", "Produtos PA precisam ter lotes disponiveis e configuracao logistica."],
    steps: ["Abra a lista de pedidos com saldo.", "Selecione o pedido, os itens da entrega parcial ou total e a quantidade de cada produto.", "Confira a prévia de litros, volumes e pesos; consultar não grava.", "Grave o rascunho do Romaneio.", "Escolha cada produto gravado e reserve somente seus lotes compatíveis.", "Informe entregador e veículo.", "Registre somente o número da NF de remessa emitida no sistema fiscal externo.", "Confirme o Romaneio para registrar a saída física do estoque."],
    after: ["A reserva reduz o disponivel sem baixar o fisico.", "Registrar a referência fiscal não baixa estoque nem libera comissão.", "A confirmação do Romaneio consolida a saida de estoque.", "O Romaneio pode ser impresso antes ou depois da referência externa."],
    blockers: ["Quantidade acima do saldo do pedido ou do lote e recusada.", "Falta de referência de remessa, entregador, veiculo ou dados logisticos impede a baixa final."],
  }),
  manual("/qualidade/rastreabilidade", "Qualidade", "Rastreabilidade total", "Consultar a genealogia de lotes, destinos e referências externas e simular recolhimento sem movimentar estoque.", {
    before: ["Tenha ao menos um código de lote, OP, pedido, Romaneio, cliente ou referência fiscal externa.", "A consulta depende de alçada individual de Qualidade."],
    steps: ["Informe o tipo e o código apresentado do ponto de partida.", "Escolha a direção para frente, para trás ou ambas.", "Revise cada elo da cadeia, incluindo quantidades e eventos de estorno.", "Use Simular recolhimento para listar somente destinos ativos.", "Exporte CSV quando possuir a alçada específica."],
    after: ["A consulta e a simulação não alteram lotes, pedidos ou expedições.", "A exportação registra usuário, data e filtros na auditoria."],
    blockers: ["Falta de alçada ou genealogia operacional incompleta impedem o resultado.", "Divergências devem ser investigadas; a tela não as corrige silenciosamente."],
  }),
  manual("/qualidade/pops", "Qualidade", "POPs e documentos controlados", "Cadastrar, versionar e vincular procedimentos industriais e de qualidade sem alterar OPs historicas.", {
    before: ["Defina codigo, titulo, finalidade, revisao, vigencia e referencia documental.", "Confirme a alcada individual para criar, publicar ou vincular um documento controlado."],
    steps: ["Pesquise o procedimento pelo codigo ou titulo.", "Crie a revisao em rascunho e confira o conteudo.", "Publique a versao com justificativa.", "Ative o POP e vincule a versao publicada a uma etapa ou formula.", "Abra uma nova OP para confirmar as referencias congeladas."],
    after: ["Versoes publicadas permanecem imutaveis.", "Novas revisoes nao alteram OPs abertas ou concluidas.", "A impressao da OP mostra somente codigo, titulo, revisao e vigencia."],
    roles: ["Consulta e manutencao dependem de alcadas individuais do PCP e Controle de Qualidade."],
    blockers: ["Versao em rascunho ou POP inativo nao pode receber novo vinculo.", "Falta de justificativa impede publicacao, ativacao e mudanca de aplicabilidade."],
    records: ["Versoes, estado, aplicabilidade, congelamento na OP e observacoes do CQ permanecem auditaveis."]
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
