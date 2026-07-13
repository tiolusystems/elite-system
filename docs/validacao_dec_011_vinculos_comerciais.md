# Validacao DEC-011 - vinculos comerciais temporais

Data: 2026-07-12

## Escopo

Validacao da migration `0052_dec_011_client_seller_temporal_links.sql` em
PostgreSQL local descartavel, sem dados do workbook real.

## Cadeia nova

`supabase db reset` aplicou `0001` a `0052`. O smoke classificou a transacao
como ambiente `test` pela RPC auditada e reverteu todas as fixtures.

Resultado: `DEC_011_CLIENT_SELLER_TEMPORAL_LINKS_SMOKE_OK`.

## Upgrade

O banco descartavel `elite_dec011_upgrade` recebeu `0001` a `0051`, fixture no
formato anterior, migration `0052` e verificacao posterior.

Foram comprovados:

- vinculo antigo preservado e classificado como `atende`;
- status e vigencia do vinculo preservados;
- vinculo pessoa/area preservado;
- nenhuma area de cliente criada por inferencia;
- nenhum pedido ligado retroativamente a relacao nao comprovada;
- `cadastrou` sem concessao de visibilidade.

Resultado: `DEC_011_UPGRADE_CHAIN_OK`.

## Contratos validados

- papeis de vinculo por catalogo e FK, sem confusao com role Auth;
- escopo global de cliente ou especifico por propriedade;
- propriedade obrigada a pertencer ao mesmo cliente;
- cliente/area e pessoa/area com vigencia;
- sobreposicao ativa duplicada bloqueada;
- pessoa de vinculo ativo obrigada a ter papel comercial vigente;
- read model direto e regional derivado somente de relacao `sistema` ativa;
- `cadastrou` preservado como fato, sem visibilidade atual;
- pedido ligado ao mesmo cliente, vendedor e propriedade do vinculo;
- historico Excel obrigado a ficar `pending_review`;
- exclusao fisica e truncate de relacao temporal bloqueados;
- batch, linha e ator `Migracao Historica` exigidos no legado.

## Regressao proporcional

- 52 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- `DEC_008_PACKAGING_LOGISTICS_SMOKE_OK`;
- `DEC_011_CLIENT_SELLER_TEMPORAL_LINKS_SMOKE_OK`;
- PostgreSQL lint sem erro de schema.

## Ausencia de dados reais

Apos rollback dos smokes:

- workbooks de origem: 0;
- papeis tecnicos de vinculo: 4;
- vinculos cliente/pessoa: 0;
- vinculos cliente/area: 0;
- pedidos com referencia de vinculo: 0.

Nenhum workbook, dump, credencial ou dado comercial foi versionado.

## Rollback

Em teste sem dependencias, restaurar backup e voltar ao commit anterior a
`0052`. Com pedidos dependentes, rollback destrutivo e proibido; a correcao
deve preservar a FK e o historico em nova migration.
