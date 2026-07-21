# Validação da reserva FIFO da OP - 0076

Data: 2026-07-21

## Escopo

A migration `0076_pcp_fifo_component_reservation.sql` torna FIFO o caminho
padrão de reserva de componentes da OP. A operação automática usa os lotes mais
antigos e pode distribuir a quantidade planejada entre vários lotes.

A seleção manual continua disponível para exceções operacionais. Quando ignora
um lote mais antigo, exige a permissão `pcp.op.reserve_override_fifo` e uma
justificativa com pelo menos 10 caracteres. O desvio é registrado na reserva e
em `action_logs`.

## Segurança e concorrência

- RPC automática disponível somente para `authenticated`;
- implementação interna e helper sem `EXECUTE` para `PUBLIC`, `anon` e
  `authenticated`;
- desvio FIFO negado por padrão;
- lock transacional por componente serializa reserva automática e manual;
- falta de saldo total aborta toda a reserva automática, sem efeito parcial;
- escrita direta nas tabelas permanece governada pelos contratos anteriores.

## Ambiente descartável

Projeto: `elite-validation-0076-clean`.

- container: `supabase_db_elite-validation-0076-clean`;
- volume: `supabase_db_elite-validation-0076-clean-data`;
- imagem: `public.ecr.aws/supabase/postgres:17.6.1.141`;
- cadeia instalada: 0001 -> 0076, total de 74 migrations;
- runtime local ativo, staging e produção não foram usados.

## Cenário aprovado

1. Dois lotes PI sintéticos foram criados, com entradas em datas diferentes.
2. A escolha manual do lote novo sem alçada foi negada.
3. Com alçada e justificativa, o desvio foi aceito e auditado como ordem FIFO 2.
4. Uma segunda OP exigiu 12 unidades.
5. A reserva automática consumiu a disponibilidade de dois lotes em ordem FIFO.
6. A transação de smoke terminou em rollback.

Marcador:

`PG_VALIDATE_0076_PCP_FIFO_COMPONENT_RESERVATION_OK`

## Limite conhecido

Este pacote governa quantidade e escolha de lotes. Ele não calcula custo
industrial de PI ou PA. A propagação de custos é uma etapa separada porque
envolve regras empresariais de aquisição, tributos, perdas e rateios que não
podem ser inferidas silenciosamente.
