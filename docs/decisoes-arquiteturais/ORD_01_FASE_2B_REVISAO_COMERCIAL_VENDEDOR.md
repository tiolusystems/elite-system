# ORD-01 Fase 2B - revisão comercial do vendedor

## Decisão

A proposta de venda permanece somente no navegador enquanto é editada. A RPC
`prever_com_revisao_comercial_venda` resolve, sem persistir pedido ou rascunho,
a condição financeira, o PMP, a referência comercial, a unidade de
precificação congelável e a comparação econômica equivalente ao contrato F2A.

Qualquer mudança material na proposta altera o `preview_hash`. A confirmação
final aceita somente o hash da recomputação atual e cria, em uma única
transação, pedido bloqueado, itens, entregas, plano financeiro 1B, snapshots
1D/1E, fatos F2A e a confirmação comercial F2B.

## Versão comercial imutável

`com_pedido_confirmacoes_comerciais` é a âncora da versão comercial. Sua
identidade contratual é formada por:

- `id` da confirmação;
- número da versão;
- documento canônico em JSON;
- SHA-256 do documento canônico;
- fingerprint da comparação F2A;
- ator e data da confirmação.

O documento congela cliente, vendedor, data, origem e contexto comercial,
participantes, condição financeira, itens, quantidades, unidades, fatores,
preços, comparação e programação de entregas. Alteração material futura exige
uma nova versão governada; F2B deliberadamente bloqueia essa sucessão até o
workflow de revisão do Pedido ser implementado.

Os campos legados `valor_unitario`, `valor_total` e `percentual_desconto` não
são fonte comercial. Quando necessários para compatibilidade, são derivados
dos fatos canônicos: valor líquido praticado por apresentação, total praticado
da linha e desconto legado zero, evitando uma segunda aplicação de desconto.

## Desconto

Qualquer item `BELOW_REFERENCE` caracteriza solicitação de desconto, mesmo que
itens `ABOVE_REFERENCE` tornem positivo o resultado líquido do pedido. O
vendedor informa uma justificativa para o pedido inteiro e confirma
explicitamente que solicita os descontos apresentados.

F2B não aprova nem rejeita desconto. Essa decisão pertence à tranche F2C.

## Aprovação, assinatura e efetividade

Aprovação Elite e assinatura do comprador são fatos independentes. Qualquer um
poderá ocorrer primeiro, mas ambos deverão referenciar o mesmo `confirmation_id`
e `documento_canonico_sha256`.

A futura SIG-01 poderá registrar evidência de assinatura por API integrada,
gov.br, assinatura digital externa ou assinatura física posteriormente
digitalizada. O contrato futuro deve preservar provedor ou envelope, identidade
do signatário, data declarada, data de registro, arquivo/evidência, SHA-256 e
estado `pending`, `accepted` ou `rejected`. Upload isolado não equivale a
assinatura aceita.

O pedido somente será efetivo quando os requisitos Elite da versão corrente e
a assinatura aceita do comprador estiverem satisfeitos. O futuro
`pedido_efetivado_em` será o horário do sistema em que a última condição for
reconhecida, sem retroagir para uma data declarada de assinatura física.

Até esse fato existir, o pedido não conta para metas, prazos operacionais,
demanda firme, programação de produção ou projeção de comissão. F2B não cria o
fato de efetividade: mantém vendas bloqueadas e impede que a decisão gerencial
antiga altere diretamente o pedido para aberto.

## Documento atual

O PDF existente ainda é derivado ao vivo de dados correntes e somente aparece
para pedidos `open` ou `fulfilled`. Ele não é o artefato imutável de assinatura
da versão comercial. A renderização futura deverá partir do documento canônico
F2B.

Antes de SIG-01, os textos contratuais que equiparem assinatura do comprador à
aceitação automática da Elite, ou aprovação Elite à assinatura do comprador,
precisam de revisão jurídica. F2B não cria nem altera cláusula jurídica.

## Segurança

As alçadas `pedidos.commercial_review.preview` e
`pedidos.commercial_review.confirm` nascem bloqueadas. Não há concessão por
cargo. Tabelas de confirmação e idempotência não possuem acesso direto para
`authenticated`; leitura e escrita passam por RPCs com escopo, auditoria,
idempotência e guards append-only.

