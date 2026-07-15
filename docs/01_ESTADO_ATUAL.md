# Elite System - estado atual

Atualizado em: 2026-07-15

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: Bloco 6 de Romaneio/Expedicao no commit `c54c328`
  e no staging;
- entrega atual: Bloco 6 validado localmente, instalado no Supabase staging e
  publicado na Vercel, ainda sem homologacao funcional autenticada;
- ultima migration no staging: `0059_romaneio_logistics_operational_contract.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Bloco 6 - Romaneio e Expedicao operacional:

- a DEC-008 continua sendo a fonte relacional de entregador, veiculo e eventos
  logisticos append-only;
- a 0059 adiciona RPC separada para atribuir e remover logistica, ambas com
  permissao atomica, `before/after` e `correlation_id`;
- a tela `/romaneios` deixou de interpretar texto `id | nome`: pedido, item,
  romaneio e lote agora enviam IDs relacionais reais;
- somente pessoas ativas com papel `entregador` vigente e veiculos ativos sao
  oferecidos;
- cada romaneio mostra a atribuicao atual sem apagar historico;
- a tela informa se o romaneio confirmado aguarda faturamento e mostra as NFs
  vinculadas quando existirem, sem mover regra fiscal para Expedicao;
- criacao total/parcial, multi-item, reserva multilote, confirmacao, baixa PA,
  cancelamento e estorno continuam usando as RPCs auditadas existentes;
- nenhum dado operacional ou workbook foi adicionado ao Git.

## Validacao desta tarefa

- 8 testes direcionados do contrato 0059: aprovados;
- TypeScript com `--noEmit --incremental false`: aprovado;
- ESLint direcionado: aprovado sem warning;
- build de producao Next.js 16.2.10: aprovado, com 24 paginas geradas e a
  rota `/romaneios` presente;
- migrations `0001` a `0059` instaladas do zero no projeto separado
  `elite-validation-0059`;
- smoke transacional: `PG_VALIDATE_0059_WITH_SMOKE_OK`;
- lint PostgreSQL: nenhum erro de schema;
- ator sem grants negado antes da validacao de parametros nas RPCs 0059;
- runtime local ativo `elite-system` nao foi resetado, migrado ou alterado;
- branch privada publicada e sincronizada;
- migration 0059 aplicada somente no Supabase `elite-system-staging`;
- deploy atualizado em `https://elite-system-staging.vercel.app`;
- `/api/health`: `status=ok` e backend configurado;
- acesso anonimo a `/romaneios`: redirecionado para login;
- homologacao visual autenticada: unico gate pendente desta entrega.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas, Garantias, Ordens, Reservas, CQ, Finalizacao, Lotes, Estoque
  e Transformacoes separados em telas operacionais e publicados no staging;
- `estoque`: consulta operacional por lote e movimentos auditados integrados ao
  fluxo de OP; ativacao do saldo real continua dependente da `DEC-012`;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise, classificacao e homologacao funcional do Excel: disponiveis
  localmente e sem escrita;
- mapa visual de implantacao: disponivel em `/modulos`;
- decisoes funcionais de Luciano: ainda nao preenchidas; I2 bloqueada;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- homologacao cloud: ambiente ativo, com login e banco declarando `staging`;
- `expedicao`: Bloco 6 completo e publicado no staging; homologacao funcional
  autenticada da 0059 pendente;
- producao cloud: continua bloqueada por homologacao, backup, monitoramento,
  migracao historica ensaiada, seguranca externa e piloto;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

Homologar o Bloco 6 no staging com usuario autenticado: criacao total/parcial,
multi-item, reserva multilote, logistica, confirmacao, baixa PA, situacao fiscal,
cancelamento e estorno. Nao iniciar o encadeamento de status antes desse gate.

## Tarefa seguinte de produto

Depois da homologacao do Romaneio, implementar a atualizacao encadeada de status
entre pedido, expedicao, faturamento, financeiro e comissoes. `DEC-013` continua
bloqueando apenas a escala proporcional de formula; o lote padrao absoluto
permanece funcional.

`H1` continua em paralelo como tarefa funcional de Luciano: decidir as 269
fontes. `I2` permanece bloqueada ate o artefato final homologado existir.

## Tarefas temporariamente adiadas

- Suporte S0 (`DEC-001`);
- MFA TOTP (`DEC-002` a `DEC-004`);
- implementacao dos perfis combinaveis (`DEC-005`).

Essas tarefas permanecem autorizadas ou pendentes conforme
`docs/02_DECISOES_PENDENTES.md`, mas nao bloqueiam `C1`, `F1` ou `H1`.

## Regra de manutencao

Ao fechar qualquer tarefa, substituir neste arquivo:

- tarefa concluida mais recente;
- validacao e resultado;
- proxima tarefa;
- tarefa seguinte;
- nova decisao bloqueante, quando houver.

Nao transformar este documento em diario. O historico pertence ao Git.
