# ORD-01 - Fase 2C - Revisao governada de desconto

## Contrato

A revisao de desconto e independente da decisao de credito. O vendedor confirma
a versao comercial na F2B; quando qualquer item estiver `BELOW_REFERENCE`, a
versao exige uma decisao posterior com a alcada `pedidos.commercial_discount.review`.
Essa acao nasce bloqueada por padrao e nao e inferida por cargo.

A decisao e `APPROVED` ou `REJECTED`, exige justificativa com no minimo dez
caracteres, e permanece append-only, auditada e idempotente.

## Vinculo exato

Cada decisao referencia o `confirmacao_comercial_id` vigente da F2B e o
`comparacao_sha256` recalculado pelo banco. Uma versao comercial futura torna
decisoes anteriores inelegiveis. O pedido e a decisao de desconto continuam
bloqueados; a F2C nao aprova credito, nao altera preco, comissao ou efetividade.

## Gate

O gate de credito no banco recusa liberar uma venda com item abaixo da
referencia sem uma decisao de desconto aprovada para a mesma versao e hash.
Pedidos sem item abaixo da referencia nao exigem revisao de desconto.
Resultado liquido positivo nao elimina a exigencia quando houver item abaixo.

## Interface

A fila de revisao mostra pedido, cliente, vendedor, justificativa comercial e
comparacao vigente. A aprovacao e a rejeicao sao acoes separadas da analise de
credito. Nenhuma acao da tela abre o pedido por si so.
