# Validacao da migration 0023 - XML/NF de MP e lote de estoque

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0023_importacao_xml_mp_lot_contract.sql`.

Escopo validado:

- documentar no banco a invariante de concorrencia usada por `confirmar_exp_romaneio`;
- migrar `gerar_lote_mp_from_imp_nfe_item` para `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- manter a entrada fisica de MP dentro de `create_est_lote_mp`, com auditoria propria de `estoque.mp.lots.create`;
- capturar `before_json` e `after_json` com NFe, item XML, resolucao, vinculo item-lote, lote MP e saldo MP;
- provar que usuario sem `estoque.mp.lots.create` nao gera lote, nao cria vinculo e nao muda status do item XML.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55449`.
- Database: `elite_validate_0023`.
- Cluster temporario: `.tools/pg-validate-0023-20260705-081801`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0023` aplicaram com sucesso no banco descartavel limpo.

As mensagens esperadas de objetos inexistentes em migrations anteriores continuam sendo tratadas como comportamento normal de banco limpo.

Funcao conferida:

| Funcao | `begin_audited_rpc` | `log_audited_rpc_change` | Snapshot composto | Chama estoque |
|---|---:|---:|---:|---:|
| `gerar_lote_mp_from_imp_nfe_item` | sim | sim | sim | `create_est_lote_mp` |

## Decisao de composicao

Este fluxo tem duas camadas de autorizacao e auditoria:

| Camada | Action key | Resultado esperado |
|---|---|---|
| Importacao XML | `importacao.nfe_xml.generate_mp_lot` | Autoriza transformar item XML conferido em lote MP. |
| Estoque MP | `estoque.mp.lots.create` | Autoriza criar lote MP fisico e movimento de entrada. |

Essa dupla autorizacao e intencional. O usuario precisa das duas alcadas para concluir a operacao.

Os dois logs sao correlacionaveis:

- log externo: `metadata_json.lote_mp_id` e `metadata_json.origem_ref`;
- log interno de estoque: `entity_id = lote_mp_id` e `metadata_json.origem_ref`.

Para novos fluxos compostos, principalmente `finalizar_pcp_op`, a regra passa a exigir `correlation_id` comum em todos os logs da mesma operacao.

## Smoke test executado

Arquivo: `.tools/smoke_importacao_xml_0023.sql`.

Casos validados:

1. Criou usuario ativo permitido e usuario ativo com override negado para `estoque.mp.lots.create`.
2. Criou materia-prima falsa.
3. Staged NFe XML falsa e item XML falso.
4. Confirmou match do item XML com fator de conversao `50`.
5. Gerou lote MP a partir do item XML conferido.
6. Validou `before_json.item.status = match_confirmado`.
7. Validou `after_json.item.status = lote_gerado`.
8. Validou vinculo `imp_nfe_item_lotes_mp` apontando para o lote criado.
9. Validou saldo fisico MP `100`.
10. Validou log `success` da importacao com `axis = movement_event`, `event = entry` e `stock_action_key = estoque.mp.lots.create`.
11. Validou log `success` aninhado de `estoque.mp.lots.create`.
12. Tentou gerar lote MP com usuario sem `estoque.mp.lots.create`.
13. Validou erro `not allowed: estoque.mp.lots.create`.
14. Validou que a negativa nao criou vinculo item-lote.
15. Validou que a negativa manteve o item XML em `match_confirmado`.
16. Registrou log `denied` em transacao controlada pelo smoke.

Resultado final:

```text
smoke_importacao_xml_0023 ok: item 3, lote 2, denied item 4
```

## Evidencia de auditoria

Consulta resumida em `action_logs` apos duas execucoes validas do smoke:

| Action key | Action | Status | Axis | Event | Stock action key | Total |
|---|---|---|---|---|---|---:|
| `estoque.mp.lots.create` | `seguranca.permissao_negada` | `denied` |  |  |  | 2 |
| `estoque.mp.lots.create` | `estoque.mp_lote_created` | `success` | `movement_event` | `entry` |  | 2 |
| `importacao.nfe_xml.generate_mp_lot` | `importacao.nfe_xml_item_lote_mp_generated` | `success` | `movement_event` | `entry` | `estoque.mp.lots.create` | 2 |

Consulta de saldo e status apos duas execucoes validas:

| Item | Status | Quantidade convertida | Lote MP |
|---:|---|---:|---:|
| 1 | `lote_gerado` | 100 | 1 |
| 2 | `match_confirmado` | 50 |  |
| 3 | `lote_gerado` | 100 | 2 |
| 4 | `match_confirmado` | 50 |  |

Saldo fisico total dos lotes gerados pelo smoke: `200`.

## Observacoes da revisao

A `0023` adiciona comentario SQL em `confirmar_exp_romaneio(bigint, text)` documentando a invariante: reservas PA de um item de romaneio devem ser alteradas apenas por RPCs que travam antes a linha pai em `exp_romaneio_itens`. Essa regra explica por que a soma de reservas pode ser calculada antes do loop que trava cada reserva ativa.

O status final do pedido em `confirmar_exp_romaneio` segue como melhoria opcional de metadata. O RPC ja atualiza `com_pedidos.status` quando o pedido fica completo, mas o snapshot principal continua focado em romaneio, reservas e saldos. Na proxima alteracao funcional desse RPC, adicionar `pedido_status_after` em `metadata_json` se a auditoria precisar identificar diretamente qual confirmacao fechou o pedido.

## Proximo bloco recomendado

Migrar `finalizar_pcp_op` por ultimo, pois e multi-tabela, multi-familia e mistura consumo de MP/PA/PI com entrada de PA/PI.
