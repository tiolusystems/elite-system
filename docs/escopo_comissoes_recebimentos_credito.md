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

## Relacao com NF

Nota fiscal e documento fiscal, nao gatilho de pagamento de comissao.

Regras:

- pedido pode ter varias NFs;
- uma NF pode nascer como `remessa_total` por romaneio confirmado ou como `simples_faturamento` direto do pedido;
- em pedido de simples faturamento, cada romaneio de carga pode gerar NF de `remessa_vinculada` vinculada a NF simples pai;
- `romaneio_id` deve ser nullable no dominio fiscal;
- recebimento deve poder apontar para pedido, NF ou parcela quando essa informacao existir;
- se um pagamento cobrir varias NFs/pedidos, a evolucao correta e uma tabela de alocacao, como `fin_recebimento_alocacoes`;
- comissao e liberada pelo valor recebido alocado na base comissionavel;
- cancelamento, devolucao ou NF complementar devem afetar a conta corrente de comissao por evento auditado.

## Bonificacao

Bonificacao nao gera comissao.

Regras:

- pedido ou item com tipo `bonificacao` deve ter base comissionavel igual a zero;
- bonificacao pode aparecer em relatorios comerciais, mas nao deve entrar em comissao;
- se um pedido misturar venda e bonificacao, apenas os itens de venda entram na base comissionavel.

## Devolucao

Devolucao abate comissao.

Regras:

- devolucao antes de pagamento da comissao reduz ou estorna a comissao prevista/liberada;
- devolucao depois de comissao paga gera saldo negativo para o comissionado;
- saldo negativo deve ser abatido de comissoes futuras;
- devolucao parcial abate proporcionalmente;
- toda devolucao deve apontar pedido, item, cliente e motivo.

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
