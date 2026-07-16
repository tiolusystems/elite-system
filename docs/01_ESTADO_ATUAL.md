# Elite System - estado atual

Atualizado em: 2026-07-15

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: Bloco 6 de Romaneio/Expedicao no commit `c54c328`
  e no staging;
- entrega atual: correcao 0060 de integridade quantitativa do Romaneio validada
  localmente e ainda nao publicada;
- ultima migration no staging: `0059_romaneio_logistics_operational_contract.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Correcao 0060 - integridade quantitativa do Romaneio:

- o staging revelou que a view descontava somente quantidade confirmada e
  oferecia novamente quantidades ja comprometidas em rascunho/separacao;
- nenhum excesso estava persistido no cenario observado, mas a interface
  apresentava capacidade incorreta e induzia uma operacao invalida;
- a view agora separa pendencia de atendimento, quantidade comprometida e
  saldo livre para novo romaneio;
- trigger relacional com lock no item do pedido impede excesso inclusive fora
  da RPC;
- criacao e inclusao de item negam sem alçada antes de ler dados, usam o saldo
  livre e registram auditoria padronizada;
- a RPC textual antiga de separacao foi fechada; lote PA e reservado apenas
  pelo contrato relacional de Estoque;
- `PUBLIC` e `anon` perderam execucao nas RPCs operacionais do Romaneio;
- a tela oferece para nova separacao apenas itens com saldo livre positivo;
- nenhum dado operacional ou workbook foi adicionado ao Git.

## Validacao desta tarefa

- 14 testes direcionados dos contratos de Romaneio: aprovados;
- migrations `0001` a `0060` instaladas do zero no projeto separado
  `elite-validation-0060`;
- smoke quantitativo: `PG_VALIDATE_0060_WITH_SMOKE_OK`;
- regressao 0059: `PG_VALIDATE_0059_WITH_SMOKE_OK`;
- zero grant sweep: `66/66` negadas;
- lint PostgreSQL: nenhum erro de schema;
- ESLint, TypeScript e build Next.js: aprovados;
- runtime local ativo `elite-system` nao foi resetado, migrado ou alterado;
- migration 0060, commit, push e staging: pendentes de fechamento/publicacao.

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
- `expedicao`: Bloco 6 publicado; homologacao encontrou a falha quantitativa e
  fica bloqueada ate a publicacao e revalidacao da 0060;
- producao cloud: continua bloqueada por homologacao, backup, monitoramento,
  migracao historica ensaiada, seguranca externa e piloto;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

Revisar o diff, criar o commit unico da 0060 e, mediante autorizacao, publicar
branch, migration e deploy no staging. Repetir visualmente o cenario de saldo
livre, excesso negado e cancelamento liberando capacidade.

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
