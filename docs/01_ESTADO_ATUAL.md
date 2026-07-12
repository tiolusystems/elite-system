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

Implementar a fase `S0` de Suporte conforme `DEC-001` e ADR-005: area
autenticada `/suporte`, apresentada como **Ajuda e Solicitacoes**, pertencente
ao `core`, sem criar modulo autonomo. A implementacao devera preservar em
`seguranca` toda acao sensivel e retirar a solicitacao de troca de e-mail da
tela publica de login.

## Tarefa seguinte

Apresentar o desenho de MFA TOTP compativel com Android e iOS, incluindo
cadastro por QR Code, desafio no login, recuperacao e exigencia AAL2. Essa
mudanca toca o boundary de autenticacao, depende de autorizacao arquitetonica
e definira a protecao adicional das operacoes criticas de `DEC-005`.

## Regra de manutencao

Ao fechar qualquer tarefa, substituir neste arquivo:

- tarefa concluida mais recente;
- validacao e resultado;
- proxima tarefa;
- tarefa seguinte;
- nova decisao bloqueante, quando houver.

Nao transformar este documento em diario. O historico pertence ao Git.
