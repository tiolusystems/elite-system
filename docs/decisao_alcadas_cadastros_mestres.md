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

`cadastros.pessoas.update.role` deve ser tratado como alteracao sensivel, nao como campo textual simples.

Motivo: mudar `tipo_comercial`, `papeis_json` ou `vendedor_responsavel_id` pode afetar pedido, comissao, gerente, agente vinculado, tecnico de campo, entregador e leitura operacional futura. A RPC deve exigir motivo e registrar no `before_json` e `after_json` quais papeis/tipos foram alterados.

Observacao: papel comercial em `cad_pessoas_comerciais` nao e a mesma coisa que role de autenticacao em `user_profiles.role`, mas ainda assim e uma mudanca de alcada de negocio. A implementacao deve manter essa diferenca explicita.

Motivos padronizados para `cadastros.pessoas.update.role`:

| Codigo | Uso |
|---|---|
| `promocao` | mudanca de funcao por promocao ou aumento de responsabilidade |
| `correcao_cadastro` | correcao de erro cadastral |
| `transferencia_carteira` | transferencia de carteira, area ou vendedor responsavel |
| `desligamento_funcao` | retirada de papel por desligamento ou fim de funcao |
| `mudanca_comissao` | alteracao relacionada a comissao ou elegibilidade |
| `outro` | excecao; exige detalhe textual |

O log de `cadastros.pessoas.update.role` deve registrar, alem de `before_json` e `after_json`:

- `motivo_codigo`;
- `motivo_detalhe`, quando houver;
- `papeis_adicionados`;
- `papeis_removidos`;
- tipo comercial antes/depois;
- vendedor responsavel antes/depois.

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

## Edicao com multiplos eixos

Nao criar RPC generica de atualizacao que aceite campos de varios eixos ao mesmo tempo.

Quando uma tela permitir alterar mais de um grupo de campos, a camada de aplicacao deve:

1. separar a mudanca por eixo;
2. chamar uma RPC especifica por eixo;
3. registrar cada alteracao com `action_key`, `before_json`, `after_json` e motivo proprios.

Exemplo: se materia-prima tiver alteracao de nome e estoque minimo no mesmo submit visual, a aplicacao deve chamar uma RPC de identidade e outra RPC de politica de estoque. Isso deixa a auditoria legivel: "alterou identidade" e "alterou estoque minimo", em vez de um log generico de "alterou MP".

Se no futuro for indispensavel aplicar multiplos eixos em uma unica transacao atomica, criar uma RPC orquestradora especifica, com action key propria e lista de subalteracoes auditadas. Nao usar isso como caminho padrao.

## Consequencia para proximas migrations

Proxima migration de `cadastros` deve implementar primeiro `pessoas_comerciais` por tipo de alteracao.

Motivo da ordem: `pessoas_comerciais` valida a separacao por eixo em um dominio menos acoplado a estoque, XML, PCP e garantias. `materias_primas` deve vir depois, porque toca conversoes, unidade base, densidade, XML/NF, estoque minimo e dados regulatorios.

Depois, `materias_primas` deve ser implementada com RPCs separadas por grupo de campo. Nao criar `materias_primas.update.own`, porque essa alcada nao representa uma regra real de negocio.
