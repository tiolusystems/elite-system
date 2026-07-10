# Validacao da operacao local e primeiro administrador

Data: 2026-07-10

## Escopo

- migration `0042_first_admin_operational_bootstrap.sql`;
- indices das FKs do runtime modular;
- bootstrap unico do primeiro administrador;
- scripts de inicio, parada e bootstrap local;
- documentacao e CI do fluxo operacional.

## Validacoes aprovadas

- `pnpm lint`: aprovado depois da conclusao dos scripts;
- `pnpm build`: aprovado com Next.js 16.2.10 e TypeScript;
- parser PowerShell: `start-local.ps1`, `stop-local.ps1` e `bootstrap-local-admin.ps1` sem erro sintatico;
- smoke `PG_MODULE_ROLLOUT_RUNTIME_OK` aprovado;
- smoke isolado `PG_FIRST_ADMIN_OPERATIONAL_BOOTSTRAP_OK` aprovado;
- marcador `PG_0042_REUSED_DB_ISOLATED_SMOKE_OK` aprovado.
- cadeia limpa `0001` a `0043` reconstruida com seed no Supabase local descartavel;
- `/api/health` respondeu `status=ok` e `backendConfigured=true`;
- login real do primeiro administrador aceito e redirecionado para a troca obrigatoria de senha;
- ambiente autoritativo ativado como `test` pela RPC auditada;
- 13 modulos retornaram `available=true` no catalogo local, sendo os de negocio ainda classificados como `technical_validation`.

O smoke 0042 confirmou:

- `anon` e `authenticated` sem `EXECUTE`;
- chamada sem claim `service_role` negada antes de ler perfis;
- primeiro perfil humano criado como `admin`, `active` e nao-sistema;
- auditoria sem email, senha ou outra credencial;
- segunda inicializacao recusada;
- nenhum perfil gravado pela segunda tentativa;
- tres indices novos cobrindo FKs dos ledgers da migration 0041.

## Suite Python

A suite completa passou depois da edicao deste bloco:

```text
Ran 201 tests
OK
```

O teste `test_operational_bootstrap_contract.py` e o novo contrato `test_schema_lint_hardening_contract.py` fazem parte do discovery e do CI.

## Supabase local

O container antigo autorizado nao existia mais e nenhum volume operacional foi encontrado. Nada foi removido. O banco foi reconstruido do zero pelo fluxo oficial `supabase db reset --local`.

No Windows, o runtime local usa o perfil minimo necessario: PostgreSQL, Auth, PostgREST e gateway. Os servicos opcionais que falharam no health-check (Studio, Storage, Realtime, Analytics, Edge Runtime e Mailpit) ficam excluidos pelo script local, sem alterar o stack completo do CI.

## Reconstrucao limpa concluida

A cadeia exata `0001` a `0043` foi reconstruida em Supabase descartavel limpo, com seed e sem reaproveitar estado anterior.

Marcadores aprovados depois da reconstrucao:

- `PG_FULL_CHAIN_0001_0043_SMOKES_OK`;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_MODULE_ROLLOUT_RUNTIME_OK`;
- `PG_FIRST_ADMIN_OPERATIONAL_BOOTSTRAP_OK`;
- `PG_SCHEMA_LINT_HARDENING_OK`;
- `supabase db lint --local --level warning` sem resultados.

A troca da senha temporaria e deliberadamente uma acao do administrador humano. Ate ela ser concluida, o guard redireciona a sessao autenticada para `/login/trocar-senha` e nao libera navegacao operacional.

## Dados e segredos

Nenhum dado comercial, workbook, dump, chave, email real ou senha foi adicionado ao Git. `.env.local`, logs, PIDs e runtimes continuam ignorados.
