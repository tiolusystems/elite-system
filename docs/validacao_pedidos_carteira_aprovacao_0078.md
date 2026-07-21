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
