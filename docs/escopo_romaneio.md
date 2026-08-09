# Escopo do romaneio

Data da decisao: 2026-07-03

## Decisao

O modulo de romaneio deve reproduzir, no minimo, o que a planilha `ROMANEIO` faz hoje.

Existem outras planilhas ou abas com nome parecido. Elas nao devem virar codigo automaticamente. A fonte canonica para este modulo e a planilha/tabela `ROMANEIO` que opera a separacao de pedidos, lotes e comunicacao com faturamento e expedicao.

## Papel do romaneio

O romaneio e a ferramenta que:

- escolhe qual pedido sera separado;
- define se a separacao sera total ou parcial;
- busca lotes disponiveis de produto acabado;
- vincula pedido, produto, quantidade e lote;
- informa o que deve seguir para faturamento;
- informa o que deve seguir para expedicao;
- gera a base auditavel para baixa de produto acabado.

## Baixa de estoque

A baixa de produto acabado deve acontecer via romaneio confirmado, nao via pedido bruto.

Regra de ciclo:

1. Pedido aberto nao baixa estoque.
2. Romaneio em rascunho nao baixa estoque.
3. Romaneio em separacao pode reservar lotes, se a regra operacional exigir.
4. Romaneio confirmado gera a saida de produto acabado.
5. Romaneio cancelado antes da confirmacao libera a reserva.
6. Romaneio estornado depois da confirmacao exige movimento de reversao auditado.

Isso evita baixar estoque de pedido ainda nao separado e evita faturar quantidade diferente da quantidade realmente separada.

## Separacao parcial

Quando o pedido for separado parcialmente:

- o romaneio baixa apenas a quantidade confirmada;
- o saldo pendente continua no pedido;
- o faturamento recebe somente a quantidade romaneada;
- a expedicao recebe somente os itens/lotes romaneados;
- a auditoria deve mostrar pedido original, quantidade romaneada e saldo pendente.

## Interfaces com outros modulos

Comercial:

- fornece pedidos e itens pendentes;
- recebe status de separado parcial, separado total ou pendente.

Estoque PA:

- fornece lotes disponiveis;
- registra reserva quando aplicavel;
- registra baixa somente por romaneio confirmado.

Faturamento:

- recebe o romaneio confirmado como base da quantidade faturavel.
- gera ou vincula NF em dominio proprio de faturamento, nao em campo editavel do pedido.
- pode existir NF sem `romaneio_id` quando o fluxo for `simples_faturamento`.
- na modalidade `remessa_total`, o romaneio de carga deve identificar sua propria NF de remessa total, sem NF pai.
- na modalidade `simples_faturamento`, cada romaneio de carga deve identificar a NF de `remessa_vinculada` e a NF simples pai.
- a decisao fiscal canonica esta em `docs/decisao_faturamento_notas_fiscais.md`.

Expedicao:

- recebe o romaneio confirmado como lista operacional de separacao/entrega.

## Implementacao tecnica atual

Migration: `supabase/migrations/0006_romaneio_foundation.sql`.

Fundacao criada:

- `exp_romaneios`: cabecalho do romaneio, pedido vinculado, tipo de separacao e ciclo de status.
- `exp_romaneio_itens`: pedido, item, produto/embalagem, lote PA informado e quantidade romaneada.
- `exp_romaneio_movimentos_pa`: movimentos auditaveis de baixa e estorno de PA gerados por romaneio confirmado ou estornado.
- `exp_pedido_item_romaneio_saldos`: view de quantidade pedida, confirmada, comprometida, pendente de atendimento e livre para novo romaneio.

Funcoes auditaveis:

- `create_exp_romaneio`: cria romaneio somente em rascunho, sem baixar ou reservar estoque.
- `registrar_exp_romaneio_separacao`: contrato textual legado indisponivel para a API; a reserva relacional usa `registrar_est_reserva_pa`.
- `confirmar_exp_romaneio`: confirma romaneio e gera movimento positivo de baixa PA.
- `cancelar_exp_romaneio`: cancela romaneio antes da confirmacao e libera reserva logica.
- `estornar_exp_romaneio`: estorna romaneio confirmado com movimento inverso auditado.

Fronteira desta etapa:

- o lote PA ainda e referencia textual (`lote_pa_ref`) ate a fundacao completa de estoque/lotes PA;
- a baixa PA fica registrada como movimento auditavel do romaneio, pronta para reconciliar com o livro de estoque quando o modulo de estoque for codado;
- nao foi implementada tela estetica de romaneio nesta etapa.

## Evolucao com estoque PA real

Migration complementar: `supabase/migrations/0007_pa_stock_lots_foundation.sql`.

A partir desta etapa, o romaneio confirmado passa a exigir reserva de lote PA real quando usado pelo fluxo novo de estoque:

- `est_lotes_pa` guarda lote PA por produto/embalagem;
- `est_reservas_pa` registra reserva ativa por item de romaneio;
- `est_movimentos_pa` registra a baixa fisica no livro de estoque;
- `est_lotes_pa_saldos` mostra saldo fisico, reserva e saldo disponivel;
- `exp_romaneio_itens.lote_pa_id` liga o item do romaneio ao lote real;
- `exp_romaneio_movimentos_pa.lote_pa_id` liga a baixa/estorno do romaneio ao lote real.

Fluxo operacional atualizado:

