# Pedidos e contrato de venda

## Criar e aprovar

1. O vendedor pesquisa um cliente da própria carteira.
2. Seleciona cliente ou propriedade e confere o limite disponível.
3. Informa itens, quantidades, contexto comercial, parcelas e entregas.
4. Calcula no banco a referência e informa o preço praticado na unidade
   comercial apresentada.
5. Confere a comparação e confirma a versão comercial. Se houver desconto,
   informa justificativa e confirma explicitamente a solicitação.
6. Uma pessoa com alçada registra a decisão de crédito, sem abrir o pedido.

## Exportar para assinatura

O documento atual só pode ser aberto quando o pedido estiver `open` ou
`fulfilled`. No histórico de Pedidos, use **Exportar PDF** e depois
**Imprimir ou salvar em PDF**.

O documento segue o modelo oficial de duas páginas:

- identificação do pedido, cliente, propriedade, vendedor e aprovação;
- produtos, apresentações, quantidades, valores e total;
- identificação do comprador e espaço para assinatura;
- observações e condições comerciais.

Dados ainda ausentes no cadastro são exibidos como **Não informado**. O operador
deve corrigir o cadastro de origem; o documento não inventa endereço, CEP,
inscrição ou contato.

## Segurança

- pedido bloqueado não gera o documento atual;
- a leitura respeita o mesmo escopo do pedido: vendedor vê sua carteira e
  gerente vê sua carteira e equipe;
- revisar um pedido bloqueado não altera o limite cadastral do cliente;
- alterar o limite exige uma alçada financeira individual e independente;
- o PDF não mostra comissão, limite de crédito ou informações internas de
  auditoria;
- a decisão de crédito exibida vem do histórico do pedido, mas não substitui
  aprovação de desconto nem assinatura aceita do comprador;
- a confirmação comercial congela um documento canônico identificado por
  SHA-256; a futura assinatura deverá referenciar exatamente essa versão.
# Totais físicos do pedido

Depois da liberação, o documento apresenta litros totais, quantidade de volumes
logísticos e peso bruto total. Os valores são calculados a partir das
apresentações cadastradas, da densidade de referência do produto, das unidades
por volume e da tara vigente da embalagem. Quando algum desses dados estiver
ausente, o sistema informa a pendência e não estima o total.
