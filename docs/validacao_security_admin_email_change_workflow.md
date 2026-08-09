# Validacao - troca administrativa de email

Data: 2026-07-12

## Regra de negocio

Usuario nao pode escolher nem trocar diretamente o email de acesso. O fluxo obrigatorio e:

1. usuario solicita a troca e informa somente o motivo;
2. administrador do sistema analisa a solicitacao no cadastro do usuario;
3. administrador aprova e define o novo endereco, ou rejeita com motivo;
4. titular pode apenas enviar a confirmacao para o endereco aprovado;
5. confirmacao do novo endereco conclui a solicitacao.

## Contrato 0048

- `security_email_change_requests` guarda o estado governado;
- `security_email_change_request_events` e ledger append-only;
- uma unica solicitacao ativa por usuario;
- aprovacao exige simultaneamente papel `admin` e `security.email_change.review`;
- endereco ficticio, duplicado ou igual ao atual e bloqueado no banco;
- `auth.updateUser` recebe apenas `approvedRequest.new_email`, retornado por RPC;
- usuario nao possui campo de novo email na propria tela;
- RPCs diretas da `0047` tiveram `execute` revogado de `authenticated`;
- logs guardam hash e estado, nunca email completo, token ou credencial.

## Evidencias

- migration executada primeiro em transacao com rollback;
- smoke `PG_VALIDATE_0048_ADMIN_EMAIL_CHANGE_WORKFLOW_OK` passou antes e depois da aplicacao;
- smoke comprovou bloqueio de revisao por usuario nao-admin;
- smoke comprovou que o usuario solicitante nao fornece email;
- smoke comprovou retorno exclusivo do endereco aprovado;
- smoke confirmou quatro eventos: solicitacao, aprovacao, envio e conclusao;
- tentativa de `update` no ledger de eventos foi bloqueada;
- `supabase db lint --local`: nenhum erro de schema;
- 238 testes Python: OK;
- TypeScript `tsc --noEmit`: OK;
- ESLint: OK;
- build Next.js de producao: OK, com 13 paginas estaticas geradas e rotas dinamicas compiladas;
- runtime local reiniciado e `/api/health` respondeu `status = ok`.
