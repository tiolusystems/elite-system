# Validacao da migration 0024 - finalizacao auditada de OP

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0024_pcp_finish_audited_contract.sql`.

Escopo validado:

- migrar `finalizar_pcp_op` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- exigir action keys granulares para consumo e entrada de estoque por familia;
- usar `correlation_id = 'pcp_op:' || p_op_id || ':finish'` em todos os logs da finalizacao;
- registrar falha de regra de negocio como `failed`, nao como `denied`;
- trocar a alcada correta de liberacao para `pcp.blocked_lot.release`;
- manter a OP como `completed` e liberar o lote bloqueado, nao a OP;
- atualizar `pcp_op_produtos_gerados.status_lote` ao liberar lote bloqueado.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55450`.
- Database: `elite_validate_0024`.
- Cluster temporario: `.tools/pg-validate-0024-20260705-085733`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0024` aplicaram com sucesso no banco descartavel limpo.

As mensagens esperadas de objetos inexistentes em migrations anteriores continuam sendo tratadas como comportamento normal de banco limpo.

Funcoes conferidas:

| Funcao | Resultado |
|---|---|
| `finalizar_pcp_op` | contrato auditado com `correlation_id` |
| `liberar_pcp_lote_bloqueado` | usa `pcp.blocked_lot.release` |
| `log_rpc_failed` | registra falha de negocio em transacao separada |
| `pcp_op_finish_audit_snapshot` | snapshot composto da OP |

## Smoke test executado

Arquivo: `.tools/smoke_pcp_0024.sql`.

Casos validados:

1. Criou usuario permitido e usuario com override negado para `estoque.pa.entry.op`.
2. Criou cadastros minimos falsos de MP, produto, embalagem e produto+embalagem.
3. Criou lote MP com saldo inicial.
4. Criou formula, OP, reserva MP e iniciou OP.
5. Finalizou OP com CQ aprovado, consumo MP e entrada PA+PI.
6. Validou cinco logs correlacionados: `pcp.op.finish`, `pcp.cq.record`, `estoque.mp.consume.op`, `estoque.pa.entry.op`, `estoque.pi.entry.op`.
7. Validou `origem_ref` dos lotes gerados com `pcp_op:<id>:finish`.
8. Tentou finalizar a mesma OP novamente.
9. Registrou falha de negocio como `status = failed` com `reason = op_already_finished`.
10. Finalizou OP com CQ `reprovado` e validou lote PA `bloqueado`.
11. Liberou lote bloqueado com `pcp.blocked_lot.release`.
12. Validou lote fisico e `pcp_op_produtos_gerados.status_lote` como `disponivel`.
13. Tentou finalizar OP com usuario sem `estoque.pa.entry.op`.
14. Validou `denied` separado para falta de alcada.
15. Validou que a OP negada permaneceu `in_process`, sem CQ, sem produto gerado e sem movimento de estoque.

Resultado final:

```text
smoke_pcp_0024 ok: op 1, retry failed, blocked lot 2, denied op 3
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Action | Status | Correlation | Total |
|---|---|---|---|---:|
| `estoque.mp.consume.op` | `estoque.mp_consumed_by_op` | `success` | `pcp_op:1:finish` | 1 |
| `estoque.mp.consume.op` | `estoque.mp_consumed_by_op` | `success` | `pcp_op:2:finish` | 1 |
| `estoque.pa.entry.op` | `seguranca.permissao_negada` | `denied` |  | 1 |
| `estoque.pa.entry.op` | `estoque.pa_entry_from_op` | `success` | `pcp_op:1:finish` | 1 |
| `estoque.pa.entry.op` | `estoque.pa_entry_from_op` | `success` | `pcp_op:2:finish` | 1 |
| `estoque.pi.entry.op` | `estoque.pi_entry_from_op` | `success` | `pcp_op:1:finish` | 1 |
| `pcp.blocked_lot.release` | `pcp.lote_bloqueado_liberado` | `success` | `pcp_lote:PA:2:release` | 1 |
| `pcp.cq.record` | `pcp.cq_recorded` | `success` | `pcp_op:1:finish` | 1 |
| `pcp.cq.record` | `pcp.cq_recorded` | `success` | `pcp_op:2:finish` | 1 |
| `pcp.op.finish` | `pcp.op_finish_failed` | `failed` | `pcp_op:1:finish` | 1 |
| `pcp.op.finish` | `pcp.op_finished` | `success` | `pcp_op:1:finish` | 1 |
| `pcp.op.finish` | `pcp.op_finished` | `success` | `pcp_op:2:finish` | 1 |

Estado final das OPs no smoke:

| OP | Status | CQ | CQ count | Outputs |
|---:|---|---|---:|---:|
| 1 | `completed` | `aprovado` | 1 | 2 |
| 2 | `completed` | `reprovado` | 1 | 1 |
| 3 | `in_process` |  | 0 | 0 |

Estado de lotes gerados:

| OP | Produto | Status em `pcp_op_produtos_gerados` | Status no lote |
|---:|---|---|---|
| 1 | PA | `disponivel` | `disponivel` |
| 1 | PI | `disponivel` | `disponivel` |
| 2 | PA | `disponivel` | `disponivel` |

## Decisao operacional

Quem libera nao libera a OP. A OP continua `completed`.

Quem libera e o lote fisico bloqueado, com motivo e alcada:

```text
pcp.blocked_lot.release
```

Essa alcada deve ser concedida apenas a CQ, qualidade ou gestor tecnico. A permissao antiga `pcp.experimental.release` fica apenas como legado de nomenclatura.

## Resultado da auditoria de estoque

Com a `0024`, `finalizar_pcp_op` deixa de ser divida tecnica no teste estatico de movimentos de estoque.

O dominio de estoque agora tem contrato auditado nos principais fluxos ja endurecidos:

- ajuste manual por familia;
- criacao de lotes PA/MP/PI;
- estorno de romaneio;
- confirmacao de romaneio;
- geracao de lote MP por XML/NF;
- finalizacao de OP com consumo e entrada por familia.
