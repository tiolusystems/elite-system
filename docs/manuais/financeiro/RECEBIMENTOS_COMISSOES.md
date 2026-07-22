# Recebimentos e comissoes

## Finalidade

Registrar recebimentos de vendas e controlar previsao, liberacao proporcional,
pagamento e ajustes de comissao por eventos auditados.

## Antes de comissionar

- o pedido precisa ser do tipo Venda e estar liberado;
- a pessoa comissionada precisa estar ativa;
- a definicao deve ocorrer antes do primeiro recebimento;
- vendedor, agente e gerente podem coexistir no mesmo pedido;
- percentual e justificativa sao registrados por pessoa e papel.

## Definir comissionados

1. Abra **Pedidos > Financeiro**.
2. Em **Definir comissionados da venda**, escolha o pedido aprovado.
3. Selecione a pessoa e o papel.
4. Informe percentual e justificativa.
5. Confirme a previsao antes de registrar qualquer recebimento.

A mesma pessoa e papel podem ser revisados antes do recebimento sem criar linha
duplicada. Bonificacao, Mostruario, Troca e Devolucao nao aceitam essa previsao.

## Registrar recebimento

1. Escolha um pedido com saldo financeiro aberto.
2. Informe valor, data e forma.
3. Inclua referencia de documento ou conciliacao quando disponivel.
4. Confirme e confira o novo saldo do pedido.

O valor nao pode superar o saldo. Cada recebimento libera a fracao da comissao
correspondente ao valor alocado naquele evento.

Duplo clique ou repeticao da mesma requisicao retorna o recebimento original e
nao cria outro evento financeiro. Recebimentos parciais diferentes continuam
permitidos e recebem chaves de requisicao diferentes.

## Pagar comissao

1. Consulte a conta corrente da pessoa.
2. Selecione somente quem possui saldo positivo.
3. Informe valor, data, forma e referencia.
4. Confirme o pagamento.

O pagamento entra como debito no ledger e nao pode superar o saldo disponivel.
Duplo clique ou repeticao de rede retorna o pagamento original. Pagamentos e
ajustes concorrentes da mesma pessoa sao processados em ordem pelo banco, para
que dois comandos nao utilizem o mesmo saldo simultaneamente.

## Ajuste manual

Ajuste e excepcional. Exige permissao superior, valor com sinal e motivo
controlado: correcao de calculo, estorno de devolucao, acordo comercial,
compensacao futura ou Outro com detalhamento. O movimento original nunca e
editado ou apagado.

Uma repeticao identica retorna o ajuste original. Alterar os dados reutilizando
a mesma chave e recusado para preservar a intencao auditada.

## Auditoria

Recebimento, alocacao, liberacao, pagamento e ajuste permanecem correlacionados.
O historico identifica usuario, data, valores, motivo e memoria de calculo.
