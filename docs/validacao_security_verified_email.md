# Validacao - convite e email verificado

Data: 2026-07-12

## Problema

O bootstrap local criou uma conta humana com email placeholder confirmado. Recuperacao solicitada para um endereco real inexistente no Auth respondia de forma neutra, como exige a protecao contra enumeracao, mas o administrador nao tinha uma tela para ver a causa.

## Contrato 0047

- novo usuario recebe convite do Supabase Auth e nao senha temporaria;
- convite confirma o controle do endereco e abre a criacao da senha;
- `invitation_pending = true` bloqueia acesso operacional ate a ativacao terminar;
- modulo Seguranca mostra email e estado de confirmacao somente para administrador autorizado;
- dominios `.local`, `.invalid`, `.test` e dominios `example.*` conhecidos sao bloqueados e aparecem como ficticios em dados antigos;
- conta autenticada pode solicitar troca do proprio email;
- a alçada da troca e verificada e auditada antes da chamada externa ao Auth;
- somente o novo endereco precisa confirmar a troca;
- logs operacionais guardam hash, ator, acao e estado, nunca email completo, senha ou token.

## Fronteira de seguranca

A tela publica de recuperacao continua sem informar se o email existe. Revelar essa informacao permitiria enumerar contas. A consulta exata fica no modulo Seguranca, protegido por sessao, perfil ativo e `security.manage_users`.

## Ambiente

Localmente, Mailpit recebe convite, alteracao de email e recuperacao em `http://127.0.0.1:54324`. Em Supabase cloud, SMTP, Site URL, redirect allowlist e os tres templates precisam ser publicados antes da homologacao.

## Diagnostico local

Na verificacao de 2026-07-12, o Auth local tinha uma conta humana com endereco placeholder confirmado e nenhuma identidade humana associada ao endereco real usado na recuperacao. Por isso o pedido de recuperacao retornava a mensagem publica neutra e nenhuma mensagem era criada: a conta solicitada nao existia no diretorio Auth.
