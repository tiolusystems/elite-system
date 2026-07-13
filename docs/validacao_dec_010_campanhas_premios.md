# Validacao DEC-010 - campanhas, pontos e premios

Data: 2026-07-12

## Escopo

Validacao da migration `0053_dec_010_campaign_rewards_contract.sql` em
PostgreSQL local descartavel, sem importar o workbook real.

## Cadeia nova

`supabase db reset` aplicou `0001` a `0053`. O smoke operou como `test` dentro
de transacao e fez rollback integral.

Resultado: `DEC_010_CAMPAIGN_REWARDS_SMOKE_OK`.

## Upgrade

O banco `elite_dec010_upgrade` recebeu `0001` a `0052`, produto antigo com
grupo textual, migration `0053` e verificacao posterior.

Foram comprovados:

- grupo textual preservado e ligado ao catalogo por FK;
- nenhum campo de produto alterado silenciosamente;
- nenhuma campanha, ponto, premio ou pagamento criado por backfill;
- todas as tabelas relacionais presentes.

Resultado: `DEC_010_UPGRADE_CHAIN_OK`.

## Contratos validados

- configuracao versionada de campanha/regra/recompensa/elegibilidade;
- duas campanhas simultaneas ativas;
- ativacao somente por humano e com periodo/regra/elegibilidade aprovados;
- ledger append-only de pontos com credito e estorno;
- premio e voucher com eventos de ciclo de vida;
- pagamento monetario sob ownership `financeiro`;
- nenhuma escrita em `fin_comissao_movimentos`;
- historico obrigado a `pending_review`, batch, linha e ator de migracao;
- saldos/read models excluem fatos pendentes;
- escrita direta de `authenticated` revogada.

## Regressao proporcional

- 59 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- smokes DEC-008, DEC-011 e DEC-010 aprovados;
- PostgreSQL lint sem erro de schema.

## Ausencia de dados reais

Apos rollback:

- workbooks: 0;
- campanhas: 0;
- movimentos de pontos: 0;
- premios: 0;
- vouchers: 0;
- pagamentos de premio: 0.

Nenhum workbook, dump, credencial ou dado comercial foi versionado.

## Rollback

Em teste sem dependencias, restaurar backup e voltar ao commit anterior a
`0053`. Com fatos dependentes, a correcao deve ser nova migration, sem apagar
ledgers de pontos, premios, vouchers ou pagamentos.
