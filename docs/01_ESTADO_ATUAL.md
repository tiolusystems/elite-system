# Elite System - estado atual

Atualizado em: 2026-07-17

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: UX-01B - shell global autenticado no commit
  `52f3dca`;
- entrega atual: UX-01C - macrociclo completo de Cadastros; a Onda 1 de
  Clientes e propriedades foi homologada visualmente para o fluxo atual de
  agricultor e esta fechada localmente sobre contratos existentes;
- ultima migration no staging: `0059_romaneio_logistics_operational_contract.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

UX-01C - Onda 1 - Clientes e propriedades:

- consulta, busca, criacao e edicao de clientes usam actions auditadas;
- UF e situacao usam controles governados com rotulos em PT-BR;
- propriedades e responsaveis sao lidos por relacionamentos existentes;
- estados vazio, sucesso e indisponibilidade usam linguagem operacional;
- desktop, notebook e mobile foram validados sem rolagem horizontal;
- Luciano homologou o layout para o fluxo atual de agricultor;
- revendas, lojas, distribuidores e filiais nao foram encaixados no formulario:
  exigem classificacao e contratos proprios antes de uso operacional;
- nenhuma migration, RPC, RLS, tabela ou regra de negocio foi alterada.

Entrega anterior:

UX-01C.1 - Central de Cadastros:

- `/cadastros` organiza os dados mestres em oito grupos funcionais;
- busca, grupo ativo, retorno a visao geral e acao contextual usam a mesma rota;
- somente o conteudo do grupo selecionado permanece visivel;
- os formularios existentes preservam as Server Actions e contratos auditados;
- os estados da central usam linguagem operacional;
- responsividade validada nas resolucoes previstas, sem rolagem horizontal;
- nenhuma migration, RPC, RLS, tabela ou regra de negocio foi alterada;
- nenhum dado operacional, workbook ou captura foi adicionado ao Git.

## Validacao desta tarefa

- 11 testes dirigidos de UX-01C.1 e regressao UX-01B: aprovados;
- ESLint: aprovado;
- TypeScript `--noEmit`: aprovado;
- build Next.js de producao: aprovado;
- `git diff --check`: aprovado;
- Supabase e banco local nao foram parados, resetados, migrados ou alterados;
- capturas de homologacao permaneceram fora do repositorio.

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

UX-01C - Onda 2 - Pessoas e vinculos comerciais, somente com contratos
existentes. O modelo de revendas e lojas permanece registrado como lacuna do
dominio Clientes e nao sera inventado na interface.

## Tarefa seguinte

Depois da Onda 2, executar a Onda 3 - Materias-primas e cadastros tecnicos.
As demais ondas do UX-01C seguem sem novo gate intermediario; UX-01D permanece
proibido ate a homologacao final de Cadastros.

## Sequencia vigente

Concluir o UX-01C como um unico macrociclo, sem gates intermediarios entre
Clientes, Pessoas, Materias-primas, Produtos, Embalagens, Logistica, Tecnicos e
Validacao. Depois da autorizacao estrutural: migrations proporcionais por
ownership, implementacao integrada, testes dirigidos e gate visual conjunto.
UX-01D a UX-01H permanecem posteriores e nao devem ser iniciados.

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
