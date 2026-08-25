# Elite System - estado atual

Atualizado em: 2026-08-25

## Estado vigente em 2026-08-25

- repositorio: `tiolusystems/elite-system`;
- base: `main` no merge `806c9e2a2e7b3b9eda22fd6b22638ac0f4d348ac`;
- branch local isolada: `work/price-list-xlsx-ui-20260825`;
- a PR cumulativa ORD-01 `#8` foi integrada a `main`;
- producao real, PWA e bancos persistentes permanecem inalterados por esta
  tarefa;
- os checkouts operacionais anteriores permanecem preservados.

## Tarefa em execucao

`PRICE-LIST.XLSX-OPERATIONAL-UI - workspace operacional de listas de precos`.

Workspace `Comercial > Listas de precos` implementado e validado localmente,
ainda sem commit. O fluxo possui modelo XLSX governado, analise por codigos
canonicos, preview de avisos e erros, publicacao atomica de versao e historico.
A migration aditiva e a `0137`; migrations `0124` a `0136` nao foram
reescritas. O delta aguarda revisao tecnica final antes de qualquer integracao.

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

Revisar o artefato integral do workspace XLSX e aguardar autorizacao antes de
commit. Push, PR, merge e deploy permanecem fora desta tarefa.
