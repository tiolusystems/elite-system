# Validacao DEC-009 - financeiro e fiscal legado

Data: 2026-07-12

## Escopo

Validacao da migration `0055_dec_009_legacy_financial_fiscal_contract.sql` em
PostgreSQL local descartavel, sem importar o workbook real.

## Cadeia nova

`supabase db reset` aplicou `0001` a `0055`. O smoke operou dentro de transacao
e fez rollback integral.

Resultado: `DEC_009_LEGACY_FINANCIAL_FISCAL_SMOKE_OK`.

## Upgrade

O banco descartavel `elite_dec009_upgrade` recebeu a infraestrutura local do
Supabase, a cadeia `0001` a `0054`, um pedido sintetico com condicao textual e
comissao marcada como paga, a migration `0055` e a verificacao posterior.

Foram comprovados:

- pedido, condicao de pagamento e estado da comissao preservados;
- nenhum plano ou parcela criado a partir de texto livre;
- nenhuma posicao recebida ou comissao paga fabricada;
- nenhuma referencia fiscal criada por inferencia.

Resultado: `DEC_009_UPGRADE_CHAIN_OK`.

## Contratos validados

- plano de pagamento versionado e vencimentos por linha;
- idempotencia por chave operacional e por batch/linha/parcela;
- status recebido como snapshot, nao recebimento;
- comissao paga como posicao, nao pagamento ou movimento;
- NF incompleta fora de `fat_notas_fiscais`;
- datas e classificacoes desconhecidas permanecem nulas;
- fatos historicos obrigados a `pending_review`, batch, linha e ator de
  migracao;
- fatos append-only, RLS de leitura e escrita direta revogada;
- read model operacional exclui todo historico pendente.

## Regressao proporcional

- 73 testes Python direcionados aprovados;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`;
- `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- smokes DEC-008, DEC-011, DEC-010, DEC-006 e DEC-009 aprovados;
- PostgreSQL lint sem erro de schema.

## Ausencia de dados reais

Apos rollback:

- workbooks: 0;
- planos: 0;
- parcelas: 0;
- posicoes de recebimento: 0;
- posicoes de comissao: 0;
- referencias fiscais: 0.

Nenhum workbook, dump, credencial ou dado comercial foi versionado.

## Rollback

Em teste sem dependencias, restaurar backup e voltar ao commit anterior a
`0055`. Com fatos dependentes, a correcao deve ser nova migration, sem apagar
planos, parcelas ou posicoes historicas.
