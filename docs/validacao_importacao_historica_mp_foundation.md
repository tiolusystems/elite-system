# Validacao da fundacao de importacao historica de MP

Data: 2026-07-11
Migration: `0045_historical_mp_import_foundation.sql`
Destino: codigo e schema para analise/reconciliacao; nenhum dado real importado

## Escopo entregue

- inventario Python por batch em modo SQLite somente leitura;
- comando `analyze-mp-history` com saida JSON;
- staging de identidade historica por source row e hash;
- sugestao de MP por SKU, codigo legado, nome e alias;
- aprovacao humana auditada com aliases imutaveis;
- origem obrigatoria e consistente entre workbook, batch e linha;
- valor de aquisicao por movimento com mercadoria, frete, DIFAL e outras despesas separados;
- total e custo unitario gerados pelo PostgreSQL;
- fila de mapeamento, resumo do batch e historico de precos em views `security_invoker`;
- tela responsiva somente leitura em `/importacao-historica/mp`;
- rota governada pelo modulo `auditoria` e alçada `migration.mp.view`.

## Invariantes verificadas

1. Staging, eventos de mapeamento, aliases e valores de aquisicao sao append-only.
2. Repetir o mesmo staging, mapeamento ou valor nao duplica o fato.
3. Repetir com qualquer snapshot ou documento diferente falha; nao mascara drift.
4. A quantidade-base do valor deve ser igual a quantidade do movimento fisico de entrada.
5. `excel_legado` exige `source_batch_id` e `source_row_id` do mesmo workbook.
6. Sugestao com mais de um candidato vira conflito e nao expoe candidato arbitrario.
7. Aprovacao exige as alcadas de migracao e identidade de cadastro.
8. Registro de valor exige as alcadas de migracao e estoque.
9. DIFAL positivo exige status informado e nao e aceito para emitente SP sob a regra aprovada.
10. Usuario autenticado nao possui escrita direta nas novas tabelas.

## Evidencias executadas

- projeto descartavel isolado `elite-mp-0045-validation`, banco na porta `55322`;
- `supabase db reset`: migrations `0001` a `0045` aplicadas do zero;
- `supabase db lint --local --level warning`: nenhum erro de schema;
- `tests/sql/historical_mp_import_foundation.sql`: `PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK`;
- smoke termina em `ROLLBACK` e nao deixa fixtures no banco;
- `python -m unittest discover -s tests -p "test*.py"`: 227 testes OK;
- ESLint dos arquivos TypeScript alterados: zero erros;
- `next build --webpack`: compilacao, TypeScript e rota `/importacao-historica/mp` OK;
- `git diff --check`: OK;
- nenhum workbook, banco, extracao ou dado comercial foi adicionado ao Git.

O primeiro `next build` com Turbopack nao compilou porque a worktree de validacao usa uma junction de `node_modules` fora da raiz do projeto. A repeticao oficial com Webpack, suportado pelo Next.js, compilou e executou o typecheck completo. Isso e limitacao do ambiente isolado, nao falha da aplicacao.

## O que a tela permite validar

- quantidade de identidades por batch;
- aprovado, sugerido, pendente e conflito;
- linha de origem e MP canonica proposta/aprovada;
- documento, lote, quantidade de origem e quantidade-base;
- valor da mercadoria, frete, DIFAL, outras despesas, total e custo unitario.

A tela e somente leitura. Ela nao cria MP, lote, movimento nem saldo.

## Gate antes de dados reais

1. definir o formato oficial do SKU de MP;
2. executar o analisador no banco local de migracao, gerando relatorio fora do Git;
3. revisar conflitos e cadastros novos com Luciano;
4. aprovar aliases em ambiente descartavel;
5. implementar a RPC de promocao historica de lote e movimento com origem no ato da insercao;
6. importar consumos e destinos conhecidos;
7. reconciliar quantidade, valor e saldo por MP/lote;
8. somente depois decidir movimento de abertura e corte.

Importar fisicamente antes desses gates violaria o contrato de migracao sem perda.
