# Decisao - migracao historica de materias-primas

Data: 2026-07-11

## Objetivo

Preservar e migrar do Tio Lu System os nomes, codigos, precos, lotes, entradas, consumos, destinos e saldos de materia-prima sem transformar o cadastro mestre em um campo de saldo ou custo editavel.

Este contrato orienta a fundacao PostgreSQL implementada na migration `0045_historical_mp_import_foundation.sql`. Nenhum dado real entra no Git.

## Estado de implementacao

Concluido nesta etapa:

- analisador Python somente leitura por batch;
- staging append-only e idempotente por `batch_id + source_row_id`;
- sugestao sem aprovacao automatica;
- aprovacao auditada e aliases historicos ligados a MP canonica;
- componentes imutaveis de aquisicao ligados ao movimento fisico de entrada;
- origem `source_batch_id + source_row_id` validada no banco;
- views de fila, resumo e historico de precos;
- tela analitica `/importacao-historica/mp`;
- smoke transacional descartavel e CI.

Deliberadamente nao implementado nesta etapa:

- promocao em massa de lotes e movimentos reais;
- importacao de consumos e destinos de producao;
- movimento de saldo de abertura;
- decisao automatica sobre conflito de nome ou codigo.

Esses itens dependem da revisao visual dos mapeamentos e da reconciliacao contra o Excel.

## Fontes historicas confirmadas

| Fonte Excel | Fatos preservados |
|---|---|
| `CADASTRO_MATERIA_PRIMA` | nome, `id_sku_mp`, unidade, densidade, estoque minimo, custo unitario historico e classificacoes |
| `ENTRADAS_MP` | data, NF, MP, lote, quantidade, unidade, custo, frete, diferencial de ICMS, valor, custo total, saldo do lote e media ponderada |
| `SAIDAS_MP` | data, MP, quantidade, lote consumido, lote da OP e produto produzido |
| `PRODUCAO_LOTES` | lote produzido, produto, quantidade e custo de MP |
| `CONT_ESTOQUEMP` | saldo atual declarado por MP |

Cada linha permanece em `source_rows` com workbook, tabela, numero da linha, hash e payload original. O registro normalizado aponta de volta para essa evidencia.

## Identidade da MP

1. `cad_materias_primas.id` e a identidade interna.
2. `sku_corrigido` e o codigo oficial novo e unico.
3. `id_sku_mp`, nomes antigos e codigos de fornecedor permanecem como aliases de origem.
4. Um alias pode apontar para uma unica MP canonica.
5. Codigo duplicado, codigo usado como nome ou nomes ambiguos entram em fila de conciliacao; nao existe unificacao automatica silenciosa.
6. A aprovacao do mapeamento registra autor, data, metodo, confianca e linha de origem.

## Regra de preco e custo de aquisicao

Preservar preco nao significa implementar agora o motor futuro de formacao de custos. Nesta fase, o sistema guarda os fatos de cada aquisicao e o snapshot do calculo usado no Tio Lu System.

Componentes separados por entrada/lote:

- valor da materia-prima;
- quantidade e unidade recebidas;
- quantidade convertida para a unidade-base;
- frete;
- diferencial de aliquota de ICMS (`difal_icms`);
- outras despesas de aquisicao aprovadas, quando existirem;
- valor total de aquisicao;
- valor unitario na unidade-base;
- custo medio ponderado informado no legado, como snapshot historico;
- NF, data, UF do emitente e linha de origem.

Regra operacional aprovada:

```text
custo_aquisicao_total = valor_materia_prima
                       + frete
                       + difal_icms_aplicavel
                       + outras_despesas_aprovadas

custo_unitario_base = custo_aquisicao_total / quantidade_convertida
```

Quando a MP vier de fora de SP, o diferencial de aliquota de ICMS aplicavel compoe o custo de aquisicao. O valor deve vir do documento/importacao ou de confirmacao manual auditada. A UF, isoladamente, nao autoriza o sistema a inventar valor tributario.

O total calculado nunca substitui os componentes. Isso permite auditar por que o custo mudou e evoluir futuramente o motor de custos sem perder o fato original.

## Lotes

