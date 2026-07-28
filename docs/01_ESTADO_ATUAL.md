# Elite System - estado atual

Atualizado em: 2026-07-28

## Referencia vigente

- branch de desenvolvimento publicada: `feature/0044-production-module-release`;
- HEAD funcional publicado: `ae091b9`;
- frontend funcional ativo: `ae091b9`;
- Supabase de homologacao: ledger alinhado de `0001` a `0115`;
- frontend estavel: `https://elite-system-staging.vercel.app`;
- backend de staging: `/api/health` com `status=ok` e `backendConfigured=true`;
- deployment estavel de staging: `dpl_4KAcP1iz9B3XbFzfx8WvvQn2Py4L`;
- deployment funcional anterior preservado para rollback:
  `dpl_CzhRWnV2KARsvoFJF3LuFFwrF5rV`;
- producao real e `main`: nao alteradas;
- PWA: adiada.

## Tarefa concluida mais recente

Macrociclo noturno PROD-UX-03 -> UX-01H:

- a migration `0115_govern_controlled_procedures.sql` criou o catalogo
  controlado de POPs no dominio PCP/Controle de Qualidade, sem novo modulo;
- versoes publicadas sao imutaveis, alteracoes geram nova revisao e as
  transicoes de estado e aplicabilidade sao auditadas;
- uma OP nova congela codigo, titulo, revisao e vigencia dos POPs aplicaveis;
- a impressao da OP apresenta somente as referencias dos procedimentos, sem
  reproduzir o seu conteudo integral;
- o CQ consulta as referencias congeladas e registra conformidade, desvio ou
  nao conformidade sem incorporar um editor de POP;
- participantes digitais permanecem vinculados a pessoas cadastradas por ID e
  as assinaturas operacionais da impressao continuam fisicas;
- `UX-01H - Romaneio` permanece na rota canonica: parte do pedido com saldo,
  permite consulta previa de carga, reserva por item/lote, gravacao explicita e
  impressao antes ou depois da referencia fiscal externa;
- a correcao `ae091b9` eliminou o estouro horizontal das linhas de assinatura
  da OP impressa;
- OP impressa e Romaneio foram validados em `1920x1080`, `1366x768`,
  `768x1024`, `390x844` e `360x800`, sem rolagem horizontal;
- a CI `30357962313` aprovou `database-contract`, `python-tests` e
  `web-contract`, incluindo instalacao limpa de `0001` a `0115`;
- o ledger remoto confirmou `0115` e o deployment
  `dpl_4KAcP1iz9B3XbFzfx8WvvQn2Py4L` publicou `ae091b9` no dominio estavel;
- `/api/health` respondeu `status=ok` e `backendConfigured=true`;
- o ensaio governado criou um POP e uma OP sinteticos: a OP foi cancelada, a
  aplicabilidade foi encerrada, o POP foi inativado, as seis alçadas temporarias
  foram removidas e o perfil tecnico foi inativado;
- POP, versao publicada, OP cancelada e eventos permanecem como evidencias
  sinteticas append-only; nenhum fato historico foi apagado;
- o E2E descartavel `30360462935` reconstruiu o banco de `0001` a `0115`,
  executou as quatro cadeias SQL, iniciou Auth e frontend isolados e aprovou a
  regressao Playwright nas cinco resolucoes; o ambiente foi encerrado ao final;
- o gatilho temporario restrito a branch foi removido depois do ensaio e o
  workflow voltou a ser exclusivamente manual;
- PROD-UX-03, POPs e UX-01H estao tecnicamente validados no staging. Nenhuma
  homologacao visual foi atribuida a Luciano.

Rollout governado e ensaio total `HOM-E2E-20260727-RG01`:

- Faturamento e Financeiro disponiveis em `business_validation` com
  `read_write`;
- Relatorios disponivel em `business_validation` com `read_only`;
- a habilitacao dos modulos nao concedeu alçada por cargo ou perfil;
- o usuario tecnico recebeu somente as alçadas individuais necessarias e foi
  inativado ao final, com auditoria antes/depois;
- a cadeia completa foi executada pela interface ate referencia fiscal
  externa, expedicao, recebimento, liberacao e pagamento de comissao;
