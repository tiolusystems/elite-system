# PRICE-LIST XLSX - workspace operacional

## Decisao

A operacao de listas de precos passa a utilizar o workspace
`Comercial > Listas de precos`, com modelo XLSX governado, analise previa e
publicacao atomica de uma nova versao imutavel.

A migration `0137` e aditiva e reutiliza os contratos canonicos de listas,
versoes, escopos, unidades de precificacao, auditoria e idempotencia definidos
pelas migrations `0124` a `0136`. Nenhuma migration historica e reescrita.

## Identidade e reconciliacao

- `codigo_produto`, `codigo_apresentacao` e `unidade_precificacao` sao as
  identidades operacionais.
- Nomes importados servem somente para confirmacao humana. Divergencia de nome
  com codigo exato gera `AVISO`; nunca altera o vinculo.
- `codigo_lista` tambem e a identidade da lista. Quando o codigo ja existe, a
  analise congela seu `lista_id`, compara o nome importado com o cadastrado e
  exige confirmacao do aviso em caso de divergencia. A planilha nunca renomeia
  a lista existente. Codigo novo cria uma lista com o nome importado.
- Codigo ausente, desconhecido ou associado a outra entidade gera `ERRO`.
- A importacao nunca cria produto, apresentacao ou unidade.
- A unidade e o fator comercial sao explicitos e congelados na versao.
- Para `L`, o fator deve corresponder ao volume positivo da apresentacao. Para
  `kg` e `un`, o fator deve ser informado sem conversao automatica.

## Modelo XLSX

O arquivo possui exatamente quatro abas:

- `INSTRUCOES`: regras de preenchimento e publicacao;
- `LISTA`: codigo, nome, vigencia, UF, canal e observacao;
- `PRECOS`: codigos, nomes auxiliares, unidade, fator, faixa PMP, preco e
  observacao;
- `CATALOGOS`: dados governados permitidos para auxiliar o preenchimento.

As abas usam tabelas do Excel, cabecalhos congelados e filtros. Datas sao
celulas de data e precos sao numericos. Formula em campo autoritativo e
rejeitada. O limite operacional e 10 MB e 10.000 linhas de preco. Antes do
ExcelJS, o servidor valida diretorio ZIP, quantidade de entradas, criptografia,
metodo de compactacao, tamanho expandido total e por entrada e taxa de
compactacao. Dimensoes excessivas tambem sao recusadas. Somente `.xlsx` sem
macro e aceito.

## PMP

Cada linha representa uma faixa com limite inferior e superior. Para cada
apresentacao, as faixas formam uma particao total e contigua: a primeira inicia
em zero e cada seguinte inicia no dia posterior ao limite anterior. Exemplo:
`0-30`, `31-60`, `61-90`. A validacao ordena os intervalos antes da conferencia,
portanto a ordem fisica das linhas nao muda o resultado. Lacuna, sobreposicao,
limite superior duplicado ou unidade/fator divergente bloqueiam a analise.

O limite superior e persistido como `prazo_dias`, preservando a regra canonica
do resolvedor: prazo exato usa a faixa que o contem e PMP intermediario usa a
primeira faixa superior autorizada. A publicacao ordena os precos pelo limite
superior.

## Analise e publicacao

O upload somente analisa. A analise preserva SHA-256 do workbook, payload
canonico, aba, linha e enderecos das celulas. O hash usa o documento de linha
`price-list-row-v1`: array JSON em ordem fixa com identidade, nomes auxiliares,
unidade, fator, PMP, preco, observacao, valores brutos `A:J`, formulas `A:J` e
enderecos das dez celulas. Numeros usam representacao decimal sem expoente. O
PostgreSQL recompoe esse documento e seu SHA-256 antes de inserir `source_rows`;
divergencia aborta sem lineage parcial. Cada linha recebe `APROVADA`, `AVISO` ou
`ERRO`.

Qualquer erro bloqueia toda a publicacao. Avisos exigem aceite visual. A
confirmacao publica, em uma unica transacao, o rascunho, os itens, as faixas,
os escopos e o fato imutavel de publicacao. A operacao vincula os hashes exatos
do arquivo e do payload analisado. Retry identico retorna a mesma versao; retry
divergente falha.

As RPCs legadas da `0125`, que reconciliavam nomes, permanecem apenas para
evidencia historica e deixam de ser executaveis pelos papeis da aplicacao.

## Seguranca

- leitura: `pedidos.price_lists.view`;
- analise: `pedidos.price_lists.import.stage`;
- publicacao: `pedidos.price_lists.publish` e
  `pedidos.price_lists.draft.manage`;
- tabelas internas sem escrita direta por `authenticated`;
- RPCs publicas com default deny, escopo, auditoria e idempotencia;
- nenhuma escrita por service role no fluxo de negocio da interface.

## Limites

Esta entrega nao altera resolucao de preco, PMP, desconto, credito, comissao,
Pedido ou contratos publicados. Nao importa XLS/CSV, nao seleciona abas e nao
faz conversao arbitraria entre unidades.
