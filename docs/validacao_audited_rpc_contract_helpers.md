# Validacao da migration 0020 - helpers de contrato RPC auditada

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0020_audited_rpc_contract_helpers.sql`.

Escopo validado:

- criar enum fechado `audit_axis`;
- normalizar o texto legado `event_movement` para `movement_event`;
- criar `begin_audited_rpc(...)` para validar action key, dominio, entidade, eixo e permissao no inicio da RPC;
- criar `log_audited_rpc_change(...)` para validar contexto de permissao antes de gravar `log_audit_event(...)`;
- impedir contexto com chaves reservadas montadas manualmente;
- manter os helpers sem grant publico, para uso por RPCs `security definer`.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55446`.
- Database: `elite_validate_0020`.
- Cluster temporario: `.tools/pg-validate-0020-20260705-073240`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0020` aplicaram com sucesso no banco descartavel limpo.

As mensagens esperadas de objetos inexistentes em migrations anteriores continuam sendo tratadas como comportamento normal de banco limpo.

Objetos conferidos:

| Objeto | Resultado |
|---|---|
| `audit_axis` | criado |
| `normalize_audit_axis` | criada |
| `begin_audited_rpc` | criada |
| `log_audited_rpc_change` | criada |

## Smoke test executado

Arquivo: `.tools/smoke_audited_rpc_0020.sql`.

Casos validados:

1. Criou usuario ativo falso.
2. Usou action key existente `audit.view`.
3. Chamou `begin_audited_rpc(...)` com eixo legado `event_movement`.
4. Validou normalizacao para `movement_event`.
5. Chamou `log_audited_rpc_change(...)`.
6. Validou log `success` em `action_logs`.
7. Validou erro esperado quando contexto tenta informar chave reservada.
8. Validou erro esperado quando `permission_context.alcada_usada` nao bate com `p_action_key`.

Resultado final:

```text
smoke_audited_rpc_0020 ok: log 1
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Action | Status | Axis | Total |
|---|---|---|---|---:|
| `audit.view` | `auditoria.smoke_contract` | `success` | `movement_event` | 1 |

## Decisao tecnica

Nao foi criado helper generico que executa SQL dinamico. A mudanca de negocio continua explicita dentro de cada RPC, e os helpers centralizam apenas:

- validacao de permissao;
- metadados obrigatorios do contrato;
- normalizacao de eixo;
- delegacao padronizada para `log_audit_event(...)`.

Isso evita repetir o erro encontrado em `create_est_lote_pa` e `estornar_exp_romaneio`, sem transformar a regra de negocio em caixa-preta dificil de auditar.

## Proximo uso recomendado

Migrar os RPCs pendentes do dominio de estoque para o novo template:

- consumo e transformacao em `finalizar_pcp_op`;

Os tres criadores de lote `create_est_lote_pa_auto`, `create_est_lote_mp` e `create_est_lote_pi` foram migrados na `0021_estoque_lot_entry_rpc_contract.sql`.

A baixa PA em `confirmar_exp_romaneio` foi migrada na `0022_estoque_romaneio_confirm_contract.sql`.

A geracao de lote MP por XML/NF foi migrada na `0023_importacao_xml_mp_lot_contract.sql`.
