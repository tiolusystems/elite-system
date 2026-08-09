# Validacao - gate de arquitetura e integridade

Data: 2026-07-10

## Escopo

- migrations `0039` e `0040`;
- cadeia completa `0001` a `0040`;
- `supabase/seed.sql`;
- RLS, privilegios diretos, PK, FK, constraints compostas e indices;
- normalizacao de papeis e participantes CQ;
- unidade-base MP historicamente estavel;
- CI e dependencias web reproduziveis.

## Banco descartavel

Validacao executada em PostgreSQL 18 local, banco `elite_architecture_fresh`, porta temporaria `59141`. Nenhum banco real ou banco oficial de teste foi utilizado.

```text
PG_FULL_CHAIN_WITH_SEED_OK
PG_ARCHITECTURE_INTEGRITY_GATE_OK
ZERO_GRANT_SWEEP_OK: targets=58, denied=58
PG_FRESH_SMOKES_OK
```

## Medidas do schema final

```text
tables|77
tables_without_pk|0
foreign_keys|285
unvalidated_constraints|0
write_policies|0
authenticated_nonselect_table_privileges|0
```

O ultimo indicador considera `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` e `TRIGGER`.

## Comportamentos testados

- papeis comerciais expandidos em linhas relacionais com vigencia;
- unidade-base MP rejeita alteracao depois de movimento;
- FK composta rejeita lote de uma MP combinado com identidade de outra;
- constraints novas existem, estao validadas e possuem indice de suporte;
- policies legadas de escrita nao sobrevivem;
- usuario web nao possui privilegio direto de escrita/truncate;
- sweep segue helpers `resolve_*_action_key` e preserva cobertura `58/58`.

## Testes de codigo

```text
python -m unittest discover -s tests -p "test*.py"
Ran 183 tests
OK

PNPM_FROZEN_LOCK_OK
WEB_LINT_OK
WEB_BUILD_OK
```

## Geracao de tipos

A Supabase CLI local tentou gerar tipos com `--db-url`, mas a versao `2.109.0` usa container nessa operacao. O Docker engine local continua parado, portanto nenhum arquivo incompleto foi mantido.

O CI gera `database.types.ts` contra Supabase descartavel e publica o artefato `elite-database-types`. Incorporar esse arquivo ao cliente tipado e o proximo commit de contrato banco/aplicacao.

## Dados versionados

Somente codigo, migration, teste e documentacao. Nenhum banco, dump, planilha, credencial ou dado comercial foi adicionado ao Git.
