# Validacao DEC-008 - embalagens, logistica e transformacoes

Data: 2026-07-12

## Escopo

Validacao da migration `0051_dec_008_packaging_logistics_contract.sql` em
PostgreSQL local descartavel. Foram usados somente dados ficticios dentro de
transacoes revertidas.

## Cadeia nova

`supabase db reset` recriou o banco e aplicou `0001` a `0051`. O smoke
configurou o runtime como `test` pela RPC auditada, executou os cenarios e fez
rollback completo.

Resultado: `DEC_008_PACKAGING_LOGISTICS_SMOKE_OK`.

## Upgrade

Um banco descartavel `elite_dec008_upgrade` recebeu a cadeia `0001` a `0050`,
fixture anterior ao novo contrato, migration `0051` e verificacao posterior.

O upgrade comprovou:

- `litros` resolvido para a unidade canonica `l` da embalagem;
- `quilogramas -> toneladas` resolvido para FKs `kg -> t` da conversao;
- conversao preexistente preservada como `approved`, sem alterar fator;
- capacidade de veiculo sem unidade preservada, mas movida para
  `pending_review`, sem inventar `kg`;
- nenhuma versao/BOM criada automaticamente a partir de campos incompletos.

Resultado: `DEC_008_UPGRADE_CHAIN_OK`.

## Contratos validados

- BOM de embalagem relacional e versionada;
- tara e cubagem positivas quando informadas;
- ativacao de versao somente por perfil humano ativo;
- conversoes canonicamente ligadas ao catalogo da DEC-007;
- atribuicao de entregador/veiculo como ledger append-only;
- papel `entregador` vigente exigido para atribuicao aprovada;
- romaneio historico impedido de entrar no workflow vivo;
- transformacao com origens/destinos PA/PI e perdas relacionais;
- inferencia restrita a `pending_review` e fora do read model aprovado;
- nenhum movimento de estoque criado automaticamente;
- origem Excel exige batch, linha do mesmo workbook e ator
  `Migracao Historica`;
- escrita direta de `authenticated` revogada nas novas tabelas.

## Regressao proporcional

- 45 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- `DEC_008_PACKAGING_LOGISTICS_SMOKE_OK`;
- `supabase db lint --local --level warning`: sem erro de schema.

## Ausencia de dados reais

Apos reset e smokes com rollback:

- `source_workbooks`: 0;
- `migration_batches`: 0;
- versoes de embalagem: 0;
- eventos logisticos: 0;
- transformacoes: 0.

Nenhum workbook, inventario local, dump, credencial ou dado comercial foi
gravado ou versionado.

## Rollback

Em banco de teste sem dependencias, restaurar o backup e voltar ao commit
anterior a `0051`. Com fatos dependentes, rollback destrutivo e proibido; a
correcao deve ser nova migration de compatibilidade que preserve os ledgers.
