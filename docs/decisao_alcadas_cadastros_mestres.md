# Decisao de alcadas para cadastros mestres

Data: 2026-07-04

## Objetivo

Evitar copiar mecanicamente o padrao `own/any` de clientes para todos os cadastros.

O padrao tecnico esta validado:

- RPC `security definer`;
- `action_key` granular;
- `before_json` e `after_json`;
- soft-delete por `status = inactive`;
- negativa persistente via `log_permission_denied(...)`;
- teste estatico contra hard-delete e `.rpc()` direto.

Mas o eixo de alcada muda conforme o dominio.

## Regra geral

`own/any` so deve existir quando houver dono operacional claro do registro.

Se o cadastro for compartilhado ou tecnico, a alcada deve ser separada por tipo de campo, papel responsavel ou risco da alteracao.

## Clientes

Eixo aprovado: escopo por autoria como primeira versao, com evolucao futura para carteira/vendedor/gerente.

Action keys ja validadas:

| Action key | Uso |
|---|---|
| `cadastros.clientes.update.own` | editar cliente criado pelo proprio usuario |
| `cadastros.clientes.update.any` | editar cliente fora do escopo proprio |
| `cadastros.clientes.deactivate.own` | desativar cliente criado pelo proprio usuario |
| `cadastros.clientes.deactivate.any` | desativar cliente fora do escopo proprio |

Observacao: `created_by` e um escopo inicial. O escopo maduro deve considerar carteira comercial, vinculo vendedor-cliente, gerente e area.

## Pessoas comerciais

Eixo aprovado: tipo de alteracao, nao autoria pura.

Motivo: `cad_pessoas_comerciais` representa vendedores, agentes, tecnicos, entregadores, gerentes e comissionados. Alterar papeis, tipo comercial ou vendedor responsavel afeta comissoes, alcadas e pedidos. Esse registro e compartilhado pela operacao, nao pertence simplesmente a quem cadastrou.

Action keys previstas:

| Action key | Campos/uso |
|---|---|
| `cadastros.pessoas.update.identity` | nome, apelidos e grafias incorretas |
| `cadastros.pessoas.update.role` | tipo_comercial, papeis_json e vendedor_responsavel_id |
| `cadastros.pessoas.deactivate` | soft-delete por `status = inactive` |

Regra: se no futuro houver edicao do proprio perfil por usuario logado, isso deve ser fluxo de `usuarios` ou `perfil`, nao permissao ampla sobre `cad_pessoas_comerciais`.

## Materias-primas

Eixo aprovado: risco tecnico/operacional do campo, nao `own/any`.

Motivo: materia-prima e cadastro mestre compartilhado por estoque, importacao XML, compras, PCP, CQ, formula e relatorios. Nao existe dono natural por usuario. Quem criou o registro nao deveria ganhar permissao especial para alterar unidade, densidade, SKU ou dados regulatorios.

Action keys previstas:

| Action key | Campos/uso |
|---|---|
| `cadastros.materias_primas.update.identity` | nome e tipo descritivo |
| `cadastros.materias_primas.update.sku` | codigo_legado e sku_corrigido |
| `cadastros.materias_primas.update.technical` | unidade_base_estoque e densidade |
| `cadastros.materias_primas.update.stock_policy` | estoque_minimo |
| `cadastros.materias_primas.update.regulatory` | ncm, ibama e codigo_ads |
| `cadastros.materias_primas.deactivate` | soft-delete por `status = inactive` |

Regra: custo de materia-prima nao entra nesse bloco. Custo fica para o modulo futuro de formacao de custos.

## Consequencia para proximas migrations

Proxima migration de `cadastros` deve implementar primeiro `pessoas_comerciais` por tipo de alteracao.

Depois, `materias_primas` deve ser implementada com RPCs separadas por grupo de campo. Nao criar `materias_primas.update.own`, porque essa alcada nao representa uma regra real de negocio.
