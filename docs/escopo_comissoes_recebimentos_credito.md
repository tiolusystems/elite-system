# Escopo de comissoes, recebimentos, credito e pedidos por vendedor

Data: 2026-07-03

## Decisao

O Elite System deve ter uma ferramenta propria para calcular comissoes no momento em que valores forem recebidos de clientes.

A comissao pode ser gerada no pedido, mas so deve ser liberada conforme recebimento parcial ou integral. O calculo precisa considerar proporcionalidade, bonificacoes, devolucoes, comissoes ja pagas, campanhas vigentes, metas, gerente, vendedor/gerente e alcadas.

NF emitida nao libera comissao sozinha. A decisao de faturamento esta em `docs/decisao_faturamento_notas_fiscais.md`: nota fiscal e relacao um-para-muitos do pedido e pode ajudar a identificar a base fiscal/parcela recebida, mas o gatilho de liberacao continua sendo o recebimento.

## Estados da comissao

Estados previstos:

- `prevista`: comissao calculada a partir do pedido, mas ainda nao liberada.
- `liberada`: comissao liberada por recebimento parcial ou integral.
- `paga`: comissao efetivamente paga ao comissionado.
- `estornada`: comissao anulada por cancelamento, devolucao ou correcao.
- `bloqueada`: comissao temporariamente travada por credito, revisao ou fluxo operacional.
- `cancelada`: comissao definitivamente anulada por cancelamento de pedido antes de pagamento.
- `compensacao_futura`: valor negativo a abater de comissoes futuras.

## Regra de recebimento

Quando um recebimento for lancado:

1. identificar cliente, pedido, NF/parcela e valor recebido;
2. localizar comissoes previstas vinculadas aos pedidos recebidos;
3. calcular a proporcao recebida sobre a base comissionavel;
4. liberar apenas a parte proporcional ainda nao liberada;
5. registrar a memoria de calculo;
6. gerar evento auditavel.

Regra base:

```text
proporcao_recebida = valor_recebido_do_pedido / valor_comissionavel_do_pedido
comissao_liberavel = comissao_prevista_total * proporcao_recebida - comissao_ja_liberada
```

A formula final pode mudar por campanha, gerente, tipo de comissionado ou regra especifica, mas toda alteracao deve ficar versionada.

## Entrega tecnica 0026

A migration `supabase/migrations/0026_finance_receipts_commissions_contract.sql` implementa o nucleo auditavel de recebimentos e comissoes.

Entregue:

- `axis = financial_event`;
- `fin_recebimento_alocacoes`, permitindo um recebimento cobrir um ou mais pedidos/NFs;
- `fin_comissao_movimentos`, conta corrente append-only de comissoes;
- `registrar_fin_recebimento_alocado(...)`, RPC para recebimento com alocacoes;
- `registrar_com_recebimento(...)`, compatibilidade com a tela atual de recebimento por pedido;
- liberacao proporcional de comissao com `memoria_calculo_json`;
- `registrar_fin_comissao_pagamento(...)`, pagamento de comissao como debito na conta corrente;
- `registrar_fin_comissao_ajuste(...)`, ajuste manual com motivo obrigatorio;
- bloqueio de escrita direta nas tabelas financeiras sensiveis;
- views `fin_recebimento_saldos_pedido` e `fin_comissao_saldos`.

Nao entregue nesta etapa:

- motor de campanhas/metas/travas;
- baixa bancaria automatica;
- estorno completo de recebimento por devolucao/cancelamento;
- regras granulares de visibilidade por carteira de vendedor/gerente.

Esses pontos devem nascer como subdominios posteriores, sem alterar retroativamente a memoria de calculo ja gravada.

## Entrega tecnica 0027

A migration `supabase/migrations/0027_finance_commission_idempotency_contract.sql` endurece a idempotencia e os ajustes manuais.

Regras fechadas:

- liberacao de comissao e incremental por evento de alocacao, nao recalc total retroativo;
- cada par `alocacao_id + comissionado_id` so pode gerar uma liberacao `liberada`;
- cada `liberacao_id` so pode gerar um movimento `credito_liberacao`;
- reprocessar a liberacao do mesmo recebimento deve falhar com `comissao_ja_liberada_para_este_recebimento`;
- a trava de reprocessamento fica no recebimento/alocacao, nao no pedido inteiro;
- a Server Action de recebimento envia metadata de contrato para registrar `failed` em erro de negocio.

Motivos padronizados para ajuste manual de comissao:

- `correcao_calculo`;
- `estorno_devolucao`;
- `acordo_comercial`;
- `compensacao_futura`;
- `outro`, exigindo `motivo_detalhe`.

Ajuste manual de comissao nao deve aceitar texto livre como unica justificativa.

## Relacao com NF

Nota fiscal e documento fiscal, nao gatilho de pagamento de comissao.

Regras:

