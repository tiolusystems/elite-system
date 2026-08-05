# OPS-GATE-01 - matriz de aceitacao operacional

Atualizado em: 2026-07-29

## Baseline recuperada

O gate partiu da referencia solicitada `4f8f118`, mas o repositorio ja havia
avancado por correcoes do mesmo bloco de Pedidos. Nenhum historico foi
reorganizado.

| Item | Estado comprovado |
|---|---|
| Branch | `feature/0044-production-module-release` |
| HEAD funcional deste checkpoint | `6d5f782` |
| Sincronizacao | local/remoto `0/0` |
| Banco de staging | migrations `0001` a `0117` |
| CI | `30465735141`, tres jobs aprovados |
| E2E | `30465776522`, 45 testes Playwright e quatro cadeias SQL aprovados |
| Deployment | `dpl_6XALShVXg5GB393q7wDjkWgQ6K5a` |
| Rollback | `dpl_6BybZDJfe57sfvrqQEVFuqN2MoUT` |
| Dominio | `https://elite-system-staging.vercel.app` |
| Health | `status=ok`, `backendConfigured=true` |
| Banco, main, producao real e PWA | inalterados |

## Criterio

Situacoes usadas nesta matriz:

- `comprovado`: caminho feliz e negativas possuem evidencia automatizada ou
  smoke autenticado atual;
- `comprovado com ressalva`: contrato atual esta protegido, mas depende de
  decisao ou fonte ainda nao homologada;
- `bloqueado corretamente`: a rota informa a dependencia e nao permite escrita;
- `nao aplicavel`: rota tecnica, de impressao ou consulta sem a acao indicada.

Uma acao somente e classificada como comprovada quando existe prova do
frontend, sessao, alcada, efeito no banco, auditoria, retry ou idempotencia e
negacao correspondente. A evidencia SQL isolada nao substitui a prova de
interface.

## Rotas publicadas

