# Elite System - estado atual

Atualizado em: 2026-07-14

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `F1.2b`, Ordens de Producao e Reservas em rota
  operacional propria;
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

`F1.2b` - Ordens de Producao e Reservas:

- `/producao/ordens` apresenta fila filtravel por texto, status e tipo de OP;
- abertura de OP usa formula versionada e os tipos estoque, experimental,
  desenvolvimento, reprocessamento ou MAPA documental;
- cada OP exibe componentes planejados, quantidade reservada e reservas ativas;
- a selecao de lote usa identificador relacional e limita as opcoes a familia,
  item, status e saldo disponivel compativeis com o componente;
- reserva parcial ou total reduz somente o saldo disponivel; a baixa fisica
  continua pertencendo a finalizacao da OP;
- inicio e cancelamento permanecem nas RPCs auditadas existentes, com retorno
  de sucesso ou erro para a propria fila;
- OP em processo aponta para o fluxo atual de CQ enquanto `F1.2c` nao estiver
  separado;
- nenhuma migration, escrita direta ou nova dependencia entre modulos foi
  criada.

`F1.1` esta publicada no staging. `F1.2a` esta no commit local `a50dc74` e
`F1.2b` aguarda commit local; ambas dependem de autorizacao antes do push. O
workbook real e os relatorios gerados permanecem fora do Git.

## Validacao desta tarefa

- 20 testes direcionados de Producao e arquitetura: aprovados;
- ESLint direcionado aos arquivos alterados: aprovado;
- build Next de producao e TypeScript: aprovado, com 21 paginas e a rota
  `/producao/ordens` reconhecida;
- runtime local `/api/health`: `ok`, com backend configurado;
- guard central: a rota redireciona usuario sem sessao para login;
- nenhuma migration foi criada ou aplicada nesta fatia;
- homologacao visual autenticada de `F1.2a/F1.2b`: pendente de publicacao no
  staging.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas, Garantias, Ordens e Reservas separadas em telas operacionais;
  CQ, finalizacao, lotes e transformacoes ainda usam a tela legada compartilhada;
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

`F1.2c` - separar CQ, finalizacao e produto gerado:

1. fila exclusiva de OP em processo;
2. pH, densidade, volume, massa e temperatura;
3. separador, conferente e formuladores;
4. resultado aprovado, bloqueado ou reprovado;
5. saidas PA/PI e lotes gerados na mesma transacao.

## Tarefa seguinte de produto

`F1.2d` - separar lotes, estoque e transformacoes PA/PI.

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
