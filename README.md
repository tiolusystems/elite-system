# Elite System

Base inicial do Elite System, o novo software comercial, industrial e auditavel criado a partir do historico preservado localmente.

## Decisao principal

O sistema tem duas camadas de dados:

1. **Camada bruta auditavel**: guarda a workbook original por hash, as tabelas extraidas, cada linha original em JSON e as formulas encontradas.
2. **Camada normalizada**: transforma as principais tabelas em entidades do software, como clientes, produtos, pedidos, estoque, producao e saidas.

Se uma regra ainda nao foi migrada, a linha original continua preservada na camada bruta.

## Comandos

Inicializar banco local:

```powershell
python -m elite_system.cli init --db .\data\elite.sqlite
```

Importar a workbook:

```powershell
python -m elite_system.cli import-excel --db .\data\elite.sqlite --workbook "..\01-original\workbook-local.xlsx"
```

Rodar auditoria:

```powershell
python -m elite_system.cli audit --db .\data\elite.sqlite
```

A auditoria inclui reconciliacoes de valores para pedidos, faturamento, entradas MP, saidas MP, saidas PA, producao e saldos de estoque.

## Observacao

SQLite e usado agora para desenvolvimento local e auditoria. O desenho evita SQL proprietario e prepara a migracao posterior para PostgreSQL/cloud.

## Politica de dados

O Git deve receber apenas codigo e documentacao tecnica sem dados reais. Workbooks, bancos locais, extracoes, relatorios gerados e qualquer evidencia com valores comerciais ficam fora do versionamento.
