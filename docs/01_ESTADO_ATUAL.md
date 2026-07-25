# Elite System - estado atual

Atualizado em: 2026-07-24

## Referencia vigente

- branch de desenvolvimento publicada: `feature/0044-production-module-release`;
- commit funcional publicado: `9e56e15`;
- Supabase de homologacao: ledger alinhado de `0001` a `0107`;
- frontend estavel: `https://elite-system-staging.vercel.app`;
- backend de staging: `/api/health` com `status=ok` e `backendConfigured=true`;
- deployment estavel de staging: `dpl_G8XBztHpeaRjYzPSYVpcYYSLAZR4`;
- deployment anterior preservado para rollback: `dpl_DK9R39zWNHshkQ9xPGwhqi2TvZDy`;
- producao real e `main`: nao alteradas;
- PWA: adiada.

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

## Tarefa concluida mais recente

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

1. UX-01G - Qualidade e finalizacao como proxima tela do fluxo visual oficial.
2. Ampliar o ensaio de navegador para percorrer OP, CQ, PI, envase,
   PA, pedido, Romaneio, recebimento e comissao pela interface.
3. Executar no staging o ensaio sintetico `HOM-E2E-*`, sem dados reais, e
   neutralizar seus efeitos pelo fluxo governado.
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

O staging permanece no deployment estavel `dpl_G8XBztHpeaRjYzPSYVpcYYSLAZR4`,
com rollback `dpl_DK9R39zWNHshkQ9xPGwhqi2TvZDy`, porque a promocao do novo SHA
aguarda deployment criado no projeto correto `elite-system-staging`. Nao houve
alteracao de migration, banco, Supabase, main, producao real ou PWA.

Pendencias tecnicas reais desta revisao: publicar e validar o novo frontend no
staging; executar a cadeia completa pelo navegador, incluindo CQ, PI, Envase,
PA, pedido, Romaneio, recebimento, comissao e rastreabilidade; fechar a
reconciliacao e os cenarios negativos no mesmo ensaio sintetico.

O commit `e7b9599` preserva os filtros relacionais da Rastreabilidade com
valores apresentados ao operador para cliente, pedido, romaneio e lote. Os IDs
continuam restritos ao contrato interno das consultas e nao sao campos de
entrada da interface. O CI `30140598039` passou em Python, web e banco
descartavel. O commit documental `bf6c074` tambem passou no CI `30140733341`.

O health-check do dominio estavel respondeu `status=ok` e
`backendConfigured=true`, mas a pagina ainda serve o deployment anterior
`9e56e15`; nao houve promocao dos novos commits porque a sessao nao possui CLI
ou credencial Vercel verificavel.
