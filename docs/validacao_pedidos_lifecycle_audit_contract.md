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

- alcadas administrativas de `seguranca`;
- visibilidade final por carteira/gerente/area;
- motor completo de campanhas e metas;
- cancelamento com estorno automatico em cadeia.

## Correcao complementar 0029

Migration: `supabase/migrations/0029_pedidos_cancel_commission_guards.sql`.

Escopo:

- devolucao nao gera comissionado, porque criacao de comissao passou a exigir `p_tipo_pedido = 'venda'`;
- `com_pedido_comissionados.status` ganhou `cancelada`, separada de `bloqueada`;
- cancelamento muda comissao `prevista` ou `bloqueada` para `cancelada`;
- comissao `paga` bloqueia cancelamento e direciona para fluxo futuro de estorno pos-pagamento;
- OP ativa vinculada bloqueia cancelamento;
- `pcp_ordens_producao.pedido_id` foi criada para permitir o vinculo pedido -> OP.

Validacao executada:

```text
python -m unittest tests.test_pedidos_cancel_commission_guards
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Status:

- `python -m unittest tests.test_pedidos_cancel_commission_guards`: OK, 7 testes.
- `python -m unittest discover -s tests -p "test*.py"`: OK, 128 testes.
- `pnpm --dir apps/web lint`: OK.
- `pnpm --dir apps/web build`: OK.

Validacao em PostgreSQL descartavel:

```text
PG_VALIDATE_0029_WITH_SMOKE_OK
```

Smoke `.tools/smoke_pedidos_0029.sql` validou:

- pedido `devolucao` nao gera comissionado;
- cancelamento de pedido sem efeitos ativos move comissao `prevista` para `cancelada`;
- pedido com comissao paga nao pode ser cancelado por `cancelar_com_pedido`;
- pedido com OP ativa vinculada nao pode ser cancelado por `cancelar_com_pedido`.
