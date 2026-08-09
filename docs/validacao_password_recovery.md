# Validacao - recuperacao e alteracao de senha

Data: 2026-07-12

## Problema fechado

Uma sessao aberta no navegador interno do Codex nao autentica automaticamente outro navegador. O navegador guarda a sessao, nao uma senha recuperavel pelo Elite System. Quando a senha temporaria era perdida, o sistema nao oferecia um caminho de recuperacao.

## Contrato implementado

- `/login` mostra `Esqueci minha senha` para usuario sem acesso e `Alterar senha` para sessao ativa.
- `/login/recuperar-senha` solicita o email e sempre devolve resposta neutra, sem confirmar se a conta existe.
- Supabase Auth envia um link de uso limitado. No ambiente local, a mensagem fica no Mailpit em `http://127.0.0.1:54324`.
- `/auth/confirm` aceita `token_hash` apenas com `type=recovery` ou o `code` PKCE emitido pelo Supabase, cria a sessao de recuperacao e remove o segredo da URL.
- `/login/trocar-senha` atende primeiro acesso, recuperacao e alteracao voluntaria.
- Apos recuperacao, a sessao temporaria e encerrada e o usuario entra com a nova senha.
- `record_security_own_password_changed()` registra somente ator, sessao Auth e fato da alteracao.

## Limites de auditoria

Pedido e validacao do link sao fatos anonimos controlados pelo Supabase Auth e permanecem nos logs nativos do provedor. O ledger `action_logs` recebe a alteracao concluida quando existe usuario autenticado e perfil ativo. Nenhuma senha, token, codigo PKCE ou segredo de recuperacao entra no PostgreSQL operacional, URL final, documento ou teste.

## Producao

O deploy deve configurar `NEXT_PUBLIC_APP_URL`, o `Site URL`, os redirect URLs e SMTP do projeto Supabase. O template `supabase/templates/recovery.html` e a referencia local; a configuracao equivalente deve estar aplicada no projeto cloud antes da homologacao externa.