1. Pedido aberto nao baixa PA.
2. Romaneio em rascunho nao baixa PA.
3. Reserva de lote PA reduz saldo disponivel, mas nao reduz saldo fisico.
4. Confirmacao do romaneio gera `saida_romaneio` em `est_movimentos_pa`.
5. Cancelamento antes da confirmacao libera reserva ativa.
6. Estorno depois da confirmacao gera `estorno_saida` no mesmo lote.

O campo textual `lote_pa_ref` permanece para compatibilidade e leitura humana, mas a chave auditavel passa a ser `lote_pa_id`.

## Evolucao com romaneio multilote

Migration complementar: `supabase/migrations/0009_pcp_op_foundation.sql`.

A partir desta etapa, um mesmo item de romaneio pode ser atendido por mais de um lote PA:

1. `registrar_est_reserva_pa` pode registrar varias reservas ativas para o mesmo item, desde que cada reserva aponte para um lote diferente.
2. A soma das reservas ativas nao pode ultrapassar a quantidade romaneada.
3. Quando ha mais de um lote, `exp_romaneio_itens.lote_pa_ref` fica como `MULTILOTE` para leitura humana.
4. `confirmar_exp_romaneio` exige que a soma das reservas ativas seja exatamente igual a quantidade romaneada.
5. A confirmacao gera uma baixa PA por lote reservado.
6. O saldo PA considera reservas de romaneio e reservas de PCP.

## Integridade quantitativa do pedido

Migration complementar: `supabase/migrations/0060_romaneio_quantity_integrity_contract.sql`.

A quantidade de um item de pedido possui tres leituras diferentes e elas nao
podem ser confundidas:

1. `quantidade_pendente`: pedido menos o que ja foi confirmado; representa o
   que ainda nao foi atendido fisicamente.
2. `quantidade_comprometida`: soma dos itens em romaneios `draft`,
   `separacao` ou `confirmado` ainda ativos.
3. `quantidade_disponivel_romaneio`: pedido menos toda quantidade
   comprometida; e o unico saldo que pode originar outro romaneio.

O PostgreSQL trava o item do pedido e rejeita qualquer insercao ou alteracao
que faca a soma ativa ultrapassar a quantidade pedida. Cancelamento e estorno
retiram o romaneio da soma ativa e liberam o saldo correspondente. A tela pode
antecipar a validacao, mas o banco permanece como autoridade final.

Validacao descartavel:

- pedido de 6 unidades;
- romaneio total de 6 unidades;
- reserva de 3 unidades no lote A;
- reserva de 3 unidades no lote B;
- confirmacao com duas baixas PA;
- pedido finalizado como `fulfilled`.

## Evolucao web operacional

Arquivos:

- `supabase/migrations/0012_romaneio_multi_item_web.sql`
- `apps/web/lib/romaneios.ts`
- `apps/web/app/romaneios/actions.ts`
- `apps/web/app/romaneios/page.tsx`

Funcionalidades implementadas:

- Tela `/romaneios` com painel visual/analitico de pedidos com pendencia, romaneios em rascunho, romaneios em separacao e quantidade pendente.
- Criacao de romaneio a partir de item pendente do pedido, em rascunho e sem baixa de PA.
- Adicao de novos itens ao mesmo romaneio pela funcao `add_exp_romaneio_item`, sem insert direto pela UI.
- Reserva de lote PA por item de romaneio via `registrar_est_reserva_pa`, com suporte a multilote.
- Confirmacao de romaneio via `confirmar_exp_romaneio`, exigindo reserva ativa fechada e gerando baixa PA por lote.
- Cancelamento antes da confirmacao e estorno apos confirmacao, ambos via funcoes auditaveis.
- Consulta de lotes PA disponiveis com saldo fisico, reservado, disponivel e validade.

Status: implementada no Next.js. Ainda precisa ser homologada contra Supabase configurado com usuario logado e dados de teste antes de uso operacional.

## Fora do escopo inicial

Nao implementar como parte do romaneio inicial, salvo se estiver na planilha `ROMANEIO` canonica:

- sistema completo de montagem de carga;
- roteirizacao;
- gestao completa de frota;
- financeiro;
- emissao fiscal completa;
- qualquer segunda planilha chamada romaneio sem mapeamento aprovado.

## Fronteira com faturamento

O romaneio informa o que pode ser faturado e expedido, mas nao deve armazenar a nota fiscal como estado principal.

Regra:

- NF de `remessa_total` deve apontar para `pedido_id` e `romaneio_id`, sem `nota_pai_id`;
- NF por simples faturamento deve apontar para `pedido_id` e deixar `romaneio_id` nullable;
- quando o pedido tiver NF de simples faturamento, a NF de `remessa_vinculada` deve apontar `nota_pai_id` para a NF simples pai;
- o romaneio de carga deve exibir a NF de remessa total ou a NF de remessa vinculada e, quando aplicavel, a NF simples pai para rastreabilidade fiscal da carga;
- NF emitida nao baixa estoque por si so;
- baixa de PA continua acontecendo pelo romaneio confirmado;
- cancelamento, carta de correcao e NF complementar pertencem ao dominio de faturamento.

## Criterio de aceite

O modulo de romaneio so sera considerado fiel quando:

- reproduzir os campos e decisoes da planilha `ROMANEIO` canonica;
- permitir separacao total e parcial;
- localizar lotes disponiveis;
- registrar pedido, produto, lote e quantidade, inclusive com varios itens no mesmo romaneio;
- gerar baixa auditada de PA apenas no momento correto;
- reconciliar as baixas contra `SAIDAS_PA` e contra o historico importado.