- `0112` corrigiu o calculo de carga do Romaneio pela densidade do envase;
- `0113` corrigiu a direcao fiscal e a travessia recursiva do recolhimento;
- o ledger do staging terminou em `0113`;
- a CI `30271650035` aprovou os tres jobs;
- o Romaneio sintetico foi estornado, o PA retornou ao estoque e o recall
  passou a mostrar zero destino ativo;
- os fatos financeiros append-only ficaram conciliados: R$ 200,00 recebidos e
  R$ 10,00 de comissao liberados/pagos, ambos sem saldo;
- cinco rotas afetadas foram validadas nas cinco resolucoes, totalizando 25
  combinacoes sem rolagem horizontal ou erro tecnico;
- nao houve novo deployment porque o frontend nao foi alterado;
- nenhum dado real, `main`, producao real ou PWA foi alterado.

O resultado consolidado e **APROVADO** para o staging. Os registros
`HOM-E2E-*` permanecem apenas como evidencias sinteticas auditaveis; nenhuma
linha append-only foi apagada ou reescrita.

## Estado tecnico comprovado

O pipeline integral do commit `9e56e15` esta aprovado na execucao
`30138727879`:

- ESLint, TypeScript e build Next.js;
- testes Python e contratos estaticos;
- reconstrucao PostgreSQL limpa com todas as migrations;
- lint do schema e geracao do contrato TypeScript;
- smokes transacionais das cadeias industrial e comercial;
- RLS, grants minimos e escrita operacional somente por RPC;
- importacao historica de materias-primas;
- catalogos tecnicos, embalagens e logistica;
- Romaneio, leitura RLS e fronteiras administrativas de Seguranca.

As migrations `0091` a `0107` foram aplicadas no Supabase de staging somente
depois de CI aprovada e dry-run controlado. O ultimo dry-run listou exclusivamente:

- `0097_manager_decision_request_idempotency.sql`;
- `0098_romaneio_request_idempotency.sql`;
- `0099_packaging_issue_request_idempotency.sql`;
- `0100_exchange_order_request_idempotency.sql`;
- `0101_commission_assignment_request_idempotency.sql`.

Um segundo dry-run listou exclusivamente
`0102_fiscal_request_idempotency.sql` antes de sua aplicacao.
O dry-run seguinte listou exclusivamente
`0103_govern_product_groups.sql` antes de sua aplicacao.
O dry-run mais recente listou exclusivamente
`0104_separate_credit_limit_adjust_permission.sql` antes de sua aplicacao.
Os dry-runs seguintes listaram unitariamente `0105`, `0106` e
`0107_pcp_supervisor_dashboard_access.sql` antes de cada aplicacao.

O ledger remoto confirmou `0107` e o health-check permaneceu saudavel depois da
aplicacao. O aviso de cache `pg-delta` da CLI ocorreu depois da execucao SQL e
nao alterou o ledger nem a disponibilidade do backend.

## Tarefa concluida anteriormente

UX-01G - Qualidade, participantes e Ordem de Producao:

- esquema visual de CQ e Ordem de Producao homologado por Luciano;
- separador, conferente, formuladores, responsavel pelo CQ e responsavel pela
  liberacao sao pessoas ativas cadastradas e vinculadas por ID;
- nomes livres, JSON e listas textuais deixaram de ser fonte operacional para
  os participantes da finalizacao;
- a finalizacao relacional preserva snapshots historicos, exige os cinco papeis
  operacionais e gera um unico lote PI na mesma transacao;
- a OP impressa mostra quantidades totais, separacao multilote, consumo real,
  desvio, rubrica e assinaturas fisicas;
- dose por litro e validade do lote permanecem nos contratos internos de
  formula e estoque, sem poluir o documento operacional;
- a rota de impressao consulta diretamente a OP solicitada e nao depende do
  limite das ordens recentes;
- migration `0114_govern_pcp_cq_participants.sql` validada em ambiente
  descartavel `elite-validation-*` e aplicada unitariamente no staging depois
  de CI verde e dry-run exclusivo;
- CI `30312513428` aprovou frontend, 659 testes Python e instalacao limpa do
  banco; a correcao objetiva da leitura de consumos passou novamente na CI
  `30314290949`;
- o smoke autenticado confirmou Ordens, CQ e impressao da OP sem erro tecnico,
  com totais por componente, lotes separados, participantes digitais e campos
  de assinatura fisica;
