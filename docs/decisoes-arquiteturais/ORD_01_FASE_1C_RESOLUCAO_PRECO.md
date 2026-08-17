# ORD-01 - Fase 1C - Resolucao de referencia comercial

## Decisao

A referencia comercial normal e resolvida automaticamente. O vendedor nao escolhe uma lista. O resolvedor recebe somente a data comercial, o PMP exato e o contexto relacional explicito da operacao, e retorna uma unica lista, versao, publicacao, regra, faixa e preco em centavos por litro.

## Elegibilidade e precedencia

Uma regra aplica AND entre dimensoes preenchidas e OR entre os valores de uma mesma dimensao. Dimensao sem valor configurado e curinga. A apresentacao deve estar na cobertura da versao publicada. Pessoa/papel e uma dimensao multivalorada do contexto operacional: a regra de pessoa aplica quando pelo menos um dos papéis informados pertence ao seu escopo, sem escolha arbitraria de participante. Antes da resolucao, origem comercial, cliente, apresentacao, area informada e todos os participantes informados sao validados por ID; a UF informada e normalizada e validada no catalogo canonico. Contexto invalido falha fechado antes de qualquer fallback curinga.

Entre regras aplicaveis, a maior especificidade vence primeiro; especificidade e a quantidade de dimensoes de escopo preenchidas. Somente entre regras de mesma especificidade, a menor `prioridade` numerica tem precedencia. Regra sem prioridade explicita fica depois de qualquer regra com prioridade numerica. Assim, uma regra de agente especifico pode prevalecer sobre uma regra geral mesmo com numero de prioridade maior, sem que a origem `agente` imponha automaticamente uma lista de agente. Empate persistente de especificidade e prioridade e ambiguidade: o resolvedor falha fechado, sem escolher por ID, data ou ordem fisica.

Somente publicacoes existentes na data comercial, vigentes naquela data e sem retirada ou sucessao efetiva participam. A alteracao posterior de uma lista nao reinterpreta uma operacao historica; a Fase 1D congelara o resultado retornado no pedido.

## PMP e faixa

O PMP vem da condicao financeira governada da Fase 1B e e comparado como `numeric`, sem arredondamento para enquadramento. A menor faixa cujo prazo seja maior ou igual ao PMP e escolhida: PMP `47` usa faixa `60`; PMP `0` usa faixa `0` quando existir. Ausencia de lista, ambiguidade, cobertura, faixa ou preco e bloqueio fail-closed.

## Fronteira

Esta fase nao altera itens, valores ou calculos de pedidos. Tambem nao cria snapshot, desconto, credito, comissao, campanha, overprice ou logistica. A Fase 1D consumira o resultado e congelara a referencia comercial da operacao.
