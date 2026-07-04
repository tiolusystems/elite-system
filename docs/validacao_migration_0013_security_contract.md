# Validacao da migration 0013 - contrato de seguranca e auditoria

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0013_security_guard_audit_contract.sql` antes de iniciar RLS por dominio.

## Ambiente usado

- Banco descartavel PostgreSQL 18 local.
- Porta local: `127.0.0.1:55432`.
- Cluster temporario em `.tools/pg-audit-contract`.
- Sem uso de banco operacional, Supabase cloud, planilhas ou dados reais.
- Supabase CLI local nao foi usado para aplicar o banco porque o Docker local nao estava expondo o pipe `docker_engine`.

## Prelude Supabase simulado

Foram criados apenas os itens minimos para executar as migrations fora do Supabase local:

- roles `anon`, `authenticated`, `service_role`;
- schema `auth`;
- tabela `auth.users`;
- funcao `auth.uid()` lendo `request.jwt.claim.sub`.

## Resultado das migrations

Todas as migrations `0001` a `0013` aplicaram com sucesso no banco descartavel.

As mensagens de `DROP TRIGGER ... nao existe` e `DROP POLICY ... nao existe` foram esperadas, pois o banco estava limpo.

## Smoke tests executados

| Caso | Resultado esperado | Resultado obtido |
|---|---|---|
| Usuario autenticado com perfil ativo | `can_current_user('cadastros.manage') = true` | OK |
| Usuario ativo com action desconhecida | `can_current_user('__unknown__') = false` | OK |
| Usuario ativo criando cliente por RPC existente | `create_cad_cliente(...)` executa e registra log | OK |
| Usuario autenticado sem `user_profiles` | permissao negada | OK |
| Usuario com perfil inativo | permissao negada | OK |
| Role `authenticated` sem claim `auth.uid()` | permissao negada | OK |
| Role `anon` | sem permissao de executar `can_current_user` | OK |

## Achado corrigido

O primeiro smoke mostrou que tentar registrar permissao negada dentro de `require_current_user_permission` antes de `raise exception` nao funciona como auditoria persistente.

Motivo: no PostgreSQL, o `insert` em `action_logs` e o `raise exception` ficam na mesma transacao. Quando a excecao sobe, o insert tambem e revertido.

Correcao aplicada:

- `require_current_user_permission(...)` apenas bloqueia com excecao.
- `log_permission_denied(...)` registra a negativa em uma transacao separada, quando a aplicacao captura o erro.
- `docs/matriz_seguranca_alcadas.md` foi atualizado para explicitar esse contrato.

## Evidencia de auditoria apos correcao

Contagem final em `action_logs` no smoke:

| Dominio | Status | Total |
|---|---|---|
| `null` | `success` | 1 |
| `seguranca` | `denied` | 4 |

Os quatro logs `denied` foram gerados por `log_permission_denied(...)`, nao por insert antes de exception.

## Decisao para proximas etapas

Nao iniciar RLS de dominio sem antes:

1. manter este padrao: RPC bloqueia, aplicacao registra negativa em transacao separada;
2. usar `cadastros` como piloto;
3. validar cada dominio com smoke de usuario ativo, sem perfil/inativo e anonimo.
