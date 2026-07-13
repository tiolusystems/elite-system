# Elite System - estado atual

Atualizado em: 2026-07-13

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `I1` - interface de analise integral do workbook;
- ultima migration aplicada localmente:
  `0055_dec_009_legacy_financial_fiscal_contract.sql`;
- ambiente ativo: Supabase local e banco de teste;
- publicacao externa: ainda nao autorizada;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

`I1` - analise integral do workbook historico, sem escrita:

- selecao local do `.xlsx` pela rota `/importacao-historica/mp`;
- identidade do arquivo por nome, tamanho, modificacao e SHA256;
- inventario de abas, tabelas, linhas, colunas, formulas e erros;
- classificacao de toda referencia por dominio, destino, status e regra;
- filtros por aba, dominio, status e texto;
- relatorio CSV somente de metadados;
- ponte server-only para o parser Python existente;
- temporario descartado em `finally`;
- nenhum batch, fato historico, movimento ou escrita PostgreSQL.

O workbook real e os relatorios gerados permanecem fora do Git.

## Validacao desta tarefa

- workbook real: 155 abas, 269 tabelas e 3.095 referencias confirmadas;
- fixture sanitizada: perfil integral `155/269/3.095` aprovado;
- testes Python e contrato web direcionados: 12 aprovados;
- ESLint direcionado: aprovado;
- TypeScript `--noEmit`: aprovado;
- lint integral, build, verificacao visual e `git diff --check`: registrados no
  fechamento do commit;
- migration criada ou cadeia completa executada: nenhuma, conforme escopo.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`, `estoque` e `pcp`: validacao de negocio;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise integral do Excel: disponivel localmente e sem escrita;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- producao cloud: bloqueada por homologacao, ambientes, backup, monitoramento,
  migracao historica ensaiada e seguranca externa;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

`I2` - carga integral na camada bruta auditavel:

1. criar batch de origem somente em Supabase local/banco de teste;
2. preservar workbook, aba, tabela, linha e hash;
3. carregar sem promover automaticamente a fatos operacionais;
4. garantir transacao, rollback e idempotencia;
5. separar validos, pendentes, rejeitados e ja existentes;
6. produzir reconciliacao e download de pendencias.

Nao iniciar simulacao nem aplicacao operacional antes de I2 estar validada.

## Tarefa seguinte apos a homologacao

Construir a lista operacional completa das ordens de producao.

## Tarefas temporariamente adiadas

- Suporte S0 (`DEC-001`);
- MFA TOTP (`DEC-002` a `DEC-004`);
- implementacao dos perfis combinaveis (`DEC-005`).

Essas tarefas permanecem autorizadas ou pendentes conforme
`docs/02_DECISOES_PENDENTES.md`, mas nao precedem a homologacao da importacao.

## Regra de manutencao

Ao fechar qualquer tarefa, substituir neste arquivo:

- tarefa concluida mais recente;
- validacao e resultado;
- proxima tarefa;
- tarefa seguinte;
- nova decisao bloqueante, quando houver.

Nao transformar este documento em diario. O historico pertence ao Git.
