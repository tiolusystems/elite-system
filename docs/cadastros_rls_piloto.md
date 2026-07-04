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

Exclusao:

- cadastro mestre nao deve usar hard-delete como regra operacional;
- exclusao vira soft-delete por mudanca de `status` para `inactive`;
- reativacao futura deve ter RPC e `action_key` proprias.

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
| Editar proprio cliente | `update_cad_cliente` | `cadastros.clientes.update.own` | `cad_clientes` |
| Editar qualquer cliente | `update_cad_cliente` | `cadastros.clientes.update.any` | `cad_clientes` |
| Desativar proprio cliente | `deactivate_cad_cliente` | `cadastros.clientes.deactivate.own` | `cad_clientes` |
| Desativar qualquer cliente | `deactivate_cad_cliente` | `cadastros.clientes.deactivate.any` | `cad_clientes` |
| Editar identidade de pessoa comercial | `update_cad_pessoa_comercial_identity` | `cadastros.pessoas.update.identity` | `cad_pessoas_comerciais` |
| Editar papeis comerciais | `update_cad_pessoa_comercial_role` | `cadastros.pessoas.update.role` | `cad_pessoas_comerciais` |
| Desativar pessoa comercial | `deactivate_cad_pessoa_comercial` | `cadastros.pessoas.deactivate` | `cad_pessoas_comerciais` |
| Editar identidade de MP | `update_cad_materia_prima_identity` | `cadastros.materias_primas.update.identity` | `cad_materias_primas` |
| Editar SKU de MP | `update_cad_materia_prima_sku` | `cadastros.materias_primas.update.sku` | `cad_materias_primas` |
| Editar dados tecnicos de MP | `update_cad_materia_prima_technical` | `cadastros.materias_primas.update.technical` | `cad_materias_primas` |
| Editar politica de estoque de MP | `update_cad_materia_prima_stock_policy` | `cadastros.materias_primas.update.stock_policy` | `cad_materias_primas` |
| Editar dados regulatorios de MP | `update_cad_materia_prima_regulatory` | `cadastros.materias_primas.update.regulatory` | `cad_materias_primas` |
| Desativar MP | `deactivate_cad_materia_prima` | `cadastros.materias_primas.deactivate` | `cad_materias_primas` |

Tabelas auxiliares de cadastro que ainda nao possuem RPC propria, como areas comerciais e vinculos pessoa-area, ficam em leitura autenticada e com escrita direta revogada. A escrita dessas tabelas so deve voltar quando houver uma RPC especifica com `action_key` e auditoria.

## Contrato de edicao e escopo

`update_cad_cliente` e `deactivate_cad_cliente` usam escopo inicial por autoria (`created_by`):

- se o cadastro foi criado pelo ator atual, a RPC tenta usar a alcada `.own`;
- se nao foi criado pelo ator atual, a RPC exige a alcada `.any`;
- se `.own` estiver negada mas `.any` estiver permitida, a RPC usa `.any`;
- a alcada efetivamente usada fica em `permission_context.alcada_usada`;
- `before_json` e `after_json` devem guardar o estado completo antes e depois da alteracao.

Este escopo por autoria e o primeiro degrau. Escopos futuros podem considerar carteira de vendedor, gerente, area comercial, filial ou propriedade.

## Contrato de pessoas comerciais

`cad_pessoas_comerciais` nao usa `own/any` como eixo inicial. A alteracao e separada por tipo de campo:

- identidade: nome, codigo legado, apelidos e grafias incorretas;
- papel comercial: `tipo_comercial`, `papeis_json` e `vendedor_responsavel_id`;
- desativacao: soft-delete por `status = inactive`.

`update_cad_pessoa_comercial_role` deve registrar motivo padronizado e diff de papeis:

- `motivo_codigo`;
- `motivo_detalhe`, quando houver;
- `papeis_adicionados`;
- `papeis_removidos`;
- tipo comercial antes/depois;
- vendedor responsavel antes/depois.

## Contrato de materias-primas

`cad_materias_primas` tambem nao usa `own/any`. A alteracao e separada por risco de campo:

- identidade: nome e tipo;
- SKU: codigo legado e SKU corrigido;
- tecnico: unidade base e densidade;
- politica de estoque: estoque minimo;
- regulatorio: NCM, IBAMA e ADS;
- desativacao: soft-delete por `status = inactive`.

Cada RPC de MP aceita somente os campos do seu eixo. Validacoes basicas ficam no banco:

- SKU corrigido obrigatorio, maiusculo e sem espacos;
- densidade positiva quando preenchida;
- estoque minimo maior/igual a zero quando preenchido;
- NCM com exatamente 8 digitos quando preenchido;
- motivo obrigatorio em toda alteracao.

## Smoke minimo obrigatorio

Antes de considerar o piloto fechado:

1. usuario ativo consegue ler cadastros;
2. usuario ativo consegue gravar via RPC permitida;
3. usuario ativo com override negado recebe `not allowed` e gera `log_permission_denied` pela aplicacao;
4. usuario sem perfil nao passa em `can_current_user`;
5. usuario inativo nao passa em `can_current_user`;
6. role `anon` nao executa RPC nem le tabela;
7. insert/update/delete direto nas tabelas de cadastro nao funciona para `authenticated`.
8. edicao registra `before_json` e `after_json` com diferenca real;
9. soft-delete muda apenas `status` para `inactive` e preserva o registro;
10. usuario com `.any` negado edita/desativa cadastro proprio, mas nao cadastro de outro usuario.
