# Decisao de faturamento e notas fiscais

Data: 2026-07-05

## Objetivo

Definir como notas fiscais entram no Elite System antes de criar migration, campo ou tabela.

A decisao principal e que nota fiscal nao e um campo solto do pedido. Nota fiscal e uma relacao um-para-muitos e tem ciclo de vida proprio. Um pedido pode ter zero, uma ou varias notas fiscais, geradas por romaneios parciais, por faturamento simples direto do pedido ou por eventos fiscais posteriores.

Mesmo nao sendo coluna editavel em `com_pedidos`, a NF deve aparecer no corpo do pedido como rastreabilidade fiscal. Essa rastreabilidade deve vir por relacionamento/view do dominio de faturamento, nao por duplicacao manual de numero, chave ou valor dentro do pedido.

## Decisao

O dominio deve nascer como `faturamento`, com tabela propria de documento fiscal e tabela propria de eventos fiscais.

Tabelas planejadas:

- `fat_notas_fiscais`: documento fiscal emitido ou registrado no sistema.
- `fat_nota_fiscal_itens`: itens/quantidades fiscais vinculados a pedido, item de pedido e romaneio quando aplicavel.
- `fat_nota_fiscal_eventos`: eventos do ciclo de vida da NF.

Campos planejados para `fat_notas_fiscais`:

- `id`;
- `pedido_id`;
- `romaneio_id` nullable;
- `nota_pai_id` nullable;
- `nota_complementada_id` nullable;
- `chave_nfe`;
- `numero`;
- `serie`;
- `data_emissao`;
- `valor_nf`;
- `tipo`;
- `status_atual`;
- `created_by`;
- `created_at`;
- `updated_at`.

Campos planejados para `fat_nota_fiscal_itens`:

- `id`;
- `nota_fiscal_id`;
- `pedido_id`;
- `pedido_item_id`;
- `romaneio_id` nullable;
- `romaneio_item_id` nullable;
- `produto_embalagem_id`;
- `quantidade`;
- `valor_item`;
- `created_at`.

Essa tabela permite reconciliar pedido, NF, romaneio e item/quantidade sem duplicar campos fiscais em `com_pedidos`.

Tipos iniciais:

- `remessa_total`;
- `simples_faturamento`;
- `remessa_vinculada`;
- `complementar`.

Status iniciais:

- `emitida`;
- `cancelada`;
- `substituida`;
- `inutilizada`.

O campo `status_atual` pode existir como cache operacional, mas a fonte auditavel do ciclo de vida deve ser `fat_nota_fiscal_eventos`.

## Modalidades fiscais

O sistema deve aceitar NF nas duas modalidades principais:

1. `remessa_total`: a NF da venda/remessa acompanha a carga. Ela aponta para `pedido_id` e `romaneio_id`, nao tem `nota_pai_id`, e pode encerrar a entrega fiscal/fisica do pedido quando o romaneio for total.
2. `simples_faturamento`: a NF fiscal nasce direto no pedido, sem romaneio e sem baixa de estoque. Depois, cada romaneio de carga sai com uma NF de `remessa_vinculada`, que aponta para a NF pai em `nota_pai_id`.

A modalidade fiscal deve ser registrada na NF, nao como um unico campo rigido em `com_pedidos`. Se um pedido futuramente tiver itens ou quantidades em modalidades diferentes, a reconciliacao deve acontecer por item/quantidade em `fat_nota_fiscal_itens`, nunca por duplicacao de campos fiscais no pedido.

Regras:

- NF de remessa total aponta para `pedido_id` e `romaneio_id`, sem NF pai;
- NF de simples faturamento aponta para `pedido_id` e deixa `romaneio_id` nulo;
- `romaneio_id` deve ser nullable porque nem toda NF nasce de remessa fisica;
- simples faturamento nao baixa estoque, nao reserva lote e nao substitui romaneio;
- se houver entrega fisica posterior, a baixa de PA continua sendo feita por romaneio confirmado;
- a NF simples e um fato fiscal/financeiro, nao um fato de estoque;
- quando um pedido for de simples faturamento, a NF de simples faturamento vira o documento fiscal pai do pedido;
- cada romaneio de carga posterior deve sair com uma NF de remessa vinculada, ligada ao mesmo pedido, ao romaneio e a NF de simples faturamento.

