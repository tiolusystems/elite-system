# Validacao da linhagem historica de Cadastros - 0072

## Problema corrigido

O trigger criado na migration 0040 tentava obter `batch_id` diretamente de
`source_tables`. Essa coluna nao existe: uma tabela-fonte pertence ao workbook,
enquanto o lote de migracao pertence a `migration_batches`.

O defeito impedia a primeira gravacao real e rastreavel em Clientes, Pessoas,
Materias-primas ou Produtos, apesar de a cadeia de migrations instalar sem erro.

## Contrato corrigido

- `source_batch_id` e `source_row_id` devem ser informados juntos;
- a linha e o lote devem pertencer ao mesmo workbook;
- registros sem origem historica continuam aceitando ambos nulos;
- nenhuma linha operacional ou historica existente e alterada;
- grants e RLS permanecem inalterados.

## Validacao

O smoke `tests/sql/master_data_source_lineage.sql` comprova, em transacao com
rollback:

1. par linha/lote do mesmo workbook aceito;
2. lote de outro workbook recusado;
3. par incompleto recusado;
4. nenhuma fixture persistida.

A carga real usada para revelar e revalidar o defeito permanece somente no
ambiente descartavel `elite-validation-real-production`, fora do Git.
