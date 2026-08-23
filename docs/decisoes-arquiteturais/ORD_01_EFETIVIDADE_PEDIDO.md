# ORD-01 — Efetividade do pedido

## Contrato

Uma venda somente se torna efetiva quando todos os fatos da mesma versão
comercial governada estiverem satisfeitos:

- confirmação comercial F2B vigente;
- fatos F2A coerentes com a comparação e o snapshot da versão vigente;
- decisão financeira `liberado` vinculada à mesma confirmação e ao mesmo
  documento canônico;
- evidência de assinatura do comprador `ACCEPTED`, vinculada à mesma
  confirmação e ao mesmo SHA-256;
- decisão F2C `APPROVED` quando existir item `BELOW_REFERENCE`.

Sem item abaixo da referência, F2C não é exigida. Assinatura do comprador não
é aprovação Elite, e aprovação de desconto não é aprovação de crédito.

## Efetivação

`com_pedidos.pedido_efetivado_em` é um fato definido uma única vez por
`clock_timestamp()` no instante em que o último gate ausente é reconhecido.

O sistema grava o timestamp e muda `blocked` para `open` na mesma transação.
O campo é imutável, o caminho `blocked -> open` é protegido no banco e o
avaliador interno é idempotente sob bloqueio da linha do pedido.

`declared_signed_at`/`declarado_assinado_em` nunca define efetividade. Não há
retroatividade nem backfill de pedidos históricos.

## Versões e auditoria

Fatos de versões F2B anteriores, hashes antigos, aprovações antigas e
assinaturas antigas não satisfazem a versão comercial vigente. A efetivação
registra no log de auditoria o pedido, a versão F2B, o SHA do documento e os
fatos que fecharam os gates.

Crédito, F2C e SIG01 continuam append-only, separados e idempotentes. O
avaliador é chamado pelos três RPCs existentes após a gravação de cada fato;
nenhuma chamada pública direta pode abrir uma venda.
## Correcoes de integridade da efetividade

O avaliador e chamado pelos tres RPCs governados, na mesma transacao apos a
gravacao de cada fato. Nao ha gatilhos `AFTER INSERT` de efetividade. O
contexto privado usado somente na transicao `blocked -> open` e restaurado
imediatamente depois da atualizacao, inclusive no caminho de excecao.

O estado e a auditoria registram os IDs exatos da decisao de credito, da
evidencia e decisao de assinatura, da decisao F2C quando exigida e da
confirmacao F2B/SHA-256 corrente, alem do ator que reconheceu o ultimo gate.