Consequencia: nao deve existir campo como `numero_nf`, `chave_nfe`, `valor_nf` ou `status_nf` dentro de `com_pedidos` como fonte da verdade.

## Hierarquia fiscal do pedido

O pedido precisa exibir o dossie fiscal completo:

- NF de simples faturamento do pedido, quando existir;
- NFs de remessa total por romaneio quando a modalidade fiscal for remessa total;
- NFs de remessa vinculada dependentes da NF de simples faturamento;
- NFs complementares vinculadas a NF original;
- eventos fiscais de cancelamento, carta de correcao, substituicao e inutilizacao.

Regras de integridade:

- `tipo = remessa_total` exige `pedido_id`, `romaneio_id`, `nota_pai_id` nulo e `nota_complementada_id` nulo;
- `tipo = simples_faturamento` exige `pedido_id` e `romaneio_id` nulo;
- `tipo = remessa_vinculada` exige `pedido_id`, `romaneio_id` e `nota_pai_id` apontando para a NF simples pai;
- NF de remessa vinculada deve pertencer ao mesmo `pedido_id` da NF pai;
- NF de remessa total e NF de remessa vinculada devem ser identificaveis no romaneio de carga;
- `tipo = complementar` deve apontar `nota_complementada_id` para a NF que esta complementando;
- `nota_pai_id` e `nota_complementada_id` nao devem ser preenchidos ao mesmo tempo;
- pedido com simples faturamento nao deve perder visibilidade das remessas posteriores;
- romaneio de carga nao deve ficar fiscalmente solto quando existir NF pai de simples faturamento;
- a mesma quantidade/item nao deve ser coberta duas vezes por `remessa_total` e `simples_faturamento`; a reconciliacao deve usar `fat_nota_fiscal_itens`.

View planejada:

- `fat_pedido_dossie_fiscal`: consolida pedido, NF de remessa total, NF pai de simples faturamento, NFs de remessa vinculada por romaneio, NFs complementares e eventos fiscais relevantes.

## Ciclo de vida fiscal

Cancelamento, carta de correcao, substituicao e complemento nao devem apagar nem sobrescrever a historia fiscal.

Regra:

- emissao cria a NF e cria evento `emitida`;
- cancelamento cria evento `cancelada` e atualiza `status_atual` apenas como cache;
- carta de correcao cria evento `carta_correcao`;
- NF complementar cria uma nova linha em `fat_notas_fiscais` com `tipo = complementar` e `nota_complementada_id` apontando para a NF original;
- substituicao cria evento `substituida` e referencia a nova NF quando aplicavel;
- correcao de erro deve ser novo evento fiscal, nao edicao silenciosa da linha original;
- hard-delete de NF/evento fiscal nao faz parte do fluxo operacional.

Campos planejados para `fat_nota_fiscal_eventos`:

- `id`;
- `nota_fiscal_id`;
- `tipo_evento`;
- `data_evento`;
- `motivo`;
- `payload_json`;
- `created_by`;
- `created_at`.

Tipos de evento planejados:

- `emitida`;
- `cancelada`;
- `carta_correcao`;
- `substituida`;
- `inutilizada`;
- `complementada`.

## Contrato do payload fiscal

`payload_json` nao e texto livre. Ele existe porque cada tipo de evento fiscal tem dados complementares diferentes, mas cada `tipo_evento` deve ter formato esperado documentado e comentado no schema da migration.

Contrato inicial:

| tipo_evento | Campos esperados em `payload_json` |
|---|---|
| `emitida` | `protocolo_autorizacao`, `ambiente`, `xml_ref`, `danfe_ref` |
| `cancelada` | `protocolo_cancelamento`, `justificativa`, `data_cancelamento`, `prazo_legal_validado` |
| `carta_correcao` | `sequencia_cce`, `protocolo_cce`, `texto_correcao` |
| `substituida` | `nota_substituta_id`, `motivo_substituicao` |
| `inutilizada` | `numero_inicial`, `numero_final`, `protocolo_inutilizacao`, `justificativa` |
| `complementada` | `nota_complementar_id`, `motivo_complemento`, `valor_complementar` |

Regras:

