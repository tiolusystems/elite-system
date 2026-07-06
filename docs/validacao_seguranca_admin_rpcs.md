# Validacao da migration 0035 - RPCs administrativas de seguranca

Data da validacao: 2026-07-06

## Objetivo

Validar o primeiro endurecimento do dominio `seguranca`: perfis e overrides de permissao passam a ter RPCs auditadas, sem alterar login/senha do Supabase Auth.

## Escopo validado

- Escrita direta de `authenticated` revogada em `user_profiles`, `permission_actions` e `user_permission_overrides`.
- `upsert_security_user_profile(...)` exige usuario preexistente em `auth.users`.
- `set_security_permission_override(...)` grava override auditado.
- `clear_security_permission_override(...)` remove override auditado.
- Perfis `is_system_actor` nao podem ser alterados por RPC operacional de usuario/permissao.
- `can_current_user(...)` respeita override negado e volta ao default apos limpar o override.

## Validacao executada

Comandos:

```text
python -m unittest tests.test_seguranca_admin_rpcs_contract
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Validacao em PostgreSQL descartavel:

```text
PG_VALIDATE_0035_WITH_SMOKE_OK
```

Smoke `.tools/smoke_seguranca_0035.sql` validou:

- migration aplicada do zero ate `0035`;
- admin ativo cria/atualiza perfil operacional por RPC;
- perfil exige usuario em `auth.users`;
- override negado altera o resultado de `can_current_user(...)`;
- limpeza do override restaura o default;
- logs `security.manage_users` e `security.manage_permissions` sao gerados;
- ator de sistema `Migracao Historica` e bloqueado pelas RPCs operacionais.

## Decisoes para revisao

- Como o usuario real sera criado no Supabase Auth: painel, script administrativo ou tela futura.
- Se os papeis atuais sao suficientes para a Elite.
- Quando iniciar o flip gradual de `default_allowed` por dominio.
