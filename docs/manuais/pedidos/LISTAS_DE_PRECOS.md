# Listas de precos

## O que esta tela faz

Permite consultar listas e versoes existentes, baixar o modelo oficial,
analisar um arquivo XLSX e publicar uma nova versao imutavel.

## Antes de comecar

- tenha permissao para consultar listas e analisar importacoes;
- para publicar, tenha tambem permissao de publicacao e de gestao de rascunho;
- cadastre previamente produtos, apresentacoes e unidades desconhecidos;
- use sempre o modelo baixado pela propria tela.

## Sequencia correta

1. Acesse `Comercial > Listas de precos`.
2. Baixe `modelo_lista_precos_elite.xlsx`.
3. Preencha uma linha na aba `LISTA`.
4. Preencha as linhas da aba `PRECOS` com codigos existentes.
5. Envie um unico arquivo `.xlsx` e informe o motivo da analise.
6. Corrija todas as linhas em `ERRO` e analise o arquivo novamente.
7. Confira e aceite os `AVISOS`, quando existirem.
8. Informe o motivo e confirme `Publicar nova versao da lista de precos`.

## Codigos e nomes

Os codigos identificam produto, apresentacao e unidade. Os nomes apenas ajudam
na conferencia. Nome diferente com codigo correto gera aviso. Nome correto sem
codigo valido nao identifica nem cria cadastro.

O mesmo vale para a lista: `codigo_lista` identifica a lista existente. Nome
divergente exige conferencia, mas a publicacao preserva o nome cadastrado. Um
codigo ainda inexistente cria a nova lista com o nome informado no arquivo.

## Abas do modelo

- `INSTRUCOES`: leia antes de preencher;
- `LISTA`: codigo, nome, vigencia, UF, canal e observacao;
- `PRECOS`: produto, apresentacao, unidade, fator, faixa PMP e preco;
- `CATALOGOS`: consulta auxiliar dos codigos permitidos.

O preco deve ser numero positivo, sem texto `R$` e sem formula. Datas devem ser
datas do Excel. Para cada apresentacao, as faixas PMP devem iniciar em zero e
ser contiguas, sem lacuna ou sobreposicao: `0-30`, `31-60`, `61-90`. As linhas
podem estar fora de ordem porque o sistema as ordena para validar e publicar.

O arquivo pode ter no maximo 10 MB e 10.000 linhas de preco. Arquivos
criptografados, com macro, dimensoes excessivas ou expansao ZIP suspeita sao
recusados antes da analise de negocio.

## Avisos e erros

- `APROVADA`: linha pronta para publicacao;
- `AVISO`: vinculo por codigo foi encontrado, mas ha informacao humana a
  conferir;
- `ERRO`: a importacao integral esta bloqueada.

A explicacao mostra a linha e a causa. Corrija o XLSX original e envie-o
novamente. Nao edite a analise no sistema.

O sistema recalcula o hash de cada linha a partir dos campos normalizados e das
celulas brutas. Alteracao do preco, codigo ou lineage sem um novo arquivo
coerente e recusada integralmente.

## Efeito da publicacao

A confirmacao cria uma nova versao publicada e imutavel. Nenhuma linha e
publicada parcialmente e a versao anterior permanece no historico. Repetir a
mesma confirmacao nao duplica a versao; mudar o conteudo com a mesma chave de
confirmacao e recusado.

## Historico

A area de listas mostra codigo, nome, abrangencia, vigencia, versao, situacao,
data e responsavel pela publicacao quando permitido. Analises recentes tambem
podem ser reabertas para consulta.
