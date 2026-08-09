# Validação da fórmula por litro e escala da OP - 0075

Data: 2026-07-21

## Regra validada

- fórmula operacional nova representa a necessidade para produzir 1 L;
- unidades admitidas: kg/L produzido, L/L produzido e UN/L produzido;
- OP operacional exige volume planejado em litros;
- quantidade total = quantidade por litro x volume planejado;
- fórmula antiga permanece legível como `legado_nao_comprovado` e não abre OP;
- fórmula MAPA permanece documental e não participa do cálculo de estoque;
- criar fórmula ou OP não baixa estoque.

## Banco descartável

Upgrade validado em `supabase_db_elite-validation-0073-clean`, já contendo a
cadeia até 0074. Instalação completa validada em
`supabase_db_elite-validation-0075-clean`, com container e volume próprios. A
trava `assert-disposable-supabase-target.ps1` retornou
`ELITE_DISPOSABLE_TARGET_OK`. Runtime ativo, staging e produção não foram
acessados durante esses testes.

O smoke transacional retornou:

`PG_VALIDATE_0075_PCP_FORMULA_PER_LITER_OP_SCALING_OK`

## Cenários

- fórmula de 0,25 kg/L para OP de 1.000 L planejou 250 kg;
- base, quantidade por litro, volume, unidade e total ficaram congelados na OP;
- fórmula sem unidade governada foi recusada;
- unidade kg comum foi recusada como unidade de fórmula operacional;
- OP sem volume foi recusada;
- fórmula legada foi recusada para nova OP;
- `anon` permaneceu sem execução nas RPCs de criação;
- nenhum dado real foi usado.

## Aplicação

- 39 testes dirigidos aprovados;
- TypeScript `--noEmit` aprovado;
- ESLint dos arquivos alterados aprovado;
- build Next.js aprovado;
- `git diff --check` aprovado.

## Incidente descartável durante a validação

Na primeira criação do container limpo, as migrations começaram durante o
reinício interno final do PostgreSQL. A conexão foi encerrada na migration
0002. Somente o container e volume `elite-validation-0075-clean` foram
recriados, após passagem pela trava obrigatória. O segundo ciclo aguardou dez
checagens consecutivas de prontidão antes de iniciar SQL. Não houve perda ou
alteração em runtime ativo, staging ou produção.
