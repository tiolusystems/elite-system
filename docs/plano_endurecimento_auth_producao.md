# Plano de endurecimento do Auth para producao

Data da auditoria: 2026-07-12

## Estado confirmado

- cadastro publico global desativado;
- login anonimo desativado;
- convite nasce somente na Server Action administrativa;
- `service_role` permanece somente no servidor e arquivos `.env*` sao
  ignorados pelo Git;
- e-mail precisa ser confirmado antes do login;
- troca de e-mail depende de solicitacao, aprovacao administrativa e
  confirmacao do endereco aprovado;
- migration 0049 fecha por papel e permissao todas as RPCs administrativas.

## Gaps que impedem declarar seguranca de producao completa

O `supabase/config.toml` local ainda e uma configuracao de desenvolvimento:

- senha minima de 6 caracteres e sem composicao obrigatoria;
- alteracao de senha sem reautenticacao forte;
- MFA TOTP nao habilitado nem exigido pela aplicacao/banco;
- CAPTCHA desabilitado;
- sessoes sem limite de inatividade e sem duracao maxima;
- e-mail local entregue no Mailpit, nao em SMTP corporativo;
- troca de e-mail confirma apenas o endereco novo no ambiente local.

## Sequencia obrigatoria antes de publicar na internet

1. Construir cadastro, desafio e recuperacao operacional de MFA TOTP.
2. Cadastrar e validar o fator do administrador atual antes de exigir AAL2.
3. Exigir `aal2` no banco para usuarios, permissoes, troca de e-mail e rollout.
4. Elevar senha minima e composicao; ativar protecao contra senhas vazadas no
   plano Supabase que oferecer o recurso.
5. Exigir reautenticacao para alteracao de senha e revisar confirmacao dupla de
   e-mail.
6. Configurar SMTP corporativo, URL HTTPS oficial e allowlist exata de
   redirects.
7. Configurar rate limits e CAPTCHA para login e recuperacao.
8. Definir timebox, inatividade e politica de sessoes simultaneas.
9. Ativar MFA na conta/organizacao Supabase e 2FA no GitHub dos mantenedores.
10. Executar Security Advisor, SSL enforcement, Network Restrictions, backup e
    teste de restauracao no projeto cloud.

## Regra contra lockout

MFA nao sera exigido do unico administrador antes de um fator TOTP ter sido
confirmado e de existir um procedimento de recuperacao administrativa testado.
Ativar a exigencia antes disso pode bloquear o unico responsavel pelo sistema.
