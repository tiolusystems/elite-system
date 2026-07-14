# Elite System - estado atual

Atualizado em: 2026-07-14

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `F1.1`, central de cadastros tecnicos para a
  operacao industrial;
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

`F1.1` - primeira fatia funcional dos cadastros tecnicos:

- `/cadastros/tecnicos` apresenta a sequencia industrial e as pendencias dos
  catalogos;
- `/cadastros/unidades` consulta unidades e nutrientes normalizados e registra
  conversoes de MP pela RPC auditada existente;
- `/cadastros/materias-primas` permite buscar, filtrar, criar, editar por eixo
  de alcada e desativar MP sem escrita direta;
- `/cadastros/embalagens` consulta e cria embalagens, incluindo o vinculo de
  estoque com MP;
- `/cadastros/produtos` consulta e cria produtos PA/PI e suas apresentacoes
  vendaveis por embalagem;
- telas responsivas substituem a dependencia do formulario monolitico para
  estes fluxos, sem remover as operacoes anteriores;
- criacao de produto e validade inicial passaram a ser atomicas na RPC
  auditada `create_cad_produto_base`;
- grupo de produto agora e resolvido pelo catalogo relacional
  `cad_grupos_produto`, com `grupo_id`, texto canonico e rejeicao de grupo
  inexistente ou inativo;
- o gate integral alinhou o teste de ownership de subrotas ao contrato
  `match_children` e removeu uma chamada RPC direta remanescente da analise
  historica, que agora usa guarda de permissao auditada.

O workbook real e os relatorios gerados permanecem fora do Git.

## Validacao desta tarefa

- contratos direcionados de arquitetura, producao, RLS de MP, integridade e
  workbench tecnico: 31 testes aprovados;
- suite integral: 327 testes aprovados;
- ESLint direcionado: aprovado;
- TypeScript `--noEmit`: aprovado;
- build Next de producao: aprovado, incluindo as cinco novas rotas de
  cadastros tecnicos;
- `git diff --check`: aprovado;
- runtime local reiniciado pelo script oficial e `/api/health` retornou `ok`;
- inspecao visual autenticada ainda depende da publicacao desta entrega em
  staging ou de sessao local ativa no navegador de teste;
- migrations `0056` e `0057` aplicadas no Supabase local de teste;
- smoke transacional local do cadastro de produto: aprovado;
- cadeia `0001` a `0057` reconstruida do zero em PostgreSQL 17 descartavel e
  smoke `PG_TECHNICAL_CATALOG_WORKBENCH_OK`: aprovado.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial implementada e aguardando homologacao
  visual/funcional em staging;
- `estoque` e `pcp`: contratos de banco em validacao de negocio; interface
  operacional ainda concentrada em `/producao`;
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

Publicar e homologar `F1.1` no staging, sem dados reais:

1. revisar o diff e confirmar ausencia de segredo/dado operacional;
2. fazer commit unico da fatia funcional;
3. publicar a branch somente apos autorizacao de Luciano;
4. validar as cinco rotas em desktop, notebook e celular com sessao staging;
5. executar criacao e edicao controladas com dados de teste e conferir
   `action_logs`.

## Tarefa seguinte de produto

`F1.2` - decompor a interface de producao em telas operacionais para:

1. formulas e garantias;
2. ordens de producao e reservas;
3. CQ, finalizacao e produto gerado;
4. lotes, estoque e transformacoes PA/PI.

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
