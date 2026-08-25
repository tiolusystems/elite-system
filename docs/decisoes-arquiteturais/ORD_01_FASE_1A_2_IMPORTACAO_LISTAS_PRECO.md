# ORD-01 Fase 1A.2 - Importacao de listas de preco

## Decisoes aplicadas

- Cada operacao recebe um unico XLSX. Somente sua primeira worksheet e processada; as demais sao ignoradas e registradas como alerta de importacao.
- Cada XLSX e registrado com hash, nome e tamanho; o SHA-256 identifica workbook repetido e retorna o staging existente sem criar outro. Cada linha processada permanece rastreavel pela infraestrutura `source_workbooks`, `source_tables`, `source_rows` e `migration_batches`.
- Abas e colunas de prazo sao apenas formatos de apresentacao. Cada preco vira uma linha com `prazo_dias`, inclusive `0` para a vista.
- O valor bruto e preservado como texto e decimal, incluindo coluna e celula de preco. O banco revalida a celula de origem antes de normalizar. A publicacao usa `valor_centavos_por_litro`, calculado com arredondamento decimal comercial `HALF_UP` para duas casas, sem ponto flutuante.
- Produto e apresentacao sao conciliados somente com IDs existentes. Grupo da planilha e contexto bruto, nunca identidade de produto. O importador nao cria cadastros.
- Produto/apresentacao ausente ou ambiguo, valor ou prazo invalido e faixa repetida deixam a importacao bloqueada. Somente importacao integralmente reconciliada pode preencher uma versao rascunho existente.
- A aplicacao recebe regras de escopo explicitamente e reutiliza a RPC canônica da Fase 1A.1. Ela nao infere regra comercial a partir do XLSX.

## Limites desta tranche

Nao inclui PMP, resolucao de lista, pedidos, descontos, credito, campanhas, COMM, overprice ou participantes. A coleta do workbook operacional real permanece pendente; os testes usam workbook sintetico descartavel para provar o contrato sem versionar arquivo comercial.
