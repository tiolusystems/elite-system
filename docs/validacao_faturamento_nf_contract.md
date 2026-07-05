# Validacao do contrato de faturamento/NF

Data: 2026-07-05

## Escopo validado

Migration: `supabase/migrations/0025_faturamento_nf_contract.sql`.

Objetivo: validar o dominio fiscal com documentos, itens e eventos auditaveis.

## Decisoes cobertas

- `complementar` usa `nota_complementada_id`, nao `nota_pai_id`.
- `remessa_vinculada` usa `nota_pai_id` apontando para NF de `simples_faturamento`.
- `remessa_total` aponta para `romaneio_id` e nao tem NF pai.
- `fat_nota_fiscal_itens` referencia `pedido_item_id` e, quando a NF nasce de carga, tambem `romaneio_item_id`.
- `remessa_vinculada` nao duplica faturamento comercial; ela compoe a cobertura de remessa fiscal/fisica.
- RPC de emissao bloqueia quantidade faturada comercialmente acima da quantidade do item do pedido.
- RPC de emissao bloqueia `remessa_vinculada` acima da quantidade da NF simples pai para o mesmo item.
- `payload_json` de evento fiscal tem contrato por `tipo_evento`.

## Validacao executada

Banco descartavel local:

- PostgreSQL 18 em data dir `.tools/pg-validate-0025-20260705-113036`.
- Aplicadas migrations `0001` a `0025` com `ON_ERROR_STOP=1`.
- Resultado: migrations aplicadas com sucesso.

Smoke local:

- Arquivo local ignorado pelo Git: `.tools/smoke_faturamento_0025.sql`.
- NF `simples_faturamento` criada para pedido.
- NF `remessa_vinculada` criada para romaneio confirmado e NF simples pai.
- Bloqueio de duplicidade por `romaneio_item_id` validado.
- Bloqueio de `remessa_vinculada` acima da NF simples pai validado.
- NF `remessa_total` criada para outro pedido/romaneio.
- Bloqueio de excesso de quantidade faturada comercialmente validado.
- Carta de correcao registrada com `payload_json` obrigatorio.
- Auditoria `faturamento.nf.issue` e `faturamento.nf.correct` validada com `axis = fiscal_event`.

Resultado do smoke:

```text
SMOKE_FATURAMENTO_0025_OK
```

## Testes automatizados

Comandos executados:

```text
python -m unittest tests.test_faturamento_nf_decision_contract tests.test_faturamento_nf_migration_contract
python -m unittest discover -s tests -p "test*.py"
```

Resultado:

- contratos especificos de faturamento: OK;
- suite completa: OK.
