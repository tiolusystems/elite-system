# Elite System - estado atual

Atualizado em: 2026-07-15

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `F1.2d`, com Lotes, Estoque e Transformacoes
  homologados no ambiente local;
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

`F1.2d` - Lotes, Estoque e Transformacoes separados do painel legado:

- `/producao/estoque` consulta MP, PA e PI por lote com saldo fisico,
  reservado e disponivel derivados do livro de movimentos;
- filtros cobrem familia, status, validade, codigo, item e origem;
- lote bloqueado PA/PI usa a RPC auditada existente para liberacao; saldo nunca
  e editado diretamente;
- `/producao/transformacoes` abre e acompanha OP do tipo `reprocessamento`,
  reutilizando formula, reserva, inicio, CQ e finalizacao existentes;
- PA para PI, PI para PA, reenvasamento e reprocessamento permanecem fatos de
  OP, com consumo e entrada correlacionados;
- o fluxo sintetico `OP-20260715-0000003` consumiu 10 kg do lote MP
  `HML-MP-0058-L01`, liberou a reserva e gerou o lote PI
  `PI-20260715-0000002` com 10 kg disponiveis;
- a reconciliacao confirmou MP `90 -> 80`, reserva `10 -> 0` e estoque PI
  agregado `10 -> 20`, com origem `pcp_op:3:finish`;
- as telas foram validadas em 1265 px sem rolagem horizontal;
- a escala proporcional da formula nao foi inventada: `DEC-013` registra a
  decisao funcional pendente e o fluxo atual executa o lote padrao absoluto.

`F1.2a`, `F1.2b` e `F1.2c` estao publicados na branch e no staging pelo commit
`a099a22`; a migration `0058` esta aplicada no Supabase de homologacao. A
homologacao visual autenticada no staging aguarda o login de Luciano. `F1.2d`
esta somente local e nao foi publicada. O workbook real e os relatorios gerados
permanecem fora do Git.

## Validacao desta tarefa

- 9 testes de contrato do workbench de Producao: aprovados;
- TypeScript com `--noEmit --incremental false`: aprovado;
- ESLint direcionado aos arquivos web alterados: aprovado;
- build Next.js de producao: aprovado com as duas novas rotas;
- cenario funcional local de reprocessamento: aprovado;
- reconciliacao de MP, reserva, lote PI e rastreabilidade: aprovada;
- ausencia de rolagem horizontal em Estoque e Transformacoes: confirmada;
- nenhuma migration nova e nenhuma escrita no Supabase cloud;
- homologacao visual autenticada de `F1.2a/F1.2b/F1.2c` no staging: pendente
  apenas do login de Luciano.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas, Garantias, Ordens, Reservas, CQ, Finalizacao, Lotes, Estoque
  e Transformacoes separados em telas operacionais;
- `estoque`: consulta operacional por lote e movimentos auditados integrados ao
  fluxo de OP; ativacao do saldo real continua dependente da `DEC-012`;
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

Retomar a homologacao autenticada no staging do bloco publicado
`F1.2a/F1.2b/F1.2c` assim que Luciano puder entrar. Depois, revisar e autorizar
o push/deploy de `F1.2d`; nenhuma nova funcionalidade deve ser iniciada antes
desse gate visual.

## Tarefa seguinte de produto

Resolver `DEC-013` antes de oferecer escala proporcional de formula por
quantidade de OP. O lote padrao absoluto permanece funcional enquanto a decisao
estiver pendente.

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
