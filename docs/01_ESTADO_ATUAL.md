# Elite System - estado atual

Atualizado em: 2026-07-14

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `F1.2a`, central de Producao com Formulas e
  Garantias em rotas operacionais proprias;
- ultima migration aplicada localmente:
  `0057_product_group_relational_resolution.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

`F1.2a` - primeira decomposicao operacional de Producao:

- `/producao` passou a ser a central do fluxo industrial, com estado real do
  PostgreSQL e acesso direto a cada etapa;
- `/producao/formulas` concentra criacao append-only, historico, componentes,
  ativacao e referencias vigentes;
- `/producao/garantias` separa garantia declarada de produto, analise de lote
  de MP e consulta das versoes vigentes;
- o shell de Producao centraliza navegacao, ambiente, falhas e feedback de
  operacoes, evitando que cada tela redefina o contrato visual;
- a tela legada `/pcp` passou a reutilizar os mesmos componentes de Formulas e
  Garantias, sem duplicar a logica de escrita;
- as Server Actions continuam chamando somente as RPCs auditadas existentes;
  nenhuma migration ou escrita direta foi adicionada;
- os redirecionamentos de sucesso e erro retornam para a subarea operacional
  que originou a acao;
- a entrega usa grade responsiva para monitor amplo, notebook e celular.

`F1.1` esta publicada no staging. `F1.2a` permanece somente na branch local ate
commit e autorizacao de publicacao. O workbook real e os relatorios gerados
permanecem fora do Git.

## Validacao desta tarefa

- 25 testes direcionados de Producao, cadastros e arquitetura: aprovados;
- ESLint direcionado aos arquivos alterados: aprovado;
- build Next de producao e TypeScript: aprovado, com 20 paginas e as rotas
  `/producao/formulas` e `/producao/garantias` reconhecidas;
- runtime local `/api/health`: `ok`, com backend configurado;
- guard central: ambas as rotas redirecionam usuario sem sessao para login;
- nenhuma migration foi criada ou aplicada nesta fatia;
- homologacao visual autenticada de `F1.2a`: pendente de publicacao no staging.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas e Garantias separadas em telas operacionais; Ordens, CQ,
  finalizacao, lotes e transformacoes ainda usam a tela legada compartilhada;
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

`F1.2b` - separar Ordens de Producao e Reservas em telas operacionais:

1. fila de OP por status e prioridade;
2. abertura de OP por formula vigente;
3. componentes planejados e lotes disponiveis;
4. reserva parcial ou total por componente;
5. inicio e cancelamento com feedback auditado.

## Tarefa seguinte de produto

`F1.2c` - separar CQ, finalizacao e produto gerado; depois `F1.2d` - lotes,
estoque e transformacoes PA/PI.

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
