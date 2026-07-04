# Validacao da migration 0018 - estoque por evento e ajuste por familia

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0018_estoque_rls_adjustment_axes.sql`.

Escopo validado:

- remover policies permissivas `for all using (true)` do dominio de estoque;
- manter leitura de estoque apenas para usuario ativo;
- bloquear escrita direta nas tabelas de estoque para `authenticated`;
- exigir action key em `create_est_lote_pa`;
- criar ajustes manuais por familia: `estoque.mp.adjust`, `estoque.pa.adjust`, `estoque.pi.adjust`;
- registrar auditoria com `before_json` e `after_json` derivados das views de saldo;
- preservar livro de movimentos append-only.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55444`.
- Database: `elite_validate_0018`.
- Cluster temporario: `.tools/pg-validate-0018-20260704-174947`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Prelude Supabase simulado

Foram criados apenas os itens minimos para executar as migrations fora do Supabase local:

- roles `anon`, `authenticated`, `service_role`;
- schema `auth`;
- tabela `auth.users`;
- funcao `auth.uid()` lendo `request.jwt.claim.sub`.

## Resultado das migrations

Todas as migrations `0001` a `0018` aplicaram com sucesso no banco descartavel limpo.

As mensagens de `DROP TRIGGER ... nao existe` e `DROP POLICY ... nao existe` foram esperadas, pois o banco estava limpo.

## Smoke test executado

Arquivo: `.tools/smoke_estoque_0018.sql`.

Casos validados:

1. Criou usuario ativo permitido e usuario ativo com override negado em `estoque.mp.adjust`.
2. Criou cadastros minimos falsos para MP, PA/embalagem e PI.
3. Criou lotes MP, PA e PI.
4. Registrou ajuste manual MP, PA e PI por RPC de familia.
5. Validou auditoria `success` para `estoque.mp.adjust`, `estoque.pa.adjust` e `estoque.pi.adjust`.
6. Tentou ajuste MP com usuario negado.
7. Validou erro `not allowed: estoque.mp.adjust`.
8. Chamou `log_permission_denied(...)` em transacao separada.
9. Validou auditoria `denied` para `estoque.mp.adjust`.
10. Criou pedido e romaneio falsos.
11. Reservou PA por romaneio.
12. Validou que reserva reduziu saldo disponivel, mas nao saldo fisico.
13. Tentou `UPDATE` direto em `est_movimentos_mp`.
14. Validou falha esperada pelo trigger append-only.
15. Tentou `DELETE` direto em `est_movimentos_pa`.
16. Validou falha esperada pelo trigger append-only.
17. Validou que movimento original de PI permaneceu preservado.

Resultado final:

```text
smoke_estoque_0018 ok: MP 3, PA 3, PI 3
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Status | Total |
|---|---:|---:|
| `estoque.mp.adjust` | `denied` | 1 |
| `estoque.mp.adjust` | `success` | 1 |
| `estoque.pa.adjust` | `success` | 1 |
| `estoque.pi.adjust` | `success` | 1 |

Policies finais de estoque no banco descartavel:

| Tabela | Policy | Comando |
|---|---|---|
| `est_lotes_mp` | `authenticated read est_lotes_mp` | `SELECT` |
| `est_lotes_pa` | `authenticated read est_lotes_pa` | `SELECT` |
| `est_lotes_pi` | `authenticated read est_lotes_pi` | `SELECT` |
| `est_movimentos_mp` | `authenticated read est_movimentos_mp` | `SELECT` |
| `est_movimentos_pa` | `authenticated read est_movimentos_pa` | `SELECT` |
| `est_movimentos_pi` | `authenticated read est_movimentos_pi` | `SELECT` |
| `est_reservas_pa` | `authenticated read est_reservas_pa` | `SELECT` |

Funcoes conferidas:

- `create_est_lote_pa`;
- `registrar_est_ajuste_mp`;
- `registrar_est_ajuste_pa`;
- `registrar_est_ajuste_pi`.

## Observacao tecnica

O smoke operacional simulou autenticacao por `auth.uid()` via `request.jwt.claim.sub`. Para evitar dependencia de grants de leitura de outros dominios ainda nao endurecidos, como pedidos/romaneios, parte do smoke rodou com role `postgres`.

Isso nao invalida o teste de alcada do estoque, porque `can_current_user(...)` e `require_current_user_permission(...)` dependem de `auth.uid()` e `user_profiles`, nao do nome da role SQL. A verificacao das policies finais confirmou que o dominio de estoque ficou apenas com policies `SELECT` para `authenticated`.
