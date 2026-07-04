# Auditorias de reconciliacao de valores

Data da implementacao: 2026-07-03

## Objetivo

Validar valores agregados do banco migrado contra os valores extraidos da planilha local, nao apenas contagens de linhas.

As reconciliacoes ficam gravadas em `value_reconciliations` e aparecem no comando:

```powershell
python -m elite_system.cli audit --db .\data\elite.sqlite
```

## Metricas implementadas

- `total_pedidos_distintos`: pedidos distintos por identificador de pedido.
- `faturamento_total`: soma do valor total de pedidos.
- `faturamento_vendas`: soma do valor total apenas para pedidos classificados como venda.
- `entradas_mp_quantidade`: soma de quantidade de entradas de materia-prima.
- `entradas_mp_valor`: soma de valor de entradas de materia-prima.
- `saidas_mp_quantidade`: soma de quantidade de saidas de materia-prima.
- `saidas_pa_quantidade`: soma de quantidade baixada de produto acabado.
- `producao_quantidade`: soma de quantidade produzida.
- `producao_custo_mp`: soma de custo de materia-prima em producao.
- `estoque_mp_saldo`: compara saldo informado de materia-prima contra entradas menos saidas.
- `estoque_pa_saldo`: compara saldo informado de produto acabado contra producao menos saidas.

## Resultado esperado

Cada reconciliacao retorna:

- `source_value`: valor agregado vindo da camada bruta importada.
- `normalized_value`: valor agregado vindo das tabelas normalizadas.
- `difference`: diferenca entre normalizado e fonte.
- `status`: `ok`, `attention` ou `issue`.
- `details`: identificadores tecnicos suficientes para rastrear a origem sem expor dados reais em documentacao versionada.

## Detalhamento por item

Alem das metricas agregadas, o sistema grava detalhes em `reconciliation_details` para localizar diferencas:

- `estoque_mp_saldo_por_materia_prima`: compara saldo de materia-prima por item contra entradas menos saidas.
- `estoque_pa_saldo_por_produto`: compara saldo de produto acabado por produto contra producao menos saidas.

Esses detalhes sao sempre vinculados ao `batch_id` da importacao. Isso evita que uma auditoria some registros normalizados de outro historico importado no mesmo banco local.

## Regra de seguranca

Relatorios com valores reais, linhas de planilha, lotes, clientes, produtos, notas fiscais ou qualquer outro historico comercial devem ficar em `outputs/` ou em outra pasta local ignorada pelo Git.

Este documento versionado descreve a logica de auditoria; ele nao deve registrar resultados reais de migracao.

## Proximas auditorias

- Separar diferencas por categoria: linha incompleta, regra ainda nao migrada, ajuste manual, saldo inicial e divergencia real.
- Gerar relatorio local completo em `outputs/`, mantendo somente a especificacao tecnica no Git.

## Fundacao Supabase/PostgreSQL

Migration: `supabase/migrations/0008_audit_reconciliation_foundation.sql`.

A camada cloud recebeu a estrutura equivalente para preservar fonte e reconciliar valores:

- `source_workbooks`: workbook original, hash e metadados.
- `migration_batches`: rodada de importacao.
- `source_tables`: tabelas/abas extraidas.
- `source_rows`: linhas brutas em JSON.
- `migration_issues`: problemas de migracao.
- `imported_records`: vinculo entre linha bruta e entidade normalizada.
- `audit_snapshots`: auditorias de contagem.
- `source_expected_metrics`: valores esperados vindos do Excel ou de resumo validado.
- `audit_reconciliation_runs`: execucoes de reconciliacao.
- `value_reconciliations`: resultado por metrica.
- `reconciliation_details`: detalhes por chave, para evolucao por item/lote/produto.

Funcoes:

- `record_aud_source_expected_metric`: registra valor esperado para uma metrica de um batch.
- `run_aud_reconciliacao_operacional`: compara metricas operacionais do sistema contra os valores esperados registrados.

View operacional:

- `aud_operational_metric_values`: consolida metricas atuais de pedidos, faturamento, recebimentos, comissoes, romaneios e estoque PA.

Metricas iniciais no Supabase:

- `total_pedidos_distintos`;
- `faturamento_total`;
- `faturamento_vendas`;
- `recebimentos_total`;
- `comissao_prevista`;
- `comissao_liberada`;
- `romaneios_confirmados`;
- `romaneios_baixa_pa_quantidade`;
- `entradas_pa_quantidade`;
- `saidas_pa_quantidade`;
- `estornos_pa_quantidade`;
- `estoque_pa_saldo`;
- `estoque_pa_reservado`.

Validacao descartavel:

- rodada com valores esperados corretos retornou `ok`;
- rodada com `faturamento_total` divergente retornou `attention`;
- tentativa de editar `source_rows` foi bloqueada como append-only.

Limite atual:

- reconciliacoes MP e producao entram quando as migrations operacionais desses modulos existirem no Supabase.
