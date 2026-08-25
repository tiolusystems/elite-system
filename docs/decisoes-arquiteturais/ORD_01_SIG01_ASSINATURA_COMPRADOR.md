# ORD-01 SIG01 — Assinatura do comprador

## Contrato

SIG01 registra evidência da assinatura do comprador separadamente da aprovação
da Elite. O documento fica disponível quando existe uma confirmação F2B, sem
dependência de crédito, e permanece vinculado ao `confirmation_id` e ao
`documento_canonico_sha256` exatos.

E-mail é somente comunicação. Upload ou referência externa isolados criam uma
evidência `PENDING`; somente uma decisão `ACCEPTED` satisfaz a assinatura. A
decisão não altera status, crédito, preço, comissão ou efetividade do pedido.

As fontes previstas são `integrated_api`, `gov_br`, `external_digital` e
`physical_digitized`. Os provedores não são integrados nesta tranche. Artefatos
digitais ficam em bucket privado e são enviados pelo servidor; o hash é
calculado no servidor para arquivos recebidos pela aplicação.

## Integridade

Evidências, decisões e metadados de idempotência são append-only, auditados e
default-deny. O documento e o contato comprador são congelados no registro da
evidência. Uma nova versão F2B torna evidências anteriores históricas; uma
decisão aceita sempre exige a versão comercial vigente.

O pedido permanece bloqueado. SIG01 não é aprovação da Elite, não abre pedido,
não executa o gate de efetividade e não depende de análise de crédito.
