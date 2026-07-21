# Romaneio

## Fluxo operacional

1. Abra **Romaneio** e localize um pedido com saldo a entregar.
2. Abra o pedido. O sistema mostra somente os produtos com saldo livre.
3. Marque os produtos que entrarão na carga e informe a quantidade de cada um.
4. Confira a prévia. Consultar a carga não cria registro nem altera estoque.
5. Selecione **Gravar romaneio**.
6. Para cada produto, escolha um ou mais lotes PA compatíveis e reserve as quantidades.
7. Imprima o romaneio, se necessário. A impressão pode ocorrer antes da NF.
8. Informe entregador e veículo.
9. Vincule a NF de remessa emitida ao romaneio.
10. Confirme a NF e a baixa. Somente esta etapa gera a saída física do PA.

## Regras de quantidade

- A soma romaneada nunca pode superar o saldo pendente do item do pedido.
- A soma das reservas por lote deve ser igual à quantidade romaneada.
- Uma separação parcial baixa somente os produtos e quantidades selecionados.
- O saldo restante continua disponível no pedido para outro romaneio.

## Litros, volumes e pesos

- Litros são calculados pelo produto e sua embalagem.
- Volumes logísticos usam a configuração da apresentação e arredondamento para cima.
- Uma caixa 4 x 5 L ou 12 x 1 L conta como um volume; qualquer caixa parcial também conta como um volume.
- Cada IBC ou bombona conta como um volume, mesmo quando parcialmente preenchido.
- Peso líquido usa a densidade do lote originada no CQ.
- Peso bruto soma o peso líquido e a tara governada da embalagem.
- Se densidade, tara ou configuração de volume estiver ausente, o sistema mostra **Pendente** e não inventa valores.

## Estoque

- Rascunho não altera estoque.
- Reserva reduz o saldo disponível e mantém o saldo físico.
- NF emitida, entregador e veículo são obrigatórios para a baixa.
- A confirmação gera movimento append-only, baixa a reserva e reduz o saldo físico.
