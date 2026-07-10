# Validacao da operacao incremental de modulos

Data: 2026-07-10

## Escopo

- migration `0041_module_rollout_runtime.sql`;
- gate central de action keys;
- grafo de dependencias;
- ledgers append-only de ambiente e rollout;
- proxy de rotas Next.js;
- tela `/modulos`;
- liveness `/health` e `/api/health`.

## Banco descartavel

Foi criado um PostgreSQL novo e descartavel. A cadeia `0001` a `0041`, seguida de `supabase/seed.sql`, foi aplicada do zero.

Resultado estrutural:

| Medida | Resultado |
|---|---:|
| Tabelas publicas | 82 |
| Tabelas sem PK | 0 |
| Foreign keys | 292 |
| Constraints nao validadas | 0 |
| Policies de escrita | 0 |
| Action keys sem modulo/acesso | 0 |
| Modulos catalogados | 13 |
| Rotas registradas | 12 |
| Dependencias obrigatorias | 36 |
| Ambiente inicial | `unconfigured` |

Marcadores aprovados:

- `PG_MODULE_ROLLOUT_RUNTIME_OK`
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`
- `ZERO_GRANT_SWEEP_OK: targets=58, denied=58`

## Cenarios do smoke 0041

- `core` acessivel no bootstrap;
- modulo operacional bloqueado em `unconfigured`;
- troca auditada para banco de teste;
- leitura de estoque permitida em `read_only`;
- escrita de estoque negada em `read_only`;
- suspensao de estoque bloqueando PCP por dependencia;
- promocao de PCP recusada enquanto estoque esta indisponivel;
- escrita em producao recusada para `technical_validation`;
- `UPDATE` e `TRUNCATE` dos ledgers recusados;
- ciclo artificial de dependencia recusado;
- mudancas administrativas registradas em `action_logs`.

## Aplicacao

- `pnpm lint`: aprovado;
- `pnpm build`: aprovado;
- Next.js 16.2.10 compilou `/modulos`, `/modulo-indisponivel`, `/health` e `/api/health`;
- TypeScript: aprovado;
- Python: 192 testes aprovados.

## Limites

- validacao executada somente em banco descartavel;
- nenhuma migration foi aplicada em Supabase cloud real;
- nenhum dado comercial foi usado;
- homologacao visual autenticada depende do projeto Supabase de teste configurado.
