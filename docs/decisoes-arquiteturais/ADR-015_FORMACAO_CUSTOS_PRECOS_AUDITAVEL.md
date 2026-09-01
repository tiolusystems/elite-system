# ADR-015 - Formação de custos e preços auditável

## Decisão

`precificacao` é um domínio próprio. Ele possui políticas, cenários, cálculos,
revisões e dossiês. Não publica lista comercial, não altera pedido, não grava
estoque, não modifica fórmula PCP e não libera comissão.

O processo usa dois métodos preservados:

- margem líquida;
- markup.

Cada cenário congela produto/apresentação, política exata, todos os componentes,
origem, referência, vigência, unidade, ator e motivo. Uma substituição manual
existe somente naquele cenário e nunca sobrescreve a fonte real.

## Unidades e fórmulas

Matéria-prima, embalagem, pontuações, premiações e frete são valores em
`BRL/L`. Comissão, tributação, marketing e risco são frações adimensionais,
porque participam dos denominadores e fatores das fórmulas aprovadas.

```text
custo_base = materia_prima + embalagem + pontuacoes + premiacoes + frete

preco_vista_margem =
  custo_base / (1 - comissao - tributacao - marketing - lucro_minimo)

preco_vista_markup =
  custo_base * (1 + markup) / (1 - comissao - tributacao - marketing)

preco_prazo_n = preco_vista + preco_vista *
  (((1 + juros_mensais)^n - 1) + risco) /
  (1 - comissao - tributacao - marketing)
```

São produzidos exatamente 18 prazos, de 30 a 540 dias. Resultados comerciais
usam `HALF_UP` com duas casas. Intermediários permanecem `numeric`, sem float.
Denominador não positivo, componente ausente ou fonte não resolvida bloqueiam o
cálculo; ausência nunca vira zero.

## Governança e ISO

Políticas, versões, revisões, cenários, componentes, cálculos, prazos, decisões
e requisições são fatos append-only. Escrita é exclusivamente por RPC auditada,
idempotente, com RLS e `default-deny`. Retry divergente é recusado.

O criador não pode aprovar a própria política nem o próprio cenário/cálculo.
Essa segregação é operacional; não concede certificação ISO 9001. A fundação
gera evidência de owner, entrada/saída controlada, versão, mudança, autorização,
rastreabilidade, reprodução, retenção e não conformidade.

## Limites

- planilhas e valores operacionais reais não entram no Git;
- fixtures usam apenas valores sintéticos ou sanitizados;
- publicação de lista pertence a `pedidos` e fica fora do PRC-01;
- emissão fiscal, pagamento de comissão e prêmio ficam fora do PRC-01;
- uma integração futura deve consumir APIs dos domínios proprietários, sem
  escrita cruzada.

## Hardening P1 em 0145

A migration aditiva 0145 bloqueia fontes system sem adapter can�nico, preserva substituicao_manual como entrada restrita ao cen�rio e registra prc-calculation-v2 com componentes e 18 prazos completos. As RPCs PRC serializam cada chave por lock transacional antes da consulta de idempot�ncia; retry id�ntico retorna o mesmo fato e retry divergente � recusado.
