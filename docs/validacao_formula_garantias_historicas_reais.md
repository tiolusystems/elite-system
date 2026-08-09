# Validacao de formula e garantias historicas

## Escopo

Validacao executada com um recorte real do workbook historico em PostgreSQL
descartavel `elite-validation-*`. O workbook, os identificadores, os lotes, os
valores e os artefatos de carga permanecem fora do Git.

## Resultado da formula

- a linha de composicao possui materia-prima, quantidade, unidade e evidencia
  de lote/estoque;
- a composicao foi preservada como formula de producao historica pendente de
  revisao;
- a formula e o item mantem `source_batch_id` e `source_row_id`;
- a formula historica nao foi ativada e nao alimenta uma OP operacional;
- rendimento e natureza de saida nao foram inferidos quando a fonte nao os
  declarou de forma inequivoca.

## Resultado das garantias

- as linhas de garantia foram preservadas na camada de origem;
- nenhum nutriente, unidade ou natureza foi inventado;
- linhas sem mapeamento catalogal inequivoco geraram pendencias de validacao;
- nenhuma garantia pendente foi promovida ao cadastro aprovado;
- o conjunto completo do workbook contem garantias estaticas e garantias
  derivadas por formula, portanto a classificacao deve ocorrer por linha e nao
  apenas pelo nome da tabela.

## Achado no calculo operacional

A funcao vigente de calculo usa media ponderada das garantias encontradas nos
lotes consumidos. Essa operacao nao fecha necessariamente com a massa ou o
volume final informado pelo CQ e pode ignorar, no denominador, um insumo sem
garantia cadastrada para o nutriente.

O resultado numerico nao deve ser homologado enquanto o contrato nao definir:

1. unidade canonica de cada garantia;
2. escala de percentual armazenada;
3. conversao de consumo em massa ou volume;
4. uso da densidade do lote ou da materia-prima;
5. denominador final proveniente do CQ;
6. tratamento de lote sem garantia informada;
7. arredondamento e precisao regulatoria.

## Gate

Ate a homologacao desse contrato, dados historicos podem ser preservados como
pendentes, mas nao podem gerar garantia calculada aprovada nem liberar produto
automaticamente por esse resultado.
