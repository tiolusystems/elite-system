# Validacao da migration 0033 - metas coupling legacy skip

Data da validacao: 2026-07-06

## Objetivo

Validar o acoplamento automatico do ledger de metas aos fluxos de cancelamento e estorno pos-pagamento, sem bloquear operacao real quando o pedido nao tem historico de meta.

Escopo:

- documentar que cancelamento sempre abate meta, sem excecao de qualidade;
- manter excecao de qualidade apenas para devolucao;
- acoplar `cancelar_com_pedido(...)` a `registrar_com_meta_cancelamento_pedido(...)` quando existir `venda_aberta`;
- acoplar `registrar_com_pedido_estorno_pos_pagamento(...)` a `registrar_com_meta_devolucao_nf(...)`;
- ajustar `registrar_com_meta_devolucao_nf(...)` para registrar `itens_sem_venda_aberta` em vez de abortar quando o item devolvido nao possui historico de meta.

## Decisoes confirmadas

- A chamada de meta mora dentro da RPC que gera o fato original, na mesma transacao.
- `cancelar_com_pedido(...)` continua com assinatura compativel. O texto livre `p_motivo` e gravado como detalhe, e o ledger de metas recebe `motivo_codigo = cancelamento_pedido`.
- A operacao exige a uniao de alcadas quando ha movimento de meta a registrar.
- Estorno pos-pagamento passa apenas `nota_fiscal_devolucao_id` para a RPC de metas.
- Dado legado sem `venda_aberta` nao bloqueia NF de devolucao, retorno de PA nem cancelamento.

## Entrega tecnica

Migration: `supabase/migrations/0033_metas_coupling_legacy_skip.sql`.

Entregue:

- nova versao de `cancelar_com_pedido(...)`;
- nova versao de `registrar_com_meta_devolucao_nf(...)`;
- nova versao de `registrar_com_pedido_estorno_pos_pagamento(...)`;
- logs com `correlation_id` compartilhavel entre pedido/fiscal e metas;
- `meta_skip_reason = sem_venda_aberta_no_ledger` para cancelamento sem historico;
- `itens_sem_venda_aberta` no log de devolucao sem historico.

## Validacao executada

Comandos:

```text
python -m unittest tests.test_metas_coupling_legacy_skip_contract
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Validacao em PostgreSQL descartavel:

```text
PG_VALIDATE_0033_WITH_SMOKE_OK
```

Smoke `.tools/smoke_metas_0033.sql` validou:

- cancelamento de pedido com `venda_aberta` gera movimento negativo de meta;
- cancelamento de pedido legado sem `venda_aberta` nao chama meta e registra `meta_skip_reason`;
- estorno pos-pagamento de pedido legado sem `venda_aberta` cria NF de devolucao, movimento PA e log de metas com `itens_sem_venda_aberta`;
- devolucao sem historico nao cria movimento de meta;
- auditoria registra os eventos compostos sem dados reais.
