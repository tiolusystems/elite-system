# Importacao XML, pedidos por propriedade e Kanban comercial

Data da decisao: 2026-07-04

## Decisao operacional

O fluxo de importacao de insumos por NF XML deve ser semiautomatico.

O sistema pode ler e estruturar o XML, sugerir materias-primas candidatas e calcular conversoes conhecidas, mas a entrada real no estoque de MP depende de confirmacao humana auditada.

Pedido comercial passa a ser identificado por cliente e, quando houver propriedade cadastrada, por sequencia propria da propriedade. Isso preserva a logica de cliente unico com varias fazendas/CNPJs e evita misturar historicos de propriedades diferentes.

O status do pedido deve ser exibido em visao tipo Kanban. O vendedor ve os pedidos que gerou. O gerente ve os pedidos dos vendedores vinculados diretamente ou por area comercial.

## Importacao semiautomatica de NF XML

Etapas:

1. Importar cabecalho da NF XML.
2. Importar itens da NF XML em area de conferencia.
3. Normalizar chave, CNPJ, codigo do fornecedor, descricao, NCM, unidade e quantidade.
4. Sugerir candidatos de MP por SKU corrigido, descricao normalizada, nome e NCM.
5. Usuario escolhe a MP correta ou ignora item que nao deve virar estoque.
6. Sistema aplica conversao de unidade cadastrada ou exige fator manual.
7. Confirmacao gera resolucao auditada do item.
8. Apenas item confirmado pode gerar lote de MP.
9. Lote de MP gerado usa codigo automatico unico por NF/item e preserva lote do fornecedor em observacao rastreavel.

Regras:

- XML nao baixa nem sobe estoque sozinho.
- Sugestao de MP nao e confirmacao.
- Conversao sem cadastro e sem fator manual deve bloquear geracao de lote.
- Resolucao e vinculo item XML -> lote MP sao append-only.
- A quantidade que entra no estoque deve ser a quantidade convertida para unidade base da MP.

Objetos tecnicos:

- `imp_nfe_xmls`: cabecalho da NF XML.
- `imp_nfe_xml_itens`: itens importados para conferencia.
- `imp_nfe_item_match_candidatos`: candidatos sugeridos de MP.
- `imp_nfe_item_resolucoes`: confirmacoes auditadas de MP/conversao.
- `imp_nfe_item_lotes_mp`: vinculo imutavel entre item XML e lote MP gerado.
- `imp_nfe_xml_itens_pendentes_match`: fila de conferencia.
- `imp_nfe_xml_resumo`: painel analitico da importacao.

Funcoes tecnicas:

- `stage_imp_nfe_xml`
- `stage_imp_nfe_xml_item`
- `confirm_imp_nfe_item_match`
- `ignore_imp_nfe_xml_item`
- `gerar_lote_mp_from_imp_nfe_item`

## Pedidos por propriedade

Regras:

- Cliente continua unico.
- Propriedade pertence a um cliente.
- Se o pedido informar propriedade, a sequencia e propria daquela propriedade.
- Se o pedido nao informar propriedade, a sequencia e propria do cliente sem propriedade.
- A propriedade do pedido deve pertencer ao cliente do pedido.
- O codigo novo do pedido segue a sequencia operacional, por exemplo `PED-P12-000001` para propriedade e `PED-C5-000001` para cliente sem propriedade.

Objetos tecnicos:

- `com_pedidos.propriedade_id`
- `com_pedidos.sequencia_propriedade`
- `com_pedidos.vendedor_gerador_id`
- `com_pedido_sequencias_propriedade`
- `next_com_pedido_sequencia`
- `create_com_pedido_operacional`

## Kanban comercial

Colunas iniciais:

- `rascunho`
- `aberto`
- `bloqueado`
- `concluido`
- `cancelado`

Visibilidade planejada:

- Vendedor: pedidos em que `vendedor_gerador_id` aponta para ele.
- Gerente vinculado: pedidos gerados por vendedores com `vendedor_responsavel_id`.
- Gerente de area: pedidos gerados por vendedores vinculados a uma area comercial ativa.

Objetos tecnicos:

- `cad_pessoas_comerciais.user_profile_id`
- `cad_areas_comerciais`
- `cad_pessoa_areas_comerciais`
- `com_pedidos_kanban`

## Proximas telas

1. Tela de importacao XML com fila de itens pendentes e seletor de MP candidata.
2. Tela de confirmacao de conversao com unidade XML, unidade base, fator e quantidade convertida.
3. Botao auditado para gerar lote de MP.
4. Tela de pedidos usando cliente + propriedade e codigo sequencial.
5. Quadro Kanban de pedidos por status, vendedor, gerente e area.

## Auditorias obrigatorias

- NF XML importada x itens conferidos.
- Itens XML sem MP definida.
- Itens XML com conversao manual.
- Itens XML confirmados x lotes MP gerados.
- Quantidade XML x fator x quantidade convertida x entrada MP.
- Pedido x cliente x propriedade.
- Sequencia sem buracos nao sera exigida em caso de cancelamento, mas duplicidade deve ser impossivel.
- Pedido x vendedor gerador x gerente/area.
