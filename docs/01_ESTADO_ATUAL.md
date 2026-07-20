# Elite System - estado atual

Atualizado em: 2026-07-20

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: UX-01B - shell global autenticado no commit
  `52f3dca`;
- entrega atual: gate critico de RLS e escrita direta; UX-01C e a promocao do
  Preview permanecem pausados;
- ultima migration validada localmente: `0066_close_direct_write_and_rpc_exposure.sql`;
- ultima migration no staging confirmada por ledger: `0066_close_direct_write_and_rpc_exposure.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

UX-01C.3 - Pessoas e vinculos comerciais:

- homonimos sao revisados, confirmados com justificativa e auditados;
- codigo legado possui unicidade normalizada e criacao concorrente protegida;
- aliases iguais podem pertencer a pessoas distintas sem repeticao interna;
- areas comerciais usam relacionamentos por ID e vigencia temporal;
- desativacao e reativacao preservam o historico e nao reabrem vinculos;
- interface PT-BR oferece consulta, filtros, criacao, edicao e gestao dos
  vinculos sem expor enums ou erros tecnicos;
- instalacao limpa, upgrade, smoke e concorrencia foram validados somente em
  projetos descartaveis `elite-validation-*`.

Entrega institucional paralela - assinatura da desenvolvedora:

- assinatura reutilizavel `by ☧ SYSTEMS` aplicada exclusivamente nos creditos
  de desenvolvedor ja existentes nos rodapes publico e autenticado;
- identidade, paleta, tipografia, navegacao, favicon e componentes operacionais
  do Elite System preservados;
- nenhum ativo raster ou SVG, dependencia, banco, migration, Supabase, regra de
  negocio ou seguranca foi alterado;
- teste de contrato, ESLint, build Next.js e verificacao visual desktop/mobile
  aprovados; captura do rodape autenticado depende de sessao real e nao foi
  obtida por contorno de autenticacao;
- nenhum rebranding foi realizado.

Entrega anterior:

UX-01C.4 - Tipos de insumo e classificacao de materias-primas:

- catalogo relacional, FK opcional, RLS e seis RPCs auditadas na migration 0063;
- texto legado preservado e bloqueado para novas escritas operacionais;
- nenhuma classificacao historica foi inferida;
- fila de revisao explicita para materias-primas sem decisao humana;
- tela PT-BR permite criar, editar, ativar, inativar e classificar por ID;
- instalacao limpa, upgrade e smoke ocorreram somente em ambiente descartavel;
- runtime local ativo e dados existentes permaneceram intactos.
- unidade base passou a ser enviada por FK de catalogo;
- SKU possui unicidade normalizada e protecao concorrente no banco;
- homonimos exigem revisao, confirmacao motivada e auditoria.

Entrega de base:

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

- auditoria somente leitura do staging: 132 tabelas publicas, todas com RLS,
  zero escrita direta para `anon`, `authenticated` ou `PUBLIC` e zero politica
  permissiva de escrita residual;
- instalacao limpa `0001` a `0066` e upgrade `0065 -> 0066`: aprovados somente
  em projetos `elite-validation-*`;
- gate de metadados: aprovado;
- sweep zero-grant: 79 de 79 RPCs negadas com auditoria;
- Data API: 99 tentativas de escrita em 11 dominios e tres contextos, sem
  alteracao dos fingerprints;
- smoke de RPC governada com permissao valida: aprovado;
- ESLint e build Next.js: aprovados;
- staging recebeu exclusivamente a migration 0066; a auditoria final read-only,
  o gate SQL, o health-check e a resposta da tela de login foram aprovados;
- detalhes: `docs/auditoria_rls_escrita_direta_0066.md`.

Validacao anterior da UX-01C.3:

- smoke SQL 0065 em instalacao limpa e upgrade: aprovado;
- lock concorrente: uma criacao persistida e a concorrente recusada apos
  recalculo de candidatos;
- lint PostgreSQL: aprovado;
- ESLint, TypeScript, build Next.js e 46 testes dirigidos: aprovados;
- desktop `1366 x 768` e mobile `390 x 844`: aprovados sem rolagem horizontal;
- runtime Supabase ativo nao foi parado, resetado, migrado ou alterado;
- capturas de homologacao permanecem fora do repositorio.

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

Continuar o UX-01C com Produtos, apresentacoes, embalagens e conversoes,
inventariando contratos existentes antes de qualquer nova alteracao estrutural.

## Tarefa seguinte

Depois, concluir Veiculos, logistica, cadastros tecnicos e validacao consolidada.
UX-01D permanece proibido ate a homologacao final de Cadastros.

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
