# Elite System - estado atual

Atualizado em: 2026-07-12

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega funcional: `ea87791` - fronteira de privilegio administrativo;
- ultima migration aplicada localmente: `0049_security_admin_privilege_boundary.sql`;
- ambiente ativo: Supabase local e banco de teste;
- publicacao externa: ainda nao autorizada;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Registro arquitetonico de `DEC-005` - matriz inicial de perfis e permissoes:

- sete perfis iniciais autorizados;
- contas individuais e perfis combinaveis definidos;
- perfil tratado como conjunto versionado de permissoes atomicas;
- backend e banco mantidos como fonte da autorizacao efetiva;
- operacoes criticas vinculadas a auditoria e futuro MFA/reautenticacao;
- ADR-006 registra alternativas, invariantes, transicao e rollback.

Somente documentacao foi alterada. Nenhum perfil, usuario, modulo, rota,
tabela, RPC, migration, autorizacao ou configuracao Auth foi implementado.

## Validacao desta tarefa

- contrato documental de perfis/permissoes: aprovado (`PROFILE_PERMISSION_DOCUMENTATION_OK`);
- `tests.test_architecture_navigation_contract`: 6 testes aprovados;
- `git diff --check`: aprovado;
- suite completa: deliberadamente dispensada por ser tarefa documental `T1`.

## Tarefa em andamento

`T2` - fluxo integral de importacao historica do Excel.

A descoberta obrigatoria anterior ao codigo foi concluida:

- workbook real localizado e analisado localmente, sem versionamento;
- 155 abas, 269 tabelas estruturadas e 114 nomes definidos inventariados;
- todas as colunas estruturadas e usadas fora de tabela classificadas;
- matriz Excel para schema produzida sem gravacao no banco;
- Supabase ativo confirmado como ambiente `test`;
- importador atual confirmado como parcial: SQLite generico, fundacao Supabase
  especifica de MP e tela web analitica, sem upload/aplicacao integral.

O gate arquitetonico encontrou destinos relacionais indispensaveis ausentes.
Por regra expressa da tarefa, nenhuma migration, rota, RPC ou aplicador foi
criado. As lacunas estao em
`docs/importacao-historica/01_MATRIZ_EXCEL_SCHEMA.md` e nas decisoes
`DEC-006` a `DEC-011`.

## Validacao do gate T2

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

## Proxima decisao bloqueante

Luciano deve autorizar ou ajustar as recomendacoes de `DEC-006` a `DEC-011`.
Elas definem como preservar formulas/OP historicas, catalogos tecnicos,
embalagens, parcelas/posicoes legadas, campanhas e papeis do vinculo
cliente-vendedor sem inventar fatos.

## Proxima tarefa apos autorizacao

Retomar `T2` e implementar, em ordem:

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
