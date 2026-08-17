# ORD-01 - Fase 1D - Snapshot comercial do pedido

## Decisao

A origem comercial e um fato explicito e historico do pedido. Participantes comerciais pertencem ao dominio de Pedidos e sao vinculados relacionalmente por `cad_pessoa_papeis`; nao ha campos fixos de vendedor, agente ou gerente. A mesma pessoa pode participar sob mais de um papel, e mais de uma pessoa pode compartilhar um papel.

O pedido bloqueado recebe, por RPC idempotente e auditada, uma unica referencia comercial imutavel para cada item ativo. A RPC usa exclusivamente o resolvedor da Fase 1C, com a data do pedido, cliente, origem, area, UF e todos os participantes informados. O PMP vem do mesmo contrato operacional do read model financeiro: plano do pedido com origem `sistema`, aprovado, vigente na data corrente da resolucao e mais recente por versao/id. Plano `excel_legado` ou fora de vigencia nao participa.

## Imutabilidade

Cada snapshot preserva contexto, participantes considerados, plano/PMP, lista, versao, publicacao, regra, faixa e preco de referencia em centavos por litro. Mudancas posteriores em cadastros, vinculos ou listas nao reinterpretam o registro. Escrita direta e atualizacao ou exclusao do snapshot sao bloqueadas. Enquanto nao existir revisao governada de pedido com sucessao explicita, a criacao de nova versao de condicao financeira apos o snapshot e bloqueada no banco; a futura revisao substituira essa trava sem editar historia.

## Fronteira

Esta fase nao altera a semantica vigente de `quantidade`, `valor_unitario` ou `valor_total` dos itens. O snapshot registra o preco comercial de referencia em centavos por litro; a integracao definitiva de litros totais vezes BRL/L permanece decisao posterior. Nao ha desconto, credito, comissao, campanha, overprice, logistica ou faturamento nesta tranche.
