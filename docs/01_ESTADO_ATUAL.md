# Elite System - estado atual

Atualizado em: 2026-09-09

## Estado vigente em 2026-08-25

- repositorio: `tiolusystems/elite-system`;
- base: `main` no merge `fb17622956b8b8ceb37ddf17d389d18d6097eb4b`;
- checkout local isolado: detached em `main@fb17622956b8b8ceb37ddf17d389d18d6097eb4b`;
- a PR cumulativa ORD-01 `#8` foi integrada a `main`;
- producao real, PWA e bancos persistentes permanecem inalterados por esta
  tarefa;
- os checkouts operacionais anteriores permanecem preservados.

## Tarefa em execucao

`PRC-01 - fundacao ISO de formacao de custos e precos`.

Fundacao local em implementacao pela migration aditiva `0138`. O novo dominio
`precificacao` possui politica versionada, cenario com fontes congeladas,
memoria de calculo para margem/markup e 18 prazos, revisao segregada e dossie.
Nao publica lista comercial, nao movimenta estoque, nao altera formula PCP e
nao gera pagamento financeiro.

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

## Proxima tarefa

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
locais sem mover foco para inputs. O replay descartavel `0001 -> 0150`, os
smokes PRC, contratos dirigidos, lint e build passaram; staging nao foi
alterado.
