# Validacao DEC-006 - formulas e OP historicas

Data: 2026-07-12

## Escopo

Validacao da migration `0054_dec_006_historical_formulas_ops_contract.sql` em
PostgreSQL local descartavel, sem importar o workbook real.

## Cadeia nova

`supabase db reset` aplicou `0001` a `0054`. O smoke operou como `test` dentro
de transacao e fez rollback integral.

Resultados:

- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `DEC_006_HISTORICAL_FORMULAS_OPS_SMOKE_OK`.

## Upgrade

O banco descartavel `elite_dec006_upgrade` recebeu a infraestrutura local do
Supabase, a cadeia `0001` a `0053`, uma formula e uma OP sinteticas anteriores
a DEC-006, a migration `0054` e a verificacao posterior.

Foram comprovados:

- formula, item e relacao formula/OP existentes preservados;
- origem `sistema` e revisao `approved` atribuidas ao estado operacional;
- produto da OP derivado somente da formula comprovada existente;
- nenhum rendimento, etapa, referencia desconhecida, saida ou CQ fabricado;
- backfill compativel com os gatilhos append-only existentes.

Resultado: `DEC_006_UPGRADE_CHAIN_OK`.

## Contratos validados

- rendimento, etapas e item/etapa relacionais;
- linhagem obrigatoria por batch e linha para fatos historicos;
- formula historica pendente impedida de ativacao operacional;
- referencia explicitamente desconhecida sem ligacao a formula atual;
- OP historica impedida de apontar para formula corrente do sistema;
- saida PA, PI ou `nao_classificada` sem movimento automatico de estoque;
- CQ parcial sem preenchimento inventado;
- estado de OP historica e fatos filhos append-only;
- compatibilidade da criacao e finalizacao de OP operacional existente.

## Regressao proporcional

- 66 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- smokes DEC-008, DEC-011, DEC-010 e DEC-006 aprovados;
- PostgreSQL lint sem erro de schema.

## Ausencia de dados reais

Apos rollback:

- workbooks: 0;
- rendimentos historicos: 0;
- etapas historicas: 0;
- referencias de formula desconhecida: 0;
- OPs historicas: 0;
- saidas historicas: 0;
- CQ historico parcial: 0.

Nenhum workbook, dump, credencial ou dado comercial foi versionado.

## Rollback

Em teste sem dependencias, restaurar backup e voltar ao commit anterior a
`0054`. Com fatos dependentes, a correcao deve ser nova migration, preservando
OPs, referencias de formula, saidas e CQ historicos append-only.
