# Decisao de faturamento e notas fiscais

Data: 2026-07-05

## Objetivo

Definir como notas fiscais entram no Elite System antes de criar migration, campo ou tabela.

A decisao principal e que nota fiscal nao e um campo do pedido. Nota fiscal e uma relacao um-para-muitos e tem ciclo de vida proprio. Um pedido pode ter zero, uma ou varias notas fiscais, geradas por romaneios parciais, por faturamento simples direto do pedido ou por eventos fiscais posteriores.

## Decisao

O dominio deve nascer como `faturamento`, com tabela propria de documento fiscal e tabela propria de eventos fiscais.

Tabelas planejadas:

- `fat_notas_fiscais`: documento fiscal emitido ou registrado no sistema.
- `fat_nota_fiscal_eventos`: eventos do ciclo de vida da NF.

Campos planejados para `fat_notas_fiscais`:

- `id`;
- `pedido_id`;
- `romaneio_id` nullable;
- `nota_referenciada_id` nullable;
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

Tipos iniciais:

- `normal`;
- `complementar`;
- `simples_faturamento`.

Status iniciais:

- `emitida`;
- `cancelada`;
- `substituida`;
- `inutilizada`.

O campo `status_atual` pode existir como cache operacional, mas a fonte auditavel do ciclo de vida deve ser `fat_nota_fiscal_eventos`.

## Simples faturamento

`simples_faturamento` convive com NF por romaneio.

Regra:

- NF por romaneio aponta para `pedido_id` e `romaneio_id`;
- NF de simples faturamento aponta para `pedido_id` e deixa `romaneio_id` nulo;
- `romaneio_id` deve ser nullable porque nem toda NF nasce de remessa fisica;
- simples faturamento nao baixa estoque, nao reserva lote e nao substitui romaneio;
- se houver entrega fisica posterior, a baixa de PA continua sendo feita por romaneio confirmado;
- a NF simples e um fato fiscal/financeiro, nao um fato de estoque.

Consequencia: nao deve existir campo como `numero_nf`, `chave_nfe`, `valor_nf` ou `status_nf` dentro de `com_pedidos` como fonte da verdade.

## Ciclo de vida fiscal

Cancelamento, carta de correcao, substituicao e complemento nao devem apagar nem sobrescrever a historia fiscal.

Regra:

- emissao cria a NF e cria evento `emitida`;
- cancelamento cria evento `cancelada` e atualiza `status_atual` apenas como cache;
- carta de correcao cria evento `carta_correcao`;
- NF complementar cria uma nova linha em `fat_notas_fiscais` com `tipo = complementar` e `nota_referenciada_id` apontando para a NF original;
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

## Relacao com romaneio e estoque

O romaneio confirmado continua sendo o evento que gera baixa fisica de PA.

Regras:

- pedido aberto nao baixa estoque;
- NF emitida nao baixa estoque por si so;
- romaneio confirmado baixa PA;
- NF por romaneio registra o fato fiscal associado a uma remessa confirmada;
- NF simples registra o fato fiscal direto do pedido, sem movimento fisico;
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

NF por romaneio:

```text
pedido aberto -> romaneio confirmado -> baixa PA -> NF normal -> recebimento -> comissao proporcional
```

Simples faturamento:

```text
pedido aberto -> NF simples faturamento -> recebimento -> comissao proporcional
```

Entrega fisica posterior ao simples faturamento:

```text
pedido ja faturado -> romaneio confirmado -> baixa PA -> reconciliacao fiscal/expedicao quando necessaria
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
