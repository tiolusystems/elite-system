# Validacao do piloto RLS - cadastros

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0014_cadastros_rls_pilot.sql` como primeiro piloto de RLS por dominio.

O piloto cobre:

- leitura de cadastros para usuario autenticado com perfil ativo;
- escrita direta revogada nas tabelas de cadastro;
- escrita por RPC `security definer` com `action_key` especifica;
- auditoria de sucesso na propria RPC;
- auditoria de negativa via `log_permission_denied(...)`, chamada pela camada de aplicacao apos capturar `not allowed`.

## Ambiente usado

- Banco PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55433`.
- Cluster temporario em `.tools/pg-cadastros-rls`.
- Database final de smoke: `elite_cadastros_rls_fresh`.
- Sem uso de banco operacional, Supabase cloud, planilhas ou dados reais.

## Prelude Supabase simulado

Foram criados apenas os itens minimos para executar as migrations fora do Supabase local:

- roles `anon`, `authenticated`, `service_role`;
- schema `auth`;
- tabela `auth.users`;
- funcao `auth.uid()` lendo `request.jwt.claim.sub`.

## Resultado das migrations

Todas as migrations `0001` a `0014` aplicaram com sucesso em banco descartavel limpo.

O ajuste da migration `0014` removeu tambem as policies antigas de:

- `cad_areas_comerciais`;
- `cad_pessoa_areas_comerciais`.

Validacao estrutural final:

- policies antigas `authenticated full%` em tabelas `cad_%`: `0`;
- policies de leitura em tabelas de cadastro: `19`;
- RPCs do piloto com `EXECUTE` para `authenticated` e sem `EXECUTE` para `anon`.

## Smoke tests executados

| Caso | Resultado esperado | Resultado obtido |
|---|---|---|
| Usuario ativo com perfil | le cadastros e `can_current_user('cadastros.clientes.create') = true` | OK |
| Usuario ativo criando cliente por RPC | `create_cad_cliente(...)` executa e registra auditoria `success` | OK |
| Usuario ativo tentando insert direto em `cad_clientes` | erro de permissao | OK |
| Usuario ativo com override negado | RPC falha com `not allowed` | OK |
| Negativa capturada pela aplicacao | `log_permission_denied(...)` registra auditoria `denied` | OK |
| Usuario autenticado sem perfil | `can_current_user(...) = false` e nao enxerga linhas | OK |
| Usuario com perfil inativo | `can_current_user(...) = false` e nao enxerga linhas | OK |
| Role `anon` lendo `cad_clientes` | erro de permissao | OK |
| Role `anon` executando `create_cad_cliente(...)` | erro de permissao | OK |

## Evidencia de auditoria no smoke final

Contagem final em `action_logs` para `cadastros.clientes.create`:

| Dominio | Status | Total |
|---|---|---|
| `cadastros` | `success` | 1 |
| `seguranca` | `denied` | 1 |

## Limite registrado

O wrapper `apps/web/lib/supabase/rpc.ts` garante log de negativa apenas para chamadas feitas pela aplicacao Next.js.

Acesso direto ao banco fora desse fluxo, como SQL editor, script administrativo ou integracao futura, nao e coberto por esse wrapper. Esses caminhos devem usar RPCs auditadas ou ter auditoria propria antes de serem considerados operacionais.

## Decisao

Piloto de `cadastros` aprovado como padrao inicial para os proximos dominios:

1. remover escrita direta;
2. manter leitura mais aberta quando necessaria a operacao;
3. expor escrita somente por RPC especifica;
4. validar permissao no inicio da RPC;
5. registrar sucesso em `action_logs`;
6. registrar negativa pela aplicacao via `log_permission_denied(...)`;
7. rodar smoke com usuario ativo, override negado, sem perfil, inativo e anonimo.
