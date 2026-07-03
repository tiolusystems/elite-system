# Arquitetura do Elite System

## Objetivo

Construir o Elite System como software operacional auditavel para comercial, producao, estoque, expedicao, relatorios e migracao historica do Excel.

O sistema deve nascer com separacao clara de responsabilidades para permitir auditorias serias, migracao segura para banco em nuvem e evolucao gradual sem perder o historico.

## Principios

1. Historico nunca e descartado silenciosamente.
2. Toda migracao tem fonte, hash, batch, linha original e resultado auditavel.
3. Regras de negocio ficam no dominio e nos servicos, nao espalhadas em telas.
4. Banco e infraestrutura ficam atras de repositories.
5. Parsers leem fontes externas, mas nao decidem regra operacional.
6. Apps/views so chamam services.
7. Cada modulo deve ter teste e auditoria antes de virar tela principal.
8. Toda acao operacional deve ter usuario, permissao e log de auditoria.

## Hierarquia de codigo

```text
elite_system/
  apps/              # Streamlit/FastAPI/CLI e entradas de usuario
  domain/            # modelos, regras e objetos de negocio
  services/          # casos de uso e orquestracao
  repositories/      # acesso a banco e persistencia
  parsers/           # leitura de Excel, CSV, PDFs e fontes externas
  validators/        # validacoes de entrada, migracao e consistencia
  maintenance/       # ferramentas de reparo, auditoria e manutencao
  services/security.py       # login, senha e log de acoes
  repositories/security_repository.py
  db.py              # conexao SQLite atual, futuro adaptador PostgreSQL
  schema.sql         # schema inicial auditavel
  migration.py       # importacao de workbook e normalizacao inicial
  reconciliation.py  # reconciliacao de valores contra Excel
  audit.py           # relatorio consolidado de auditoria
  cli.py             # comandos operacionais locais
```

## Dependencias permitidas

```text
apps -> services
services -> domain, repositories, validators, parsers
repositories -> domain, db
parsers -> bibliotecas de arquivo, sem depender de services
validators -> domain
maintenance -> services, repositories, audit
domain -> sem dependencia interna de infraestrutura
```

Dependencias proibidas:

- `domain` importar `db`, `sqlite3`, Streamlit, FastAPI ou parsers.
- `apps` acessar SQLite diretamente.
- `parsers` gravarem no banco diretamente.
- `repositories` chamarem telas.
- regras de custo/estoque/pedido ficarem escondidas em SQL sem teste.

## Modulos de negocio

### Cadastros

Responsavel por clientes, vendedores, veiculos, materias-primas, produtos, embalagens e garantias.

Entidades principais:

- `Cliente`
- `Vendedor`
- `MateriaPrima`
- `Produto`
- `Veiculo`
- `Embalagem`
- `Garantia`

### Comercial

Responsavel por pedidos, itens de pedido, bonificacoes, devolucoes, status de entrega, comissoes e faturamento.

Entidades principais:

- `Pedido`
- `PedidoItem`
- `Comissao`
- `EntregaPrevista`

### Estoque

Responsavel por saldos, movimentos, lotes, inventario e posicao por periodo.

Entidades principais:

- `MovimentoEstoqueMP`
- `MovimentoEstoquePA`
- `LoteMateriaPrima`
- `SaldoEstoque`
- `Inventario`

### Producao

Responsavel por ordens de producao, fichas tecnicas, consumo de materia-prima, lotes produzidos e simulacao.

Entidades principais:

- `OrdemProducao`
- `FichaTecnica`
- `FormulaItem`
- `LoteProducao`
- `SimulacaoProducao`

### Expedicao

Responsavel por romaneio, carregamento, veiculos, volumes, pesos, lotes e entrega.

Entidades principais:

- `Romaneio`
- `RomaneioItem`
- `Entrega`
- `Carga`

### Auditoria e Migracao

Responsavel por preservar fonte, reconciliar dados e mostrar pendencias.

Entidades principais:

- `SourceWorkbook`
- `MigrationBatch`
- `SourceRow`
- `MigrationIssue`
- `ValueReconciliation`

## Banco de dados

Fase atual:

- SQLite local para desenvolvimento e auditoria.
- Todos os imports preservam camada bruta.
- Todas as entidades normalizadas guardam `source_row_id`.
- Usuarios, senha e `action_logs` ja existem no schema local.

Fase cloud:

- PostgreSQL gerenciado.
- Backups automatizados.
- Migrações versionadas.
- Controle de acesso por perfil.
- Banco online com multiplos usuarios e trilha de auditoria.

## Perfis de usuario previstos

- Administrador
- Comercial
- Producao
- Estoque
- Expedicao
- Auditoria/gestao

## Segurança e auditoria operacional

Regras obrigatorias:

- senha nunca fica em texto puro;
- login bem-sucedido e login negado ficam em `action_logs`;
- todo usuario ativo com login valido comeca com autonomia total;
- alçadas futuras serao retiradas por checkboxes em permissoes por perfil ou usuario;
- toda escrita futura deve chamar `log_action()` na mesma transacao;
- `action_logs` e append-only;
- telas nao recebem permissao para alterar log de auditoria.

Detalhamento: `docs/arquitetura_online_multiusuario.md`.

## Regra de homologacao

Um modulo so e considerado pronto quando:

1. importa ou grava dados com rastreabilidade;
2. possui auditoria de contagem e valores;
3. tem testes automatizados;
4. tem tela ou comando de operacao;
5. passa em reconciliacao contra Excel ou explica as divergencias.
