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

## Regra de seguranca

Relatorios com valores reais, linhas de planilha, lotes, clientes, produtos, notas fiscais ou qualquer outro historico comercial devem ficar em `outputs/` ou em outra pasta local ignorada pelo Git.

Este documento versionado descreve a logica de auditoria; ele nao deve registrar resultados reais de migracao.

## Proximas auditorias

- Detalhar reconciliacao por materia-prima.
- Detalhar reconciliacao por produto acabado.
- Separar diferencas por categoria: linha incompleta, regra ainda nao migrada, ajuste manual, saldo inicial e divergencia real.
- Gerar relatorio local completo em `outputs/`, mantendo somente a especificacao tecnica no Git.