- pedido pode ter varias NFs;
- uma NF pode nascer como `remessa_total` por romaneio confirmado ou como `simples_faturamento` direto do pedido;
- em pedido de simples faturamento, cada romaneio de carga pode gerar NF de `remessa_vinculada` vinculada a NF simples pai;
- `romaneio_id` deve ser nullable no dominio fiscal;
- recebimento deve poder apontar para pedido, NF ou parcela quando essa informacao existir;
- se um pagamento cobrir varias NFs/pedidos, a evolucao correta e uma tabela de alocacao, como `fin_recebimento_alocacoes`;
- `remessa_vinculada` nao deve ser usada como base financeira de pagamento/comissao, porque ela documenta a carga vinculada a uma NF simples pai;
- comissao e liberada pelo valor recebido alocado na base comissionavel;
- cancelamento, devolucao ou NF complementar devem afetar a conta corrente de comissao por evento auditado.

## Bonificacao

Bonificacao nao gera comissao.

Regras:

- pedido ou item com tipo `bonificacao` deve ter base comissionavel igual a zero;
- bonificacao pode aparecer em relatorios comerciais, mas nao deve entrar em comissao;
- se um pedido misturar venda e bonificacao, apenas os itens de venda entram na base comissionavel.

## Troca e mostruario

Mostruario nao gera comissao, mesmo quando houver vendedor informado no pedido. O valor comercial do item fica zero no fluxo operacional, porque a finalidade e controle de envio/amostra, nao faturamento comissionavel.

troca exige pedido e item de origem. Ela nao deve ser criada pelo fluxo generico de pedido, porque precisa preservar a rastreabilidade do que esta sendo substituido. A RPC propria de troca cria um novo pedido `tipo_pedido = troca`, com `pedido_origem_id` e `pedido_item_origem_id`, sem gerar comissionado previsto.

Regra decidida:

- venda gera comissionado previsto quando houver percentual;
- bonificacao nao gera comissionado previsto;
- devolucao nao gera comissionado previsto;
- mostruario nao gera comissao prevista;
- troca nao gera comissionado previsto;
- a soma das trocas ativas de um item nao pode ultrapassar a quantidade original desse item.

## Devolucao

Devolucao abate comissao.

Regras:

- devolucao antes de pagamento da comissao reduz ou estorna a comissao prevista/liberada;
- devolucao depois de comissao paga gera saldo negativo para o comissionado;
- saldo negativo deve ser abatido de comissoes futuras;
- devolucao parcial abate proporcionalmente;
- toda devolucao deve apontar pedido, item, cliente e motivo.

## Estorno pos-pagamento

Quando a comissao ja foi paga, o pedido nao deve ser cancelado pelo fluxo `cancelar_com_pedido`. O pedido permanece `fulfilled`, pois a venda, o faturamento, a expedicao e o pagamento de comissao ja sao fatos historicos.

Nesse caso, a devolucao pos-pagamento deve gerar documento fiscal de devolucao e retorno de estoque PA como novo movimento append-only, sem alterar comissao paga e sem alterar o status do pedido.

Regra decidida:

- exige pedido `fulfilled`;
- exige evidencia direta de comissao paga;
- emite NF de devolucao vinculada a NF original;
- item fiscal de devolucao aponta para o item fiscal original;
- retorno de PA entra como movimento `estorno_saida` no lote informado;
- pedido continua `fulfilled`;
- comissionados e conta corrente de comissao nao sao alterados por essa RPC;
- abatimento de meta vira evento do futuro ledger de metas, nao recalculo retroativo da comissao paga.

## Conta corrente de comissao

Cada comissionado deve ter uma conta corrente de comissoes.

Movimentos previstos:

- credito por comissao liberada;
- debito por comissao paga;
- debito por devolucao/estorno;
- ajuste manual autorizado;
- compensacao de saldo negativo em comissao futura.

Nenhum ajuste manual pode existir sem usuario, motivo e auditoria.

## Papeis comerciais

Papeis previstos:

- vendedor;
- gerente;
- vendedor/gerente;
- agente direto;
- agente vinculado;
- tecnico de campo;
- outro comissionado aprovado.

Gerente pode ganhar comissao sobre:

- vendas de vendedores especificos;
- vendas de uma regiao de atuacao;
- clientes sob sua gestao;
- campanhas especificas;
- regras combinadas.

Vendedor/gerente pode receber simultaneamente:

- comissao propria como vendedor;
- comissao gerencial sobre equipe/regiao;
- premio de campanha, se aplicavel.

## Campanhas, metas e travas

O sistema deve suportar mais de uma campanha vigente.

Exemplos de regra:

- ao atingir meta X, comissao passa para Y;
- ao atingir meta X em periodo definido, vendedor ganha voucher de viagem;
- campanha por vendedor;
- campanha por gerente;
- campanha por regiao;
- campanha por produto;
- campanha por cliente;
- campanha acumulavel ou nao acumulavel.

Cada campanha deve ter:

- periodo de vigencia;
- publico alvo;
- regra de calculo;
- prioridade ou acumulabilidade;
- tipo de premio;
- auditoria de criacao/alteracao.

