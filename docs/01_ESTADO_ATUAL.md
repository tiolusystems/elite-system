# Elite System - estado atual

Atualizado em: 2026-07-29

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- HEAD funcional publicado: `35a1633`;
- sincronizacao local/remoto: `0/0`;
- Supabase de staging: ledger `0001` a `0117`;
- deployment ativo: `dpl_HmBGrrYnLhpvMHLgwtQKawtCvznF`;
- rollback preservado: `dpl_6XALShVXg5GB393q7wDjkWgQ6K5a`;
- URL: `https://elite-system-staging.vercel.app`;
- CI do HEAD funcional: `30472806418`, com `database-contract`,
  `python-tests` e `web-contract` aprovados;
- E2E operacional: `30473086759`, com o contrato dos cadastros canonicos,
  cinco resolucoes e cadeias SQL aprovados em ambiente descartavel;
- producao real, `main` e PWA: inalterados.

O estado detalhado acumulado ate esta data foi preservado em
`docs/historico/01_ESTADO_ATUAL_ATE_2026-07-28.md`. O Git e os documentos de
validacao preservam as evidencias anteriores.

## Tarefa em execucao

`OPS-GATE-01 - fechamento operacional total e tolerancia a erro humano`.

Escopo congelado:

- classificar todas as rotas e acoes existentes;
- repetir os fluxos operacionais positivos e negativos;
- corrigir defeitos objetivos P0 e P1;
- revisar manuais contextuais;
- consolidar estado atual, decisoes e evidencias;
- nao iniciar Relatorios Gerenciais, PWA, importacao historica definitiva,
  novo modulo ou nova regra de negocio.

A homologacao funcional das fontes historicas e a etapa `I2` permanecem
bloqueadas; nenhuma decisao de importacao e inferida. A ativacao de saldos
oficiais depende da `DEC-012`.

Matriz vigente:

- `docs/validacoes/OPS_GATE_01_MATRIZ.md`.

## Entregas deste gate

### Pedidos

- `6fd77b7` reorganizou a criacao na sequencia Cliente, Local, Itens,
  Programacao, Revisao e Liberacao;
- `7f50fee` separou consulta gerencial de criacao pelo vendedor: a conta sem
  identidade comercial vinculada nao recebe formulario que o banco recusaria;
- o staging mostra orientacao em PT-BR e preserva a consulta da carteira;
- nenhuma alcada foi ampliada e nenhuma migration foi criada.

### Manuais e inventario

- manuais operacionais genericos foram substituidos por sequencias,
  bloqueios, efeitos e historico especificos;
- o teste de cobertura descobre as rotas publicadas em `page.tsx`;
- a matriz OPS-GATE-01 inventaria paginas, route handlers e 121 Server Actions.

### Clientes

- a busca deixou de depender do recorte previamente carregado e passou a ser
  paginada, normalizada e executada no servidor;
- lista, ficha cadastral e novo cliente sao modos separados na mesma rota
  canonica, sem interface concorrente;
- a ficha utiliza a largura operacional disponivel e carrega relacoes somente
  para o cliente selecionado;
- a migration `0117` adicionou apenas a RPC de leitura governada, sem alterar
  dados, tabelas ou contratos de escrita;
- o contexto de busca e preservado ao abrir a ficha e ao retornar para a lista.

### Cadastros canonicos

- Materias-primas, Produtos PA/PI, Embalagens, Grupos de produto, Tipos de
  insumo e Unidades seguem o mesmo contrato visual homologado em Clientes;
- consulta, ficha e novo cadastro sao modos exclusivos, sem formularios
  concorrentes ou paineis laterais comprimindo a area operacional;
- a Central e a visao de Cadastros tecnicos direcionam explicitamente para as
  rotas canonicas e para o modo de novo cadastro;
- a terminologia de Unidades foi simplificada para o operador, sem alterar os
  valores internos ou contratos do banco;
- nenhuma migration, regra de negocio ou permissao foi alterada.

## Validacao vigente

- CI `30472806418`: aprovada;
- instalacao limpa `0001` a `0117`: aprovada no job `database-contract`;
- smokes SQL de integridade, rollout, industrial, comercial, estoque,
  Romaneio, Seguranca e importacoes: aprovados;
- regressao Python completa: 695 testes aprovados;
- E2E `30473086759`: aprovado em `1920 x 1080`, `1366 x 768`,
  `768 x 1024`, `390 x 844` e `360 x 800`;
- TypeScript, ESLint e build Next.js: aprovados;
- o smoke anterior de Pedidos confirmou o SHA `8d677ae` e o estado
  `Consulta disponivel, criacao indisponivel` para conta sem identidade de
  vendedor.
- `/api/health`: `status=ok` e `backendConfigured=true`;
- cinco verificacoes responsivas adicionais no staging nao encontraram
  rolagem horizontal, erro tecnico ou divergencia do SHA;
- o smoke autenticado de Clientes confirmou busca por codigo, abertura da
  ficha sem lista lateral, retorno preservando o filtro, novo cadastro isolado
  e SHA `6d5f782`;
- o smoke autenticado dos cadastros canonicos confirmou consulta, criacao e
  ficha em modos exclusivos, sem rolagem horizontal ou erro tecnico, no SHA
  `35a1633`;
- a migration de leitura `0117` foi aplicada unitariamente no staging.

## Classificacao

`OPS-GATE-01`: tecnicamente aprovado.

Todas as rotas e acoes publicadas estao classificadas na matriz. As funcoes
futuras permanecem bloqueadas de forma explicita. Os defeitos P1 encontrados
foram corrigidos; nenhum P0 permaneceu aberto.

O sistema esta protegido contra o catalogo de erros humanos previsiveis
testados. Isso nao constitui declaracao de infalibilidade.

## Proxima tarefa

Nenhuma nova frente esta autorizada. Depois do OPS-GATE-01, parar para a
homologacao operacional consolidada de Luciano.
