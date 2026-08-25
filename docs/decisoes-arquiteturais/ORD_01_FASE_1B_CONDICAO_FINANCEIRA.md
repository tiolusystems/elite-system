# ORD-01 Fase 1B - Condicao financeira, parcelas e PMP

- A condicao financeira pertence ao pedido e e registrada como versao relacional append-only de plano e parcelas.
- Cada parcela informa forma de pagamento, valor em centavos, vencimento e prazo em dias. Formas iniciais: boleto, PIX, TED e cessao de credito; combinacoes sao permitidas.
- A soma dos centavos das parcelas deve coincidir exatamente com o valor atual do pedido, que permanece sem alteracao nesta fase.
- PMP e `soma(valor_centavos x dias_prazo) / soma(valor_centavos)`, persistido com seis casas decimais por arredondamento numerico deterministico. A data-base e sempre `com_pedidos.data_pedido`, lida pela RPC; revisoes posteriores nao a alteram. Vencimento na propria data de emissao produz prazo zero; vencimento anterior e bloqueado.
- A Fase 1C consumira o PMP para selecionar a faixa imediatamente superior quando nao houver correspondencia exata. Acima da maior faixa aplicavel devera bloquear, sem fallback para faixa inferior.
- Esta fase nao resolve lista ou preco, nao faz analise de credito e nao altera recebimentos, comissoes ou logistica.
