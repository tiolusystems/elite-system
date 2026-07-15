# Elite System - estado atual

Atualizado em: 2026-07-15

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `F1.2c`, com o fluxo integral de Producao
  homologado no ambiente local;
- ultima migration aplicada localmente:
  `0058_restore_production_catalog_view_access.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

`F1.2c` - CQ, finalizacao, produto gerado e homologacao integral:

- `/producao/qualidade` apresenta somente OP iniciadas na fila de finalizacao;
- pH, densidade, volume, massa e temperatura sao obrigatorios;
- separador, conferente e ate tres formuladores sao escolhidos por identificador
  de pessoa ativa, sem parse de texto livre;
- resultado de CQ aceita aprovado, bloqueado ou reprovado;
- saidas PA usam produto e embalagem; saidas PI usam o produto-base;
- a RPC `finalizar_pcp_op` continua executando consumo, CQ e geracao de lotes em
  uma unica transacao auditada e idempotente;
- resultado bloqueado ou reprovado preserva o fato fisico e gera lote bloqueado
  para decisao posterior;
- finalizacoes recentes exibem lotes gerados e permitem calculo versionado das
  garantias sobre os lotes efetivamente consumidos;
- a tela legada `/pcp` reutiliza o mesmo formulario de finalizacao, removendo a
  duplicacao do bloco sensivel;
- a migration `0058` restaurou a leitura autenticada das views de garantias
  recriadas pela `0050`, mantendo `security_invoker`, RLS e menor privilegio;
- um cenario sintetico percorreu produto, formula, OP, reserva, inicio, CQ,
  finalizacao e lote PI pela interface;
- a reconciliacao confirmou MP `100 -> 90`, reserva `10 -> 0` e entrada PI
  `0 -> 10`, com quatro eventos correlacionados em `pcp_op:1:finish`.

`F1.1` esta publicada no staging. `F1.2a` esta no commit `a50dc74`, `F1.2b` no
commit `cf5c53d` e `F1.2c` aguarda o commit local desta validacao; todas
dependem de autorizacao antes do push. O workbook real e os relatorios gerados
permanecem fora do Git.

## Validacao desta tarefa

- migration `0058` instalada na cadeia limpa `0001` a `0058` e validada em
  upgrade;
- smoke de leitura autenticada: `PG_PRODUCTION_CATALOG_VIEW_ACCESS_OK`;
- cenario funcional completo pela interface: aprovado;
- reconciliacao relacional, estoque e auditoria: aprovada;
- 8 testes direcionados da `0058` e da trava destrutiva: aprovados;
- ESLint direcionado aos 7 arquivos TypeScript/TSX alterados: aprovado;
- TypeScript com `--noEmit`: aprovado;
- lint PostgreSQL: nenhum erro de schema;
- runtime local `/api/health`: `ok`, com backend configurado;
- guard central: a rota redireciona usuario sem sessao para login;
- homologacao visual autenticada de `F1.2a/F1.2b/F1.2c`: aprovada localmente e
  ainda nao repetida no staging.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas, Garantias, Ordens, Reservas, CQ e Finalizacao separados em
  telas operacionais; lotes e transformacoes ainda usam a tela legada;
- `estoque`: contratos de banco em validacao de negocio e interface operacional
  ainda acoplada aos fluxos de PCP;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise, classificacao e homologacao funcional do Excel: disponiveis
  localmente e sem escrita;
- mapa visual de implantacao: disponivel em `/modulos`;
- decisoes funcionais de Luciano: ainda nao preenchidas; I2 bloqueada;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- homologacao cloud: ambiente ativo, com login e banco declarando `staging`;
- producao cloud: continua bloqueada por homologacao, backup, monitoramento,
  migracao historica ensaiada, seguranca externa e piloto;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

`F1.2d` - separar Lotes, Estoque e Transformacoes:

1. consulta por MP, PA e PI com saldo fisico, reservado e disponivel;
2. validade, status e origem de cada lote;
3. liberacao auditada de lote bloqueado;
4. abertura e acompanhamento de reprocessamento;
5. transformacoes PA para PI, PI para PA e reenvasamento.

## Tarefa seguinte de produto

Repetir no staging o fluxo homologado localmente Base tecnica -> Formula -> OP
-> Reserva -> CQ -> Lote, somente depois de autorizacao de publicacao das
entregas locais.

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
