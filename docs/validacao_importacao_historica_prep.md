# Validacao da migration 0034 - preparo para importacao historica

Data da validacao: 2026-07-06

## Objetivo

Validar o preparo estrutural minimo para uma futura importacao historica do Excel, sem importar dados reais e sem implementar o importador.

## Escopo validado

- `user_profiles` passa a identificar ator nao-humano por `is_system_actor` e `system_actor_key`.
- O ator `Migracao Historica` fica inativo por design.
- Tabelas centrais recebem `origem_dados` e `codigo_legado` nulos.
- `origem_dados` aceita somente `sistema`, `excel_legado` ou `null`.
- A receita de RLS/RPC registra que novas regras nao podem presumir nascimento por RPC ao vivo.

## Tabelas preparadas

- `com_pedidos`;
- `com_pedido_itens`;
- `cad_clientes`;
- `cad_pessoas_comerciais`;
- `cad_materias_primas`;
- `cad_produtos_base`;
- `cad_embalagens`;
- `cad_produto_embalagens`.

## Validacao executada

Comandos:

```text
python -m unittest tests.test_importacao_historica_prep_contract
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Validacao em PostgreSQL descartavel:

```text
PG_VALIDATE_0034_WITH_SMOKE_OK
```

Smoke `.tools/smoke_importacao_historica_0034.sql` validou:

- migration aplicada do zero ate `0034`;
- ator `Migracao Historica` existente no banco descartavel, inativo e marcado como `is_system_actor`;
- `current_actor_id()` nao trata ator inativo como usuario operacional ativo;
- colunas `origem_dados` e `codigo_legado` existem nas tabelas preparadas;
- `origem_dados = excel_legado` e aceito;
- `origem_dados` invalido falha por constraint;
- nenhum dado real foi versionado.

## Decisoes para revisao

- Confirmar se os marcadores devem entrar tambem em NF, recebimentos, romaneios, lotes e movimentos de estoque.
- Confirmar se o ator de sistema sera provisionado por migration ou por bootstrap controlado do ambiente Supabase.
- Confirmar se `codigo_legado` deve ter unicidade por tabela ou por lote de importacao.
