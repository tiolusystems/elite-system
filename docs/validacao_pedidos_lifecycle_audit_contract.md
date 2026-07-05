# Validacao da migration 0028 - pedidos lifecycle audit contract

Data da validacao: 2026-07-05

## Objetivo

Validar o endurecimento do dominio `pedidos`.

Escopo:

- bloquear escrita direta em `com_pedidos`, itens, comissionados, decisoes de credito e sequencia;
- manter leitura autenticada para a tela operacional;
- substituir auditoria manual de pedido por `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`;
- separar criacao por `pedidos.create.own` e `pedidos.create.any`;
- governar credito e cancelamento por `axis = status_transition`;
- criar tabela de transicoes permitidas;
- revogar execucao direta de `next_com_pedido_sequencia(...)`.

## Decisoes confirmadas

- Pedido permanece entidade operacional, nao ledger append-only.
- Mudanca de status relevante passa por RPC auditada.
- Cancelamento de pedido nao tenta desfazer romaneio, NF ou recebimento ativo.
- Fluxos com efeito fisico, fiscal ou financeiro devem usar estorno do dominio responsavel.
- A RPC antiga `create_com_pedido_rascunho(...)` foi preservada como wrapper para compatibilidade.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55857`.
- Cluster temporario: `.tools/pg-validate-0028-20260705-150148`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Resultado das migrations

Todas as migrations `0001` a `0028` aplicaram com sucesso no banco descartavel limpo.

As mensagens de `DROP TRIGGER ... nao existe` e `DROP POLICY ... nao existe` foram esperadas, pois o banco estava limpo.

## Smoke test executado

Arquivo: `.tools/smoke_pedidos_0028.sql`.

Casos validados:

1. Criou usuario ativo permitido.
2. Criou cliente, vendedor vinculado ao usuario, produto, embalagem e item vendavel falsos.
3. Criou pedido `own` via `create_com_pedido_operacional(...)`.
4. Validou log `pedidos.create.own` com `permission_context.scope = own`.
5. Registrou revisao de credito `liberado`.
6. Validou status do pedido como `open` e log `pedidos.credit.review` com `axis = status_transition`.
7. Criou e cancelou pedido sem efeito ativo.
8. Validou status `cancelled` e log `pedidos.cancel`.
9. Criou pedido `any` sem vendedor e validou log `pedidos.create.any`.
10. Tentou cancelar pedido com romaneio ativo e recebeu erro esperado.
11. Registrou falha auditada `pedidos.cancel_failed` para o bloqueio de estado.
12. Validou que `authenticated` nao tem `INSERT/UPDATE/DELETE` direto em `com_pedidos`.
13. Validou que `authenticated` nao executa `next_com_pedido_sequencia(...)` diretamente.

Resultado final:

```text
PG_VALIDATE_0028_WITH_SMOKE_OK
```

## Testes automatizados

Comandos:

```text
python -m unittest tests.test_pedidos_lifecycle_audit_contract
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Status inicial:

- `python -m unittest tests.test_pedidos_lifecycle_audit_contract`: OK.
- `python -m unittest discover -s tests -p "test*.py"`: OK, 121 testes.
- `pnpm --dir apps/web lint`: OK.
- `pnpm --dir apps/web build`: OK.

## Fora desta etapa

- alçadas administrativas de `seguranca`;
- visibilidade final por carteira/gerente/area;
- motor completo de campanhas e metas;
- cancelamento com estorno automatico em cadeia.