1. O lote interno recebe identidade e codigo automaticos e unicos.
2. Lote do fornecedor e lote legado ficam em campos de origem e nao precisam ser globalmente unicos.
3. Cada lote aponta para a MP canonica e, quando disponivel, para NF/item, source row e batch.
4. Data de fabricacao, validade, fornecedor e garantias do lote sao preservados quando existirem.
5. Correcao nao troca o lote historico; cria evento ou vinculo corretivo auditado.

## Onde a MP foi usada

O caminho de rastreabilidade pretendido e:

```text
MP canonica -> lote MP -> movimento de consumo -> OP/lote de producao
             -> lote PA/PI produzido -> romaneio -> cliente
```

`SAIDAS_MP` fornece MP, quantidade, lote consumido, lote da OP e produto. Esses dados devem ser ligados a OP/producao historica quando a relacao for inequivoca.

Se o Excel nao informar lote ou OP suficiente, o sistema preserva a saida e registra a pendencia `sem_lote_informado_no_legado` ou `op_historica_nao_resolvida`. Nunca inventa o vinculo.

## Saldo atual e corte

Saldo operacional continua derivado do livro append-only:

```text
saldo = entradas + ajustes_entrada - consumos - ajustes_saida
```

Processo de corte:

1. importar movimentos historicos confiaveis;
2. calcular saldo derivado por MP e lote;
3. comparar com `CONT_ESTOQUEMP.SALDO ATUAL`;
4. classificar diferencas por dado ausente, conversao, lote nao resolvido ou divergencia real;
5. se a historia for incompleta, registrar um unico movimento explicito de saldo de abertura na data de corte, com motivo, batch e valor esperado;
6. nunca editar movimentos antigos ou gravar saldo diretamente.

Depois do corte, o saldo atual resulta do movimento de abertura reconciliado mais todos os eventos do Elite System.

## Estrutura planejada

- aliases/identificadores historicos da MP ligados a `cad_materias_primas`;
- fila de mapeamento por batch e source row;
- marcadores `origem_dados`, `source_batch_id` e `source_row_id` em lotes e movimentos historicos;
- ledger append-only de valores de aquisicao ligado ao movimento de entrada MP;
- referencia separada para codigo interno do lote e lote legado/fornecedor;
- views de historico de precos, rastreabilidade e reconciliacao por MP/lote;
- RPCs auditadas e idempotentes para mapear, importar e reconciliar.

## Ordem de implementacao

1. inventario somente leitura das variantes de nome/codigo no Excel;
2. staging por batch com hash e source row;
3. tela de conciliacao `registro Excel -> MP canonica`;
4. aliases aprovados e novo SKU oficial;
5. importacao de lotes e entradas com valores separados;
6. importacao dos consumos e seus destinos conhecidos;
7. reconciliacao por MP, lote, quantidade, valor e saldo;
8. ensaio em PostgreSQL descartavel;
9. relatorio local de divergencias fora do Git;
10. backup, corte, importacao final e aceite.

## Gate de aceitacao

- nenhuma linha de origem perdida;
- nenhuma MP duplicada por variacao de nome;
- nenhum codigo ambiguo aceito automaticamente;
- somas de quantidade e valor reconciliadas ou divergencia documentada;
- saldo por MP e lote reconciliado ou abertura explicitamente justificada;
- preco, frete e DIFAL consultaveis separadamente;
- repeticao do mesmo batch nao duplica cadastro, lote, movimento ou valor;
- toda escrita deixa autor e action log.

## Fora deste bloco

- definicao fiscal/legal de quando o DIFAL e devido;
- apuracao tributaria;
- criterio contabil de credito recuperavel;
- formacao completa de custo de producao e margem;
- alteracao retroativa de custo de OP ja encerrada.

Essas regras futuras consumirao os fatos preservados por este contrato, sem reescrever a historia.

## Decisao ainda necessaria

Definir o formato do novo SKU oficial de MP. Essa decisao nao bloqueia inventario, staging, conciliacao e preservacao do codigo legado.

Antes do primeiro ensaio com dados reais, tambem devem ser confirmados:

1. data de corte do estoque;
2. responsavel pela aprovacao de aliases ambiguos;
3. tolerancia de quantidade e valor por MP/lote;
4. criterio para aceitar vinculo historico `saida MP -> OP/produto` quando o Excel nao trouxer chave inequivoca.
