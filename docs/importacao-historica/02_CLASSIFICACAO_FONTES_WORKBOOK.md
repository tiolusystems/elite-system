# Classificacao das fontes do workbook e corte de estoque

## Objetivo

Este documento fecha a etapa `I1.1`. Ele define a finalidade estrutural das 269
tabelas do workbook de referencia e impede que relatorios, caches de formula ou
saldos historicos sejam promovidos como fatos operacionais.

A classificacao pertence ao schema e a finalidade da tabela. A inclusao de
novas linhas nao altera a classificacao. Mudanca de aba, tabela ou cabecalho
gera drift e bloqueia somente a fonte afetada ate nova aprovacao.

Nenhuma carga, migration ou escrita PostgreSQL faz parte desta etapa.

## Resultado quantitativo

| Classificacao | Tabelas | Uso aprovado |
|---|---:|---|
| `source_formula` | 245 | 119 formulas, 114 garantias e 12 BOMs de embalagem |
| `source_master` | 8 | cadastros oficiais comprovados |
| `source_transaction` | 7 | fatos historicos comprovados |
| `reconciliation_report` | 5 | comparacao, nunca normalizacao |
| `derived_calculation` | 2 | simulacao recalculavel |
| `dashboard_or_summary` | 2 | projecao e ranking |
| `duplicate_source` | 0 | nenhuma duplicidade foi provada |
| `deferred` | 0 | nenhuma tabela inteira foi adiada |
| `out_of_scope` | 0 | nenhuma tabela inteira foi descartada |
| **Total** | **269** | exatamente uma classificacao por tabela |

As 3.095 referencias permanecem vinculadas: 2.160 colunas estruturadas usam o
`source_table_id` da tabela; 935 referencias fora de tabelas usam um id de
metadado da propria planilha. Essa distincao evita fingir que conteudo solto
pertence a uma tabela inexistente. Referencias perdidas: zero.

O inventario anterior registrava 112 tabelas de garantias. A leitura estrutural
UTF-8 revalidada encontrou 114; o catalogo aprovado usa o numero comprovado.

## Matriz integral e protecao dos dados

A matriz versionada esta em
`docs/importacao-historica/03_MATRIZ_CLASSIFICACAO_269_TABELAS.md`. Ela possui
269 linhas e todos os campos de decisao, mas substitui nomes comerciais por:

- `sheet_ref` e `table_ref` sequenciais;
- `source_table_id` irreversivel;
- fingerprint de identidade e schema;
- cabecalhos canonicos sem nome de produto.

O manifesto exato, com aba, nome de tabela, intervalo e cabecalhos brutos, foi
gerado localmente em:

`01-original/analise-importacao-local/03_CLASSIFICACAO_FONTES_WORKBOOK_EXATA.csv`

Esse arquivo e o workbook permanecem fora do Git. O catalogo funcional
versionado contem hashes e regras, nunca valores de celula.

## Fontes cadastrais oficiais

As oito tabelas `source_master` sao:

1. especificacoes fisicas de embalagem (`PESO_EMBALAGENS`);
2. catalogo de garantias/nutrientes;
3. regras de pontos e premio da campanha;
4. cadastro de materias-primas;
5. cadastro de clientes;
6. cadastro de PA/PI;
7. cadastro de pessoas e papeis comerciais;
8. cadastro de veiculos.

Propriedades, fornecedores e unidades sem tabela primaria exclusiva serao
resolvidos a partir das fontes oficiais que realmente os referenciam. A I2 nao
criara cadastro ausente nem inferira identidade.

## Fontes transacionais oficiais

As sete tabelas `source_transaction` sao:

1. entradas de MP;
2. pedidos, itens e posicoes historicas associadas;
3. fatos de pontuacao por documento/produto;
4. producao e OP historicas;
5. snapshot comprovado de romaneio;
6. saidas/consumos de MP;
7. saidas de PA.

Ser fonte transacional nao autoriza formar estoque corrente. Antes do corte,
essas linhas sao fatos historicos de auditoria com
`afeta_estoque_operacional = false` como regra conceitual.

## Fontes constitutivas de formula

As 245 tabelas `source_formula` se dividem em:

- 119 tabelas de componentes e sequencia de formula;
- 114 tabelas de garantias associadas a produto/formula;
- 12 tabelas de composicao historica de embalagem.

Componentes, quantidades por base de rendimento, unidades e etapas comprovadas
poderao ser normalizados futuramente. Custos, lotes correntes, estoque,
percentuais, totais e quantidade simulada permanecem memoria de calculo ou
reconciliacao.

Garantia calculada, especificacao tecnica e garantia documental MAPA continuam
entidades distintas. A origem nao autoriza misturar esses tres significados.

## Relatorios de reconciliacao

As cinco tabelas `reconciliation_report` sao:

- analise de prazo de pedidos/entregas;
- controle de estoque PA;
- controle de estoque MP;
- posicao de estoque MP por periodo;
- posicao de estoque PA por periodo.

Elas preservam metadados, cabecalhos, contagens, hash e totais necessarios para
comparar pedidos, faturamento, entradas MP, saidas MP, saidas PA, producao e
estoques. Nao geram fatos e nao sao normalizadas.

## Calculos, paineis e duplicidades

`SIMULA_PRODUCAO` e `SIMULA_PRODUCAO_PARAMETRO` sao
`derived_calculation`. A projecao de faturamento e o ranking de clientes sao
`dashboard_or_summary`.

Nenhuma tabela recebeu `duplicate_source`: o sufixo `(2)` sozinho nao prova
duplicidade. Existem 13 abas de formula com esse sufixo, totalizando 23 tabelas
marcadas com risco alto. Elas permanecem `source_formula` ate que a comparacao
de produto, vigencia, componentes e finalidade prove se sao versoes historicas
ou copias. Nao havera fusao automatica.

