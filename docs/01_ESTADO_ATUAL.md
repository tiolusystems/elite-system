# Elite System - estado atual

Atualizado em: 2026-07-14

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: mapa visual de implantacao e estabilizacao da
  interface `I1.2`;
- ultima migration aplicada localmente:
  `0055_dec_009_legacy_financial_fiscal_contract.sql`;
- ambiente ativo: Supabase local e banco de teste;
- publicacao externa: autorizada para homologacao, mas ainda nao executada;
- cloud: Supabase CLI sem sessao autenticada, nenhum projeto Supabase vinculado
  e nenhum projeto ou CLI Vercel vinculado nesta maquina;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Mapa visual de implantacao e estabilizacao da homologacao do workbook:

- selecao do `.xlsx` inicia a analise sem depender de um segundo clique;
- falha de origem entre `localhost` e `127.0.0.1` corrigida no runtime Next;
- matriz das 269 fontes reorganizada para monitor grande, notebook e celular,
  sem exigir rolagem horizontal para decidir uma tabela;
- `/modulos` agora mostra os seis gates ate a operacao e a proxima validacao
  concreta de cada modulo;
- maturidade e acesso continuam vindo do PostgreSQL, sem uma segunda fonte de
  status;
- nenhuma rota, migration, tabela, dependencia ou regra de negocio foi criada.

O workbook real e os relatorios gerados permanecem fora do Git.

## Validacao desta tarefa

- contratos de arquitetura e runtime modular: 16 testes aprovados;
- contratos direcionados da importacao: 18 testes aprovados no commit anterior;
- ESLint direcionado e TypeScript `--noEmit`: aprovados;
- build Next de producao: aprovado, incluindo `/modulos` e
  `/importacao-historica/mp`;
- `git diff --check`: aprovado;
- runtime local reiniciado pelo script oficial e `/api/health` retornou `ok`;
- publicacao cloud nao executada por ausencia de autenticacao e vinculo, sem
  criar conta, custo ou projeto por suposicao;
- migration criada ou cadeia PostgreSQL executada: nenhuma.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`, `estoque` e `pcp`: validacao de negocio;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise, classificacao e homologacao funcional do Excel: disponiveis
  localmente e sem escrita;
- mapa visual de implantacao: disponivel em `/modulos`;
- decisoes funcionais de Luciano: ainda nao preenchidas; I2 bloqueada;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- homologacao cloud: autorizada e pendente de autenticacao/vinculo dos
  provedores;
- producao cloud: continua bloqueada por homologacao, backup, monitoramento,
  migracao historica ensaiada, seguranca externa e piloto;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

`C1` - publicar o primeiro ambiente cloud de homologacao, sem dados reais:

1. autenticar a Supabase CLI na conta que sera proprietaria da homologacao;
2. criar ou escolher projeto Supabase exclusivo de staging;
3. autenticar e vincular projeto Vercel exclusivo de staging;
4. configurar variaveis protegidas, URLs de Auth e migrations;
5. validar health, login, RLS, auditoria, gates de modulo e rollback;
6. registrar URL e evidencias sem versionar segredos.

O analisador do workbook permanece local. Nenhum `.xlsx` sera enviado ao
frontend cloud.

## Tarefa seguinte de produto

`F1` - revisar e homologar o fluxo mestre de operacao por telas, iniciando em
`cadastros -> estoque -> formulas -> OP -> CQ -> produto gerado`.

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