- o deployment `dpl_BRHbYKEDG4BM3L7WLVUyAQUoyuDg` publica o commit `098b5ea`
  no projeto `elite-system-staging`, com health-check saudavel.

Implementacao da decisao arquitetural de POPs:

- POPs pertencem ao PCP/Controle de Qualidade e nao criam novo modulo;
- localizacao funcional: `Controle -> Qualidade -> POPs e documentos
  controlados`;
- versoes publicadas sao imutaveis, auditadas e vinculaveis em relacao
  muitos-para-muitos aos processos aplicaveis;
- a OP congela codigo, titulo, revisao e vigencia dos POPs aplicaveis;
- a impressao mostra somente referencias, sem reproduzir o conteudo integral;
- manual contextual e POP permanecem documentos distintos;
- a implementacao foi entregue em pacote estrutural proprio, sem reabrir o
  UX-01G.

O catalogo de POPs nao integra esse escopo interno do Romaneio; os dois blocos
compartilham apenas o shell, as alçadas e os contratos transversais vigentes.

Promocao controlada e ensaio online `HOM-E2E-20260725-MS08GPR2`:

- o commit `5d94325` foi publicado no projeto Vercel
  `elite-system-staging` e promovido ao dominio estavel;
- a CI `30156953429` aprovou `database-contract`, `python-tests` e
  `web-contract`;
- `/api/health` respondeu `status=ok` e `backendConfigured=true`;
- o smoke autenticado percorreu 18 rotas operacionais sem erro tecnico ou
  rolagem horizontal;
- a cadeia industrial foi executada pela interface ate formula operacional,
  OP, reserva FIFO em duas camadas de lote, producao, CQ aprovado, lote PI,
  formula MAPA, envase, consumo de embalagem e lote PA;
- a reserva de um Romaneio parcial reduziu apenas o saldo disponivel do pedido,
  sem baixar o estoque fisico, e o cancelamento liberou integralmente a reserva;
- o frontend agora traduz o bloqueio do modulo responsavel e nao afirma que
  entregador e veiculo foram ambos gravados quando apenas um deles foi
  informado;
- nenhuma migration, configuracao Supabase, `main`, producao real ou PWA foi
  alterada.

O ensaio completo permanece tecnicamente reprovado: Faturamento, Financeiro,
Relatorios e Rastreabilidade estao desabilitados no rollout do staging. A
referencia fiscal externa foi negada mesmo com alcada individual, com causa
exata `module_disabled`; sem essa etapa nao e possivel confirmar a expedicao,
o recebimento, a comissao e a rastreabilidade online completa.

UX-01F - Ordens e reservas:

- consulta, criacao, reservas e mudancas de estado possuem fluxos separados;
- situacoes da OP, finalidades e mensagens operacionais aparecem em PT-BR;
- a OP nasce exclusivamente de formula operacional vigente e revisada por
  litro, sem expor IDs tecnicos;
- cada componente mostra quantidade necessaria, reservada, pendente e
  disponivel;
- reserva automatica segue FIFO e pode distribuir a necessidade entre varios
  lotes;
- lote fora do FIFO exige alcada individual e justificativa;
- reservas comprometem o saldo disponivel sem baixar o saldo fisico;
- lote bloqueado, saldo insuficiente ou reserva incompleta impedem o inicio;
- criacao, reserva, excecao ao FIFO, inicio e cancelamento usam alcadas
  independentes, sem inferencia por cargo;
- retries permanecem idempotentes e as mudancas de estado continuam auditadas;
- manual contextual, desktop, tablet e celular foram validados;
- nenhuma migration ou alteracao de banco foi necessaria.

UX-01E tecnicamente validado; homologacao visual de Luciano pendente para
revisao consolidada posterior.

Formulas permanece tecnicamente concluido:

- referencias vigentes aparecem antes do historico;
- consulta por produto, finalidade e situacao permanece separada da criacao;
- componentes sao adicionados progressivamente;
- formula operacional por 1 L e composicao documental MAPA possuem fluxos
  inequivocos;
- versoes anteriores permanecem somente leitura e podem originar uma nova
  versao sem alterar o historico;
- formulas antigas sem base por litro comprovada exibem revisao necessaria;
- ativacao exige motivo e passa pela RPC auditada existente;
- nenhum ID tecnico e exibido ao operador;
- manual contextual e rotulos PT-BR foram validados no staging;
- nenhuma migration, alteracao de banco ou exportacao Excel foi introduzida.

