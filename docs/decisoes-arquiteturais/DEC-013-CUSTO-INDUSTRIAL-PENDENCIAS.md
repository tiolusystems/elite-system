# DEC-013 - Pendências do custo industrial por lote

## Contrato já definido

- custo de aquisição de MP preserva mercadoria, frete, DIFAL e outras despesas;
- a UF do emitente não cria tributo por inferência;
- custo planejado usa quantidade reservada e custo unitário congelado do lote;
- custo realizado usa quantidade efetivamente consumida;
- preço futuro não recalcula OP histórica;
- custo ausente permanece pendente, nunca vira zero silenciosamente.

## Fonte relacional existente

`est_movimentos_mp_valores` contém um registro imutável por movimento de entrada
de MP, com quantidade-base, moeda, mercadoria, frete, DIFAL, outras despesas,
custo total e custo unitário calculado. Essa tabela permite calcular e congelar
o custo direto da MP consumida por lote.

## Lacunas que impedem implementar sem decisão empresarial

| Decisão | Por que é necessária | Risco de inferir |
|---|---|---|
| Método de custo do lote com mais de uma entrada | definir média ponderada móvel, média do lote ou camada por entrada | custo diferente para a mesma saída |
| OP com mais de um lote/produto gerado | definir rateio por litros, massa, quantidade, valor ou produto principal/subproduto | margem e estoque valorizados incorretamente |
| Perda de processo | definir se integra custo da produção boa ou vira perda separada | custo unitário subestimado ou superestimado |
| Mão de obra e custos indiretos | definir se entram agora e qual direcionador usar | resultado contábil sem fundamento |
| Envase PI -> PA | definir se custo da embalagem soma ao PI por unidade efetivamente consumida | PA sem custo completo ou com dupla contagem |
| MP/PI/PA sem custo anterior | bloquear fechamento, gerar pendência ou permitir custo parcial | relatório financeiro enganoso |

## Implementação segura após decisão

1. ledger append-only de snapshots de custo por reserva e consumo;
2. fontes de custo relacionadas por FK, sem JSON como substituto relacional;
3. custo planejado congelado na reserva;
4. custo realizado congelado na baixa;
5. custo do lote PI/PA relacionado à OP e às fontes consumidas;
6. views de custo completo e pendências;
7. RPCs auditadas, RLS, testes concorrentes e reconciliação.

Nenhuma regra de rateio foi implementada neste documento.

## Decisões empresariais aprovadas em 2026-07-21

- entradas diferentes da mesma partida de MP permanecem em camadas de custo
  separadas e são consumidas na ordem de entrada;
- uma OP de produção gera somente um produto e um lote PI;
- perda de processo e perda de estoque possuem fatos e custos distintos;
- o custo do PI inclui somente as MP consumidas, líquidas da perda de processo;
- o custo do PA inclui o custo do PI consumido mais as embalagens consumidas;
- a perda de estoque de PA carrega PI e embalagens na proporção retirada;
- custos operacionais, mão de obra e indiretos ficam fora do escopo atual;
- o custo final do PA por embalagem será a base de uma futura precificação.

Essas decisões são implementadas pela migration 0077. Valores ausentes continuam
pendentes e moedas diferentes permanecem como componentes monetários separados,
sem multiplicar a quantidade física do lote.
