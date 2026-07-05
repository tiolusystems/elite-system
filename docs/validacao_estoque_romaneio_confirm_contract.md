# Validacao da migration 0022 - confirmacao de romaneio e baixa PA

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0022_estoque_romaneio_confirm_contract.sql`.

Escopo validado:

- criar action key `estoque.pa.issue.romaneio`;
- exigir `romaneios.confirm` para a decisao operacional de confirmar romaneio;
- exigir `estoque.pa.issue.romaneio` para a baixa fisica de PA;
- migrar `confirmar_exp_romaneio` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- capturar `before_json` e `after_json` com romaneio, itens, reservas PA, saldos PA, movimentos de expedicao e movimentos de estoque;
- provar que a confirmacao muda reserva de `ativa` para `baixada` e gera `saida_romaneio`;
- provar que usuario sem alcada de baixa PA nao altera romaneio, reserva nem estoque.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55448`.
- Database: `elite_validate_0022`.
- Cluster temporario: `.tools/pg-validate-0022-20260705-075717`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0022` aplicaram com sucesso no banco descartavel limpo.

As mensagens esperadas de objetos inexistentes em migrations anteriores continuam sendo tratadas como comportamento normal de banco limpo.

Funcao conferida no banco:

| Funcao | `begin_audited_rpc` | `log_audited_rpc_change` | Snapshot de reservas | Snapshot de saldos |
|---|---:|---:|---:|---:|
| `confirmar_exp_romaneio` | sim | sim | sim | sim |

## Smoke test executado

Arquivo: `.tools/smoke_estoque_0022.sql`.

Casos validados:

1. Criou usuario ativo permitido e usuario ativo com override negado para `estoque.pa.issue.romaneio`.
2. Criou cadastros minimos falsos para cliente, vendedor, produto, embalagem e produto+embalagem.
3. Criou lote PA com saldo fisico 10.
4. Criou pedido aberto com quantidade 10.
5. Criou romaneio parcial com quantidade 4.
6. Reservou 4 unidades do lote PA.
7. Confirmou romaneio.
8. Validou `before_json.reservas_pa` com reserva `ativa`.
9. Validou `after_json.reservas_pa` com reserva `baixada`.
10. Validou saldo antes: fisico 10, reservado 4, disponivel 6.
11. Validou saldo depois: fisico 6, reservado 0, disponivel 6.
12. Validou log `success` com `action_key = estoque.pa.issue.romaneio`, `axis = movement_event`, `event = issue` e `business_action_key = romaneios.confirm`.
13. Criou segundo romaneio com reserva ativa.
14. Tentou confirmar com usuario sem `estoque.pa.issue.romaneio`.
15. Validou erro `not allowed: estoque.pa.issue.romaneio`.
16. Validou que a negativa nao criou movimento PA.
17. Validou que a negativa nao confirmou romaneio.
18. Validou que a negativa manteve reserva ativa.
19. Registrou log `denied` em transacao controlada pelo smoke.

Resultado final:

```text
smoke_estoque_0022 ok: confirmado 1, negado 2
```

## Evidencia de auditoria

Consulta resumida em `action_logs`:

| Action key | Action | Status | Axis | Event | Business action key | Total |
|---|---|---|---|---|---|---:|
| `estoque.pa.issue.romaneio` | `seguranca.permissao_negada` | `denied` |  |  |  | 1 |
| `estoque.pa.issue.romaneio` | `estoque.pa_romaneio_confirmado` | `success` | `movement_event` | `issue` | `romaneios.confirm` | 1 |

## Resultado da auditoria de confirmacao

`confirmar_exp_romaneio` deixou de ser divida tecnica no teste estatico de movimentos de estoque.

O contrato novo registra a parte que faltava para auditoria operacional: a reserva PA aparece ativa no `before_json`, baixada no `after_json`, e o saldo fisico cai enquanto o saldo disponivel permanece coerente.

## Revisao posterior

A migration `0023_importacao_xml_mp_lot_contract.sql` adicionou um comentario SQL em `confirmar_exp_romaneio(bigint, text)` documentando a invariante de concorrencia: reservas PA de um item de romaneio devem ser alteradas apenas por RPCs que travam antes a linha pai em `exp_romaneio_itens`.

O status final do pedido segue como melhoria opcional de metadata. O RPC atualiza `com_pedidos.status` quando o pedido fica completo, mas o snapshot principal continua focado em romaneio, reservas e saldos. Na proxima alteracao funcional desse RPC, adicionar `pedido_status_after` em `metadata_json` se a auditoria precisar identificar diretamente qual confirmacao fechou o pedido.

## Proximo bloco recomendado

`finalizar_pcp_op` foi migrado na `0024_pcp_finish_audited_contract.sql`, com `correlation_id` e action keys granulares para consumo/entrada por familia.
