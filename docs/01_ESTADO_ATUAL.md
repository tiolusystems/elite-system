# Elite System - estado atual

Atualizado em: 2026-07-13

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `I1.1` - classificacao das fontes e politica de corte;
- ultima migration aplicada localmente:
  `0055_dec_009_legacy_financial_fiscal_contract.sql`;
- ambiente ativo: Supabase local e banco de teste;
- publicacao externa: ainda nao autorizada;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

`I1.1` - classificacao estrutural das fontes e corte de estoque, sem escrita:

- 269 tabelas com exatamente uma classificacao principal;
- catalogo sanitizado e fingerprints de identidade/schema versionados;
- 3.095 referencias ligadas a uma fonte, sem omissao;
- fontes oficiais separadas de relatorios, calculos e paineis;
- schema drift bloqueia somente a tabela alterada;
- matriz exata mantida somente no diretorio local ignorado pelo Git;
- politica de historico pre-corte, inventario fisico e movimentos pos-corte;
- quatro pendencias preservadas sem inferencia: densidade, pH, contato e UF;
- nenhuma carga, migration, fato historico, movimento ou escrita PostgreSQL.

O workbook real e os relatorios gerados permanecem fora do Git.

## Validacao desta tarefa

- workbook real: perfil `155/269/3.095`, 26.397 linhas e UTF-8 valido;
- classificacoes: 245 formula, 8 master, 7 transacao, 5 reconciliacao,
  2 calculo derivado e 2 painel/resumo;
- tabelas sem classificacao, referencias sem vinculo, drift e rejeicoes: zero;
- pendencias mantidas: quatro;
- testes direcionados Python/web: 23 aprovados;
- ESLint direcionado, TypeScript `--noEmit` e build Next: aprovados;
- `git diff --check`: aprovado;
- migration criada ou cadeia PostgreSQL executada: nenhuma, conforme escopo.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`, `estoque` e `pcp`: validacao de negocio;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise e classificacao integral do Excel: disponiveis localmente e sem escrita;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- producao cloud: bloqueada por homologacao, ambientes, backup, monitoramento,
  migracao historica ensaiada e seguranca externa;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

`I2` - carga bruta auditavel somente das fontes oficiais selecionadas:

1. criar batch de origem somente em Supabase local/banco de teste;
2. aceitar somente `source_master`, `source_transaction` e `source_formula`;
3. preservar workbook, aba, tabela, linha e hash;
4. carregar sem promover automaticamente a fatos operacionais;
5. garantir transacao, rollback e idempotencia;
6. separar validos, pendentes, rejeitados e ja existentes;
7. produzir reconciliacao e download de pendencias.

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