Nao existem tabelas inteiras classificadas como `deferred` ou `out_of_scope`.
Conteudo solto de indice, anotacoes, analises sem tabela e planilha vazia fica
como metadado de worksheet; nao entra na contagem das 269 tabelas.

## Politica da camada bruta

Para `source_master`, `source_transaction` e `source_formula`, a I2 devera
preservar integralmente workbook/hash, batch, aba, tabela, intervalo, linha,
chave de origem, payload bruto, formulas relevantes, hash de linha e revisao.

Para `reconciliation_report`, preservar metadados, cabecalhos, contagens, hash
e indicadores. Linhas so serao materializadas quando indispensaveis para
comprovar uma divergencia.

Para `derived_calculation`, `duplicate_source` e `dashboard_or_summary`,
preservar metadados e relacao com a fonte primaria. A carga integral de linhas
nao e o padrao.

## Politica de corte e saldos de abertura

### Tres periodos separados

1. Historico anterior ao corte: auditoria, sem efeito operacional.
2. Inventario fisico aprovado: unico saldo oficial de abertura.
3. Movimentos posteriores ao corte: livro operacional do sistema novo.

### Historico anterior ao corte

O historico nao cria lote disponivel, saldo atual, custo atual, reserva, baixa
corrente, cliente nao comprovado nem rastreabilidade inexistente. Correcao nao
sera fabricada por venda, perda, descarte, OP ou movimento ficticio.

### Inventario fisico de abertura

O saldo inicial sera exclusivamente o que for contado e aprovado na data de
corte. Cada item deve registrar produto/insumo, embalagem quando aplicavel,
quantidade, unidade, deposito, lote real quando conhecido, fabricacao e validade
quando conhecidas, responsavel, data e estado de aprovacao.

O saldo calculado do Excel e comparador, nunca saldo oficial.

### Lote conhecido, desconhecido e fantasma

- lote real conhecido: manter a identificacao fisica real, sem reconstruir
  artificialmente todos os movimentos anteriores;
- lote desconhecido com quantidade real: criar futuramente um lote tecnico de
  abertura, marcado como lote industrial nao comprovado, sem inventar OP,
  fabricacao, validade ou cliente;
- lote presente no Excel, mas ausente fisicamente: manter apenas referencia
  historica, `confirmado_no_inventario = false`, disponibilidade e saldo inicial
  iguais a zero.

### Divergencia de abertura

Comparar saldo calculado no Excel com saldo fisico contado e registrar a
diferenca como divergencia auditavel. A justificativa pode ficar pendente; o
sistema nao criara um evento operacional para fazer os numeros coincidirem.

### MP, PI, embalagens e outros insumos

A mesma regra se aplica por entidade. Historico confiavel pode ser recalculado
e reconciliado, mas o inventario aprovado continua sendo o corte operacional.
Historico incompleto permanece apenas para auditoria. A decisao pode variar por
fonte, nunca por conveniencia de fechar saldo.

### Decisoes de ativacao ainda abertas

Nao foi inventada data de corte. Antes de ativar saldos, Luciano deve definir:

- data oficial de corte e data do inventario;
- responsaveis pela contagem;
- depositos incluidos;
- criterio de aprovacao;
- tratamento dos movimentos durante a contagem.

Essas decisoes nao bloqueiam a I1.1 nem a preservacao bruta da I2. Bloqueiam a
promocao de saldos para operacao.

## Quatro pendencias de coluna

| Pendente | Fonte afetada | Motivo e impacto | Bloqueia bruto | Bloqueia normalizacao | Regra provisoria |
|---|---|---|---|---|---|
| densidade | `LOTES_PRODUCAO.PRODUCAO_LOTES.Densidade OP`; conferir entradas e cadastros | valor de CQ sem contexto/unidade plenamente comprovados | nao | sim, no CQ | preservar valor e formula brutos; nao inferir |
| pH | `LOTES_PRODUCAO.PRODUCAO_LOTES.Ph` | medicao historica parcial sem contrato completo do ensaio | nao | sim, no CQ | preservar exatamente; nao usar como aprovacao |
| contato de cliente | `RELACAO CLIENTES.CLIENTES.CONTATO` | texto pode misturar pessoa, telefone, email e funcao | nao | sim, no contato | preservar campo bruto; nao dividir por suposicao |
| UF | `RELACAO CLIENTES.CLIENTES.UF` | preenchimento incompleto e sem prova por cidade | nao | sim, no cliente | preservar vazio/valor original; nao deduzir pela cidade |

Pendencias preservadas: quatro. Valores inventados: zero.

## Comportamento em futuras atualizacoes do workbook

1. cada execucao tera workbook e batch proprios;
2. linha sera identificada por origem, chave natural e hash;
3. linha ja importada nao sera duplicada;
4. linha nova sera adicionavel sem reclassificar a tabela;
5. linha alterada sera versionada ou enviada a revisao;
6. exclusao no Excel nao apagara historico;
7. rename de aba/tabela e mudanca de cabecalho geram drift;
8. drift bloqueia apenas a fonte afetada;
9. tipo, unidade ou significado alterados exigem declaracao humana quando o
   XLSX nao fornecer metadado estrutural suficiente;
10. as demais fontes permanecem processaveis.

## Gate para I2

A I2 podera carregar somente `source_master`, `source_transaction` e
`source_formula` aprovadas. Ela devera manter transacao, rollback, idempotencia,
rastreabilidade e separacao entre camada bruta e promocao relacional.

Esta classificacao nao autoriza normalizacao, criacao de lote, saldo, movimento,
pedido, OP, recebimento ou qualquer outro registro operacional.
