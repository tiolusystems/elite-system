# Elite System - estado atual

Atualizado em: 2026-10-04

## Tarefa em execucao

- `ENG-ENV-01` estabelece a topologia canonica e normalizou a linhagem Git:
  `staging` e ancestral de `main`;
- `staging` e a branch permanente de integracao e homologacao;
- `main` e a branch permanente de producao;
- ambas exigem PR, `python-tests`, `web-contract`, `database-contract`,
  enforcement para administradores e negam force push e exclusao;
- staging canonico: o deploy Vercel `elite-system-staging` foi comprovado em
  `elite-system-staging.vercel.app`; o Supabase `elite-system-staging` /
  `igwweatzuxmeayibyuge` esta no ledger de migration `0152`;
- producao: Vercel `elite-system`; o Supabase `elite-system-production` /
  `oncssgiocivoknwwcuuz` existe, esta `ACTIVE_HEALTHY` e possui ledger de
  migrations vazio; ele nao esta ativado nem conectado a uma release de producao;
- a PR #30 promoveu staging validado para `main` e gerou um deployment Vercel
  com `target=production`; o banco de producao nao foi alterado e o trafego foi
  restaurado para o deployment validado anterior;
- a investigacao confirmou Production Branch=`main` e Auto-assign Custom
  Production Domains desabilitado: o modelo canonico e deployment staged mais
  promocao explicita, e nao publicacao automatica pelo build;
- a base de producao permanece nao inicializada e o deploy automatico de banco
  permanece desabilitado ate que o pipeline governado seja validado.
- o primeiro `verify-staging` falhou fechado antes de conectar ao banco porque
  o PAT com escopo reduzido nao tinha `api_gateway_keys_read`; nenhuma migration
  foi aplicada. O transporte canonico foi simplificado para URL direta de banco
  pelo session pooler, sem Management API PAT; o deploy remoto automatico
  permanece desabilitado.

## Proxima tarefa

Executar a readiness verify-only do banco de producao antes de qualquer
promocao ou migracao remota.

## Historico de implementacao por modulo

As secoes seguintes preservam fatos de implementacao e validacao por modulo.
Elas incluem o registro historico "Estado vigente em 2026-08-25", que nao
substitui o estado global acima.

## Validacao vigente

- instalacao limpa `0001 -> 0137` e upgrade `0136 -> 0137` aprovados no runtime
  descartavel `elite-validation-price-list-ui`;
- na validacao da `0136`, o upgrade e o smoke comportamental `order_revision_and_addendum.sql` foram aprovados;
- os 46 smokes SQL padrao e o smoke dirigido
  `price_list_operational_xlsx.sql` foram aprovados;
- 32 testes Python dirigidos da importacao e dos contratos de lista foram
  aprovados;
- TypeScript, ESLint e build de producao foram aprovados, com
  `apps/web/next-env.d.ts` preservado;
- o E2E operacional aprovou `10/10` casos em 1920, 1366, 768, 390 e 360 px,
  incluindo download, erros, avisos, publicacao, historico, retry e acesso
  negado;
- o parser aprovou `4/4` casos dirigidos: limite de 10.000 linhas, rejeicao de
  10.001 linhas/dimensao excessiva, expansao ZIP suspeita e hash canonico;
- o lint PostgreSQL nao registrou diagnostico novo da migration `0137`; o erro
  preexistente de `lote_id` ambiguo permanece fora deste escopo;
- `OPS-GATE-01` permanece como evidencia historica do gate operacional anterior.

## Contratos preservados

- regras comerciais e financeiras permanecem no PostgreSQL governado;
- fatos financeiros, comerciais, assinaturas, efetividade e revisoes sao
  append-only quando o contrato determina;
- aplicacao usa `Server Action -> RPC auditada -> dominio proprietario`;
- uma venda somente se torna efetiva quando todos os gates da versao comercial
  exata forem reconhecidos pelo avaliador;
- `pedido_efetivado_em` e imutavel e nunca deriva da data declarada da assinatura;
- a migration `0136` nao reescreve migrations `0124` a `0135`.

## Limites vigentes

- aditivos pos-efetivacao permanecem fail-closed enquanto os consumidores
  downstream nao suportarem o contrato versionado;
- logistica, producao, Romaneio, estoque, comissao, troca e devolucao nao foram
  ampliados pela `0136`;
