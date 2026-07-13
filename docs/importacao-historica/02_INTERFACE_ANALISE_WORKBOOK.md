# I1 - interface de analise integral do workbook

Status: implementada em 2026-07-13.

## Objetivo

Permitir que um usuario autenticado selecione o workbook historico e confira
sua estrutura completa antes de qualquer carga. Esta etapa pertence a
`auditoria/importacao historica` e nao cria fatos, batches ou movimentos.

Mensagem obrigatoria da operacao:

> Esta etapa apenas analisa o arquivo. Nenhum dado sera gravado no banco.

## Fluxo tecnico

1. a rota existente `/importacao-historica/mp` recebe o arquivo `.xlsx`;
2. uma Server Action valida ambiente local, limite, extensao e a permissao
   `migration.mp.view`;
3. o arquivo e copiado para um diretorio temporario com nome aleatorio;
4. a ponte server-only chama o modulo Python
   `elite_system.services.historical_workbook` sem shell;
5. o parser existente le somente a estrutura OOXML;
6. o resultado retorna ao navegador como metadados e classificacoes;
7. o diretorio temporario e removido em `finally`, inclusive em erro;
8. o CSV e montado no navegador somente com metadados.

Nao foi criado parser Excel em TypeScript. Nao foi criada dependencia nova,
rota nova, modulo novo, migration, RPC de escrita ou tabela.

## Limites de seguranca

- execucao bloqueada em Vercel e quando `ELITE_DATABASE_MODE=production`;
- fora de desenvolvimento, exige `ELITE_WORKBOOK_ANALYSIS_MODE=local`;
- limite de arquivo: 32 MB;
- limite de resposta do processo local: 64 MB;
- timeout do analisador: 120 segundos;
- nenhuma chamada com service role;
- unica consulta ao Supabase: verificacao de `migration.mp.view`;
- nenhum valor de celula e devolvido pelo contrato estrutural;
- workbook, temporario e relatorio nao sao persistidos pelo sistema;
- o CSV neutraliza celulas iniciadas por `=`, `+`, `-` ou `@`.

## Contrato de analise

O resultado informa:

- nome, tamanho, data de modificacao e SHA256 do arquivo selecionado;
- abas, tabelas, nomes definidos e linhas declaradas;
- formulas e erros Excel por aba;
- intervalo, cabecalhos, linhas e colunas por tabela;
- colunas usadas fora de tabelas estruturadas;
- destino, dominio, status, regra e alerta por referencia;
- totais por dominio e por status;
- compatibilidade com o perfil de referencia `155/269/3.095`.

Os cinco status apresentados sao:

| Status | Significado |
|---|---|
| `defined` | destino relacional direto definido |
| `transform` | exige resolucao de identidade, unidade ou regra |
| `pending` | exige decisao humana antes da carga |
| `rejected` | referencia estrutural invalida para processamento |
| `out_of_scope` | preservada para auditoria/reconciliacao, sem fato operacional |

Todo cabecalho de tabela e toda coluna usada fora de tabela recebe uma
classificacao. O fallback e deliberadamente restritivo: preserva na camada
bruta e impede promocao automatica.

## Ponte Python local

A ponte procura o interpretador nesta ordem:

1. `ELITE_PYTHON_PATH`;
2. runtime Python local do Codex no Windows;
3. launcher `py -3` no Windows;
4. `python` no Windows ou `python3` nos demais sistemas.

`ELITE_REPO_ROOT` pode fixar a raiz do repositorio quando o processo web nao
for iniciado a partir de `apps/web`. A ponte nao envia dados a servicos
externos.

## Relatorio

O download CSV contem somente ordem e nome da aba, tipo de origem, tabela,
intervalo, coluna, codigo de classificacao, status, dominio, destino, regra e
alerta. Valores de clientes, produtos, lotes, pedidos e documentos nao entram
no relatorio.

## Limite desta entrega

I1 encerra na analise. I2 sera responsavel pela carga integral na camada bruta
auditavel, com origem, batch, linha, idempotencia e transacao. I1 nao inicia
nem antecipa essa carga.