Visao geral supervisoria de Producao e navegacao responsiva:

- a alcada individual `pcp.dashboard.view` pertence ao PCP, e somente leitura
  e nasce bloqueada;
- sem a alcada, `/producao` redireciona no servidor para a primeira fila
  operacional e nao consulta o painel;
- com a alcada, a Visao geral apresenta somente pendencias, excecoes e atalhos
  de supervisao;
- no desktop, as areas de Producao permanecem em abas;
- no tablet e celular, somente a area atual ocupa a barra compacta e as demais
  aparecem sob abertura explicita;
- o mapa didatico das oito etapas pertence a `Como operar`, sem duplicacao no
  painel supervisor.

Separacao da revisao de pedido e da manutencao do limite cadastral de credito:

- `pedidos.credit.review` revisa exclusivamente o pedido bloqueado;
- `financeiro.credit_limits.adjust` altera exclusivamente o limite permanente;
- a nova alcada e individual, explicita, pertence ao Financeiro e nasce
  bloqueada;
- nenhum papel organizacional, inclusive gerente, Financeiro ou admin, concede
  a nova permissao automaticamente;
- a action key legada permanece somente para historico e nao autoriza a RPC;
- nenhum override positivo legado existia e nenhuma concessao foi migrada;
- Clientes, Pedidos, Seguranca, manuais e testes refletem a separacao.

O fechamento anterior de grupos de produto permanece vigente:

Governanca relacional de grupos de produto e eliminacao das interfaces
concorrentes da Central de Cadastros:

- Central de Cadastros atua como portal para Materias-primas, Produtos,
  Embalagens e catalogos tecnicos;
- Produtos usa exclusivamente `grupo_id` para novos vinculos;
- grupos inativos permanecem legiveis no historico e nao podem receber novos
  produtos;
- criacao, edicao, inativacao e reativacao de grupos sao auditadas;
- rotulos operacionais em PT-BR sao centralizados e enums internos nao sao
  exibidos diretamente;
- rota canonica `/cadastros/grupos-produto` possui busca, filtros, manutencao,
  historico e manual contextual.

O fechamento anterior de idempotencia permanece vigente para:

- recebimento financeiro;
- pagamento e ajuste de comissao;
- criacao de pedido por vendedor;
- criacao de formula e OP;
- ajuste de limite e decisao gerencial;
- criacao de rascunho de Romaneio;
- emissao conjunta de OP MAPA e Ordem de Envase;
- criacao de pedido de troca;
- atribuicao manual de comissao;
- emissao de NF e estorno pos-pagamento com devolucao fisica.

Cada operacao usa chave de requisicao, trava transacional, reaproveitamento do
resultado em retry identico e rejeicao quando a mesma chave chega com payload
divergente. As tabelas de requisicao nao foram abertas para leitura direta dos
papeis da API.

## Validacao desta tarefa

- CI integral do commit `5d94325` aprovada no run `30156953429`;
- deployment `dpl_F9kRyxh3DsnDTmMWMqPJdjZxhpnM` ativo no dominio estavel,
  contendo exatamente o commit `5d94325`;
- health-check HTTP 200 com backend configurado;
- 20 rotas autenticadas percorridas online; 18 operacionais e 2 bloqueadas
  corretamente pelo rollout (`Relatorios` e `Rastreabilidade`);
- Romaneio validado em 1920 x 1080, 1366 x 768, 768 x 1024, 390 x 844 e
  360 x 800, sem rolagem horizontal e sem mensagem tecnica;
- ensaio funcional `HOM-E2E-20260725-MS08GPR2` neutralizado no Romaneio pelo
  cancelamento governado, preservando auditoria;
- nenhum dado real, reset, migration ou alteracao em producao.

- CI integral do commit `9e56e15` aprovada nos jobs `database-contract`,
  `python-tests` e `web-contract`;
- ambiente descartavel `elite-validation-e2e-ux01f-012809` confirmou
  instalacao limpa ate `0107`, smoke SQL FIFO e Playwright `10/10` nas
  resolucoes de 1920, 1366, 768, 390 e 360 pixels;
- 626 testes Python, ESLint, TypeScript, build Next.js, `git diff --check` e
  varreduras de arquivos proibidos foram aprovados;
