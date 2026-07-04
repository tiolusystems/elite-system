# Escopo de relatorios do Elite System

Data da etapa: 2026-07-04

## Decisao

Relatorios sao modulo essencial do Elite System, nao acessorio.

O Tio Lu System em Excel tinha dezenas de telas e consultas de relatorios. A migracao para software precisa preservar essa capacidade analitica, mas com consultas auditaveis, filtros consistentes e fonte de dados versionada.

## Principios

1. Todo relatorio deve ter fonte clara: tabela, view ou funcao.
2. Relatorios operacionais devem reconciliar com o historico importado quando houver metrica equivalente no Excel.
3. Relatorios nao devem corrigir dado; eles apontam situacao, divergencia, risco ou pendencia.
4. Relatorios criticos devem permitir exportacao futura para Excel/PDF.
5. Relatorios devem respeitar alçadas de usuario.
6. Indicadores devem ser clicaveis ate o detalhe operacional: pedido, lote, OP, cliente, romaneio ou recebimento.

## Catalogo tecnico

Migration: `supabase/migrations/0010_product_validity_reports_foundation.sql`.

Tabela criada:

- `relatorio_catalogo`: catalogo dos relatorios ativos, planejados ou inativos.

Relatorios iniciais registrados:

- `estoque_lotes_vencimento`
- `estoque_reprocessamento_candidatos`
- `pcp_op_status`
- `comercial_pedidos_abertos`
- `romaneio_pendencias`
- `auditoria_reconciliacao`

Tela inicial:

- Next.js: `apps/web/app/relatorios/page.tsx`.
- Preview estatico: `apps/web/preview/relatorios.html`.
- Dados: `apps/web/lib/reports.ts`.

Permissao:

- `reports.view`: visualizar relatorios e dashboards operacionais.

## Relatorios implementados nesta etapa

### Lotes por vencimento

View: `rel_estoque_lotes_vencimento`.

Unifica PA, PI e MP com:

- tipo do lote;
- codigo do lote;
- produto, item ou materia-prima;
- embalagem quando aplicavel;
- status do lote;
- saldo fisico;
- quantidade reservada;
- saldo disponivel;
- data de fabricacao;
- data de validade;
- prazo de validade mestre quando aplicavel;
- dias para vencer;
- status de vencimento.

Status de vencimento:

- `sem_validade`
- `vencido_com_saldo`
- `vencido_sem_saldo`
- `vence_30_dias`
- `vence_60_dias`
- `vigente`

### Candidatos a reprocessamento

View: `rel_estoque_reprocessamento_candidatos`.

Mostra lotes PA, PI ou MP com saldo disponivel que exigem avaliacao:

- vencidos com saldo;
- vencendo em ate 30 dias;
- bloqueados com saldo.

O relatorio classifica prioridade como `alta`, `media` ou `baixa`.

## Prazo de validade no produto

O cadastro de produto-base passa a ter `prazo_validade_meses`.

Uso:

- PA gerado por OP pode receber validade automaticamente quando houver data de fabricacao.
- PI gerado por OP pode receber validade automaticamente quando houver data de fabricacao.
- MP continua usando validade do lote do fornecedor, XML/NF ou informacao manual.

Regra:

- `prazo_validade_meses` pode ficar vazio.
- Quando informado, deve estar entre 1 e 240 meses.
- Mudanca do prazo deve ser auditada por `set_cad_produto_prazo_validade`.

## Relatorios prioritarios ainda planejados

Comercial:

- pedidos em aberto;
- pedidos por cliente;
- faturamento por periodo;
- bonificacoes;
- devolucoes;
- ranking de clientes;
- limite de credito e inadimplencia;
- comissao prevista, liberada e paga.

Romaneio:

- pedidos pendentes de separacao;
- romaneios em rascunho;
- romaneios em separacao;
- baixas por lote;
- divergencia pedido x romaneio x saida PA.

Estoque:

- saldo MP;
- saldo PA;
- saldo PI;
- estoque por lote;
- lotes vencidos;
- lotes bloqueados;
- reservas ativas;
- inventario e ajustes.

PCP:

- OPs abertas;
- OPs finalizadas;
- consumo teorico x consumo baixado;
- PA/PI gerado por OP;
- CQ por OP;
- formulas ativas;
- produtos sem formula.

Auditoria:

- reconciliacao contra Excel;
- diferencas por metrica;
- acoes por usuario;
- tentativas negadas por permissao;
- dados importados sem mapeamento.

## Criterio de aceite

O modulo de relatorios sera considerado fiel quando os principais relatorios do Tio Lu System XLSX estiverem mapeados para:

- nome do relatorio;
- objetivo;
- fonte Excel original;
- fonte no banco novo;
- filtros;
- colunas;
- totalizadores;
- regra de reconciliacao;
- permissao de acesso.