- o lint PostgreSQL ainda registra o erro preexistente em
  `consultar_est_estoque_lotes`, por `lote_id` ambiguo; ele nao pertence a ORD-01;
- importacao historica `I2` permanece bloqueada ate a homologacao funcional das
  fontes por Luciano e a decisao `DEC-012`;
- nenhum deploy, migration remota ou alteracao de banco persistente integra a
  implementacao local do workspace XLSX.

## Proxima tarefa registrada no estado anterior

Publicar a correcao IAM-01A depois da validacao descartavel aprovada e usar o
CI remoto como gate. IAM-02 (sessoes e dispositivos) permanece fora deste
escopo.

## IAM-01A - identidade e perfis de acesso

A migration aditiva `0147_iam01_access_governance.sql` cria catalogo
versionado de perfis, permissoes relacionais explicitas, atribuicoes multiplas
por conta humana e RPCs administrativas auditadas. O campo legado
`user_profiles.role` permanece como fallback de transicao para contas sem
atribuicao; contas novas recebem perfil de acesso inicial pelo fluxo de convite.
Perfil de acesso, funcao organizacional e papel comercial continuam separados.

O replay descartavel `0001` a `0147` concluiu as 146 migrations e os smokes de
Pessoa/Cadastros e IAM passaram. A fixture administrativa recebeu o perfil
restritivo `consulta_auditoria` v1 para impedir fallback legado. A pessoa criada
mantem `tipo_comercial = NULL` e usa o papel cadastral `funcionario`, em vez do
valor de funcao organizacional `funcionario_elite`. O perfil
`administrador_sistema` agora inclui a permissao atomica
`security.identity.person.link`, ainda com `default_allowed = false`; nao recebeu
`cadastros.pessoas.create`. A fronteira privada de Cadastros, RLS, ACL,
default-deny e auditoria permanecem preservados.

A correcao local dos P1 registra a primeira adocao de perfil em marcador
persistente: remover ou expirar o ultimo perfil agora falha fechado, enquanto
contas que nunca adotaram perfis preservam o fallback legado de transicao. O
onboarding automatico deixou de reutilizar Pessoa por nome ou alias; qualquer
candidato exige selecao explicita por `p_pessoa_id`. Os contratos Python
dirigidos passaram em `11/11`, a suite completa passou em `867` testes com uma
omissao prevista, e o replay limpo `0001 -> 0147`, o smoke Cadastros e o smoke
IAM passaram no runtime descartavel `elite-validation-iam01-20260908b`.

Durante a homologacao IAM-01A foi identificada exposicao ampla de leitura nos
dominios PCP e Estoque. O hotfix 0148 fecha a navegacao, o acesso por URL direta,
o autosservico de senha e as politicas RLS de PCP/Estoque. O replay descartavel
`0001 -> 0148` e o smoke `iam01_fail_closed_navigation_password.sql` passaram;
o hotfix foi homologado em staging.

## Home governada por capability

A rota `/` separa a superficie comercial da operacional por
`getNavigationAccess`. Quem nao possui nenhuma capability operacional recebe
somente atalhos comerciais autorizados para pedidos, Kanban e, quando liberado,
clientes; a home nao executa getters de PCP, Estoque, XML, Romaneio, Seguranca,
Auditoria, modulos ou relatorios nesse caminho. A superficie operacional chama
cada getter somente depois de confirmar a capability da rota correspondente.
Os 11 contratos dirigidos, o lint e o build web passaram localmente. A proxima
etapa e revisao do delta antes de qualquer commit, push ou deploy.

## Feedback operacional persistente

Os resultados de gravacao dos Cadastros e catalogos tecnicos agora usam uma
notificacao compartilhada fixa abaixo da topbar. Sucessos fecham apos alguns
segundos; avisos e erros exigem fechamento manual. A URL e o contexto da ficha
permanecem preservados, sem rolagem forcada. O contrato dirigido, lint e build
web passaram; a proxima etapa e revisao do delta antes de qualquer publicacao.

## Fluxo comercial do vendedor

A migration local `0149_grant_seller_commercial_review.sql` concede ao perfil
`comercial_vendedor` somente as alçadas F2B necessárias para resolver
referência, registrar preço e contexto, calcular e confirmar a própria proposta.
Desconto, crédito, publicação de lista, administração e domínios não comerciais
continuam bloqueados. O replay SQL descartável permanece pendente nesta tarefa.

