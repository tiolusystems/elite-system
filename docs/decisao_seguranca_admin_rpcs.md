# Decisao tecnica - RPCs administrativas de seguranca

Data: 2026-07-06

## Objetivo

Endurecer o dominio `seguranca` sem misturar com tela ou provisionamento de senha.

A migration `0035_security_admin_rpcs.sql` cria RPCs auditadas para administrar:

- perfis em `user_profiles`;
- checks de permissao em `user_permission_overrides`.

## Decisoes aplicadas

### Supabase Auth continua sendo a origem do login

`upsert_security_user_profile(...)` exige que o usuario ja exista em `auth.users`.

Ela nao cria senha, nao confirma email e nao altera credenciais. Isso evita acoplar o schema operacional ao contrato interno do Supabase Auth.

### Perfil operacional e separado de ator de sistema

Perfis com `is_system_actor = true`, como `Migracao Historica`, nao podem ser alterados pelas RPCs normais de usuario.

Motivo: ator de sistema e referencia auditavel, nao usuario operacional.

### Checks de permissao por override

`set_security_permission_override(...)` grava ou atualiza uma excecao por usuario + action key.

`clear_security_permission_override(...)` remove a excecao e devolve o usuario ao comportamento padrao de `permission_actions.default_allowed`.

A remocao do override e permitida porque a tabela de override representa estado atual da configuracao. O historico fica preservado em `action_logs`, nao como append-only na propria tabela de overrides.

### Escrita direta restringida

A migration revoga `insert`, `update` e `delete` de `authenticated` em:

- `user_profiles`;
- `permission_actions`;
- `user_permission_overrides`.

Alteracao operacional deve passar pelas RPCs auditadas.

## RPCs criadas

- `security_user_profile_snapshot(user_id)`;
- `upsert_security_user_profile(user_id, display_name, role, status)`;
- `set_security_permission_override(user_id, action_key, allowed)`;
- `clear_security_permission_override(user_id, action_key)`.

Todas usam `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`.

## Decisoes pendentes para Luciano

- Definir se o cadastro de usuario no Supabase Auth sera feito manualmente no painel, por script administrativo, ou por futura tela interna.
- Confirmar se os papeis atuais (`admin`, `comercial`, `producao`, `estoque`, `expedicao`, `auditoria`) sao suficientes.
- Definir se a tela de alçadas mostrara apenas overrides ou tambem o valor efetivo calculado (`default_allowed` + override).
- Definir quando trocar `default_allowed = true` para restricao por dominio em producao.
- Definir se `permission_actions` podera ser alterada por tela ou se continuara sendo catalogo controlado por migration.
