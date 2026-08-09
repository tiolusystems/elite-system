# Validacao I1 - analise integral do workbook

Data: 2026-07-13.

## Resultado funcional

O workbook real, mantido fora do Git, foi analisado localmente em modo
somente leitura. O resultado confirmou:

- 155 abas;
- 269 tabelas estruturadas;
- 114 nomes definidos;
- 26.397 linhas declaradas em tabelas;
- 3.095 referencias classificadas;
- SHA256 calculado com 64 caracteres, sem versionar o valor;
- correspondencia integral com o perfil estrutural aprovado.

Nenhum valor de celula foi incorporado ao resultado de validacao ou aos
arquivos versionados.

## Testes direcionados

Comando:

```text
python -m unittest tests.test_historical_workbook_analysis tests.test_historical_workbook_web_contract
```

Resultado: 12 testes aprovados.

Cobertura confirmada:

- arquivo valido;
- arquivo ausente;
- extensao incorreta;
- workbook corrompido;
- fixture sintetica com 155 abas, 269 tabelas e 3.095 referencias;
- nenhuma referencia sem status, destino ou regra;
- analisador Python sem dependencia de escrita PostgreSQL;
- erro CLI legivel por maquina;
- ambiente local e permissao no backend;
- bloqueio de ambiente remoto/operacional;
- remocao do temporario em `finally`;
- aviso literal de somente leitura;
- CSV de metadados com protecao contra formula injection;
- ausencia de workbook, banco ou dump rastreado pelo Git.

## Frontend

- ESLint direcionado aos arquivos I1: aprovado;
- TypeScript `--noEmit`: aprovado;
- lint integral: aprovado;
- build de producao Next.js 16.2.10: aprovado;
- rota autenticada: redirecionamento sem sessao para `/login` aprovado;
- inspecao visual autenticada: pendente de sessao valida no navegador local;
  nao foi criado usuario nem contornado o guard para obter imagem.

## Banco e schema

- migration criada: nenhuma;
- escrita PostgreSQL: nenhuma;
- batch de importacao: nenhum;
- cadeia de migrations: nao executada, pois o schema nao foi alterado;
- unica operacao Supabase: leitura da permissao `migration.mp.view`.

## Dados e versionamento

O workbook real, relatorios locais, JSON de analise e dados comerciais
permanecem fora do repositorio. A fixture de teste e produzida em memoria e em
diretorio temporario durante o teste; nenhum `.xlsx` sintetico e versionado.
