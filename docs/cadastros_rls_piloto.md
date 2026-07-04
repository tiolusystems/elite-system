# Piloto RLS - cadastros

## Politica escolhida

Cadastros sera o primeiro dominio com RLS endurecido.

Leitura:

- permitida para usuario autenticado com perfil ativo;
- usada por telas operacionais, pedidos, PCP, romaneio, XML e relatorios;
- mais aberta que escrita nesta fase.

Escrita:

- bloqueada por acesso direto as tabelas;
- permitida apenas por RPC `security definer`;
- cada RPC valida uma `action_key` especifica;
- cada RPC registra auditoria com `log_audit_event`.

## Limite explicito do contrato atual

O wrapper `apps/web/lib/supabase/rpc.ts` garante log de negativa para chamadas feitas pela aplicacao Next.js.

Acesso direto ao banco fora desse fluxo, como SQL editor, script administrativo ou integracao futura, nao e coberto por esse wrapper. Esses caminhos devem usar RPCs auditadas ou receber uma camada propria de auditoria antes de serem considerados operacionais.

## Mapeamento do piloto

| Acao | RPC | Action key | Tabela principal |
|---|---|---|---|
| Criar cliente | `create_cad_cliente` | `cadastros.clientes.create` | `cad_clientes` |
| Criar pessoa comercial | `create_cad_pessoa_comercial` | `cadastros.pessoas.create` | `cad_pessoas_comerciais` |
| Criar materia-prima | `create_cad_materia_prima` | `cadastros.materias_primas.create` | `cad_materias_primas` |
| Criar produto base | `create_cad_produto_base` | `cadastros.produtos.create` | `cad_produtos_base` |
| Definir validade de produto | `set_cad_produto_prazo_validade` | `cadastros.produtos.validity.set` | `cad_produtos_base` |
| Criar embalagem | `create_cad_embalagem` | `cadastros.embalagens.create` | `cad_embalagens` |
| Criar item vendavel | `create_cad_produto_embalagem` | `cadastros.produto_embalagens.create` | `cad_produto_embalagens` |
| Criar conversao de unidade MP | `create_cad_conversao_unidade_mp` | `cadastros.conversoes_unidade_mp.create` | `cad_conversoes_unidade_mp` |

Tabelas auxiliares de cadastro que ainda nao possuem RPC propria, como areas comerciais e vinculos pessoa-area, ficam em leitura autenticada e com escrita direta revogada. A escrita dessas tabelas so deve voltar quando houver uma RPC especifica com `action_key` e auditoria.

## Smoke minimo obrigatorio

Antes de considerar o piloto fechado:

1. usuario ativo consegue ler cadastros;
2. usuario ativo consegue gravar via RPC permitida;
3. usuario ativo com override negado recebe `not allowed` e gera `log_permission_denied` pela aplicacao;
4. usuario sem perfil nao passa em `can_current_user`;
5. usuario inativo nao passa em `can_current_user`;
6. role `anon` nao executa RPC nem le tabela;
7. insert/update/delete direto nas tabelas de cadastro nao funciona para `authenticated`.