## Atualizacao PRC-01 P1

A migration aditiva 0145 endurece origem system, hash do snapshot completo e
idempotencia concorrente. A migration 0150 passa a emitir o codigo da politica
no banco e recebe a identidade da politica existente somente por ID; o replay
descartavel `0001 -> 0150`, o smoke PRC e a prova de emissao concorrente
confirmaram codigos unicos sem ampliar permissoes.
### PRC-01: exportacao auditavel

O workspace `/custos-precos` oferece XLSX e PDF apenas para calculos aprovados. Ambos sao gerados do snapshot `prc-calculation-v2` retornado pela superficie governada 0146; decisao e SHA-256 persistidos sao verificados antes da entrega.

### PRC-01: validacao da chave de idempotencia

Staging reproduziu `/custos-precos?result=invalid-request`: o guard em
`apps/web/app/custos-precos/actions.ts` usava um formato UUID incorreto e
rejeitava UUIDs padrao 8-4-4-4-12. A correcao restaura esse formato, preserva
o fail-closed e possui teste comportamental para UUIDs validos e invalidos.
O PR #15 estabilizou a chave client-side, mas nao corrigiu a causa raiz do
guard. A proxima etapa e homologar a criacao de politica de precos em staging;
depois, executar `ENG-01 Regression & Diagnostic Governance`.

### PRC-UX-01: workspace de custos e precos

O workspace `/custos-precos` passou a validar entradas no formulario antes da
RPC, converter percentuais humanos para fracao interna e manter feedback local
por acao. Margem liquida e Markup agora sao mutuamente exclusivos na tela e na
Server Action; erros preservam os valores preenchidos e permanecem junto ao
botao da acao, sem mover automaticamente o cursor do operador. O formulario
usa o CSS Module responsivo, e a leitura inicial de valores nao avalia globals
do DOM durante SSR. A origem de validacao sintetica permanece exclusiva dos
testes; a tela oferece apenas substituicao manual enquanto nao houver fonte
canonica de sistema. Estados vazios, indisponibilidade da consulta e
carregamento foram separados. Os contratos PRC dirigidos, ESLint e o build web
passaram. A proxima etapa e a homologacao integral de `/custos-precos`; em
seguida, `ENG-01 Regression & Diagnostic Governance`.

### PRC-UX-02: formulario de politica governada

O formulario passou a selecionar a politica existente por ID e a mostrar
`POL-######## - Nome` como identidade emitida pelo sistema. Para uma politica
nova, apenas nome e parametros sao informados; para uma nova versao, o nome e
o codigo permanecem congelados no banco. O layout do CSS Module usa tres,
duas e uma colunas em desktop, tablet e mobile, respectivamente. Percentuais
aceitam o sufixo opcional `%` sem mudar a conversao para fracao interna, e
somente o campo aplicavel de Margem ou Markup e renderizado. Erros continuam
locais sem mover foco para inputs; quando o feedback fica fora da viewport,
o proprio painel recebe foco e rolagem, nunca um controle de entrada. A 0150
mantem a assinatura N-1 como wrapper de compatibilidade: um codigo existente
seleciona a mesma politica e exige o nome correspondente; um codigo desconhecido
nao define a identidade, que continua emitida pelo banco. A aplicacao usa somente
a RPC V2. A sequence
`POL-00000001` a `POL-99999999` nao cicla, valida configuracao preexistente e
falha de forma controlada na exaustao. Nomes de politica usam o limite uniforme
de 3 a 120 caracteres. O replay descartavel `0001 -> 0150`, o upgrade
`0149 -> 0150`, incluindo retry legado trans-migration, o smoke PRC e as provas
de concorrencia de codigo e versao passaram; staging nao foi alterado.

### PRC-UX-03: workspace guiado de precificacao

A implementacao local reorganiza `/custos-precos` em cinco etapas: produto e
base de custo, politica comercial, cenario, precos e prazos, revisao e dossie.
O estado de progresso usa somente politicas, cenarios, calculos e revisoes ja
carregados pela superficie governada. A tela deixa explicito que a composicao
tecnica automatica ainda nao esta disponivel e que os cenarios atuais usam
substituicao manual governada. Os componentes do cenario foram agrupados por
finalidade comercial sem alterar campos, payloads, actions ou RPCs. Esta
entrega permanece somente local, sem staging, deploy ou mudanca de regra de
negocio.

