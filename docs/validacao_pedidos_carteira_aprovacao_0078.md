# Validacao 0078 - Pedidos por carteira e aprovacao

## Contrato

- vendedor derivado da sessao, sem campo livre de identidade;
- cliente limitado ao vinculo comercial temporal ativo;
- pedido sempre criado como aguardando liberacao;
- gerente limitado a carteira propria e vendedores subordinados;
- decisao e ajuste de limite exigem justificativa;
- historico de limite append-only;
- leitura de pedidos protegida por RLS de carteira/equipe.

## Banco descartavel

- upgrade validado em `supabase_db_elite-validation-0077-clean`;
- instalacao limpa validada em `supabase_db_elite-validation-0078-clean`, com
  container e volume exclusivos;
- cadeia `0001 -> 0078`: 76 migrations aplicadas;
- smoke transacional: `PG_VALIDATE_0078_SELLER_MANAGER_OK`;
- todos os dados sinteticos foram revertidos por `ROLLBACK`.

## Cenarios aprovados

- vendedor A cria pedido da propria carteira;
- pedido nasce bloqueado e com decisao pendente;
- vendedor nao aprova o proprio pedido;
- vendedor B nao le pedido da carteira A;
- gerente direto enxerga o pedido da equipe;
- gerente nao ganha acesso a vendedor sem subordinacao;
- ajuste de limite gera evento auditavel;
- gerente libera pedido e o status passa a aberto;
- escrita direta permanece negada;
- `anon` nao executa as RPCs governadas.
- RPC legada de pedido nao permite escolher outro vendedor nem abrir a venda;
- RPC legada de credito nao permite ao vendedor liberar o proprio pedido.

## Aplicacao

- ESLint dirigido: aprovado;
- TypeScript `--noEmit`: aprovado;
- build Next.js: aprovado;
- 13 testes dirigidos: aprovados;
- `git diff --check`: aprovado.

## Limite conhecido

A primeira versao governada cria um item por pedido. O proximo incremento deve
permitir varios itens no mesmo pedido sem reabrir o escopo de carteira, credito
ou aprovacao aqui validado.

## Compatibilidade 0079

Como a Vercel nao conseguiu provisionar o novo Preview, a migration 0079 fecha
tambem as RPCs consumidas pelo frontend estavel anterior. Assim, a indisponibilidade
temporaria do novo layout nao reabre os atalhos de vendedor e aprovacao.
