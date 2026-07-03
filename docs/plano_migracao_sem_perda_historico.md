# Plano de migracao sem perda de historico

## Resposta direta

Sim, conseguimos migrar sem perder o historico operacional, desde que a migracao seja feita em camadas e com auditoria.

O ponto central e nunca transformar a planilha diretamente em tabelas finais descartando colunas. Primeiro guardamos tudo em uma camada bruta auditavel. Depois criamos as tabelas normalizadas do sistema. Assim, mesmo que uma tela ou regra ainda nao exista no software, a informacao original continua preservada.

## O que sera preservado

- Arquivo original, com hash SHA-256.
- Versoes futuras da workbook, cada uma como uma nova fonte importada.
- Todas as tabelas estruturadas do Excel.
- Nome da aba, nome da tabela, intervalo original e numero da linha no Excel.
- Valores originais por coluna.
- Formulas por celula quando existirem.
- Linhas que ainda nao forem entendidas pelo modelo normalizado.
- Issues de migracao, sem apagar a linha de origem.

## Camadas do banco

### 1. Camada de fonte

Tabelas:

- `source_workbooks`
- `migration_batches`

Responsabilidade:

- registrar arquivo importado;
- registrar hash, caminho, tamanho e data;
- manter cada rodada de importacao auditavel.

### 2. Camada bruta

Tabelas:

- `source_tables`
- `source_rows`

Responsabilidade:

- guardar cada tabela estruturada extraida da workbook;
- guardar cada linha original em JSON;
- guardar formulas separadamente;
- permitir reprocessar no futuro sem voltar ao Excel.

### 3. Camada normalizada

Tabelas iniciais:

- `materias_primas`
- `produtos`
- `clientes`
- `vendedores`
- `veiculos`
- `pedidos_linhas`
- `entradas_mp`
- `lotes_producao`
- `saidas_mp`
- `saidas_pa`

Responsabilidade:

- alimentar o futuro software operacional;
- criar chaves, filtros, regras, telas e relatorios;
- permitir migracao para PostgreSQL/cloud.

### 4. Camada de auditoria

Tabelas:

- `migration_issues`
- `imported_records`
- `audit_snapshots`

Responsabilidade:

- comparar o que existia na planilha com o que entrou no banco;
- registrar linhas ignoradas por regra;
- registrar dados faltantes, erros de tipo e conflitos;
- produzir evidencias para homologacao.

## Regra de ouro

Nenhuma linha deve ser descartada silenciosamente.

Se a linha nao entra em uma entidade normalizada, ela permanece em `source_rows`. Se houver problema de interpretacao, o sistema registra em `migration_issues`.

## Estrategia para historico

1. Fazer copia imutavel da workbook.
2. Calcular hash SHA-256.
3. Importar todas as tabelas estruturadas para a camada bruta.
4. Popular a camada normalizada com as tabelas ja mapeadas.
5. Rodar auditoria de contagem por tabela.
6. Criar reconciliacoes de valores importantes:
   - total de pedidos;
   - total vendido;
   - quantidade produzida;
   - entradas de materia-prima;
   - saidas de materia-prima;
   - saidas de produto acabado;
   - saldo de estoque MP;
   - saldo de estoque PA.
7. Repetir a importacao para novas versoes do Excel sem apagar historico anterior.

## Ponto importante

A primeira versao do codigo ainda nao precisa reproduzir todas as formulas. Ela precisa garantir que os dados historicos sejam capturados de forma rastreavel. As regras de negocio serao migradas modulo por modulo e comparadas contra os resultados da planilha.

## Criterio de aceite da migracao

Uma migracao so sera considerada aceita quando:

- a workbook original estiver preservada;
- o hash da fonte estiver registrado;
- as tabelas estruturadas tiverem contagem auditada;
- as entidades normalizadas tiverem rastreio para `source_rows`;
- as diferencas forem registradas em `migration_issues`;
- os relatorios principais fecharem contra o Excel dentro de tolerancia definida.
