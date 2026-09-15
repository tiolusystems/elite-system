# PRC-01 - validação da fundação

## Objetivo

Comprovar que a formação de custos e preços é reproduzível, segregada e
auditável sem publicar preços comerciais nem gerar efeito financeiro.

## Evidências exigidas

- instalação limpa `0001 -> 0138`;
- upgrade `0137 -> 0138`;
- smoke `tests/sql/cost_pricing_iso_foundation.sql`;
- teste Python `tests.test_cost_pricing_iso_foundation_contract`;
- suíte Python completa;
- lint e build web;
- verificação responsiva em desktop e smartphone;
- lint PostgreSQL e `git diff --check`.

O smoke usa somente usuários e valores sintéticos dentro de transação revertida.
Ele prova margem, markup, preço à vista, 18 prazos, taxas, componentes de
pontuação/premiação, substituição manual, bloqueio por ausência, denominador
inválido, snapshot histórico, retry, RLS e append-only.

## Critérios de aceite

1. Cada cálculo referencia a política e as fontes congeladas.
2. Recalcular um cenário histórico não consulta política mutável nem custo atual.
3. A pessoa criadora não aprova o próprio fato.
4. Cálculo bloqueado informa o motivo sem persistir resultado parcial.
5. O dossiê expõe versão, fonte, resultado e decisão em linguagem de negócio.
6. Nenhuma lista comercial, pagamento, estoque ou fórmula PCP é alterado.
7. Esta evidência demonstra controle de software; não declara certificação ISO.

## Resultado

Pendente da execução final dos gates proporcionais desta entrega local.
