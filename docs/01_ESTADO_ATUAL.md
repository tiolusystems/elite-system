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

Implantacao do protocolo de eficiencia de execucao:

- entrada curta em `docs/00_MAPA_EXECUTIVO.md`;
- estado e proxima tarefa neste arquivo;
- decisoes abertas em `docs/02_DECISOES_PENDENTES.md`;
- obrigacao de atualizar este estado ao concluir cada tarefa;
- gate explicito contra mudanca arquitetonica sem autorizacao.

Arquivos de governanca foram alterados. Nenhum modulo, rota, tabela, RPC ou
dependencia de negocio foi modificado.

## Validacao desta tarefa

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

Preparar proposta arquitetonica para mover a solicitacao de troca de email da
tela de login para uma area autenticada de Suporte.

Antes de codar:

1. verificar se Suporte ja existe como responsabilidade de modulo atual;
2. se nao existir, apresentar opcoes sem criar modulo unilateralmente;
3. registrar a autorizacao em `docs/02_DECISOES_PENDENTES.md`;
4. somente depois alterar rota, navegacao e ownership.

## Tarefa seguinte

Apresentar o desenho de MFA TOTP compativel com Android e iOS, incluindo
cadastro por QR Code, desafio no login, recuperacao e exigencia AAL2. Essa
mudanca toca o boundary de autenticacao e depende de autorizacao arquitetonica.

## Regra de manutencao

Ao fechar qualquer tarefa, substituir neste arquivo:

- tarefa concluida mais recente;
- validacao e resultado;
- proxima tarefa;
- tarefa seguinte;
- nova decisao bloqueante, quando houver.

Nao transformar este documento em diario. O historico pertence ao Git.
