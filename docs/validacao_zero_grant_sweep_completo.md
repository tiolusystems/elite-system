# Validacao - zero grant default deny sweep

Data: 2026-07-06

## Objetivo

Confirmar que os dominios operacionais ja fechados negam escrita quando o ator esta ativo, mas nao possui nenhuma concessao efetiva.

Este documento fecha o sweep antes de empilhar o endurecimento final do dominio `seguranca`.

## Artefato versionado

Script:

- `tests/sql/zero_grant_default_deny_sweep.sql`

O script e versionado porque faz parte do contrato de auditoria. Ele nao contem dado real.

Migration corretiva:

- `supabase/migrations/0037_pre_permission_guard_wrappers.sql`

A primeira execucao do sweep encontrou RPCs que validavam parametros antes de negar permissao. A `0037` corrige isso com wrappers de pre-guard: a assinatura publica nega alcada primeiro e so entao chama a implementacao auditada existente, renomeada para `_impl_0037` e sem execute para `public`/`authenticated`.

## Escopo

Dominios primarios cobertos:

- `cadastros`;
- `estoque`;
- `pcp`;
- `faturamento`;
- `financeiro`;
- `pedidos`.

Action keys satelites incluidas porque ja estao acopladas aos fluxos desses dominios:

- `romaneios`;
- `importacao`;
- `metas`.

Fora do escopo deste sweep:

- `seguranca`.

`seguranca` fica fora de proposito. A ordem aprovada e validar a fundacao operacional primeiro e so depois fechar o dominio mais sensivel.

## Modelo do ator zero-grant

O script cria o ator:

- id: `00000000-0000-4000-8000-000000000037`;
- nome: `Zero Grant Sweep Actor`;
- role: `auditoria`;
- status: `active`.

Em seguida:

- remove todos os overrides desse ator;
- forca `default_allowed = false` para os modulos do escopo no banco descartavel;
- usa `request.jwt.claim.sub` para simular `auth.uid()`;
- descobre as RPCs por `pg_proc`, action keys e uso de `begin_audited_rpc(...)` ou `require_current_user_permission(...)`.

Essa configuracao prova a regra "negado por padrao" sem depender de perfil existente ou permissao herdada.

## Criterios de aceite

Para cada RPC descoberta:

1. A chamada deve falhar com `not allowed: <action_key>`.
2. O action key negado deve estar dentro do escopo do sweep.
3. O action key negado deve aparecer no corpo da propria RPC.
4. `log_permission_denied(...)` deve persistir um log `denied` com `origin = 'zero_grant_sweep'`.
5. Nenhuma tabela operacional pode mudar contagem de linhas depois da tentativa negada.
6. Se a RPC retornar sucesso, o sweep falha.
7. Se a RPC validar regra de dominio antes de negar permissao, o sweep falha.

## Resultado

Status: aprovado em PostgreSQL descartavel limpo.

Marcador esperado em PostgreSQL descartavel:

```text
ZERO_GRANT_SWEEP_OK
```

Marcador obtido:

```text
ZERO_GRANT_SWEEP_OK: targets=58, denied=58, actor=00000000-0000-4000-8000-000000000037
PG_ZERO_GRANT_SWEEP_FULL_CHAIN_OK
```

## Achado corrigido

Antes da `0037`, o sweep falhou com `unexpected_exception_before_permission_denial` em RPCs de pedidos, PCP, faturamento, financeiro e metas. O motivo era consistente: algumas funcoes validavam `pedido_id`, `cliente_id`, `op_id`, `valor_recebido` ou status antes de chamar `begin_audited_rpc(...)`.

Esse comportamento nao persistia escrita indevida, mas revelava detalhes de validacao para ator sem alcada. A correcao aplicada foi criar wrappers de pre-permission guard, preservando a implementacao operacional e a auditoria de sucesso ja existentes.

## Observacao tecnica

O script mantem `permission_actions` porque essa tabela e catalogo de action keys e e referenciada por `action_logs`. O estado "zero grant" e representado por ator sem overrides e `default_allowed = false` no escopo do sweep, executado apenas em banco descartavel.

A `0038` centralizou duas escolhas de alcada em helpers `resolve_*_action_key`. O descobridor foi ampliado no gate `0039/0040` para seguir esses helpers. Sem essa correcao, a cobertura cairia silenciosamente de 58 para 56 RPCs; depois da correcao, o resultado voltou a `targets=58, denied=58`.
