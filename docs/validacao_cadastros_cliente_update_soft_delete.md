# Validacao de edicao e soft-delete de cliente

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0015_cadastros_cliente_update_soft_delete.sql`, que estende o piloto de `cadastros` para:

- edicao auditada de cliente;
- soft-delete por `status = inactive`;
- alcada por escopo `own` versus `any`;
- `before_json` e `after_json` reais no `action_logs`.

## Ambiente usado

- Banco PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55433`.
- Cluster temporario em `.tools/pg-cadastros-rls`.
- Database final de smoke: `elite_cadastros_scope_fresh`.
- Sem uso de banco operacional, Supabase cloud, planilhas ou dados reais.

## Resultado das migrations

Todas as migrations `0001` a `0015` aplicaram com sucesso em banco descartavel limpo.

## Modelo decidido

Exclusao de cliente nao usa hard-delete.

A RPC `deactivate_cad_cliente(...)` altera `cad_clientes.status` para `inactive`, preservando:

- chave primaria;
- relacionamentos historicos;
- trilha de `created_by` e `updated_by`;
- `before_json` e `after_json` em `action_logs`.

Reativacao futura deve ser outra RPC, com `action_key` propria.

## Alcadas adicionadas

| Action key | Uso |
|---|---|
| `cadastros.clientes.update.own` | editar cliente criado pelo proprio usuario |
| `cadastros.clientes.update.any` | editar qualquer cliente |
| `cadastros.clientes.deactivate.own` | desativar cliente criado pelo proprio usuario |
| `cadastros.clientes.deactivate.any` | desativar qualquer cliente |

As quatro nascem com `default_allowed = true` para respeitar a fase de autonomia inicial, mas ja ficam separadas para retirada futura por checkbox/alcada.

## Smoke tests executados

| Caso | Resultado esperado | Resultado obtido |
|---|---|---|
| Usuario A cria cliente proprio | `created_by = A` e log `cadastros.cliente_created` | OK |
| Usuario B cria outro cliente | `created_by = B` e log `cadastros.cliente_created` | OK |
| Usuario A com `.any` negado edita cliente proprio | RPC usa `cadastros.clientes.update.own` | OK |
| Update direto em `cad_clientes` | erro de permissao | OK |
| Usuario A com `.any` negado tenta editar cliente de B | RPC falha com `not allowed` | OK |
| Negativa de update `.any` | `log_permission_denied(...)` registra `denied` | OK |
| Usuario A desativa cliente proprio | RPC usa `cadastros.clientes.deactivate.own` e muda status para `inactive` | OK |
| Usuario A tenta desativar cliente de B | RPC falha com `not allowed` | OK |
| Negativa de deactivate `.any` | `log_permission_denied(...)` registra `denied` | OK |
| Usuario sem perfil | `can_current_user(...) = false` | OK |
| Usuario inativo | `can_current_user(...) = false` | OK |
| Role `anon` executando update RPC | erro de permissao | OK |

## Evidencia de auditoria no smoke final

Contagem final em `action_logs` para `cadastros.clientes.%`:

| Action | Action key | Status | Total |
|---|---|---|---|
| `cadastros.cliente_created` | `cadastros.clientes.create` | `success` | 2 |
| `cadastros.cliente_updated` | `cadastros.clientes.update.own` | `success` | 1 |
| `cadastros.cliente_deactivated` | `cadastros.clientes.deactivate.own` | `success` | 1 |
| `seguranca.permissao_negada` | `cadastros.clientes.update.any` | `denied` | 1 |
| `seguranca.permissao_negada` | `cadastros.clientes.deactivate.any` | `denied` | 1 |

O smoke tambem conferiu que:

- `before_json.nome` guardou o nome antigo antes da edicao;
- `after_json.nome` guardou o nome novo depois da edicao;
- `before_json.status` estava `active` antes da desativacao;
- `after_json.status` ficou `inactive` depois da desativacao;
- `permission_context.scope` ficou `own` nas operacoes proprias.

## Decisao

O padrao de `cadastros` agora esta validado para criacao, edicao e soft-delete.

Antes de aplicar em `seguranca`, o proximo refinamento recomendado e repetir o mesmo desenho para outros cadastros mestres criticos, comecando por pessoas comerciais e materia-prima.
