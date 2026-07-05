# Validacao da migration 0021 - entradas de lote no contrato RPC auditado

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0021_estoque_lot_entry_rpc_contract.sql`.

Escopo validado:

- migrar `create_est_lote_pa_auto` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- migrar `create_est_lote_mp` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- migrar `create_est_lote_pi` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- manter saldo como estado derivado das views `est_lotes_*_saldos`;
- registrar `movement_event` com `event = entry`;
- registrar `movimento_id`, `tipo_movimento`, `quantidade` e `origem_ref` em `metadata_json`;
- bloquear usuario sem alcada antes de inserir lote/movimento.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55447`.
- Database: `elite_validate_0021`.
- Cluster temporario: `.tools/pg-validate-0021-20260705-074849`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0021` aplicaram com sucesso no banco descartavel limpo.

As mensagens esperadas de objetos inexistentes em migrations anteriores continuam sendo tratadas como comportamento normal de banco limpo.

Funcoes conferidas no banco:

| Funcao | `begin_audited_rpc` | `log_audited_rpc_change` |
|---|---:|---:|
| `create_est_lote_mp` | sim | sim |
| `create_est_lote_pa_auto` | sim | sim |
| `create_est_lote_pi` | sim | sim |

## Smoke test executado

Arquivo: `.tools/smoke_estoque_0021.sql`.

Casos validados:

1. Criou usuario ativo permitido e usuario ativo com override negado para `estoque.mp.lots.create`.
2. Criou cadastros minimos falsos para MP, produto, embalagem e produto+embalagem.
3. Criou lote PA via `create_est_lote_pa_auto`.
4. Criou lote MP via `create_est_lote_mp`.
5. Criou lote PI via `create_est_lote_pi`.
6. Validou saldo fisico PA = 11.
7. Validou saldo fisico MP = 22.
8. Validou saldo fisico PI = 33.
9. Validou tres logs `success` com `axis = movement_event` e `event = entry`.
10. Tentou criar lote MP com usuario negado.
11. Validou erro `not allowed: estoque.mp.lots.create`.
12. Validou que a negativa nao criou novo lote MP.
13. Registrou e conferiu log `denied` em transacao controlada pelo smoke.

Resultado final:

```text
smoke_estoque_0021 ok: PA 1, MP 1, PI 1
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Action | Status | Axis | Event | Total |
|---|---|---|---|---|---:|
| `estoque.mp.lots.create` | `seguranca.permissao_negada` | `denied` |  |  | 1 |
| `estoque.mp.lots.create` | `estoque.mp_lote_created` | `success` | `movement_event` | `entry` | 1 |
| `estoque.pa.lots.create` | `estoque.pa_lote_auto_created` | `success` | `movement_event` | `entry` | 1 |
| `estoque.pi.lots.create` | `estoque.pi_lote_created` | `success` | `movement_event` | `entry` | 1 |

## Teste estatico novo

Foi adicionado teste estatico em `tests/test_estoque_event_ledger_contract.py`:

- toda funcao SQL que insere em `est_movimentos_mp`, `est_movimentos_pa` ou `est_movimentos_pi` deve chamar `begin_audited_rpc(...)`;
- excecoes antigas precisam ficar declaradas em lista explicita de divida tecnica;
- qualquer nova RPC de movimento que nascer sem helper falha no teste.

Dividas ainda declaradas:

- pre-helper ja endurecidas: `create_est_lote_pa`, `registrar_est_ajuste_mp`, `registrar_est_ajuste_pa`, `registrar_est_ajuste_pi`, `estornar_exp_romaneio`;
- pendentes de migracao: `confirmar_exp_romaneio`, `finalizar_pcp_op`.

## Proximo bloco recomendado

1. Migrar `confirmar_exp_romaneio`, fechando a simetria com `estornar_exp_romaneio`.
2. Migrar geracao de lote MP por XML/NF para contrato auditado proprio, mesmo que a entrada de lote ja use `create_est_lote_mp`.
3. Migrar `finalizar_pcp_op` por ultimo, pois e multi-tabela, multi-familia e mistura consumo de MP/PA/PI com entrada de PA/PI.
