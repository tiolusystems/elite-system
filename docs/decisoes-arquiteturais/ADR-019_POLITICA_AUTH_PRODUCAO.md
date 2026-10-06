# ADR-019 - Politica Auth de producao

## Status

Autorizada em 2026-10-06. A configuracao remota e a primeira invitacao humana
continuam pendentes de execucao controlada.

## Decisao

A autenticacao de producao do Elite System e fechada por convite
administrativo. Nao existe cadastro publico.

A URL canonica da aplicacao em producao e
`https://elite-system-seven.vercel.app`.

O ingresso humano permitido e:

1. autorizacao administrativa governada;
2. convite administrativo pelo Supabase;
3. confirmacao de controle do endereco de e-mail;
4. definicao da propria senha pela pessoa convidada;
5. atribuicao governada de perfil e acesso;
6. acesso operacional apos os gates aplicaveis.

O fluxo existente permanece `auth.admin.inviteUserByEmail(...)`, seguido por
`/auth/confirm`, estado `invitation_pending`, definicao de senha e perfil
governado. A recuperacao permanece `resetPasswordForEmail(...)`, seguida por
`/auth/confirm` e definicao de senha.

## Limites proibidos

Sao proibidos em producao:

- cadastro publico;
- login anonimo;
- contas compartilhadas;
- senha temporaria enviada pelo Elite;
- criacao direta de usuario Auth pelo navegador;
- redirecionamentos amplos ou com wildcard;
- segredo administrativo no frontend;
- ativacao automatica sem perfil governado.

## Parametros preservados

Esta decisao preserva `jwt_expiry = 3600`,
`enable_refresh_token_rotation = true` e
`refresh_token_reuse_interval = 10`.

Nao define timebox de sessao, inatividade de sessao, MFA, regras de composicao
de senha nem governanca de troca de e-mail. Esses temas permanecem fora deste
ADR e, quando aplicavel, dependem das decisoes proprias ja registradas.

## Prerequisitos para execucao remota

Antes da primeira invitacao humana, a configuracao remota deve estar aplicada
e verificada com SMTP transacional customizado operacional, entrega de e-mails
de convite e recuperacao comprovada, Site URL de producao correta e allow-list
restritiva de redirecionamentos.

Antes de promover trafego publico, devem estar comprovados: DEC-004 aplicada e
verificada, smoke de convite e recuperacao de producao, ausencia de cadastro
publico, login anonimo e wildcard de redirecionamento, e uso do Supabase de
producao exato pela aplicacao. DEC-002 continua independente.

SMTP e protecao contra abuso nao sao habilitados neste repositorio sem
credenciais reais de provedor. Ambos sao prerequisitos de release explicitamente
pendentes, e nao valores ficticios de configuracao.