- ambiente descartavel `elite-validation-prodnav-dd4aeab` confirmou todas as
  migrations, quatro cadeias SQL e Playwright `30/30` em cinco resolucoes;
- instalacao limpa, upgrade `0102` para `0103`, concorrencia e smokes
  PostgreSQL executados em ambientes `elite-validation-*`;
- ledger de staging confirmado ate `0107`;
- health-check de staging com `status=ok` e `backendConfigured=true`;
- deployment `dpl_G8XBztHpeaRjYzPSYVpcYYSLAZR4` promoveu exatamente o commit
  `9e56e15` no projeto `elite-system-staging`;
- smoke autenticado de Formulas confirmou busca, filtros, consulta de versoes,
  fluxo de criacao, componentes progressivos, separacao MAPA, aviso de revisao
  por litro, manual e ausencia de IDs tecnicos;
- smoke autenticado de Ordens confirmou consulta, filtros, estados PT-BR,
  cobertura por componente, saldo insuficiente, FIFO, criacao separada,
  mudancas governadas e manual contextual;
- a abertura de nova OP permaneceu corretamente indisponivel no staging sem
  formula operacional vigente e revisada;
- desktop de 1366 x 768 e celular de 390 x 844 foram comprovados online sem
  rolagem horizontal; as cinco resolucoes foram cobertas no ensaio descartavel;
- smoke autenticado confirmou Clientes em somente leitura, nova alcada
  bloqueada na Seguranca e ausencia do ajuste permanente em Pedidos;
- grupo e produto sinteticos foram inativados pelo fluxo governado, sem apagar
  o historico;
- nenhum dado real, reset ou alteracao em producao.

## Fluxos funcionais disponiveis

### Cadastros

- Clientes e ficha relacional completa;
- Pessoas e vinculos comerciais;
- Materias-primas e tipos de insumo;
- Produtos, apresentacoes e embalagens;
- catalogos tecnicos, unidades, garantias e logistica;
- governanca PT-BR e manuais contextuais.

### Producao e estoque

- formula operacional com base por litro;
- garantias documentais e calculo fisico por lote consumido;
- OP, reserva FIFO, inicio, CQ e finalizacao;
- um produto e um lote PI por OP;
- OP MAPA documental e Ordem de Envase;
- um lote PA por envase/apresentacao;
- custo por camada de entrada de MP;
- perda de processo separada de perda de estoque;
- custo PI por MP e custo PA por PI mais embalagens;
- relatorios com filtro MP, PI e PA.

### Comercial, expedicao e financeiro

- pedidos de Venda, Bonificacao, Mostruario e Troca;
- todo pedido nasce bloqueado e depende de decisao superior;
- PDF liberado somente depois da aprovacao, em A4 paisagem;
- totais de litros, volumes e peso bruto derivados;
- comissionados flexiveis por pedido: vendedor, agente, gerente ou outro;
- bonificacao e mostruario sem comissao;
- recebimento, liberacao proporcional, pagamento e ajuste de comissao;
- Romaneio por pedido, item, quantidade parcial, lote e embalagem;
- reserva sem baixa fisica e baixa consolidada pela informacao fiscal.

### Importacao fiscal e historica

- XML de NF-e possui chave de acesso normalizada unica;
- cada item XML pode originar somente um lote de MP;
- analise e homologacao funcional das fontes historicas sem escrita;
- staging e mapeamento de MP auditados;
- custos de aquisicao com mercadoria, frete, DIFAL e despesas separados;
- rastreabilidade por workbook, tabela e linha;
- aplicacao integral do workbook continua condicionada a homologacao das fontes
  e ao corte fisico de abertura.

## Seguranca vigente

- contas individuais e escrita sensivel por RPC auditada;
- RLS e menor privilegio;
- escrita direta revogada;
- fatos historicos append-only;
- limite de credito controlado pela alcada individual
  `financeiro.credit_limits.adjust`, sem inferencia por papel;
- `anon` e `PUBLIC` sem execucao das RPCs operacionais;
- convite, recuperacao de senha e troca administrativa de e-mail governados;
- assinatura institucional `by ☧ SYSTEMS` preservada.

## Decisoes ainda bloqueantes

