# Decisao tecnica - RPCs administrativas de seguranca

Data: 2026-07-06

## Objetivo

Endurecer o dominio `seguranca` sem misturar senha/login ao schema operacional.

A migration `0035_security_admin_rpcs.sql` cria RPCs auditadas para administrar:

- perfis em `user_profiles`;
- checks de permissao em `user_permission_overrides`.

## Decisoes aplicadas

### Supabase Auth continua sendo a origem do login

`upsert_security_user_profile(...)` exige que o usuario ja exista em `auth.users`.

Ela nao cria senha, nao confirma email e nao altera credenciais. Isso evita acoplar o schema operacional ao contrato interno do Supabase Auth.

### Criacao por email com senha temporaria

Evolucao 0038: por decisao operacional, a rotina interna cria o usuario no Supabase Auth por email e gera uma senha temporaria.

A aplicacao deve primeiro validar a alcada por RPC auditada (`authorize_security_auth_user_provision`). Depois disso, o boundary administrativo server-only chama `auth.admin.createUser` com `SUPABASE_SERVICE_ROLE_KEY`, gera senha temporaria em memoria e envia pelo canal configurado em `ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL`.

O log registra apenas autorizacao e envio, com hash do email, ator, data, origem da chamada e `contains_password = false`. Nenhuma senha temporaria, token, service role key ou credencial pode ser gravada em `action_logs`, metadata, URL, documento operacional ou output de teste.

Se o webhook de envio nao estiver configurado, a tela deve bloquear a criacao. Se o envio falhar depois da criacao do Auth user, a Server Action tenta remover o usuario criado para evitar acesso incompleto.

O usuario criado recebe `temporary_password_bootstrap = true` em `user_metadata`. Ao primeiro login, o proxy redireciona para `/login/trocar-senha` antes de liberar modulos operacionais. A troca atualiza a senha no Supabase Auth, remove o bootstrap e registra `record_security_own_password_changed()` sem gravar a nova senha.

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

## Evolucao 0036 - leitura administrativa e tela inicial

A migration `0036_security_admin_read_rpcs.sql` adiciona RPCs de leitura para alimentar a tela `/seguranca` sem abrir RLS de leitura ampla diretamente nas tabelas:

- `list_security_user_profiles()`;
- `list_security_effective_permissions(user_id)`.

Essas RPCs exigem `security.manage_users` e `security.manage_permissions`, respectivamente. A tela usa essas leituras para listar perfis, selecionar usuario e mostrar `default_allowed`, override e permissao efetiva.

Escritas continuam passando por `upsert_security_user_profile(...)`, `set_security_permission_override(...)` e `clear_security_permission_override(...)`.

## Evolucao 0038 - acesso por email e helpers de guard

A migration `0038_security_email_temp_password_contract.sql` adiciona:

- `authorize_security_auth_user_provision(email, display_name, role, status)`: valida permissao `security.manage_users` antes de qualquer chamada administrativa ao Supabase Auth;
- `record_security_auth_user_temp_password_sent(user_id, email)`: registra que a senha temporaria foi enviada, sem gravar a senha;
- `record_security_own_password_changed()`: registra a troca obrigatoria da propria senha temporaria, sem gravar a nova senha;
- `resolve_com_pedido_create_action_key(vendedor_id)`: centraliza a decisao `pedidos.create.own` vs `pedidos.create.any`;
- `resolve_pcp_formula_action_key(produto_id, tipo_receita)`: centraliza a decisao `pcp.formula.create` vs `pcp.formula.change`.

As duas funcoes `resolve_*` sao excecoes documentadas de leitura minima antes do guard. Elas existem apenas para escolher a action key correta e nao retornam dados operacionais ao usuario.

## Decisoes pendentes para Luciano

- Configurar o provedor real de envio em `ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL` antes de usar criacao de acesso em ambiente operacional.
- Confirmar se os papeis atuais (`admin`, `comercial`, `producao`, `estoque`, `expedicao`, `auditoria`) sao suficientes.
- Definir se a tela de alçadas mostrara apenas overrides ou tambem o valor efetivo calculado (`default_allowed` + override).
- Definir quando trocar `default_allowed = true` para restricao por dominio em producao.
- Definir se `permission_actions` podera ser alterada por tela ou se continuara sendo catalogo controlado por migration.