- dados centrais de identificacao da NF ficam em colunas tipadas, nao escondidos no JSON;
- `payload_json` guarda detalhes fiscais variaveis, protocolo, referencias de arquivo e memoria do evento;
- motivo obrigatorio continua em coluna propria `motivo` quando o evento exigir justificativa;
- RPC de evento deve validar no minimo os campos obrigatorios do tipo de evento;
- migration deve adicionar comentario de coluna explicando este contrato;
- nenhum fluxo deve aceitar `payload_json` vazio para cancelamento, carta de correcao, substituicao, inutilizacao ou complemento.

## Relacao com romaneio e estoque

O romaneio confirmado continua sendo o evento que gera baixa fisica de PA.

Regras:

- pedido aberto nao baixa estoque;
- NF emitida nao baixa estoque por si so;
- romaneio confirmado baixa PA;
- NF de remessa total registra o fato fiscal associado a uma remessa confirmada sem depender de NF pai;
- NF simples registra o fato fiscal direto do pedido, sem movimento fisico;
- NF de remessa vinculada registra o fato fiscal da carga e referencia a NF simples quando o pedido foi faturado por simples faturamento;
- romaneio de carga deve exibir a NF de remessa total ou a NF de remessa vinculada e, quando aplicavel, a NF simples pai;
- divergencia entre valor fiscal e quantidade fisica deve virar reconciliacao, nao ajuste manual de saldo.

## Relacao com recebimentos e comissoes

Comissao continua sendo liberada por `recebimento`, nao por pedido fechado nem por NF emitida.

Regra:

- a comissao pode ser prevista no pedido;
- NF emitida nao libera comissao sozinha;
- recebimento parcial ou integral libera comissao proporcional;
- bonificacao nao gera comissao;
- devolucao ou cancelamento fiscal deve abater comissao;
- se a comissao ja foi paga, o abatimento vira debito para compensacao futura.

Evolucao planejada:

- `com_recebimentos` deve poder identificar pedido, NF, parcela ou cliente;
- para pagamentos que cobrem varias NFs/pedidos, criar alocacao propria, como `fin_recebimento_alocacoes`;
- a memoria de calculo de comissao deve apontar para o recebimento e, quando houver, para a NF/parcela que originou a base proporcional.

## Alcadas iniciais

Action keys planejadas:

- `faturamento.nf.view`;
- `faturamento.nf.issue`;
- `faturamento.nf.cancel`;
- `faturamento.nf.correct`;
- `faturamento.nf.complement`;
- `faturamento.nf.substitute`.

Cancelamento, correcao e complemento exigem motivo obrigatorio e log auditavel.

## Anti-patterns proibidos

- Colocar NF como campo editavel dentro de `com_pedidos`.
- Assumir uma unica NF por pedido.
- Usar NF emitida como gatilho de baixa de estoque.
- Usar NF emitida como gatilho de pagamento de comissao.
- Apagar ou sobrescrever NF cancelada.
- Guardar apenas `status = cancelada` sem evento fiscal auditavel.
- Criar `valor_faturado` manual como fonte da verdade do pedido.
- Misturar emissao fiscal, baixa fisica e recebimento financeiro em uma unica RPC generica.

## Fluxos canonicos

Remessa total:

```text
pedido aberto -> romaneio total confirmado -> baixa PA -> NF remessa_total -> recebimento -> comissao proporcional
```

Simples faturamento:

```text
pedido aberto -> NF simples faturamento pai -> recebimento -> comissao proporcional
```

Romaneio de carga posterior ao simples faturamento:

```text
pedido ja faturado -> romaneio de carga -> NF remessa_vinculada -> baixa PA no romaneio confirmado -> rastreabilidade pedido/NF pai/NF remessa
```

NF complementar:

```text
NF original -> NF complementar referenciada -> recebimento complementar -> comissao proporcional se houver base comissionavel
```

Cancelamento:

```text
NF original -> evento cancelada -> ajuste financeiro/comissao por evento auditado
```

## Criterio para migration futura

A migration de faturamento so deve ser escrita depois que esta decisao estiver refletida em:

- matriz de seguranca e alcadas;
- receita RLS/RPC auditada;
- fluxo operacional canonico;
- escopo de romaneio;
- escopo de recebimentos e comissoes;
- teste de contrato impedindo regressao para campo de NF no pedido.
