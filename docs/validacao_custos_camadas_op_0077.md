# Validação 0077 - custos por camadas e saída única da OP

## Escopo

A migration `0077_pcp_mp_cost_layers_single_output.sql` implementa:

- custo de MP por camada de entrada, inclusive entradas distintas do mesmo lote;
- consumo das camadas na ordem de entrada, com trava transacional por lote;
- uma única saída PI por OP de produção;
- perda de processo separada de perda de estoque;
- propagação do custo direto de MP para o lote PI;
- propagação do custo do PI e das embalagens para o lote PA no envase;
- custo final do PA por embalagem, sem mão de obra, operação ou indiretos;
- fatos de custo append-only, RLS e permissão específica de leitura.

## Banco descartável

- projeto: `elite-validation-0077-final`;
- container: `supabase_db_elite-validation-0077-final`;
- volume: `supabase_db_elite-validation-0077-final-data`;
- imagem: `public.ecr.aws/supabase/postgres:17.6.1.141`;
- runtime ativo, staging e produção não foram acessados para a instalação limpa.

## Resultados

- cadeia completa `0001 -> 0077`: aprovada;
- smoke `pcp_cost_layers_single_output.sql`: aprovado e revertido ao final;
- duas entradas de 6 kg no mesmo lote, a R$ 10/kg e R$ 20/kg: preservadas;
- consumo de 10 kg: custo FIFO confirmado em R$ 140;
- perda de processo de 1 L: custo confirmado em R$ 14;
- lote PI de 9 L: custo material confirmado em R$ 126;
- saldo da segunda camada: 2 kg confirmado;
- tentativa de finalizar a OP com duas saídas: recusada;
- quantidade física separada dos componentes monetários: confirmada.

Marcadores: `PG_VALIDATE_0077_COST_LAYERS_OK` e
`PG_VALIDATE_0077_FINAL_OK`.

## Staging

- dry-run remoto apresentou somente a migration 0077;
- migration 0077 aplicada isoladamente e confirmada no ledger;
- `/api/health`: `status=ok` e `backendConfigured=true`;
- nenhuma migration intermediária, reset ou dado sintético foi aplicado;
- frontend estável permaneceu no release anterior enquanto o novo deployment
  não foi promovido.

## Limites deliberados

- custos operacionais, mão de obra e indiretos não são calculados;
- valores ausentes deixam o custo pendente, nunca são convertidos em zero;
- precificação ainda não foi implementada; o custo PA por embalagem é sua futura
  fonte governada.
