# Elite System - estado atual

Atualizado em: 2026-07-16

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: UX-01B - shell global autenticado no commit
  `52f3dca`;
- entrega atual: UX-01C.1 - Central de Cadastros homologada visualmente,
  validada tecnicamente e ainda nao publicada;
- ultima migration no staging: `0059_romaneio_logistics_operational_contract.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

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

UX-01C.2 - Clientes e propriedades: revisar e organizar a experiencia completa
de identidade do cliente, propriedades com CNPJ proprio, enderecos, contatos,
vendedores vinculados, duplicidades e unificacao. Antes do codigo, aplicar o
gate de `docs/UX_DATA_GOVERNANCE_PTBR.md` e inventariar somente os campos dessa
tela. Nao iniciada.

## Sequencia vigente

Concluir UX-01C.2 com inventario de campos, implementacao, testes, capturas e
homologacao explicita. As demais telas de UX-01C e os blocos UX-01D a UX-01H
permanecem posteriores e nao devem ser iniciados antecipadamente.

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
