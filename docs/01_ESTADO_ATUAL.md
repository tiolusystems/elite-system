# Elite System - estado atual

Atualizado em: 2026-08-24

## Estado vigente em 2026-08-24

- repositorio: `tiolusystems/elite-system`;
- branch: `work/orders-rules-review-20260813`;
- HEAD local e remoto: `85e7d31d86dcede091b59f1c3cd8a26e95cb6c1f`;
- PR cumulativa ORD-01: `#8`, aberta contra `main`;
- `main`, producao real, PWA e bancos persistentes permanecem inalterados;
- `apps/web/next-env.d.ts` e uma alteracao local preexistente e permanece fora
  do delta ORD-01.

## Tarefa em execucao

`ORD-01 PR8 - integracao do macrociclo comercial e contratual`.

A PR integra os 14 commits intencionais da ORD-01, desde o fechamento do
entrypoint legado ate revisoes e aditivos contratuais. A sequencia inclui:

- listas de preco, importacao XLSX, condicao financeira, PMP e resolvedor;
- snapshot comercial e unidade de precificacao generica;
- preco praticado, confirmacao do vendedor e aprovacao independente de desconto;
- evidencia de assinatura do comprador e efetividade do pedido;
- revisoes pre-efetivacao e cadeia contratual `H0 -> H1 -> H2`.

O commit de protocolo AXL e infraestrutura de trabalho e auditoria do mesmo
macrociclo. Nao ha commit funcional alheio a ORD-01 na branch.

## Validacao vigente

- a revisao tecnica da migration `0136` foi aprovada antes do commit;
- instalacao limpa `0001 -> 0136` e upgrade `0135 -> 0136` foram aprovados em
  runtime descartavel;
- a instalacao limpa e o smoke comportamental `order_revision_and_addendum.sql` foram aprovados;
- smokes F2A, F2B, F2C, SIG01, efetividade e revisao/aditivo foram aprovados;
- o contrato Python dirigido da revisao aprovou 17 testes;
- a primeira execucao da CI da PR identificou falhas de integracao em contratos
  antigos, documentacao, fronteira RPC auditada e ACL de decisao gerencial;
- as correcoes de integracao permanecem locais, sem commit ou push;
- a suite Python completa aprovou `823/823` testes;
- lint e build web foram aprovados, e o contrato TypeScript do banco foi gerado;
- os 45 smokes SQL padrao e o upgrade dirigido `0128 -> 0129` foram aprovados;
- o lint PostgreSQL nao registrou diagnostico novo introduzido pela ORD-01;
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
  correcao local da PR.

## Proxima tarefa

Revisar o artefato integral das correcoes de integracao da PR `#8` e aguardar
autorizacao antes de commit ou push. Merge e deploy permanecem fora desta
tarefa.
