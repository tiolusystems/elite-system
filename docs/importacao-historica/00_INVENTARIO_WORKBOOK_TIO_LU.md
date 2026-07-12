# Inventario agregado do workbook legado

Status: gate de descoberta T2 concluido em 2026-07-12.

Este documento e deliberadamente agregado. O inventario completo contem nomes
de produtos e outros dados mestres; por isso permanece fora do repositorio, ao
lado do workbook, em `01-original/analise-importacao-local/`. Git recebe apenas
codigo e documentacao sem dados operacionais.

## Totais estruturais

- 155 abas;
- 269 tabelas estruturadas;
- 114 nomes definidos;
- 139 abas com ao menos uma tabela estruturada;
- 16 abas sem tabela estruturada;
- 1 aba vazia;
- 2.160 colunas de tabelas estruturadas classificadas;
- 935 referencias de coluna usadas fora de tabelas classificadas;
- 3.095 referencias de coluna cobertas no total;
- zero referencia deixada como `review_required`.

## Grupos encontrados

| Grupo | Natureza | Tratamento |
|---|---|---|
| formulas de produto | 119 abas com componentes, lotes correntes e custos derivados | importar componentes somente apos decidir base de rendimento e etapas |
| garantias de produto | 112 tabelas associadas a formulas | separar calculada, especificacao tecnica e documental MAPA |
| cadastros mestres | MP, produtos, clientes, pessoas e veiculos | deduplicar, normalizar e resolver aliases |
| embalagens | composicao de custo, peso e cubagem | bloqueado por destino relacional ausente |
| pedidos | itens, vencimentos, fiscal, entrega e comissoes | bloqueado parcialmente por parcelas e posicoes legadas |
| producao | OP/lotes, consumo MP e saida PA | bloquear inferencia de formula, PA/PI e transformacao |
| estoque | entradas/saidas e varios saldos derivados | movimentos sao fonte; saldos servem para reconciliacao |
| romaneio | template e snapshot corrente | nao tratar como livro historico completo |
| campanhas | pontos e premiacoes | bloqueado por dominio ainda inexistente |
| relatorios e simulacoes | tabelas dinamicas, analises e projecoes | reconciliacao; nunca gerar fato duplicado |

## Qualidade observada

- 1.293 linhas de componentes de formula foram identificadas;
- 40 linhas de formula possuem materia-prima, mas nao possuem quantidade nem
  concentracao por litro utilizavel;
- 994 linhas possuem sequencia/fase e 245 delas usam texto, nao apenas numero;
- 157 linhas de cadastro de MP, 115 produtos e 344 clientes foram encontradas;
- 617 entradas MP, 14.616 saidas MP, 1.448 producoes e 3.622 saidas PA foram
  encontradas nas tabelas historicas;
- 2.562 linhas de item de pedido foram encontradas;
- somente 33 de 344 clientes possuem UF preenchida;
- formulas com cache e erros Excel foram contadas e devem permanecer no source
  ledger para auditoria.

Esses numeros sao contagens, nao dados operacionais. Nenhuma linha, valor,
cliente, produto, lote, nota fiscal ou pedido aparece neste documento.

## Artefatos locais nao versionados

O diretorio local `01-original/analise-importacao-local/` contem:

- inventario completo de abas e tabelas;
- cobertura coluna a coluna;
- inventario estrutural JSON;
- estatisticas semanticas por tabela.

Esses arquivos nao devem ser adicionados ao Git. O workbook tambem permanece
fora do repositorio.

## Resultado do gate

O schema efetivamente aplicado no Supabase local foi consultado em modo
somente leitura e o ambiente foi confirmado como `test`. A matriz agregada esta
em `docs/importacao-historica/01_MATRIZ_EXCEL_SCHEMA.md`.

Foram encontrados destinos relacionais indispensaveis ausentes. Conforme a
regra da tarefa T2, nenhuma migration, rota, RPC ou aplicador foi criado antes
da decisao de Luciano.