- `DEC-002`: MFA TOTP e exigencia de AAL2;
- `DEC-003`: autoaprovacao de troca de e-mail do unico administrador;
- `DEC-004`: politica Auth de producao, SMTP corporativo e CAPTCHA;
- `DEC-012`: corte e inventario fisico de abertura;
- emissao fiscal sem chave de NF-e: definir se o fluxo admite rascunho fiscal ou
  se toda emissao definitiva deve exigir chave fiscal antes de ganhar uma chave
  de requisicao propria.

Essas decisoes nao bloqueiam desenvolvimento e homologacao no staging, mas
bloqueiam entrada segura em producao real ou ativacao de saldos oficiais.

## Proxima tarefa

1. Corrigir de forma governada o rollout de Faturamento, Financeiro,
   Relatorios e Rastreabilidade no staging, sem ampliar alcadas individuais.
2. Fechar as lacunas operacionais de veiculo, vinculo do usuario com a carteira
   comercial, configuracao logistica da apresentacao e garantias do produto.
3. Reexecutar o ensaio `HOM-E2E-*` desde pedido ate referencia fiscal,
   recebimento, comissao, rastreabilidade, recolhimento e reconciliacao.
4. Preparar o corte fisico `DEC-012` antes de ativar saldos reais.

UX-01F esta publicado e tecnicamente validado no staging: Ordens opera por
consulta, criacao, reserva e transicao de estado separadas, preserva FIFO,
multilote, alçadas atomicas, auditoria e idempotencia. UX-01E e UX-01F
permanecem na fila de homologacao visual consolidada de Luciano.

## Tarefa seguinte

Concluir a homologacao funcional do workbook e executar a etapa I2 somente para
fontes aprovadas, mantendo a importacao operacional bloqueada ate essa decisao.

Nao reaplicar migrations, nao resetar banco e nao alterar producao real.

## E2E-01 + TRACE-01

O commit `1f9200a` esta publicado na branch de desenvolvimento. Instalacao
limpa, upgrades `0066 -> 0067` e `0104 -> 0105 -> 0106`, quatro cadeias SQL,
Playwright `15/15`, 608 testes Python, build e CI foram aprovados.

As migrations `0105` e `0106` foram aplicadas separadamente no staging depois
de dry-runs unitarios. Esse fechamento E2E confirmou o ledger ate `0106`; o
estado atual do staging ja inclui a `0107`, aplicada unitariamente para a
Visao geral de Producao. O health-check esta saudavel e os smokes remotos
terminaram em rollback sem dados sinteticos residuais. O resultado e
**aprovado com ressalvas** ate que toda a cadeia seja tambem executada pelo
navegador.

## Revisao integral E2E-01 + TRACE-01 em andamento

Os commits `c860d49` e `28ef700` corrigiram a exposicao de identificadores
tecnicos nas telas de Estoque e Rastreabilidade, preservaram ausencia como
“Nao informado” e ampliaram os manuais de Garantias, CQ, Envase, Estoque,
Transformacoes e Rastreabilidade. A CI `30139897844` passou em Python, web e
contratos de banco.

O staging esta no deployment estavel `dpl_F9kRyxh3DsnDTmMWMqPJdjZxhpnM`,
com rollback `dpl_G2kFxfxcgaq9s76CHBd59mWcZS2r`, contendo o commit
`5d94325`. Nao houve alteracao de migration, banco, Supabase, main, producao
real ou PWA.

Pendencias tecnicas reais desta revisao: liberar de forma governada os modulos
necessarios no rollout do staging; concluir a cadeia pelo navegador desde a
referencia fiscal ate recebimento, comissao e rastreabilidade; fechar a
reconciliacao e os cenarios negativos no mesmo ensaio sintetico.

O commit `e7b9599` preserva os filtros relacionais da Rastreabilidade com
valores apresentados ao operador para cliente, pedido, romaneio e lote. Os IDs
continuam restritos ao contrato interno das consultas e nao sao campos de
entrada da interface. O CI `30140598039` passou em Python, web e banco
descartavel. O commit documental `bf6c074` tambem passou no CI `30140733341`.

O health-check do dominio estavel respondeu `status=ok` e
`backendConfigured=true`. O ensaio online confirmou a cadeia industrial ate
PA e o comportamento correto de reserva/cancelamento do Romaneio, mas nao
concluiu referencia fiscal, recebimento, comissao e rastreabilidade porque os
modulos proprietarios correspondentes permanecem desabilitados no rollout.