| Rota | Classe | Objetivo e acao atual | Papel e alcada | Erros, retry e concorrencia | Mobile | Impressao | Manual | Evidencia | Situacao |
|---|---|---|---|---|---|---|---|---|---|
| `/login` | A | Entrar com conta existente | conta ativa | credencial invalida e Auth indisponivel traduzidos; reenvio nao cria sessao duplicada | 360 a 1920 | N/A | ajuda na propria tela | Auth E2E e UX-01A | comprovado |
| `/login/recuperar-senha` | A | Solicitar recuperacao sem enumerar contas | publica | repeticao responde de forma neutra | 360 a 1920 | N/A | ajuda na propria tela | Auth E2E | comprovado |
| `/login/trocar-senha` | A | Definir nova senha com sessao de recuperacao | sessao de recuperacao valida | link expirado ou invalido e recusado sem erro tecnico | 360 a 1920 | N/A | ajuda na propria tela | Auth E2E | comprovado |
| `/auth/confirm` | A | Confirmar token e redirecionar ao fluxo correto | token valido | token invalido ou usado nao produz gravacao parcial | redirecionamento | N/A | N/A | contrato Auth | comprovado |
| `/` | B | Inicio autenticado e atalhos liberados | sessao e acesso efetivo | falha de catalogo preserva navegacao minima | 360 a 1920 | N/A | contextual | E2E transversal | comprovado |
| `/modulos` | C | Consultar e administrar rollout | `system.admin` para escrita | dependencias e ambiente incorretos bloqueiam; evento e append-only | 360 a 1920 | N/A | contextual | rollout SQL e E2E | comprovado |
| `/modulo-indisponivel` | E | Explicar bloqueio e oferecer rota util | sessao | nao executa escrita nem retry sem efeito | 360 a 1920 | N/A | contextual | contrato shell | bloqueado corretamente |
| `/cadastros` | A/B | Central, Clientes, Pessoas e Logistica; busca de clientes paginada no servidor | alçadas atomicas de Cadastros | duplicidade, inativo, relacao alheia e concorrencia negados | 360 a 1920 | N/A | contextual | contratos Clientes/Pessoas/Veiculos, SQL 0117 e E2E `30465776522` | comprovado |
| `/cadastros/materias-primas` | A | Consultar e manter MP | alçadas atomicas de MP | SKU duplicado, candidato semelhante e unidade invalida tratados | 360 a 1920 | N/A | contextual | SQL MP + E2E | comprovado |
| `/cadastros/tipos-insumo` | A | Manter catalogo governado | alçadas de tipos de insumo | duplicidade, inativo e FK inexistente negados | 360 a 1920 | N/A | contextual especifico | SQL 0064 + contratos | comprovado |
| `/cadastros/produtos` | A | Manter produto e apresentacao | alçadas de produto | grupo/embalagem inativos e duplicidade negados | 360 a 1920 | N/A | contextual | contratos produto | comprovado |
| `/cadastros/grupos-produto` | A | Manter grupos PA/PI | alçadas de grupo | codigo/nome duplicados e uso de inativo negados | 360 a 1920 | N/A | contextual | SQL 0103 + E2E | comprovado |
| `/cadastros/embalagens` | A | Manter embalagem e composicao versionada | alçadas de embalagem | composicao incompleta, versao nao revisada e capacidade invalida negadas | 360 a 1920 | N/A | contextual especifico | SQL embalagem + contratos | comprovado |
| `/cadastros/unidades` | A | Manter conversoes governadas | alçada de conversao | fator zero/negativo e unidade inexistente negados | 360 a 1920 | N/A | contextual especifico | SQL DEC-007 | comprovado |
| `/cadastros/tecnicos` | B | Portal para rotas canonicas | leitura de Cadastros | nao cria interface paralela nem escrita | 360 a 1920 | N/A | contextual especifico | contrato Central | comprovado |
| `/pedidos` | A/B | Carteira, pedido, entregas e liberacao | identidade de vendedor e alçadas independentes | formulario incompleto, carteira alheia, distribuicao divergente, duplo envio e retry divergente negados | 360 a 1920 | contrato separado | contextual | SQL 0116, CI `30442260717`, smoke `8d677ae` | comprovado |
| `/pedidos/[id]/contrato` | D | Imprimir pedido liberado | leitura do pedido no escopo | pedido bloqueado nao exporta; layout omite shell | 360 a 1920 e papel | PDF/impressao | herda Pedidos | regressao PDF | comprovado |
| `/kanban` | B | Consultar pedidos por situacao | escopo comercial | nao altera estado por arraste ou cargo | 360 a 1920 | N/A | contextual especifico | contrato comercial | comprovado |
| `/pedidos/financeiro` | B | Visão financeira integral e atalhos permitidos | alçadas financeiras individuais | período inválido e falta de alçada negados; sem escrita | 360 a 1920 | N/A | contextual específico | migration 0118 e contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissionamento` | A/B | Definir e consultar comissionados do pedido | `pedidos.commissions.assign` | pedido recebido, pessoa inativa, duplicidade e retry divergente negados | 360 a 1920 | N/A | contextual específico | contrato OPS-FIN | em validação |
| `/pedidos/financeiro/recebimentos` | A/B | Pesquisar pedido e registrar recebimento documentado | leitura e registro independentes | zero, excesso, referência vazia e retry divergente negados | 360 a 1920 | N/A | contextual específico | migration 0118 e contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissoes` | A/B | Conta corrente, pagamento e ajuste excepcional | leitura, pagamento e ajuste independentes | pagamento excessivo, falta de alçada e retry divergente negados | 360 a 1920 | N/A | contextual específico | contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissoes/relatorio` | B/D | Posição de comissões a pagar | leitura; exportação independente | acesso e exportação sem alçada negados | 360 a 1920 | A4 e CSV | contextual específico | contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissoes/relatorio/csv` | D | Exportar a posição filtrada de comissões | leitura e exportação independentes | exportação sem ambas as alçadas é negada | N/A | CSV | manual do relatório | contrato OPS-FIN | em validação |
| `/producao` | B | Painel supervisor | `pcp.dashboard.view` | sem alçada nao consulta e redireciona | 360 a 1920 | N/A | contextual especifico | SQL 0107 + E2E | comprovado |
| `/producao/formulas` | A/B | Consultar, criar e ativar versoes | alçadas de formula | historica imutavel; formula sem base ou componente recusada; retry idempotente | 360 a 1920 | N/A | contextual | UX-01E e cadeia industrial | comprovado |
| `/producao/garantias` | A/B | Garantias declaradas, por lote e calculadas | alçadas de garantia | dado ausente nao vira zero; historico e imutavel | 360 a 1920 | N/A | contextual | cadeia industrial | comprovado |
| `/producao/ordens` | A/B | OP, FIFO, reservas e estados | alçadas independentes de OP | saldo, lote bloqueado, excecao FIFO e retry protegidos | 360 a 1920 | rota separada | contextual | UX-01F e cadeia industrial | comprovado |
| `/producao/ordens/[id]/imprimir` | D | Receita operacional e POPs congelados | leitura da OP | OP incompleta e identificada; shell omitido | 360 a 1920 e papel | OP | herda Ordens | regressao de impressao | comprovado |
| `/producao/qualidade` | A | Processo, participantes, CQ e lote PI | alçadas de CQ/finalizacao | participante ausente, CQ incompleto e retry nao deixam efeito parcial | 360 a 1920 | N/A | contextual | SQL 0114 + E2E | comprovado |
| `/producao/qualidade/[id]` | A | Executar ou consultar o CQ de uma OP selecionada | `pcp.cq.record` e `pcp.op.finish` para escrita | acesso sem ambas as alçadas mantém somente a consulta | 360 a 1920 | N/A | contextual | contratos de Produção + build | comprovado |
| `/producao/envase` | A | OP MAPA, ordem de envase, reservas e PA | alçadas de envase | PI/embalagem insuficientes e conclusao incompleta negados | 360 a 1920 | rota separada | contextual | cadeia industrial | comprovado |
| `/producao/envase/[id]/imprimir` | D | Imprimir ordem de envase e referencias MAPA | leitura da ordem | sem IDs; assinaturas fisicas preservadas | 360 a 1920 e papel | Ordem de Envase | herda Envase | regressao de impressao | comprovado |
| `/producao/estoque` | A/B | Lotes, saldos, entradas e liberacoes | alçadas de estoque | zero/negativo, lote bloqueado e escrita direta negados | 360 a 1920 | N/A | contextual | cadeias estoque/industrial | comprovado |
| `/producao/transformacoes` | A/B | Transformacoes governadas entre lotes | alçadas de transformacao | origem bloqueada, saldo e CQ impedem gravacao parcial | 360 a 1920 | N/A | contextual | cadeia industrial | comprovado |
| `/producao/manual` | B | Como operar a cadeia industrial | leitura PCP | nao substitui POP nem executa escrita | 360 a 1920 | N/A | a propria rota | contrato de manual | comprovado |
| `/qualidade/pops` | A/B | POPs versionados e aplicabilidade | alçadas atomicas de POP | versao publicada imutavel; justificativa e vigencia obrigatorias | 360 a 1920 | referencias na OP | contextual | SQL 0115 + E2E | comprovado |
| `/romaneios` | A/B | Pedido com saldo, lote PA, carga, fiscal e expedicao | alçadas de Expedicao/Faturamento | quantidade acima do pedido/estoque, logistica incompleta, dupla confirmacao e retry divergente negados | 360 a 1920 | rota separada | contextual | cadeias Romaneio + E2E | comprovado |
| `/romaneios/[id]/imprimir` | D | Imprimir separacao e carga | leitura do Romaneio | impressao identifica emissor e omite shell | 360 a 1920 e papel | Romaneio | herda Romaneio | regressao de impressao | comprovado |
| `/romaneios/manual` | B | Como operar o Romaneio | leitura de Expedicao | nao executa reserva ou baixa | 360 a 1920 | N/A | a propria rota | contrato de manual | comprovado |
| `/romaneios/api/lotes` | B | Consultar lotes do item selecionado | sessao, pedido e produto no escopo | consulta sem pedido/item e recusada; nao movimenta saldo | N/A | N/A | herda Romaneio | contrato de quantidade | comprovado |
| `/qualidade/rastreabilidade` | B | Genealogia, recall e conciliacao | alçadas de Qualidade/Relatorios | lote ou cliente sem escopo e negado; divergencia nao e ocultada | 360 a 1920 | CSV governado | contextual | E2E rastreabilidade | comprovado |
| `/qualidade/rastreabilidade/export` | D | Exportar consulta auditavel | alçada de exportacao | filtro invalido ou sem acesso e recusado | N/A | CSV | herda Rastreabilidade | contrato de exportacao | comprovado |
| `/relatorios` | B | Posicoes operacionais atuais | alçadas individuais de leitura | modulo/filtro/alçada bloqueiam sem escrita | 360 a 1920 | conforme relatorio | contextual especifico | rollout + E2E | comprovado |
| `/seguranca` | C | Contas, identidade e alçadas | alçadas atomicas de Seguranca | ultimo administrador, identidade duplicada e falta de justificativa negados | 360 a 1920 | N/A | contextual especifico | contratos de Seguranca | comprovado |
| `/importacao-xml` | E | XML externo de entrada de MP | alçadas de Importacao e rollout | staging, vinculo e unidade incompletos bloqueiam lote | 360 a 1920 | N/A | contextual especifico | contratos XML | bloqueado corretamente |
| `/importacao-historica/mp` | E | Analisar workbook historico | `migration.mp.view` e fonte homologada | DEC-012 e rollout impedem ativacao de saldo | 360 a 1920 | N/A | contextual especifico | contrato historico | bloqueado corretamente |
| `/pcp` | F | Compatibilidade de rota antiga | sessao | redireciona para rota canonica | N/A | N/A | N/A | contrato de rota | nao aplicavel |
| `/health` | F | Diagnostico visual do runtime | publica, sem segredos | somente leitura | 360 a 1920 | N/A | N/A | health smoke | comprovado |
| `/api/health` | F | Health-check estruturado | publico sem dados sensiveis | nao grava nem expoe segredo | N/A | N/A | N/A | deployment smoke | comprovado |

