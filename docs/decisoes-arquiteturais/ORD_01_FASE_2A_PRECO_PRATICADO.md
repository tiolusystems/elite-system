# ORD-01 - Fase 2A - Preco praticado e comparacao comercial

## Decisao

O preco praticado passa a ser um fato append-only por item de pedido de venda bloqueado. Ele usa exclusivamente a unidade, o fator e o preco de referencia genericos ja congelados no snapshot comercial da ORD-01 1D/1E. Nenhum valor legado de `com_pedido_itens` participa da nova comparacao.

O chamador informa somente o preco praticado inteiro, em centavos por unidade comercial. O banco congela a quantidade de apresentacoes, a quantidade comercial, a unidade, o fator e a referencia; valida todos os itens ativos do pedido em uma unica transacao idempotente e recusa venda com preco zero ou negativo.

## Calculo

- quantidade comercial = quantidade de apresentacoes x fator congelado;
- percentual do item = `(praticado - referencia) / referencia x 100`, com seis casas decimais;
- cada valor economico de linha e arredondado em centavos pelo metodo decimal `HALF_UP`;
- os totais somam as linhas ja arredondadas;
- desconto bruto soma impactos negativos em valor absoluto;
- overprice bruto soma impactos positivos;
- resultado liquido = overprice bruto - desconto bruto;
- percentual liquido = resultado liquido / total de referencia.

Um item abaixo da referencia permanece classificado e visivel mesmo quando o resultado liquido total do pedido for positivo.

## Fronteira

Esta tranche nao altera `valor_unitario`, `percentual_desconto`, `valor_total` ou o valor legado do pedido. Tambem nao implementa alerta de vendedor, confirmacao, aprovacao de desconto, credito, comissao, campanhas, bonificacao, mostruario, troca ou devolucao. A futura revisao governada do pedido devera criar novos fatos; nao pode editar os fatos desta tranche.