## Ledger de metas e faixas

Meta e faixa de comissao sao subdominios diferentes da liberacao financeira.

Regra decidida:

- base de meta/faixa e vendido ativo, nao recebido;
- recebimento controla quando a comissao e liberada financeiramente;
- pedido so entra na meta quando estiver `open`;
- mesmo que a aprovacao ocorra depois, o periodo de meta e definido pela data do pedido;
- periodo de meta e periodo customizado da empresa, nao necessariamente mes calendario;
- cancelamento sempre abate meta no periodo em que o cancelamento acontece, sem reabrir periodo original;
- devolucao abate meta no periodo vigente, sem efeito retroativo no periodo original;
- devolucao com `motivo_devolucao = qualidade` nao penaliza vendedor;
- demais motivos de devolucao abatem meta por indicarem falha comercial, operacional ou negociacao;
- cancelamento por qualidade antes da baixa ainda e ponto pendente: decidir se segue a excecao de qualidade da devolucao ou se todo cancelamento abate sem excecao.

O ledger append-only de meta deve registrar:

- venda aberta gera evento positivo;
- cancelamento gera evento negativo;
- devolucao gera evento negativo, salvo motivo de qualidade;
- ajuste manual de meta exige motivo, alcada e auditoria.

Faixa por volume acumulado usa fracionamento por volume acumulado. Exemplo: se a faixa muda em 500k, a parte ate 500k usa a taxa anterior e a parte acima usa a taxa nova.

Faixa por grupo ou linha de produto nao usa o mesmo fracionamento: cada item busca sua taxa pela classificacao propria.

Faixa combinada por grupo + meta so deve ser implementada quando existir necessidade real, porque mistura lookup por item com fracionamento por acumulado.

A taxa congelada no momento da criacao do pedido deve ficar gravada em `com_pedido_comissionados`, usando o acumulado imediatamente anterior ao pedido. Cancelamentos e devolucoes posteriores de outros pedidos nao recalculam retroativamente pedidos ja criados; afetam apenas o proximo calculo.

Para evitar concorrencia perto da fronteira de faixa, o calculo deve usar lock por vendedor + periodo, por exemplo linha de resumo por vendedor/periodo com `for update` ou advisory lock equivalente. O lock precisa existir antes do motor de fracionamento virar operacional.

## Pedido inserido por vendedor

O sistema pode e deve ter ferramenta para vendedores preencherem pedidos diretamente.

Essa ferramenta deve respeitar alcadas especificas:

- vendedor so ve clientes autorizados para ele;
- vendedor pode criar pedido em rascunho;
- vendedor nao altera limite de credito;
- vendedor nao altera regra de comissao;
- vendedor nao aprova pedido bloqueado por credito/inadimplencia sem alcada;
- gerente pode aprovar ou encaminhar conforme alcada;
- financeiro/comercial autorizado controla limite, bloqueio e liberacoes;
- toda criacao, alteracao, aprovacao, bloqueio e rejeicao fica em `action_logs`.

## Credito e inadimplencia

Ao inserir pedido, o sistema deve mostrar:

- limite de credito do cliente;
- limite disponivel;
- pedidos em aberto;
- titulos vencidos;
- historico de inadimplencia relevante;
- bloqueios ou reducoes de limite aplicadas.

Regras iniciais:

- inadimplencia pode reduzir limite disponivel;
- pedido acima do limite deve ir para aprovacao ou bloqueio;
- cliente bloqueado nao deve gerar pedido aprovado automaticamente;
- reducao de limite por inadimplencia deve ser explicavel e auditavel;
- limite manual e limite calculado devem ser separados.

## Estados de pedido no fluxo vendedor

Estados previstos:

- `rascunho`;
- `enviado`;
- `bloqueado_credito`;
- `bloqueado_inadimplencia`;
- `pendente_aprovacao`;
- `aprovado`;
- `rejeitado`;
- `cancelado`.

## Auditorias obrigatorias

- pedido criado por vendedor;
- limite exibido no momento da criacao;
- motivo de bloqueio de credito/inadimplencia;
- aprovacao ou rejeicao por gerente/financeiro;
- comissao prevista no pedido;
- recebimento lancado;
- comissao liberada por recebimento;
- comissao paga;
- devolucao e abatimento;
- saldo negativo compensado em comissao futura;
- campanha aplicada e memoria de calculo.

## Perguntas para revisao

- Recebimento sera lancado por pedido, NF, boleto/parcela ou apenas por cliente?
- Como alocar recebimento parcial quando cliente paga varios pedidos juntos?
- Qual data manda na comissao: recebimento, baixa financeira ou conciliacao bancaria?
- Quais usuarios podem ver limite de credito completo?
- Vendedor pode ver inadimplencia detalhada ou apenas status/alerta?
- Qual regra inicial de reducao de limite por atraso?
- Gerente aprova acima de qual limite?
- Campanhas podem acumular entre gerente e vendedor?
