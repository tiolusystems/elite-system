# Validacao - seguranca email e senha temporaria

> Registro historico da 0038. O provisionamento ativo foi substituido por convite com email verificado na 0047. Contas legadas continuam suportadas para troca obrigatoria da senha temporaria.

Data: 2026-07-10

## Escopo

Bloco 0038:

- consolidar helpers de decisao pre-guard para wrappers residuais;
- criar contrato auditado para provisionamento de usuario Auth por email;
- implementar tela `/seguranca` para criar acesso com senha temporaria;
- impedir que senha, token ou service role key sejam gravados em log/documento/URL.

## Decisoes

O login permanece em `/login`, usando email e senha pelo Supabase Auth.

A criacao de acesso operacional passa por:

1. `authorize_security_auth_user_provision(...)` com `security.manage_users`;
2. `auth.admin.createUser(...)` no servidor com `SUPABASE_SERVICE_ROLE_KEY`;
3. `upsert_security_user_profile(...)` para criar o perfil operacional;
4. envio da senha temporaria por `ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL`;
5. `record_security_auth_user_temp_password_sent(...)` para registrar o fato do envio sem credencial.
6. primeiro login redireciona para `/login/trocar-senha` enquanto `temporary_password_bootstrap = true`.

Sem webhook configurado, a Server Action bloqueia a criacao antes de gerar senha.

## Limite operacional

O projeto nao traz provedor de email embutido. O envio real depende de configurar um webhook seguro em:

- `ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL`;
- `ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_TOKEN` quando o provedor exigir bearer token.

O payload enviado ao webhook contem a senha temporaria porque esse e o boundary de entrega. Esse payload nao deve ser logado pelo provedor.

## Validacoes esperadas

- Migration 0038 cria `authorize_security_auth_user_provision` e `record_security_auth_user_temp_password_sent`.
- Ambas usam `security.manage_users`, `begin_audited_rpc` e `log_audited_rpc_change`.
- Logs gravam `email_hash`, `provision_mode` e `contains_password = false`.
- Server Action usa `auditedRpc(...)` antes de `auth.admin.createUser(...)`.
- `SUPABASE_SERVICE_ROLE_KEY` fica apenas em helper server-only.
- A tela `/seguranca` contem formulario de novo acesso por email.
- A tela `/login/trocar-senha` troca a senha temporaria e registra `record_security_own_password_changed`.
- O proxy impede acesso operacional enquanto `temporary_password_bootstrap = true`.
- A decisao antiga de convite por link foi substituida pela regra nova.

## Validacoes executadas

Resultado desta sessao:

- `python -m unittest discover -s tests -p "test*.py"`: OK, 176 testes.
- `pnpm --dir apps/web lint`: OK apos incluir o Node do runtime Codex no `PATH` da sessao.
- `pnpm --dir apps/web build`: OK apos limpar `apps/web/.next`, que continha artefato gerado corrompido em `.next/dev/types/routes.d.ts`.
- `git diff --check`: OK, sem erro de whitespace.

Nao executado:

- Aplicacao das migrations em PostgreSQL descartavel. Motivo: `supabase` nao esta no PATH, `psql` nao esta no PATH e o Docker daemon nao esta acessivel nesta sessao.

## Pendencia real

Antes de uso operacional, configurar e testar o provedor de email. Sem isso, a tela informa `Envio nao configurado` e nao cria usuario Auth.
