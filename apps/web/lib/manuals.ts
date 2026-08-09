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
    steps: ["Escolha a area do cadastro.", "Em Clientes, pesquise por identidade, documento, codigo, propriedade, localizacao ou contato e use os filtros da consulta.", "Abra a ficha desejada; a consulta permanece separada da manutencao e pode ser retomada pelo botao Voltar aos clientes.", "Use Novo cliente somente depois de confirmar que o registro ainda nao existe.", "Revise a mensagem de confirmacao e o historico quando disponivel."],
    after: ["Cadastros ativos passam a alimentar os respectivos fluxos operacionais.", "Veiculos ativos ficam disponiveis para atribuicao no Romaneio."],
    blockers: ["Nenhum resultado indica que os termos ou filtros devem ser revisados; isso nao cria cadastro automaticamente.", "Duplicidades e dados obrigatorios impedem a gravacao.", "Sem alcada, a consulta pode permanecer disponivel, mas os controles de escrita nao sao exibidos."],
    records: ["Criacoes e mudancas de situacao governadas registram usuario, data e estado anterior ou posterior."]
  }),
  manual("/cadastros/materias-primas", "Cadastros", "Materias-primas", "Cadastrar e revisar insumos, unidades e classificacoes governadas.", {
    before: ["Tenha SKU, nome, tipo de insumo e unidade de estoque.", "Confirme se ja existe material com nome ou codigo semelhante."],
    steps: ["Pesquise o material antes de criar.", "Abra Novo insumo e preencha identidade, unidade e classificacao.", "Revise os candidatos a duplicidade.", "Confirme e justifique somente quando for um cadastro realmente distinto."],
    after: ["O insumo fica disponivel para lotes, formulas e XML conforme sua situacao.", "Dados tecnicos ou regulatorios pendentes continuam sinalizados."],
    blockers: ["SKU repetido e unidade invalida bloqueiam a gravacao.", "Possivel duplicidade exige revisao e justificativa."],
  }),
  manual("/cadastros/tipos-insumo", "Cadastros", "Tipos de insumo", "Manter o catálogo controlado de classificação dos insumos.", {
    before: ["Pesquise o tipo antes de criar outro.", "Tenha código, nome e finalidade operacional definidos."],
    steps: ["Localize o tipo pelo código ou nome.", "Crie ou edite o cadastro com a alçada correspondente.", "Revise as matérias-primas vinculadas.", "Justifique a inativação ou reativação."],
    after: ["Tipos ativos podem ser usados em novos vínculos de matéria-prima.", "Tipos inativos permanecem legíveis nos vínculos históricos."],
    roles: ["Consulta e manutenção dependem de alçadas individuais de Cadastros."],
    blockers: ["Código ou nome duplicado é recusado.", "Tipo inativo não pode ser usado em novo vínculo."],
    records: ["Criação, edição e mudança de situação ficam auditadas sem exclusão física."]
  }),
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
  manual("/cadastros/embalagens", "Cadastros", "Embalagens", "Manter embalagens, composição, tara e capacidade usadas no envase e na expedição.", {
    before: ["Pesquise a embalagem antes de criar.", "Tenha capacidade, unidade, tara e composição física conferidas."],
    steps: ["Consulte a embalagem pelo código ou descrição.", "Crie ou edite a identidade e os dados físicos.", "Crie uma nova versão da composição quando houver mudança.", "Inclua os componentes, revise e ative a versão.", "Informe a configuração logística usada para volumes e peso bruto."],
    after: ["A versão ativa alimenta envase, estoque PA, pedido e Romaneio.", "Versões anteriores permanecem somente leitura."],
    roles: ["Consulta, edição, revisão e ativação são alçadas independentes."],
    blockers: ["Capacidade inválida, composição vazia ou versão não revisada impedem a ativação.", "Embalagem inativa não pode ser usada em nova apresentação."],
    records: ["Identidade, dados físicos, componentes, revisão, ativação e justificativas ficam versionados."]
  }),
  manual("/cadastros/unidades", "Cadastros", "Unidades e conversões", "Manter unidades governadas e conversões autorizadas de matéria-prima.", {
    before: ["Confirme a unidade de origem, a unidade de estoque e o fator documentado.", "Não use conversão estimada."],
    steps: ["Consulte as unidades disponíveis.", "Selecione a matéria-prima quando a conversão for específica.", "Informe origem, destino, fator e referência.", "Revise o resultado antes de gravar."],
    after: ["Conversões válidas podem normalizar entradas e consumos para a unidade de estoque.", "A unidade apresentada ao operador permanece em PT-BR."],
    roles: ["Somente usuários com alçada de catálogo técnico podem criar conversões."],
    blockers: ["Fator zero ou negativo, unidade desconhecida e conversão sem fonte são recusados."],
    records: ["Origem, destino, fator, fonte, usuário e data permanecem auditáveis."]
  }),
  manual("/cadastros/tecnicos", "Cadastros", "Cadastros técnicos", "Consultar a base técnica que alimenta fórmulas, estoque, produção e rastreabilidade.", {
    before: ["Use esta tela como portal; a manutenção ocorre nas rotas canônicas de cada cadastro."],
    steps: ["Escolha matéria-prima, produto, embalagem, unidade ou tipo de insumo.", "Abra a rota canônica correspondente.", "Pesquise o registro antes de criar ou editar.", "Retorne ao portal para mudar de área."],
    after: ["A navegação não altera dados.", "Cada cadastro mantém sua própria alçada, validação e auditoria."],
    roles: ["Usuários com acesso a Cadastros consultam o portal; cada ação respeita sua alçada específica."],
    blockers: ["Catálogo indisponível ou falta de permissão mantém a área em modo de consulta ou bloqueada."],
    records: ["O portal não grava fatos; as rotas de destino registram as operações executadas."]
  }),
  manual("/pedidos", "Pedidos", "Pedidos", "Pesquisar clientes da carteira, criar pedidos e acompanhar aprovacao.", {
    before: ["O cliente deve estar vinculado a carteira do vendedor.", "O cliente precisa ter propriedade, estabelecimento ou endereco de entrega ativo.", "As apresentacoes precisam estar ativas e os precos devem ser conferidos."],
    steps: ["Escolha um cliente na primeira pagina da carteira ou pesquise por nome, documento, municipio, propriedade ou estabelecimento.", "Confira limite e situacao de credito.", "Selecione o local e a previsao de entrega; use Adicionar outra entrega quando precisar dividir quantidades.", "Escolha o produto e depois a apresentacao comercial correspondente.", "Distribua integralmente os itens entre as entregas.", "Revise cliente, locais, datas, quantidades, valores e confirme o envio.", "O responsavel com alcada de revisao aprova ou reprova com justificativa.", "Depois da aprovacao, use Exportar PDF para imprimir ou salvar o contrato."],
    after: ["Todo pedido nasce bloqueado.", "A programacao de entrega nao reserva nem baixa estoque.", "Pedido liberado pode seguir para impressao, romaneio e faturamento.", "O PDF calcula litros, volumes e peso bruto a partir dos cadastros logisticos."],
    roles: ["Vendedor cria e acompanha pedidos de sua carteira.", "Gerente pode consultar sua equipe e revisar pedidos quando possuir a alcada correspondente.", "Alterar o limite cadastral exige uma permissao financeira individual e independente do papel organizacional."],
    blockers: ["Cliente fora da carteira, local de outro cliente, data anterior ao pedido, apresentacao inativa ou quantidades nao distribuídas impedem o envio.", "Bonificacao exige justificativa e nao gera comissao.", "PDF permanece indisponivel enquanto o pedido estiver bloqueado."],
    records: ["Pedido, itens, programacao de entregas, decisao de credito e justificativa ficam registrados.", "Uma aprovacao excepcional do pedido nao altera o limite cadastral do cliente."],
  }),
  manual("/kanban", "Pedidos", "Kanban comercial", "Acompanhar pedidos por situação e responsabilidade comercial.", {
    before: ["Os pedidos precisam existir e estar dentro do escopo comercial da conta."],
    steps: ["Filtre a fila pela situação desejada.", "Localize o pedido pelo código ou cliente.", "Abra a operação correspondente em Pedidos.", "Retorne ao Kanban para conferir a mudança de situação."],
    after: ["O Kanban apresenta o estado atual; ele não substitui as ações governadas de aprovação, expedição ou recebimento."],
    roles: ["Vendedor vê sua carteira; responsáveis autorizados veem a equipe conforme os vínculos vigentes."],
    blockers: ["Pedido fora do escopo não é exibido.", "Mudanças de situação não são feitas por arraste sem contrato governado."],
    records: ["As mudanças aparecem no Kanban depois do evento auditado no domínio proprietário."]
  }),
  manual("/producao", "Produção", "Produção", "Acompanhar exceções e acessar a cadeia de fórmula, OP, reserva, CQ e lote.", {
    before: ["A visão geral exige alçada supervisória; operadores são direcionados às rotas operacionais permitidas."],
    steps: ["Revise pendências e exceções quando possuir acesso ao painel.", "Abra Fórmulas, Ordens, CQ, Envase ou Estoque pela navegação compacta.", "Use Como operar para consultar a sequência industrial."],
    after: ["O painel não movimenta estoque nem altera OPs.", "As correções são executadas nas telas operacionais correspondentes."],
    roles: ["A visão geral depende de pcp.dashboard.view.", "Cada rota operacional mantém alçadas próprias."],
    blockers: ["Sem alçada do painel, /producao redireciona para a primeira rota operacional disponível."],
    records: ["O painel consulta fatos existentes; as ações auditadas pertencem às telas operacionais."]
  }),
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
    steps: ["Informe o tipo e o código apresentado do ponto de partida.", "Escolha a direção para frente, para trás ou ambas.", "Revise cada elo da cadeia, incluindo quantidades e eventos de estorno.", "Use Simular recolhimento para listar somente destinos ativos.", "Use Exportar e prefira Excel (.xlsx) para trabalho operacional; CSV permanece disponível para integração técnica."],
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
  manual("/pedidos/financeiro/comissionamento", "Financeiro", "Comissionamento do pedido", "Definir as pessoas e os percentuais previstos de uma venda antes do primeiro recebimento.", {
    before: ["O pedido deve estar liberado e ainda não pode possuir recebimento.", "As pessoas comissionadas precisam estar ativas e cadastradas com seus papéis comerciais."],
    steps: ["Pesquise o pedido pelo código ou cliente.", "Abra o pedido e confira o total da venda.", "Adicione uma pessoa por vez, informando papel e percentual.", "Revise o total distribuído e registre uma justificativa operacional.", "Confirme o comissionamento antes do primeiro recebimento."],
    after: ["A definição gera somente comissão prevista.", "A comissão será liberada proporcionalmente quando o recebimento for registrado."],
    roles: ["A operação exige a alçada individual para definir comissionados; nenhum cargo a concede automaticamente."],
    blockers: ["Pedido sem liberação, pessoa inativa, percentual inválido, duplicidade ou recebimento já existente impedem a alteração."],
    records: ["Pessoas, papéis, percentuais, valores previstos, justificativa, usuário e data permanecem auditáveis."],
  }),
  manual("/pedidos/financeiro/recebimentos", "Financeiro", "Recebimentos", "Localizar pedidos com saldo financeiro e registrar valores efetivamente recebidos.", {
    before: ["O pedido deve estar liberado ou atendido e possuir saldo financeiro aberto.", "Tenha a data, a forma e a referência documental do recebimento."],
    steps: ["Pesquise pelo pedido, cliente, documento, propriedade ou referência fiscal externa.", "Abra o pedido e confira total, valor recebido e saldo aberto.", "Revise as referências fiscais e os recebimentos anteriores.", "Informe valor, data, forma e referência documental.", "Confirme uma única vez e aguarde a mensagem de resultado."],
    after: ["O recebimento reduz o saldo financeiro do pedido.", "A comissão prevista é liberada somente na proporção recebida."],
    roles: ["Consulta e registro são alçadas individuais separadas."],
    blockers: ["Valor zero, negativo ou acima do saldo é recusado.", "Referência documental ausente, pedido incompatível ou repetição divergente impedem a gravação."],
    records: ["Recebimento, referência, alocação no pedido, comissão liberada, usuário e data são fatos auditáveis e imutáveis."],
  }),
  manual("/pedidos/financeiro/comissoes/relatorio", "Financeiro", "Relatório de comissões", "Consultar e imprimir a posição integral das comissões a pagar em uma data de corte.", {
    before: ["Defina a data de corte e os filtros de pessoa, papel e saldo.", "A exportação exige alçada própria."],
    steps: ["Aplique os filtros.", "Confira créditos liberados, pagamentos, estornos, ajustes e saldo.", "Imprima a posição quando necessário.", "Use Exportar: Excel (.xlsx) é o formato principal e CSV (.csv) permanece como alternativa técnica."],
    after: ["A consulta, a impressão e a exportação não alteram a conta corrente."],
    roles: ["Consulta e exportação dependem de alçadas individuais distintas."],
    blockers: ["Sem alçada de leitura, o relatório não abre; sem alçada de exportação, as opções de arquivo não são exibidas."],
    records: ["A posição é derivada do histórico financeiro até a data de corte, sem editar movimentos anteriores."],
  }),
  manual("/pedidos/financeiro/comissoes", "Financeiro", "Conta corrente de comissões", "Consultar créditos liberados, pagamentos, estornos, compensações e ajustes por pessoa.", {
    before: ["Pesquise a pessoa ou filtre o saldo na data de corte.", "Pagamento e ajuste manual exigem alçadas independentes."],
    steps: ["Abra a conta corrente da pessoa.", "Confira o histórico cronológico e o saldo.", "Registre pagamento somente até o saldo disponível.", "Use ajuste manual apenas em situação excepcional, com referência e justificativa."],
    after: ["Pagamento e ajuste criam novos movimentos; fatos anteriores não são editados.", "O saldo é recalculado a partir do histórico."],
    roles: ["Leitura, pagamento e ajuste são alçadas individuais separadas; nenhuma função organizacional concede acesso automaticamente."],
    blockers: ["Pagamento acima do saldo, valor inválido, falta de referência ou justificativa insuficiente são recusados."],
    records: ["Cada movimento registra tipo, valor, pedido quando aplicável, referência, justificativa, usuário e data."],
  }),
  manual("/pedidos/financeiro", "Financeiro", "Visão financeira", "Consultar a posição integral de recebíveis, recebimentos e comissões sem executar operações sensíveis.", {
    before: ["Confirme o período e a data de corte.", "As áreas exibidas dependem das alçadas individuais da conta."],
    steps: ["Aplique o período desejado.", "Confira recebíveis em aberto, recebido no período, comissões a pagar e pedidos com saldo.", "Abra Comissionamento, Recebimentos ou Comissões conforme a operação necessária."],
    after: ["A visão financeira não grava recebimentos, pagamentos ou ajustes.", "Os totalizadores consideram a base integral filtrada, não apenas a lista recente."],
    roles: ["Cada atalho é exibido somente quando a conta possui a alçada correspondente."],
    blockers: ["Sem nenhuma alçada financeira, o módulo não aparece no menu e o acesso direto é negado."],
    records: ["A tela apenas consulta fatos já registrados nos domínios financeiro e comercial."],
  }),
  manual("/importacao-xml", "Importação", "XML de matéria-prima", "Conferir uma referência de NF-e externa e relacionar seus itens aos insumos cadastrados.", {
    before: ["O módulo precisa estar liberado no ambiente.", "Use somente XML recebido de fonte autorizada e confira emitente, documento e itens."],
    steps: ["Carregue o conteúdo do XML.", "Confira o cabeçalho antes de levar itens ao estágio de análise.", "Relacione cada item a uma matéria-prima governada.", "Confirme o vínculo ou ignore justificadamente.", "Gere o lote somente após a conferência final."],
    after: ["O estágio não cria saldo.", "Somente a confirmação governada gera lote e movimento de entrada."],
    roles: ["Importação, conciliação e geração de lote exigem alçadas distintas."],
    blockers: ["Módulo desabilitado, XML inválido, item sem vínculo ou unidade sem conversão impedem a conclusão."],
    records: ["Documento, linha de origem, vínculo, decisão, lote e movimento permanecem rastreáveis."]
  }),
  manual("/importacao-historica/mp", "Auditoria", "Excel histórico", "Analisar e homologar fontes históricas antes da importação definitiva.", {
    before: ["A fonte precisa estar identificada e homologada.", "O DEC-012 e o corte físico precisam estar aprovados antes da ativação de saldos oficiais."],
    steps: ["Selecione a fonte permitida.", "Execute somente a análise de estrutura e consistência.", "Revise pendências, aliases e divergências.", "Registre a decisão sem ativar saldos quando o rollout estiver bloqueado."],
    after: ["A análise não altera o estoque oficial.", "Resultados permanecem separados dos dados operacionais até a homologação formal."],
    roles: ["Somente Auditoria e responsáveis explicitamente autorizados acessam a análise."],
    blockers: ["Fonte não homologada, workbook divergente ou rollout desabilitado bloqueiam a importação."],
    records: ["Fonte, hash, lote de análise, divergências e decisões ficam registrados sem apagar a origem."]
  }),
  manual("/relatorios", "Relatórios", "Relatórios", "Consultar posições operacionais e rastreabilidade conforme as permissões.", {
    before: ["Escolha período e filtros coerentes com a consulta.", "Confirme se o módulo está liberado em modo de leitura."],
    steps: ["Selecione o relatório operacional disponível.", "Informe período, produto, família ou situação quando aplicável.", "Revise físico, reservado e disponível sem somar reservas ao consumo.", "Abra a rastreabilidade para investigar divergências."],
    after: ["A consulta não altera fatos.", "Divergências permanecem visíveis para conciliação; não são ajustadas automaticamente."],
    roles: ["Cada relatório e exportação depende de alçada individual de leitura."],
    blockers: ["Módulo bloqueado, falta de alçada ou filtros incompatíveis impedem a consulta."],
    records: ["Consultas sensíveis e exportações registram usuário, data e filtros conforme o contrato vigente."]
  }),
  manual("/seguranca", "Segurança", "Segurança", "Administrar usuários, identidade operacional e alçadas individuais auditadas.", {
    before: ["Confirme a conta selecionada e a ação exata que será administrada.", "Nunca compartilhe senha, token ou chave."],
    steps: ["Convide a pessoa pelo e-mail corporativo.", "Confira confirmação, ativação e papel organizacional.", "Vincule a conta à pessoa comercial somente quando ambas representarem a mesma pessoa.", "Consulte a alçada efetiva e sua origem.", "Conceda, bloqueie ou remova o override individual com justificativa."],
    after: ["Papel não concede automaticamente ações sensíveis.", "A próxima operação já usa a nova decisão efetiva."],
    roles: ["Somente administradores de Segurança com alçadas específicas gerenciam usuários, identidade e permissões."],
    blockers: ["Último administrador capaz, conta inativa, identidade já vinculada ou falta de justificativa impedem a alteração."],
    records: ["Convite, perfil, vínculo de identidade e override registram ator, motivo, antes e depois; credenciais nunca entram na auditoria."]
  }),
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
