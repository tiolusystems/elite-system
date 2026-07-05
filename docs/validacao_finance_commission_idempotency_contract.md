# Validacao da migration 0027 - idempotencia de comissoes

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0027_finance_commission_idempotency_contract.sql`.

Escopo validado:

- idempotencia por `alocacao_id + comissionado_id`;
- modelo incremental por evento de recebimento/alocacao;
- bloqueio de reprocessamento da mesma liberacao;
- motivo padronizado para ajuste manual de comissao;
- metadata de falha de negocio na Server Action de recebimento;
- build real do app web com TypeScript.

## Decisao tecnica

Como a migration `0026` ja foi publicada no Git, a correcao foi feita como migration incremental `0027`, em vez de reescrever a migration anterior.

## Regras confirmadas

- A liberação de comissão nao recalcula o total acumulado.
- A base do calculo e o valor daquela alocacao financeira.
- O mesmo evento de alocacao nao pode liberar comissao duas vezes para o mesmo comissionado.
- Dois recebimentos diferentes do mesmo pedido podem liberar fracoes independentes.
- A funcao de liberacao trava `com_recebimentos` e `fin_recebimento_alocacoes`; nao trava o pedido para liberar comissao.
- Ajuste manual aceita somente `correcao_calculo`, `estorno_devolucao`, `acordo_comercial`, `compensacao_futura` ou `outro`.
- `outro` exige `motivo_detalhe`.

## Validacoes executadas

- `python -m unittest tests.test_finance_commission_idempotency_contract`
- `python -m unittest discover -s tests -p 'test*.py'`: 114 testes OK.
- `pnpm --dir apps/web lint`, com `node.exe` do runtime Codex adicionado ao `PATH` da sessao.
- `pnpm --dir apps/web build`, com `node.exe` do runtime Codex adicionado ao `PATH` da sessao.
- migrations `0001` a `0027` aplicadas em PostgreSQL descartavel.
- smoke `.tools/smoke_finance_0027.sql`.

## Ajuste de ferramenta web

O lint nao rodava antes porque `node` nao estava no `PATH` da sessao. Depois de usar o `node.exe` do runtime Codex, o ESLint tambem revelou que a dependencia `eslint = latest` tinha instalado `eslint@10`, incompatível com `eslint-plugin-react@7.37.5`.

Correcao aplicada:

- `eslint` fixado na major `9`;
- `apps/web/eslint.config.mjs` criado com os presets `eslint-config-next/core-web-vitals` e `eslint-config-next/typescript`;
- links internos apontados pelo lint convertidos de `<a href="/">` para `Link`.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55465`.
- Cluster temporario: `.tools/pg-validate-0027-20260705-143850`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Smoke esperado

O smoke operacional da `0027` deve cobrir:

1. um recebimento com alocacoes gerando comissao incremental;
2. segunda chamada de liberacao para o mesmo `recebimento_id` falhando com `comissao_ja_liberada_para_este_recebimento`;
3. log `failed` simulado para a falha de negocio;
4. segundo recebimento diferente do mesmo pedido liberando nova fracao;
5. ajuste manual com motivo fechado;
6. ajuste manual `outro` sem detalhe falhando.

Resultado final:

```text
PG_VALIDATE_0027_WITH_SMOKE_OK
```
