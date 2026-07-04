# Validacao de pessoas comerciais por eixo de alteracao

Data da validacao: 2026-07-04

## Objetivo

Validar a migration `0016_cadastros_pessoas_role_axis.sql`, que estende `cadastros` para:

- edicao de identidade de pessoa comercial;
- edicao sensivel de papeis comerciais;
- motivo padronizado para alteracao de papel;
- diff de `papeis_json` com adicionados/removidos;
- soft-delete por `status = inactive`;
- comentario SQL separando papel comercial de `user_profiles.role`.

## Ambiente usado

- Banco PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55433`.
- Cluster temporario em `.tools/pg-cadastros-rls`.
- Database final de smoke: `elite_cadastros_pessoas_fresh`.
- Sem uso de banco operacional, Supabase cloud, planilhas ou dados reais.

## Resultado das migrations

Todas as migrations `0001` a `0016` aplicaram com sucesso em banco descartavel limpo.

## Action keys adicionadas

| Action key | Uso |
|---|---|
| `cadastros.pessoas.update.identity` | editar nome, codigo legado, apelidos e grafias |
| `cadastros.pessoas.update.role` | editar tipo comercial, papeis e vendedor responsavel |
| `cadastros.pessoas.deactivate` | desativar pessoa comercial por soft-delete |

As tres nascem com `default_allowed = true` para respeitar a fase de autonomia inicial, mas ja ficam separadas para retirada futura por checkbox/alcada.

## Motivos padronizados para papel comercial

| Codigo | Uso |
|---|---|
| `promocao` | aumento de funcao ou responsabilidade |
| `correcao_cadastro` | correcao de erro cadastral |
| `transferencia_carteira` | transferencia de carteira, area ou responsavel |
| `desligamento_funcao` | retirada de papel por desligamento ou fim de funcao |
| `mudanca_comissao` | alteracao relacionada a comissao ou elegibilidade |
| `outro` | excecao; exige detalhe textual |

## Smoke tests executados

| Caso | Resultado esperado | Resultado obtido |
|---|---|---|
| Usuario ativo cria pessoa comercial | log `cadastros.pessoa_comercial_created` | OK |
| Edita identidade | log `cadastros.pessoa_comercial_identity_updated` com before/after | OK |
| Update direto em `cad_pessoas_comerciais` | erro de permissao | OK |
| Edita papel comercial com `promocao` | log `cadastros.pessoa_comercial_role_updated` | OK |
| Motivo invalido em papel comercial | RPC falha com `invalid motivo_codigo` | OK |
| Override nega `cadastros.pessoas.update.role` | RPC falha com `not allowed` | OK |
| Negativa capturada pela aplicacao | `log_permission_denied(...)` registra `denied` | OK |
| Desativa pessoa comercial | `status` muda para `inactive` | OK |
| Usuario sem perfil | `can_current_user(...) = false` | OK |
| Usuario inativo | `can_current_user(...) = false` | OK |
| Role `anon` executando RPC | erro de permissao | OK |
| Comentario SQL da RPC de papel | explicita que nao altera `user_profiles.role` | OK |

## Evidencia de auditoria no smoke final

Contagem final em `action_logs` para `cadastros.pessoas.%`:

| Action | Action key | Status | Total |
|---|---|---|---|
| `cadastros.pessoa_comercial_created` | `cadastros.pessoas.create` | `success` | 1 |
| `cadastros.pessoa_comercial_identity_updated` | `cadastros.pessoas.update.identity` | `success` | 1 |
| `cadastros.pessoa_comercial_role_updated` | `cadastros.pessoas.update.role` | `success` | 1 |
| `cadastros.pessoa_comercial_deactivated` | `cadastros.pessoas.deactivate` | `success` | 1 |
| `seguranca.permissao_negada` | `cadastros.pessoas.update.role` | `denied` | 1 |

O smoke tambem conferiu:

- `before_json.nome` e `after_json.nome` na edicao de identidade;
- `metadata_json.motivo_codigo = promocao`;
- `metadata_json.papeis_adicionados = ["gerente"]`;
- `metadata_json.papeis_removidos = ["comissionado"]`;
- tipo comercial antes/depois;
- `before_json.status = active` e `after_json.status = inactive` na desativacao.

## Decisao

`pessoas_comerciais` fica validado como primeiro cadastro por eixo de alteracao, sem `own/any`.

O proximo dominio recomendado e `materias_primas`, tambem por eixo, mas com maior segmentacao por risco tecnico, operacional e regulatorio.