### PRC-UX-04: workspace focado por etapa

O workspace local de `/custos-precos` passou a apresentar uma etapa operacional
por vez, selecionada por `?etapa=`, com navegacao horizontal e contexto do
processo separado do conteudo em uso. Revisoes pendentes agora tem prioridade
como gargalo atual e indicam o revisor de precificacao como responsavel. Os
formularios, payloads, actions, RPCs, exportacoes aprovadas e a substituicao
manual governada foram preservados. Os contratos dirigidos de workspace e
exportacao, ESLint, build web e `git diff --check` passaram localmente. A
proxima etapa e a revisao do delta UX antes de qualquer publicacao.

### UX-SYS-02: fundacao compartilhada de layout

A fundacao compartilhada recebeu o shell operacional reutilizavel de cabecalho,
fatos, stepper governado, superficie principal, painel contextual e heading de
etapa. `/custos-precos` continua como referencia dourada e passou a consumir
essa fundacao sem alterar regras, actions, RPCs ou comportamento de etapas.
Os estilos especificos de precificacao permanecem locais; nenhum outro modulo
foi migrado. Os contratos dirigidos, lint, build e `git diff --check` foram
executados localmente. A proxima tarefa e selecionar um unico modulo piloto
depois da revisao arquitetural.

### PRC-02B: fundacao do motor de formulas versionado

A migration 0151 implementa, de forma aditiva, identidades `FML-########`,
versoes append-only, catalogo de 14 parametros tipados, AST JSON fechada,
avaliador `numeric`, grades versionadas e lifecycle segregado. A fronteira e o
database da organizacao; nao existe identificador de tenant paralelo.

O PRC-01 permanece a unica fonte oficial. O motor novo executa somente em
shadow mode, sem alterar calculos, snapshots, exportacoes ou publicacao
comercial. `ACTIVE` ativa apenas o motor shadow. Aprovacao, substituicao e
retirada sao fatos separados e auditados; nao existe promocao automatica.
A formula congela ID e SHA-256 da grade; a execucao revalida os hashes da
formula e da grade. O smoke cobre golden masters Elite e o perfil alternativo
de cinco parametros, limites numericos e da AST, determinismo, default-deny e
helpers privados. No runtime descartavel, replay 0001-0151, upgrade real
0150-0151 com fatos PRC-01 previos, concorrencia FML em duas sessoes e
regressoes PRC-01 passaram. O Python completo passou (915 testes, 1 skip).
O lint local de banco retornou apenas diagnosticos historicos fora do PRC-02,
mas terminou com erro de telemetria; nao foi classificado como PASS.
Staging permanece inalterado.

### PRC-03B: motor versionado de valoracao

A migration 0152 implementa politicas versionadas e snapshots de valoracao sem
escrever em Estoque ou PCP. A linhagem FIFO persiste tambem camadas totalmente
reservadas, com quantidade disponivel zero; checks da mesma linha mantem as
quantidades coerentes. A selecao de ultima aquisicao usa ordenacao global por
entrada, movimento e valor; transicoes de lifecycle serializam por identidade
proprietaria; e a leitura governada revalida o hash do documento integral do
snapshot. Em 2026-09-26, replay descartavel 0001-0152 (151/151), smoke PRC-03,
upgrade real 0151-0152 com fingerprints PRC-01/02, contratos de seguranca e
Python completo (926 testes, 1 skip) passaram.

Em 2026-09-28, a migration 0152 foi aplicada em elite-system-staging e o ledger
terminou em `0152 prc03_versioned_valuation_engine`; o staging permaneceu
ACTIVE_HEALTHY. O smoke runtime descartavel passou com o marcador
`PG_PRC03_VERSIONED_VALUATION_ENGINE_OK`. WEIGHTED_AVAILABLE_BALANCE,
LATEST_ELIGIBLE_ACQUISITION, APPROVED_MANUAL_REFERENCE, reserva FIFO,
normalizacao de unidade e o gate de politica aprovada e ativa passaram. Tambem
passaram os fechamentos fail-closed para moeda mista e lote vencido, a deteccao
de adulteracao do hash, RLS/default-deny, privacidade dos helpers e append-only.
PRC-01 foi preservado, PRC-02 permaneceu em shadow mode, nenhuma fixture ficou
persistida e producao nao foi tocada.
