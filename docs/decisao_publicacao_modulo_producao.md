# Decisao - publicacao do modulo Producao

Data: 2026-07-11

## Objetivo

Publicar o modulo Producao para validacao de negocio no ambiente `test`, reunindo a jornada de materias-primas, produtos, embalagens, formulas, garantias, ordens de producao, CQ, lotes bloqueados e transformacoes.

Publicar neste bloco nao significa liberar o ambiente `production`. Promocao para staging, piloto ou producao real continua dependendo de homologacao e de evento auditado no runtime modular.

## Fronteiras e dependencias

- `cadastros` continua dono de MP, produtos, embalagens e produto + embalagem;
- `estoque` continua dono de lotes, reservas, movimentos e saldos derivados;
- `pcp` continua dono de formulas, OPs, CQ, garantias calculadas e decisao sobre lote bloqueado;
- Producao apresenta uma jornada integrada, mas nao duplica tabelas nem regras dos dominios dependentes;
- toda escrita usa RPC auditada; nenhuma tela grava tabela diretamente.

## Garantias

- garantia MAPA de produto e garantia de lote MP sao append-only;
- correcao cria novo registro encadeado por `supersedes_id`;
- garantia de faixa exige valor minimo e maximo;
- garantia de laboratorio ou fornecedor exige documento de referencia;
- calculo por OP gera snapshot versionado e imutavel;
- o calculo pondera garantias dos lotes MP pelas quantidades efetivamente consumidas;
- ausencia ou incompatibilidade de dados gera status explicito, nunca valor inventado;
- `declarado` e informativo ate existir tolerancia de laboratorio formalizada.

## Transformacoes

- PA para PI, PI para PA, reembalagem e reprocessamento usam OP do tipo `reprocessamento`;
- a OP reserva o lote de origem, baixa na finalizacao e cria lote de destino;
- perdas ficam representadas pela diferenca entre entradas consumidas e outputs informados, com justificativa da OP;
- nunca existe RPC para editar saldo ou trocar o tipo de um lote existente.

## Experiencia publicada

- rota funcional `/producao`, vinculada ao modulo `pcp`;
- seletores enviam IDs estruturados e nao fazem parsing de textos `id | nome`;
- atalhos para os cadastros tecnicos compartilhados;
- registro e consulta de garantias;
- calculo/recalculo versionado de garantias por OP concluida;
- liberacao auditada de lote PA/PI bloqueado;
- fila dedicada de transformacoes por OP de reprocessamento.

## Criterio de liberacao

Depois de migrations, smoke SQL, testes Python, lint e build web aprovados, `cadastros`, `estoque` e `pcp` podem receber lifecycle `business_validation` e acesso `read_write` somente no ambiente `test`.

## Fora deste bloco

- formacao de custos;
- simulador de necessidade de compra e estoque regulador;
- agenda de capacidade de maquinas e pessoas;
- promocao para staging ou production;
- tolerancias laboratoriais por nutriente ainda nao aprovadas pelo negocio.
