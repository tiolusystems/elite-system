# Decisao tecnica - preparo minimo para importacao historica

Data: 2026-07-06

## Objetivo

Preparar o schema para uma futura importacao historica do Excel sem implementar o importador agora.

Este bloco nao importa planilhas, nao reconcilia saldos e nao grava dado real. Ele cria apenas marcadores estruturais para que dados historicos possam ser rastreados quando o projeto de importacao comecar.

## Decisoes aplicadas na 0034

### Ator de sistema

Foi criada a estrutura para ator nao-humano em `user_profiles`:

- `is_system_actor boolean not null default false`;
- `system_actor_key text`, unico quando preenchido;
- ator de sistema deve ficar `status = inactive`.

A migration tenta provisionar o ator tecnico:

- `id = 00000000-0000-4000-8000-000000000034`;
- `display_name = Migracao Historica`;
- `role = auditoria`;
- `status = inactive`;
- `system_actor_key = migracao_historica`.

O perfil fica inativo por design. Ele serve como referencia auditavel em `created_by`/`updated_by` de dados historicos, nao como usuario de login.

Observacao operacional: em ambiente Supabase real, `auth.users` pode ter contrato proprio. Se o bootstrap automatico em `auth.users` nao for aceito pelo ambiente, a migration nao deve falhar; o ator devera ser provisionado pelo processo controlado de deploy antes da importacao historica.

### Campos de origem historica

Foram adicionadas colunas nulas:

- `origem_dados text`;
- `codigo_legado text`.

`origem_dados` aceita apenas:

- `sistema`;
- `excel_legado`;
- `null`, enquanto o registro ainda nao foi classificado.

As colunas foram aplicadas em:

- `com_pedidos`;
- `com_pedido_itens`;
- `cad_clientes`;
- `cad_pessoas_comerciais`;
- `cad_materias_primas`;
- `cad_produtos_base`;
- `cad_embalagens`;
- `cad_produto_embalagens`.

## Decisao assumida sem interromper o desenvolvimento

A orientacao original citava como candidatas `com_pedidos`, `cad_clientes`, `cad_pessoas_comerciais` e `cad_materias_primas`.

Foi assumido que `com_pedido_itens`, `cad_produtos_base`, `cad_embalagens` e `cad_produto_embalagens` tambem precisam dos marcadores, porque pedido historico sem rastreabilidade de item/produto/embalagem fica fraco para auditoria posterior.

Essa decisao e reversivel em termos operacionais porque as colunas sao nulas e nao mudam fluxo atual, mas deve ser revisada por Luciano antes do desenho do importador real.

## Fora de escopo

- Importador Excel.
- RPCs de importacao historica.
- Mapeamento definitivo de workbook/abas/colunas.
- Reconciliacao de estoque historico.
- Atualizacao retroativa de registros ja existentes.
- Regras finais de seguranca do dominio `seguranca`.

## Decisoes pendentes para Luciano

- Confirmar se os marcadores devem ficar tambem em NF, recebimentos, romaneios, lotes e movimentos de estoque.
- Confirmar se o ator `Migracao Historica` deve ser criado por migration, bootstrap de deploy, ou ferramenta administrativa.
- Confirmar se `codigo_legado` deve ser unico por tabela em pedidos e itens, ou se a unicidade deve depender de `source_batch_id` no importador futuro.
- Confirmar quando evoluir `cancelar_com_pedido` para motivo fechado, em vez do mapeamento compativel atual para `cancelamento_pedido`.
