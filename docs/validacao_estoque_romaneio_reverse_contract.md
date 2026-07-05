# Validacao da migration 0019 - estorno de romaneio e estoque PA

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0019_estoque_romaneio_reverse_contract.sql`.

Escopo validado:

- criar action key `estoque.pa.reverse.romaneio`;
- exigir `romaneios.cancel` para cancelar romaneio em rascunho/separacao;
- exigir `romaneios.cancel` e `estoque.pa.reverse.romaneio` para estornar romaneio confirmado;
- substituir `log_action(...)` antigo por `log_audit_event(...)` em cancelamento e estorno;
- registrar `before_json` e `after_json` com snapshot de romaneio, reservas PA e saldos PA derivados;
- gerar reversao por novo movimento `estorno_saida`, sem editar movimento original.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55445`.
- Database: `elite_validate_0019`.
- Cluster temporario: `.tools/pg-validate-0019-20260704-180304`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0019` aplicaram com sucesso no banco descartavel limpo.

As mensagens de `DROP TRIGGER ... nao existe` e `DROP POLICY ... nao existe` foram esperadas, pois o banco estava limpo.

## Smoke test executado

Arquivo: `.tools/smoke_estoque_0019.sql`.

Casos validados:

1. Criou usuario ativo falso.
2. Criou cadastros minimos falsos para cliente, vendedor, produto, embalagem e produto+embalagem.
3. Criou lote PA com saldo fisico 10.
4. Criou pedido e romaneio.
5. Reservou PA.
6. Confirmou romaneio e validou saldo PA 4.
7. Estornou romaneio confirmado.
8. Validou saldo PA restaurado para 10.
9. Validou log `success` com `action_key = estoque.pa.reverse.romaneio`.
10. Validou `before_json` e `after_json` presentes.
11. Validou `permission_context.business_action_key = romaneios.cancel`.
12. Criou outro romaneio em rascunho, reservou PA e cancelou.
13. Validou log `success` com `action_key = romaneios.cancel`.

Resultado final:

```text
smoke_estoque_0019 ok: romaneio 1, cancelado 2
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Action | Status | Total |
|---|---|---:|---:|
| `estoque.pa.reverse.romaneio` | `estoque.pa_romaneio_estornado` | `success` | 1 |
| `romaneios.cancel` | `expedicao.romaneio_cancelado` | `success` | 1 |

Action key criada:

| Action key | Default allowed |
|---|---:|
| `estoque.pa.reverse.romaneio` | `true` |

Funcoes conferidas:

- `cancelar_exp_romaneio`;
- `estornar_exp_romaneio`.

## Resultado da auditoria de eventos de estoque

Com a `0019`, o ponto critico encontrado na auditoria do estoque foi corrigido: estorno de romaneio confirmado nao fica mais como funcao antiga sem guard central.

Ainda nao considero o dominio de estoque totalmente fechado.

As entradas automaticas `create_est_lote_pa_auto`, `create_est_lote_mp` e `create_est_lote_pi` foram migradas na `0021_estoque_lot_entry_rpc_contract.sql`.

Proximo bloco recomendado:

1. auditar baixa PA em `confirmar_exp_romaneio` para migrar o log final de `log_action(...)` para `log_audited_rpc_change(...)` com action key e snapshots derivados;
2. auditar geracao de lote MP por XML/NF com contrato proprio, alem da chamada a `create_est_lote_mp`;
3. auditar consumo/transformacao dentro de `finalizar_pcp_op`.

Esses pontos ja passam por RPC `security definer` e permissoes de negocio em parte dos casos, mas ainda misturam o contrato antigo de auditoria em alguns fluxos. Por isso, devem ser tratados antes de marcar `estoque` como concluido.
