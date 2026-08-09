# I1.2 - homologacao funcional das fontes do workbook

## Objetivo

A I1.2 permite que Luciano determine, tabela por tabela, quais fontes do
workbook historico podem participar da futura carga I2. A interface apresenta
as 269 tabelas estruturadas identificadas na I1/I1.1 e nao escreve no
PostgreSQL.

Esta etapa nao executa importacao, nao cria migration e nao promove nenhum
dado historico para operacao corrente.

## Separacao de responsabilidades

- a classificacao tecnica da I1.1 permanece imutavel e continua sendo a
  avaliacao de engenharia;
- a decisao funcional pertence a Luciano e prevalece para definir a carga;
- nenhuma decisao e inferida a partir da classificacao tecnica;
- divergencia de schema, identidade do workbook ou catalogo tecnico impede a
  reutilizacao silenciosa de uma revisao antiga;
- I2 permanece bloqueada ate existir um artefato final homologado.

## Informacoes apresentadas

Cada uma das 269 tabelas mostra:

- aba, nome da tabela, intervalo e identificador tecnico;
- quantidade de linhas, linhas preenchidas e colunas;
- principais colunas;
- classificacao tecnica sugerida;
- dominio proprietario e destino previstos;
- quantidade e presenca de formulas;
- indicio de relatorio e de calculo derivado;
- risco de duplicidade;
- justificativa tecnica;
- decisao final de Luciano;
- observacao de Luciano.

## Catalogo fechado de decisoes

As unicas decisoes funcionais aceitas sao:

1. `importar_integralmente`;
2. `importar_apenas_metadados`;
3. `usar_somente_reconciliacao`;
4. `nao_importar`;
5. `adiar`;
6. `revisar`.

O estado interno `sem_decisao` existe somente enquanto Luciano ainda nao fez
uma escolha. Ele nao e uma decisao final e bloqueia a exportacao da
homologacao final.

## Regra de entrada na I2

Somente tabelas com decisao `importar_integralmente` serao elegiveis para a
I2. As demais decisoes tem os seguintes efeitos:

- `importar_apenas_metadados`: preserva apenas informacao descritiva da fonte;
- `usar_somente_reconciliacao`: permite comparacao, sem virar fato importado;
- `nao_importar`: exclui a tabela da carga;
- `adiar`: mantem a decisao para etapa futura;
- `revisar`: bloqueia somente a propria tabela ate nova revisao.

Relatorios, ferramentas, calculos e paineis podem, por decisao expressa,
preservar apenas metadados ou ser usados somente em reconciliacao.

## Operacao da tela

A area de homologacao fica na mesma tela da analise integral do workbook. O
fluxo e:

1. selecionar e analisar o workbook real;
2. conferir o perfil `155/269/3.095` e a ausencia de schema drift;
3. filtrar por texto, dominio, classificacao tecnica ou decisao;
4. registrar uma decisao e, opcionalmente, uma observacao em cada tabela;
5. usar decisao em lote apenas quando houver uma escolha explicita e
   confirmacao do usuario;
6. revisar as listas de aprovadas para I2, excluidas e pendentes;
7. exportar CSV para leitura humana e JSON para continuidade auditavel;
8. exportar a homologacao final somente quando as 269 tabelas tiverem decisao.

O rascunho e salvo apenas no armazenamento local do navegador, vinculado ao
SHA256 do workbook. Esse rascunho nao e enviado ao banco e nao deve ser
confundido com o artefato formal de revisao.

## Historico de revisao

O artefato JSON possui:

- tipo e versao de contrato;
- `revisionId` e `parentRevisionId`;
- data, status e trilha de revisoes;
- SHA256 e perfil do workbook;
- identificador e fingerprint de schema de cada tabela;
- snapshot da classificacao tecnica;
- decisao, observacao e historico de mudanca por tabela;
- resumo por decisao;
- listas de aprovadas para I2, excluidas, pendentes, metadados e
  reconciliacao.

Ao importar uma revisao anterior, a interface valida SHA256, conjunto exato de
tabelas, unicidade dos identificadores, fingerprint e classificacao tecnica.
Somente decisao e observacao voltam para edicao; a revisao nunca substitui a
fonte tecnica atual.

Cada nova exportacao JSON cria uma revisao descendente. Assim, alteracoes
futuras preservam a trilha de revisao sem editar a classificacao I1.1.

## Saidas

- matriz CSV das 269 tabelas, inclusive itens ainda sem decisao;
- revisao JSON em estado `draft`, utilizavel para continuar o trabalho;
- artefato JSON `homologated`, disponivel apenas apos 269 decisoes explicitas;
- resumo por todas as seis decisoes;
- lista de aprovadas para I2;
- lista de excluidas da carga;
- lista de pendentes, incluindo `sem_decisao`, `adiar` e `revisar`.

O CSV aplica protecao contra formula injection. Os artefatos exportados podem
conter nomes e observacoes reais e, portanto, permanecem locais e fora do Git.

## Garantias e limites

- nenhuma coluna ou tabela estruturada e omitida da matriz;
- nenhuma decisao e inferida automaticamente;
- nenhuma escrita operacional e disponibilizada;
- nenhuma chamada Supabase, RPC ou Server Action pertence a esta area;
- nenhuma migration foi criada;
- a classificacao tecnica original e sempre preservada;
- a interface nao substitui a homologacao humana;
- I1.2 entrega o mecanismo de decisao, nao as decisoes de Luciano.

## Criterios para encerrar a homologacao funcional

1. o workbook real foi analisado e confirmou exatamente 269 tabelas;
2. nao existe schema drift nem classificacao tecnica pendente;
3. cada tabela recebeu uma das seis decisoes autorizadas;
4. as listas de aprovadas, excluidas e pendentes foram revisadas;
5. o artefato final `homologated` foi exportado e guardado fora do Git;
6. a futura I2 recebeu somente a lista `approvedForI2` desse artefato.

Enquanto esses seis criterios nao forem cumpridos, I2 nao deve ser iniciada.
