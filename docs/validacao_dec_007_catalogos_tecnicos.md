# Validacao DEC-007 - catalogos tecnicos normalizados

Data: 2026-07-12

## Escopo

Validacao da migration `0050_dec_007_technical_catalogs.sql`, do contrato
relacional de catalogos tecnicos e do upgrade a partir da cadeia anterior.
Somente PostgreSQL local descartavel e dados ficticios foram utilizados.

## Cadeia nova

O comando `supabase db reset` recriou o banco local e aplicou as migrations
`0001` a `0050` sem erro. O banco nasce `unconfigured` por seguranca. O smoke
concede `system.admin` a um ator ficticio, configura `test` pela RPC auditada
`set_system_runtime_environment` e executa toda a validacao na mesma
transacao. O `rollback` remove ator, permissao, evento e fixtures.

Resultado: `DEC_007_TECHNICAL_CATALOGS_SMOKE_OK`.

## Upgrade da cadeia existente

Um banco `elite_dec007_upgrade` foi criado dentro do PostgreSQL local. A cadeia
`0001` a `0049` foi aplicada do zero, seguida de fixture ficticia anterior a
`0050`, migration `0050` e verificacao posterior.

Foram comprovados:

- alias `quilogramas` convertido para FK da unidade `kg`;
- alias `litros` convertido para FK da unidade `l`;
- garantia antiga ligada por FK a nutriente e unidade canonicos;
- garantia MAPA classificada como documental e aprovada;
- nenhuma dependencia do workbook real.

Resultado: `DEC_007_UPGRADE_CHAIN_OK`.

## Contratos validados

- unidade e nutriente canonicos por FK, com alias consultavel;
- especificacao e valor tecnico relacionais, sem JSON como substituto;
- versoes e fatos tecnicos append-only;
- ativacao de especificacao proibida para ator nao humano;
- garantia calculada legada fora da view MAPA atual;
- `excel_legado` exige `source_batch_id`, `source_row_id` e ator
  `Migracao Historica`;
- batch e linha devem pertencer ao mesmo workbook;
- historico importado nasce `pending_review` e nao e promovido;
- troca de unidade-base depois de movimento de estoque continua bloqueada;
- escrita direta de usuario autenticado permanece revogada.

## Regressao proporcional

- 38 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- `DEC_007_TECHNICAL_CATALOGS_SMOKE_OK`;
- `supabase db lint --local --level warning`: sem erro de schema.

## Ausencia de dados reais

Apos o reset, o banco continha:

- `source_workbooks`: 0;
- `migration_batches`: 0;
- especificacoes de produto: 0;
- unidades tecnicas: 11 referencias de sistema;
- nutrientes: 1 referencia tecnica generica (`N/Nitrogenio`).

O ambiente persistente voltou a `unconfigured` depois do rollback, como
previsto. Nenhum workbook, inventario local, dump, credencial ou dado
comercial integra esta entrega.

## Rollback

Em banco de teste sem dependencias, restaurar o backup e voltar ao commit
anterior a `0050`. Depois de fatos dependentes, rollback destrutivo e proibido;
uma migration de compatibilidade deve preservar as FKs e o historico.
