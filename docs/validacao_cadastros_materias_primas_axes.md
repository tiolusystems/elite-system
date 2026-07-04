# Validacao de materias-primas por eixo de risco

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0017_cadastros_materias_primas_axes.sql`, que estende `cadastros` para materia-prima por eixo de risco:

- identidade;
- SKU;
- tecnico;
- politica de estoque;
- regulatorio;
- desativacao.

## Ambiente usado

- Banco PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55433`.
- Cluster temporario em `.tools/pg-cadastros-rls`.
- Database final de smoke: `elite_cadastros_mp_axes_fresh`.
- Sem uso de banco operacional, Supabase cloud, planilhas ou dados reais.

## Resultado das migrations

Todas as migrations `0001` a `0017` aplicaram com sucesso em banco descartavel limpo.

## Action keys adicionadas

| Action key | Uso |
|---|---|
| `cadastros.materias_primas.update.identity` | nome e tipo |
| `cadastros.materias_primas.update.sku` | codigo legado e SKU corrigido |
| `cadastros.materias_primas.update.technical` | unidade base e densidade |
| `cadastros.materias_primas.update.stock_policy` | estoque minimo |
| `cadastros.materias_primas.update.regulatory` | NCM, IBAMA e ADS |
| `cadastros.materias_primas.deactivate` | soft-delete por `status = inactive` |

As seis nascem com `default_allowed = true` para respeitar a fase de autonomia inicial, mas ja ficam separadas para retirada futura por checkbox/alcada.

## Validacoes no banco

| Eixo | Validacao |
|---|---|
| `identity` | nome e nome normalizado obrigatorios |
| `sku` | SKU obrigatorio, maiusculo, sem espaco e ate 80 caracteres |
| `technical` | unidade base obrigatoria; densidade nula ou positiva |
| `stock_policy` | estoque minimo nulo ou maior/igual a zero |
| `regulatory` | NCM nulo ou com exatamente 8 digitos |
| `deactivate` | motivo obrigatorio e status anterior diferente de `inactive` |

## Smoke tests executados

| Caso | Resultado esperado | Resultado obtido |
|---|---|---|
| Usuario ativo cria MP | log `cadastros.materia_prima_created` | OK |
| Edita identidade | log `cadastros.materia_prima_identity_updated` com before/after | OK |
| Edita SKU | log `cadastros.materia_prima_sku_updated` com SKU antes/depois | OK |
| SKU com espaco | RPC falha com validacao de SKU | OK |
| Edita tecnico | log `cadastros.materia_prima_technical_updated` | OK |
| Densidade negativa | RPC falha com validacao de densidade | OK |
| Edita politica de estoque | log `cadastros.materia_prima_stock_policy_updated` | OK |
| Estoque minimo negativo | RPC falha com validacao de estoque minimo | OK |
| Edita regulatorio | log `cadastros.materia_prima_regulatory_updated` | OK |
| NCM invalido | RPC falha com validacao de NCM | OK |
| Update direto em `cad_materias_primas` | erro de permissao | OK |
| Override nega `update.regulatory` | RPC falha com `not allowed` | OK |
| Negativa capturada pela aplicacao | `log_permission_denied(...)` registra `denied` | OK |
| Desativa MP | `status` muda para `inactive` | OK |
| Usuario sem perfil | `can_current_user(...) = false` | OK |
| Usuario inativo | `can_current_user(...) = false` | OK |
| Role `anon` executando RPC | erro de permissao | OK |

## Evidencia de auditoria no smoke final

Contagem final em `action_logs` para `cadastros.materias_primas.%`:

| Action | Action key | Status | Total |
|---|---|---|---|
| `cadastros.materia_prima_created` | `cadastros.materias_primas.create` | `success` | 1 |
| `cadastros.materia_prima_identity_updated` | `cadastros.materias_primas.update.identity` | `success` | 1 |
| `cadastros.materia_prima_sku_updated` | `cadastros.materias_primas.update.sku` | `success` | 1 |
| `cadastros.materia_prima_technical_updated` | `cadastros.materias_primas.update.technical` | `success` | 1 |
| `cadastros.materia_prima_stock_policy_updated` | `cadastros.materias_primas.update.stock_policy` | `success` | 1 |
| `cadastros.materia_prima_regulatory_updated` | `cadastros.materias_primas.update.regulatory` | `success` | 1 |
| `cadastros.materia_prima_deactivated` | `cadastros.materias_primas.deactivate` | `success` | 1 |
| `seguranca.permissao_negada` | `cadastros.materias_primas.update.regulatory` | `denied` | 1 |

## Decisao

`materias_primas` fica validado como cadastro por eixo de risco, com validacao basica no banco.

Proximo refinamento recomendado: levar o mesmo desenho para produtos, embalagens e conversoes, ou abrir UI de edicao por eixo para validar o fluxo visual antes de seguir com mais subdominios.
