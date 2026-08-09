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

## Stack de produto

A stack operacional aprovada e:

- Next.js com App Router e TypeScript para o frontend.
- Supabase como backend inicial.
- PostgreSQL como banco principal em nuvem.
- Vercel para deploy do frontend.
- Python mantido como nucleo de migracao, reconciliacao, auditoria e ferramentas internas.

FastAPI com Uvicorn e ORM fica reservado para uma etapa posterior, se o Supabase deixar de ser suficiente para regras complexas, integracoes externas ou processamento assicrono. App desktop em C# com Avalonia fica fora da primeira entrega e sera reavaliado somente se houver necessidade real de desktop nativo.

Detalhamento: `docs/decisao_stack_web_cloud.md`.

## Hierarquia de codigo

```text
apps/
  web/               # Next.js operacional com Supabase
supabase/
  migrations/        # schema PostgreSQL e politicas Supabase
elite_system/
  apps/              # CLI, admin local e futuras entradas internas Python
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

### Romaneio e expedicao

Responsavel pelo romaneio canonico: escolher pedido a separar, definir separacao total ou parcial, buscar lotes disponiveis, informar faturamento/expedicao e gerar a base auditavel da baixa de produto acabado.

O escopo inicial nao deve transformar toda planilha com nome parecido em codigo. O modulo parte da planilha/tabela `ROMANEIO` aprovada. Montagem completa de carga, roteirizacao, frota e fiscal ficam fora do escopo inicial, salvo se forem regra direta dessa planilha canonica.

Entidades principais:

- `Romaneio`
- `RomaneioItem`
- `ReservaLotePA`
- `BaixaPA`

Regra central:

- pedido aberto nao baixa estoque;
- romaneio em rascunho nao baixa estoque;
- romaneio em separacao pode reservar lote;
- romaneio confirmado gera baixa de PA;
- separacao parcial baixa apenas a quantidade romaneada e mantem saldo pendente no pedido.

Detalhamento: `docs/escopo_romaneio.md`.

### Auditoria e Migracao

Responsavel por preservar fonte, reconciliar dados e mostrar pendencias.

Entidades principais:

- `SourceWorkbook`
- `MigrationBatch`
- `SourceRow`
- `MigrationIssue`
- `ValueReconciliation`

## Banco de dados

Produto operacional:

- PostgreSQL gerenciado via Supabase;
- migrations versionadas e reconstruidas do zero no CI;
- RLS de leitura e escrita somente por RPC auditada;
- relacoes operacionais por PK, FK e constraints;
- backups automatizados e restore ainda a homologar no ambiente cloud.

Ferramentas locais:

- SQLite permanece apenas para migracao, reconciliacao e auditoria do Excel legado;
- PostgreSQL descartavel valida migrations e smokes sem tocar banco real;
- camada bruta preserva workbook, tabela, linha, batch e payload original.

O gate `0039/0040` e sua matriz de propriedade estao documentados em `docs/decisao_gate_arquitetura_integridade.md` e `docs/matriz_propriedade_modulos.md`.

## Operacao incremental

A migration `0041` permite homologar e liberar modulos de forma independente. O banco guarda ambiente, maturidade, acesso e dependencias; o frontend nao decide sozinho se um modulo esta pronto.

Banco novo nasce `unconfigured`. Rotas autenticadas sao vinculadas a modulos, action keys declaram leitura ou escrita e os ledgers de rollout sao append-only. Detalhes: `docs/decisao_operacao_incremental_modulos.md` e `docs/operacao_gradual_modulos.md`.

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
