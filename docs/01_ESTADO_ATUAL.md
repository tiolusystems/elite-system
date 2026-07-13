# Elite System - estado atual

Atualizado em: 2026-07-12

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `DEC-011` - vinculos comerciais temporais, aguardando commit;
- ultima migration aplicada localmente: `0052_dec_011_client_seller_temporal_links.sql`;
- ambiente ativo: Supabase local e banco de teste;
- publicacao externa: ainda nao autorizada;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Implementacao de `DEC-011` - vinculos cliente, vendedor, propriedade e area:

- papeis `cadastrou`, `atende`, `gerencia` e `apoio` normalizados por FK;
- `cadastrou` preservado como fato sem conceder visibilidade atual;
- vinculo direto pode valer para cliente inteiro ou propriedade especifica;
- cliente/area e pessoa/area possuem vigencia e linhagem historica;
- pedido pode referenciar o vinculo comercial exato usado na criacao;
- historico pendente nao concede visibilidade nem entra no fluxo vivo.

Nenhum dado do workbook real foi gravado ou versionado. A entrega contem
somente schema, dados tecnicos de referencia, testes e documentacao.

## Validacao desta tarefa

- cadeia limpa `0001` a `0052`: aprovada;
- upgrade descartavel `0051` para `0052`: `DEC_011_UPGRADE_CHAIN_OK`;
- smoke transacional em ambiente `test`: `DEC_011_CLIENT_SELLER_TEMPORAL_LINKS_SMOKE_OK`;
- gates de arquitetura, Producao e importacao MP: aprovados;
- PostgreSQL lint: sem erro de schema;
- testes Python direcionados: 52 aprovados.

## Tarefa em andamento

`T3` - contratos relacionais obrigatorios antes do importador integral.

`DEC-007`, `DEC-008` e `DEC-011` foram concluidas. As demais decisoes estao autorizadas e serao
implementadas isoladamente, cada uma com migration, testes e commit proprios.

Ordem vigente: `DEC-010`, `DEC-006` e `DEC-009`.

## Validacao do gate de importacao

- inventario: 155/155 abas classificadas;
- cobertura: 3.095 referencias de coluna classificadas e zero
  `review_required`;
- ambiente PostgreSQL: `test`, consultado em modo somente leitura;
- workbook e dados operacionais: fora do Git;
- codigo, migration, rota, RPC e configuracao Auth: inalterados.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`, `estoque` e `pcp`: validacao de negocio;
- demais modulos: validacao tecnica ou tela dedicada pendente;
- producao cloud: bloqueada por homologacao, ambientes, backup, monitoramento,
  migracao historica ensaiada e seguranca externa;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

Implementar `DEC-010` - campanhas, pontos e premiacao - sem
iniciar o importador e sem trabalhar nas tarefas temporariamente adiadas.

## Proxima tarefa apos DEC-006 a DEC-011

Construir o importador historico integral, em ordem:

1. contratos relacionais aprovados;
2. upload e analise integral sem escrita;
3. simulacao com validos, pendentes, rejeitados e existentes;
4. aplicacao transacional e idempotente somente no banco de teste;
5. rollback, rastreabilidade, reconciliacao e download de pendencias;
6. homologacao Excel -> sistema -> OP.

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
