# ADR-018 - Governanca de ambientes e release

Status: APPROVED

Data: 2026-10-02

## Decisao

A topologia canonica do Elite System e:

```text
feature/* -> PR -> staging -> homologation -> release PR -> main
```

`staging` e a branch permanente de integracao e homologacao. Ela alimenta o
projeto Vercel `elite-system-staging`, usa o projeto Supabase
`elite-system-staging` e representa o ambiente fixo de homologacao. Push direto
nao e permitido.

`main` e a branch permanente de producao. Ela alimenta o projeto Vercel
`elite-system`. O banco de producao esta explicitamente estabelecido como
Supabase `elite-system-production`, ref `oncssgiocivoknwwcuuz`. Ele foi
provisionado vazio e permanece nao inicializado para migrations do Elite
System. Push direto nao e permitido.

Branches `feature/*` sao temporarias, partem de `staging`, retornam a `staging`
por PR e sao removidas apos integracao bem-sucedida quando for seguro.

Deploys preview sao evidencia temporaria de engenharia. Nunca constituem
staging ou producao canonicos.

## Staged production release

`main` e a branch de release de producao. Um merge para `main` pode criar um
deployment Vercel com `target=production`; esse deployment e um artefato
imutavel candidato a release, nao uma versao publicada no dominio canonico.
Nem `target=production` nem Vercel `READY` significam que o trafego canonico
foi alterado.

`Auto-assign Custom Production Domains` permanece desabilitado. O dominio
canonico de producao somente pode mudar por promocao explicita do exato
deployment validado. Antes dessa promocao, devem existir compatibilidade de
banco, ledger de migration, CI, smoke, SHA de release e identidade do
deployment validados. Rollback muda o roteamento para um deployment antes
validado; ele nao reescreve historico Git nem historico de banco.

Preview/staged deployment, deployment com `target=production` e trafego
canonico de producao sao estados distintos. A sequencia canonica e:

```text
feature/* -> PR -> staging -> homologation -> release PR -> main
-> Vercel staged production deployment
-> governed production database release
-> smoke / release identity
-> explicit Promote
-> canonical production traffic
```

## Evidencia de release

Uma release ou deploy so esta completa quando existem todas as evidencias
aplicaveis:

1. commit Git esperado;
2. CI obrigatorio aprovado;
3. target de deploy correto;
4. URL canonica servindo o commit esperado;
5. ledger de migration de banco compativel.

Vercel `READY` nao e equivalente a deploy canonico.

## Regra de banco

Web e banco de staging devem representar uma geracao de release compativel.
Web e banco de producao tambem devem representar uma geracao compativel.
Validacao destrutiva usa somente bancos descartaveis. Quando a compatibilidade
entre ordem de deploy importar, usar a estrategia aditiva
expand-migrate-contract.

A release de banco de staging segue `CI -> dry-run -> governed db push ->
ledger verification`. A release de banco de producao e manual e possui dois
gates distintos: `verify-production` executa somente a verificacao de
configuracao, leitura do ledger e dry-run, sem aprovacao humana e sem escrita;
`apply-production` repete essas verificacoes no mesmo run, aguarda aprovacao
explicita no ambiente `elite-system-production-approval`, revalida o banco,
executa o `db push` e registra o ledger posterior. Push normal para `main`
nunca aplica migrations de producao.

A autenticacao de release de banco usa conexao PostgreSQL direta pelo session
pooler do Supabase. A migration nao exige acesso a Management API: o CI recebe
somente credenciais de banco com escopo de ambiente, gera a URL de conexao de
forma efemera, codifica a senha para URL, mascara a URL completa e exige TLS.
Nenhum PAT faz parte da arquitetura canonica de migrations. Credenciais de
producao permanecem isoladas das credenciais de staging. As credenciais de
banco de producao ficam somente em `elite-system-production`. O ambiente
`elite-system-production-approval` contem apenas o gate humano, sem
credenciais ou variaveis de banco.

O deploy automatico de banco permanece desabilitado ate que as credenciais
sejam instaladas e a execucao verify-only seja aprovada. Provisionar um projeto
nao autoriza migration. A migration de producao nunca usa seed, reset ou repair
como fluxo normal de release.

## Seguranca de producao

O provisionamento do target de producao nao constitui ativacao de producao.
Nenhuma migration, conexao da aplicacao ou release de producao pode ocorrer ate
que o pipeline governado de release de producao seja estabelecido e validado.