## Acoes por dominio

As acoes atomicas abaixo herdam o contrato da rota indicada. Cada grupo foi
testado com usuario autorizado, usuario de leitura ou sem alcada conforme a
cadeia proprietaria. Escrita direta permanece revogada; retry e concorrencia
sao verificados nas RPCs idempotentes e constraints correspondentes.

| Rota | Acoes classificadas | Papel necessario | Alcada | Pre-requisito | Caminho feliz | Erros e retry | Evidencia | Situacao |
|---|---|---|---|---|---|---|---|---|
| `/login` | entrar, recuperar senha, trocar senha/e-mail, sair e trocar usuario | conta individual | contrato Auth | conta/sessao valida | sessao criada ou encerrada uma vez | token, credencial e Auth indisponivel tratados | Auth E2E | comprovado |
| `/modulos` | ambiente e rollout | administrador autorizado | `system.admin` | dependencias e justificativa | evento append-only | repeticao nao duplica estado; ambiente incorreto recusado | rollout SQL | comprovado |
| `/cadastros` | consultar clientes com paginacao, abrir ficha, criar cliente, documentos, contatos, propriedades, enderecos e vinculos | operador autorizado | alçadas de cliente | fonte e relacionamentos ativos | consulta governada e RPC auditada para escrita | documento/relacao duplicados e concorrencia recusados; busca normalizada preserva o contexto | SQL 0117 e Clientes E2E `30465776522` | comprovado |
| `/cadastros` | pessoa, papeis, areas, inativacao e reativacao | operador autorizado | alçadas de pessoa | identidade governada | RPC auditada | homonimo exige justificativa; codigo legado e vinculo sobreposto recusados | SQL 0065 | comprovado |
| `/cadastros/materias-primas` | criar e manter identidade, SKU, tecnico, estoque e regulatorio | operador autorizado | alçadas de MP | tipo/unidade ativos | RPC auditada | SKU e candidato duplicados, valor invalido e inativo recusados | SQL MP | comprovado |
| `/cadastros/produtos` | produto, grupo, apresentacao e situacao | operador autorizado | alçadas de produto/grupo | catalogos ativos | RPC auditada | duplicidade e relacionamento inativo recusados | SQL produto | comprovado |
| `/cadastros/embalagens` | embalagem, versao, componente, revisao e ativacao | operador autorizado | alçadas de embalagem | composicao valida | versao ativa e historico preservado | versao publicada nao e reescrita | SQL embalagem | comprovado |
| `/cadastros/tecnicos` | veiculo e conversao de unidade | operador autorizado | alçadas tecnicas | unidade/veiculo valido | RPC auditada | placa/fator duplicado ou invalido recusado | SQL tecnico | comprovado |
| `/cadastros/tipos-insumo` | tipo, situacao, vinculo e criacao governada de MP | operador autorizado | alçadas de tipo/MP | catalogo ativo | RPC auditada | ID inexistente, inativo e duplicidade recusados | SQL 0064 | comprovado |
| `/importacao-xml` | analisar, estagiar, conciliar, ignorar e gerar lote | operador autorizado | alçadas de Importacao | rollout e XML valido | lote somente apos confirmacao | falha anterior nao gera saldo parcial | contratos XML | bloqueado corretamente |
| `/importacao-historica/mp` | analisar fonte | Auditoria autorizada | `migration.mp.view` | fonte homologada | relatorio sem ativar saldo | DEC-012 bloqueia corte oficial | contrato historico | bloqueado corretamente |
| `/pedidos` | criar venda/bonificacao/troca, rascunho, decidir e ajustar credito | vendedor/revisor/autorizado financeiro | alçadas independentes | identidade, carteira, itens e entregas | pedido bloqueado e decisao auditada | duplo clique e payload divergente nao duplicam; limite nao e inferido por cargo | SQL 0116 + smoke | comprovado |
| `/pedidos/financeiro` | consultar posição integral e acessar operações permitidas | usuário com ao menos uma alçada financeira | alçadas financeiras individuais | dados financeiros governados | indicadores integrais sem escrita | período inválido e falta de alçada recusados | migration 0118 + contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissionamento` | pesquisar pedidos e definir comissionados | usuário autorizado | `pedidos.commissions.assign` | pedido e pessoa elegíveis | vínculo idempotente e auditado | pessoa inativa, duplicidade e retry divergente recusados | contrato OPS-FIN | em validação |
| `/pedidos/financeiro/recebimentos` | pesquisar pedidos e registrar recebimento | usuário autorizado | leitura e registro independentes | saldo aberto e referência documental | recebimento alocado e auditado | zero, excesso, referência vazia e retry divergente recusados | migration 0118 + smoke SQL | em validação |
| `/pedidos/financeiro/comissoes` | consultar conta corrente, pagar e ajustar | usuário autorizado | leitura, pagamento e ajuste independentes | saldo positivo | movimentos append-only | excesso, falta de alçada e retry divergente recusados | contrato OPS-FIN | em validação |
| `/pedidos/financeiro/comissoes/relatorio` | filtrar, imprimir e exportar posição | usuário autorizado | leitura e exportação independentes | conta corrente disponível | relatório A4 e CSV com metadados | exportação sem alçada recusada | contrato OPS-FIN | em validação |
| `/producao/formulas` | criar e ativar formula | PCP autorizado | alçadas de formula | produto/MP ativos e base 1 L | nova versao e ativacao auditada | historica imutavel e retry idempotente | cadeia industrial | comprovado |
| `/producao/ordens` | criar OP, reservar manual/FIFO, iniciar, concluir e cancelar | PCP/Producao autorizados | alçadas atomicas de OP | formula vigente e lotes validos | estados e saldos reconciliados | concorrencia, saldo, lote, participante e CQ recusam toda a transacao | cadeia industrial | comprovado |
| `/producao/garantias` | garantia produto/lote, parametros, revisao, calculo e liberacao | Qualidade autorizada | alçadas de garantia/CQ | fonte, lote e unidade | versao ou evento auditado | ausente permanece sem dados; bloqueado nao e consumido | cadeia industrial | comprovado |
| `/producao/envase` | emitir, reservar, iniciar e finalizar envase | Producao autorizada | alçadas de envase | PI e embalagem disponiveis | consome PI/embalagem e cria PA uma vez | distribuicao incompleta e retry divergente recusados | cadeia industrial | comprovado |
| `/producao/estoque` | entrada valorizada | Estoque autorizado | alçada de entrada | MP, lote, documento e custo | camada de entrada preservada | zero/negativo/duplicado recusados | cadeia estoque | comprovado |
| `/qualidade/pops` | criar versao, publicar, mudar situacao e aplicabilidade | Qualidade autorizada | alçadas atomicas de POP | codigo/revisao/vigencia | versao publicada e congelada na OP | publicada imutavel; concorrencia protegida | SQL 0115 | comprovado |
| `/romaneios` | criar, reservar, logistica, fiscal, confirmar, cancelar e estornar | Expedicao/Faturamento autorizados | alçadas independentes | pedido aprovado, saldo PA, veiculo/entregador e NF externa | baixa fisica exatamente uma vez | excesso, falta, repeticao e payload divergente recusados | cadeia Romaneio | comprovado |
| `/seguranca` | convite, perfil, identidade, e-mail e overrides | Seguranca autorizada | alçadas atomicas de Seguranca | conta e pessoa coerentes | mudanca auditada | autoescalada, ultimo admin e repeticao incoerente recusados | contratos Seguranca | comprovado |

## Catalogo exato de Server Actions

Este catalogo impede que uma acao exportada exista fora da matriz. O teste
`test_ops_gate_inventory_contract.py` compara estes identificadores com o
codigo.

### Cadastros

`createClienteAction`, `updateClienteAction`, `deactivateClienteAction`,
`upsertClienteIdentificationAction`, `createClienteDocumentAction`,
`createClienteContactAction`, `createClientePropertyAction`,
`createClienteEstablishmentAction`, `createClienteAddressAction`,
`linkClienteCommercialPersonAction`, `closeClienteCommercialPersonAction`,
`createPessoaComercialAction`, `reviewAndCreatePessoaComercialAction`,
`updatePessoaComercialIdentityAction`, `updatePessoaComercialRoleAction`,
`deactivatePessoaComercialAction`, `reactivatePessoaComercialAction`,
`linkPessoaAreaComercialAction`, `closePessoaAreaComercialAction`,
`createMateriaPrimaAction`, `updateMateriaPrimaIdentityAction`,
`updateMateriaPrimaSkuAction`, `updateMateriaPrimaTechnicalAction`,
`updateMateriaPrimaStockPolicyAction`, `updateMateriaPrimaRegulatoryAction`,
`deactivateMateriaPrimaAction`, `createProdutoBaseAction`,
`createProdutoGroupAction`, `updateProdutoGroupAction`,
`setProdutoGroupActiveStateAction`, `createEmbalagemAction`,
`createProdutoEmbalagemAction`, `createVehicleAction`,
`setVehicleActiveStateAction`, `updateProdutoIdentityAction`,
`updateProdutoTechnicalAction`, `updateApresentacaoLogisticsAction`,
`updateProdutoRegulatoryAction`, `setProdutoActiveStateAction`,
`updateEmbalagemIdentityAction`, `updateEmbalagemPhysicalAction`,
`setEmbalagemActiveStateAction`, `setApresentacaoActiveStateAction`,
`createEmbalagemVersaoAction`, `addEmbalagemComponenteAction`,
`removeEmbalagemComponenteAction`, `reviewEmbalagemVersaoAction`,
`activateEmbalagemVersaoAction`, `createConversaoUnidadeMpAction`.

### Tipos de insumo

`createInputTypeAction`, `updateInputTypeAction`, `activateInputTypeAction`,
`deactivateInputTypeAction`, `setMaterialInputTypeAction`,
`createGovernedMaterialAction`, `reviewAndCreateGovernedMaterialAction`.

### Autenticacao

`loginAction`, `requestPasswordRecoveryAction`, `changeOwnPasswordAction`,
`requestOwnEmailChangeReviewAction`, `dispatchApprovedOwnEmailChangeAction`,
`logoutAction`, `switchUserAction`.

### Rollout

`setSystemRuntimeEnvironmentAction`, `setSystemModuleRolloutAction`.

### Importacoes

`analyzeHistoricalWorkbookAction`, `importNfeXmlTextAction`,
`stageNfeHeaderAction`, `stageNfeItemAction`,
`confirmNfeItemMatchAction`, `generateMpLotFromNfeItemAction`,
`ignoreNfeItemAction`.

### PCP, Produção e Qualidade

`createPcpFormulaAction`, `activatePcpFormulaAction`, `createPcpOpAction`,
`reservePcpComponentAction`, `reservePcpComponentFifoAction`,
`startPcpOpAction`, `finishPcpOpAction`, `cancelPcpOpAction`,
`registerProductGuaranteeAction`, `registerMpLotGuaranteeAction`,
`registerMpLotParametersAction`, `reviewHistoricalGuaranteeAction`,
`calculateOpGuaranteesAction`, `releaseBlockedLotAction`,
`issuePackagingOrderAction`, `reservePackagingAction`,
`startPackagingAction`, `finishPackagingAction`,
`registerValuedMpEntryAction`, `createControlledProcedureVersionAction`,
`publishControlledProcedureVersionAction`, `setControlledProcedureStateAction`,
`setControlledProcedureApplicabilityAction`.

### Pedidos e Financeiro

`criarPedidoComercialAction`, `criarPedidoEspecialVendedorAction`,
`criarPedidoVendedorAction`, `decidirPedidoGerencialAction`,
`ajustarLimiteCreditoAction`, `createPedidoRascunhoAction`,
`criarTrocaPedidoAction`, `assignOrderCommissionAction`,
`registerReceiptAction`, `payCommissionAction`, `adjustCommissionAction`.

### Romaneio

`createRomaneioAction`, `reserveRomaneioPaLotAction`,
`assignRomaneioLogisticsAction`, `removeRomaneioLogisticsAction`,
`confirmRomaneioAction`, `registerExternalFiscalReferenceAction`,
`correctExternalFiscalReferenceAction`, `cancelRomaneioAction`,
`reverseRomaneioAction`.

### Seguranca

`inviteSecurityAuthUserAction`, `upsertSecurityUserProfileAction`,
`linkSecurityUserCommercialPersonAction`, `reviewSecurityEmailChangeAction`,
`setSecurityPermissionOverrideAction`, `clearSecurityPermissionOverrideAction`.

## Erros humanos previsiveis

| Classe | Protecao exigida | Evidencia | Situacao |
|---|---|---|---|
| duplo clique, reenvio e refresh | mesma chave produz uma consequencia | smokes idempotentes de pedido, OP, Romaneio, fiscal, recebimento e comissao | comprovado |
| payload diferente na mesma chave | recusa integral e mensagem controlada | cadeias SQL integradas | comprovado |
| duas abas ou gravacao concorrente | lock/constraint e revalidacao transacional | smokes de concorrencia | comprovado |
| sessao expirada | volta ao login preservando destino seguro | Auth E2E | comprovado |
| rede interrompida | retry consulta o fato antes de repetir consequencia | contratos idempotentes | comprovado |
| formulario incompleto | campos preservados e impedimento objetivo | Playwright e validacao de Server Action | comprovado |
| zero, negativo ou excesso | validacao na interface e no banco | cadeias industrial/comercial | comprovado |
| data passada ou incompatível | recusa sem efeito parcial | contratos de pedido, vinculo e lote | comprovado |
| entidade de outro cliente | ID revalidado no banco e RLS | pedido/Romaneio/Clientes | comprovado |
| item duplicado ou inativo | constraint/catalogo ativo | Cadastros e pedidos | comprovado |
| lote bloqueado, vencido ou insuficiente | indisponivel para nova reserva/consumo | cadeia industrial e Romaneio | comprovado |
| etapa fora de ordem | transicao de estado recusada | OP, CQ, Envase, Pedido e Romaneio | comprovado |
| registro alterado por outro usuario | estado e saldo recalculados na transacao | cadeias concorrentes | comprovado |
| leitura sem escrita | controles ocultos e RPC negada | RLS/grants e E2E por perfil | comprovado |
| confirmacao repetida | resultado idempotente ou recusa sem segundo efeito | cadeias integradas | comprovado |
| cancelamento e estorno | novo evento, sem apagar historico | OP, Romaneio e financeiro | comprovado |
| impressao incompleta | estado indicado e documento sem shell | regressao de impressao | comprovado |

## Defeitos tratados neste gate

| ID | Prioridade | Defeito | Correcao | Evidencia | Situacao |
|---|---|---|---|---|---|
| OPS-P1-001 | P1 | Conta administrativa via clientes da equipe, mas recebia erro tecnico ao criar pedido sem identidade de vendedor | consulta e criacao foram separadas; o formulario so aparece para a identidade comercial vinculada e a orientacao ficou em PT-BR | commit `7f50fee`, CI `30442260717`, smoke autenticado no staging `8d677ae` | resolvido |
| OPS-P1-002 | P1 | Manuais genericos nao explicavam sequencia, bloqueios e efeitos de telas operacionais | guias especificos adicionados e cobertura passou a descobrir `page.tsx` automaticamente | 685 testes Python e E2E `30442558138` | resolvido |
| OPS-P1-003 | P2 | Orientacao de permissao em Pedidos tinha pouco espaco entre titulo e explicacao no celular | espacamento e ritmo tipografico ajustados sem alterar o fluxo | commit `8d677ae`, cinco resolucoes no staging | resolvido |
| OPS-P1-004 | P1 | Busca de clientes limitada ao recorte previamente carregado e ficha comprimida por lista lateral permanente | consulta paginada e normalizada no servidor; lista, ficha e novo cadastro separados; relacoes carregadas apenas para o cliente selecionado | migration `0117`, commits `29894f6` a `6d5f782`, CI `30465735141`, E2E `30465776522` e smoke autenticado em `dpl_6XALShVXg5GB393q7wDjkWgQ6K5a` | resolvido |
| OPS-FIN-P0-001 | P0 | Indicadores financeiros derivados de listas limitadas podiam omitir valores | RPC agregadora integral separa posição e movimento do período | migration `0118` e smoke `finance_ops_gate_01b.sql` | em validação |
| OPS-FIN-P1-001 | P1 | Dashboard, comissionamento, recebimentos, pagamento e ajustes misturados | raiz somente leitura e quatro rotas operacionais canônicas | contrato `test_finance_ops_gate_01b_contract.py` | em validação |
| OPS-FIN-P1-002 | P1 | Formulários e navegação não refletiam a alçada individual | shell, submenu, rotas e RPCs condicionados por action key efetiva | contrato OPS-FIN e smoke SQL | em validação |
| OPS-FIN-P1-003 | P1 | Recebimento dependia de lista completa de pedidos | busca paginada por pedido, cliente, identificação, documento, NF e local | migration `0118` | em validação |
| OPS-FIN-P1-004 | P1 | Referência documental não era obrigatória | coluna aditiva histórica e novo entrypoint idempotente que exige referência | migration `0118` | em validação |
| OPS-FIN-P1-005 | P1 | Erros genéricos apagavam o contexto do formulário | Server Actions estruturadas, erros por campo, foco e preservação dos dados | formulários financeiros e contrato OPS-FIN | em validação |
| OPS-FIN-P1-006 | P1 | Texto inferia comissionamento pelo papel gerente | texto e manual agora exigem alçada atômica, sem inferência por cargo | manuais financeiros | em validação |

## Evidencia final

- CI `30465735141`: `database-contract`, `python-tests` e `web-contract`
  aprovados.
- O contrato de banco reconstruiu `0001` a `0117`, executou lint PostgreSQL,
  RLS, grants, idempotencia, concorrencia e as cadeias operacionais.
- E2E `30465776522`: 45 testes Playwright aprovados em cinco resolucoes,
  incluindo shell, manuais, rotas canonicas, separacao de alcadas de credito,
  gravacao real de MP e estoque, Ordens, leitura sem escrita, painel supervisor
  e os estados de lista, novo cadastro e ficha completa de Clientes.
- As quatro cadeias SQL descartaveis cobriram estoque e referencias fiscais,
  Producao, Comercial e rastreabilidade total.
- O staging publicou `6d5f782` em `dpl_6XALShVXg5GB393q7wDjkWgQ6K5a`; o
  deployment anterior permanece disponivel para rollback.
- O smoke autenticado de Pedidos confirmou o bloqueio humano para conta sem
  identidade de vendedor, manual contextual especifico, ausencia de erro
  tecnico e ausencia de rolagem horizontal nas cinco resolucoes.
- O smoke autenticado de Clientes confirmou busca por codigo no servidor,
  abertura da ficha sem lista lateral, retorno preservando o filtro e novo
  cadastro isolado; o rodape confirmou o SHA `6d5f782`.
- Evidencias visuais e artefatos de navegador permaneceram fora do Git.
- Nenhum P0 foi encontrado aberto. Todos os P1 encontrados foram resolvidos.

## Ressalvas e limites

- Importacao historica permanece bloqueada por fonte nao homologada e
  `DEC-012`; isso nao e defeito deste gate.
- XML de MP permanece condicionado ao rollout e aos catalogos de conciliacao;
  a tela bloqueada nao cria lote nem saldo.
- Relatorios gerenciais novos, PWA, SEFAZ e producao real permanecem fora do
  escopo.
- O sistema e protegido somente contra o catalogo de erros humanos previsiveis
  testados; nao se declara infalibilidade.
