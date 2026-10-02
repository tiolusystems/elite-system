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
`elite-system`. O banco de producao deve ser identificado explicitamente antes
de qualquer ativacao. Push direto nao e permitido.

Branches `feature/*` sao temporarias, partem de `staging`, retornam a `staging`
por PR e sao removidas apos integracao bem-sucedida quando for seguro.

Deploys preview sao evidencia temporaria de engenharia. Nunca constituem
staging ou producao canonicos.

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

## Seguranca de producao

O banco de producao ainda nao esta identificado. Nenhum deploy de banco de
producao e autorizado ate que esse target seja explicitamente estabelecido e
validado.
