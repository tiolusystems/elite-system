# Ajuste manual de comissão

## O que esta operação faz

Registra uma correção excepcional na conta corrente de uma pessoa sem editar ou
apagar os movimentos anteriores.

## Antes de começar

- abra a conta corrente da pessoa correta;
- confira o saldo e o histórico completo;
- confirme que pagamento, estorno ou compensação normal não resolve o caso;
- tenha a alçada individual de ajuste e uma justificativa documentada.

## Como executar

1. Abra o bloco **Ajuste manual excepcional**.
2. Informe um valor positivo para crédito ou negativo para débito.
3. Selecione o motivo controlado.
4. Descreva a causa e a referência da correção.
5. Revise a pessoa, o valor e o efeito esperado.
6. Confirme uma única vez e aguarde a mensagem de resultado.

## O que acontece depois

O sistema cria um novo movimento append-only. O saldo é recalculado, mas os
créditos, pagamentos, estornos e ajustes anteriores permanecem inalterados.

## Bloqueios e correção

Valor zero, motivo inválido, justificativa insuficiente, falta de alçada ou
repetição divergente são recusados. Atualize a página antes de reenviar uma
solicitação já utilizada com dados diferentes.

## Histórico gerado

O evento registra pessoa, valor, motivo, detalhamento, usuário, data e chave de
idempotência. Ajuste manual não substitui pagamento nem altera a regra de
liberação proporcional.
