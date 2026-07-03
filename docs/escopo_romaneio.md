# Escopo do romaneio

Data da decisao: 2026-07-03

## Decisao

O modulo de romaneio deve reproduzir, no minimo, o que a planilha `ROMANEIO` faz hoje.

Existem outras planilhas ou abas com nome parecido. Elas nao devem virar codigo automaticamente. A fonte canonica para este modulo e a planilha/tabela `ROMANEIO` que opera a separacao de pedidos, lotes e comunicacao com faturamento e expedicao.

## Papel do romaneio

O romaneio e a ferramenta que:

- escolhe qual pedido sera separado;
- define se a separacao sera total ou parcial;
- busca lotes disponiveis de produto acabado;
- vincula pedido, produto, quantidade e lote;
- informa o que deve seguir para faturamento;
- informa o que deve seguir para expedicao;
- gera a base auditavel para baixa de produto acabado.

## Baixa de estoque

A baixa de produto acabado deve acontecer via romaneio confirmado, nao via pedido bruto.

Regra de ciclo:

1. Pedido aberto nao baixa estoque.
2. Romaneio em rascunho nao baixa estoque.
3. Romaneio em separacao pode reservar lotes, se a regra operacional exigir.
4. Romaneio confirmado gera a saida de produto acabado.
5. Romaneio cancelado antes da confirmacao libera a reserva.
6. Romaneio estornado depois da confirmacao exige movimento de reversao auditado.

Isso evita baixar estoque de pedido ainda nao separado e evita faturar quantidade diferente da quantidade realmente separada.

## Separacao parcial

Quando o pedido for separado parcialmente:

- o romaneio baixa apenas a quantidade confirmada;
- o saldo pendente continua no pedido;
- o faturamento recebe somente a quantidade romaneada;
- a expedicao recebe somente os itens/lotes romaneados;
- a auditoria deve mostrar pedido original, quantidade romaneada e saldo pendente.

## Interfaces com outros modulos

Comercial:

- fornece pedidos e itens pendentes;
- recebe status de separado parcial, separado total ou pendente.

Estoque PA:

- fornece lotes disponiveis;
- registra reserva quando aplicavel;
- registra baixa somente por romaneio confirmado.

Faturamento:

- recebe o romaneio confirmado como base da quantidade faturavel.

Expedicao:

- recebe o romaneio confirmado como lista operacional de separacao/entrega.

## Fora do escopo inicial

Nao implementar como parte do romaneio inicial, salvo se estiver na planilha `ROMANEIO` canonica:

- sistema completo de montagem de carga;
- roteirizacao;
- gestao completa de frota;
- financeiro;
- emissao fiscal completa;
- qualquer segunda planilha chamada romaneio sem mapeamento aprovado.

## Criterio de aceite

O modulo de romaneio so sera considerado fiel quando:

- reproduzir os campos e decisoes da planilha `ROMANEIO` canonica;
- permitir separacao total e parcial;
- localizar lotes disponiveis;
- registrar pedido, produto, lote e quantidade;
- gerar baixa auditada de PA apenas no momento correto;
- reconciliar as baixas contra `SAIDAS_PA` e contra o historico importado.
