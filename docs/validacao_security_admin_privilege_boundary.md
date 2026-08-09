# Validacao - fronteira de privilegio administrativo

Data: 2026-07-12

## Achado

As action keys `system.admin`, `security.manage_users` e
`security.manage_permissions` nasceram com `default_allowed = true` na fundacao
inicial. Enquanto existia apenas um administrador isso nao produziu acesso
indevido real, mas um futuro usuario operacional ativo herdaria capacidade de
administrar usuarios e permissoes se nao recebesse overrides negativos.

## Correcao 0049

- quatro capacidades criticas passaram para default deny;
- administradores humanos ativos preexistentes receberam grants explicitos;
- toda RPC publica de usuarios, permissoes e rollout exige papel `admin` e a
  action key correspondente;
- promover ou administrar outro `admin` exige tambem
  `security.manage_permissions`;
- implementacoes internas nao sao executaveis por `authenticated`;
- snapshot interno e logger legado de senha temporaria foram fechados;
- o ultimo administrador capaz nao pode perder grants, ser rebaixado ou
  desativado;
- bootstrap do primeiro administrador continua exclusivo de `service_role` e
  agora cria os quatro grants explicitos.

## Smoke de ataque

`tests/sql/security_admin_privilege_boundary.sql` concede propositalmente as
quatro action keys a um perfil `comercial` e comprova que ele continua incapaz
de:

- listar o diretorio de usuarios;
- promover usuario para administrador;
- alterar alçadas;
- alterar o ambiente de runtime.

O teste tambem comprova a separacao entre `manage_users` e
`manage_permissions`, o bloqueio de acesso aos `_impl_0049` e a protecao contra
lockout do ultimo administrador capaz.

## Evidencias executadas

- migration validada primeiro em transacao com rollback;
- migration `0049` aplicada no Supabase local;
- `PG_VALIDATE_0049_SECURITY_ADMIN_PRIVILEGE_BOUNDARY_OK` passou antes e
  depois da aplicacao;
- administrador ativo manteve os quatro grants criticos efetivos;
- chamada governada confirmou que o administrador ativo continua lendo o
  diretorio de Seguranca;
- endpoint Auth confirmou `disable_signup = true`, confirmacao de email ativa e
  usuario anonimo desativado;
- `supabase db lint --local`: nenhum erro de schema;
- 243 testes Python: OK;
- TypeScript `tsc --noEmit`: OK;
- ESLint: OK.

## Limite desta entrega

Esta migration fecha autorizacao administrativa no banco. Ela nao substitui o
endurecimento da autenticacao da conta: senha forte, MFA TOTP, sessao limitada,
CAPTCHA, SMTP de producao e protecoes da organizacao Supabase permanecem gates
obrigatorios antes de exposicao publica.
