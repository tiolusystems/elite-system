# ORD-01 — Revisão e aditivo contratual

## Decisão

Antes da primeira efetivação, uma alteração material cria nova versão F2B.
Depois da efetivação, a alteração material cria aditivo contratual governado.

O contrato original permanece válido. `pedido_efetivado_em` nunca é alterado.
Um aditivo pendente ou rejeitado não modifica o contrato vigente.

## Cadeia contratual

A primeira efetivação cria o estado gênese `H0`. Cada aditivo efetivado cria o
próximo estado, formando `H0 -> H1 -> H2`.

Quando uma revisão pré-efetivação `H1` é a primeira versão que satisfaz os
gates, `H0` continua sendo o estado comercial original congelado. A efetivação
de `H1` não o substitui nem o incorpora silenciosamente na gênese.

Cada elo preserva:

- hash do estado base;
- hash do delta;
- hash do estado resultante;
- sequência base e sequência resultante;
- fatos comerciais e financeiros utilizados.

Base obsoleta, fork, gap ou divergência de hash bloqueiam a efetivação.

Pedidos efetivados antes da criação da gênese podem materializar `H0` de forma
lazy e idempotente somente a partir dos fatos F2B/F2A congelados. Cadastro,
preço ou embalagem mutáveis não são fonte histórica. Estado incompleto ou
ambíguo bloqueia aditivos.

## Impacto e gates

O banco deriva a máscara de impacto:

- `pricing`;
- `discount`;
- `financial`;
- `buyer_signature`;
- `commercial_resolution`.

Dimensão impactada exige novo fato vinculado à revisão. Dimensão não impactada
é `NOT_REQUIRED`; não existe rebinding silencioso de fato antigo.

A efetivação também exige capacidade comprovada dos consumidores downstream.
Para revisão pré-efetivação, os consumidores comerciais já versionados
(condição financeira, referência, F2A, F2B, crédito, assinatura e F2C) usam
os fatos materializados da revisão exata. A venda permanece bloqueada até que
os gates novos e impactados estejam presentes e a RPC governada a efetive.
Dimensão sem consumidor compatível permanece pendente/bloqueada.

Na 0136, aditivos pós-efetivação continuam conservadoramente bloqueados:
logística, produção, Romaneio, estoque, comissão, troca e devolução ainda não
consomem a projeção contratual versionada. A projection não autoriza aditivo
silencioso enquanto esses consumidores não forem adaptados.

## Materialização pré-efetivação

Cada item resultante é registrado em `com_pedido_revisao_itens`. Produto,
quantidade, unidade comercial, fator e quantidade precificável pertencem ao
estado da revisão; o item original permanece apenas como linhagem imutável.
`com_pedido_revisao_materializacoes` liga a mesma revisão ao plano financeiro,
referências comerciais, fatos F2A e confirmação F2B exatos. Nenhum consumidor
seleciona o último fato global ou reutiliza quantidade/apresentação do item
original para uma revisão material.

Logística, produção, Romaneio, estoque, comissão, troca, devolução e interface
de revisão não fazem parte da migration 0136.

## Segurança

Revisões e eventos são append-only, auditados, idempotentes, serializados por
pedido e protegidos por RLS, grants mínimos e default-deny. Escrita direta em
fatos, eventos e gênese é recusada.
## Registro da decisao

- Luciano: SIM, em 2026-08-23.
- A identidade do pedido permanece a mesma; versoes e aditivos sao fatos novos.
- Versoes anteriores permanecem imutaveis e cada gate material e vinculado a uma versao exata.
- A leitura da projecao vigente e somente leitura, sem materializacao lazy.
- A materializacao lazy de H0 ocorre apenas em caminho governado de escrita e nunca altera a efetividade original.
- A migration 0136 deixa a efetivacao de revisoes bloqueada quando um consumidor downstream ainda nao possui suporte comprovado ao contexto versionado.
