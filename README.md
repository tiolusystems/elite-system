# Elite System

Base inicial do Elite System, o novo software comercial, industrial e auditavel criado a partir do historico preservado localmente.

## Comece pelo mapa

Antes de alterar codigo ou procurar um modulo, consulte `docs/arquitetura/ARQUITETURA_GERAL.md`. O documento mostra as camadas, os dominios proprietarios, as dependencias, os fluxos ponta a ponta, a maturidade e o localizador rapido de arquivos.

A tela `/modulos` apresenta o mesmo sistema de forma visual e consulta no PostgreSQL o ambiente, a maturidade e o acesso efetivo de cada modulo.

## Decisao principal

A stack operacional definida e PostgreSQL, Supabase, Next.js e Vercel.

O nucleo Python permanece responsavel por migracao, auditoria e reconciliacao do historico. O app operacional novo fica em `apps/web` e usa Supabase/PostgreSQL como backend inicial.

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

Criar usuario local:

```powershell
python -m elite_system.cli create-user --db .\data\elite.sqlite --username admin --role admin
```

Testar login:

```powershell
python -m elite_system.cli login --db .\data\elite.sqlite --username admin
```

Ver trilha de auditoria:

```powershell
python -m elite_system.cli audit-log --db .\data\elite.sqlite --limit 20
```

Listar permissoes/checks:

```powershell
python -m elite_system.cli permissions --db .\data\elite.sqlite --user-id 1
```

Abrir tela administrativa local:

```powershell
python -m elite_system.cli admin --db .\data\elite.sqlite --port 8765
```

Quando essa tela operar com banco local, temporario ou descartavel, ela exibe aviso visual e resumo analitico do ambiente. Essa regra evita confundir teste com banco operacional.

Iniciar o ambiente web e o Supabase local:

```powershell
.\iniciar-elite-local.cmd
```

O script gera `apps/web/.env.local` somente com as chaves locais e espera o health-check antes de informar sucesso. O bootstrap auditado do primeiro administrador esta documentado em `docs/operacao_local_modulos.md`.

## Supabase/PostgreSQL

A CLI do Supabase pode ser instalada localmente em `.tools/supabase-cli/supabase.exe`. A pasta `.tools/` e ignorada pelo Git.

Verificar CLI local:

```powershell
.\.tools\supabase-cli\supabase.exe --version
```

O projeto Supabase fica configurado em `supabase/config.toml` e as migrations ficam em `supabase/migrations`. O banco novo nasce fechado em `unconfigured`; modulos sao liberados por ambiente na tela `/modulos`.

Validacao estrutural sem dados reais:

- criar um PostgreSQL descartavel em `.tools/pg-validate`;
- aplicar as migrations em ordem com `psql -v ON_ERROR_STOP=1`;
- executar smoke tests sem dados reais;
- descartar/parar o banco ao final.

O registro da validacao fica em `docs/validacao_supabase_migrations_descartavel.md`.

## Observacao

SQLite e usado agora para desenvolvimento local e auditoria. O desenho prepara a migracao para PostgreSQL/Supabase.

O sistema ja possui base de usuarios, hash de senha, `action_logs` append-only e permissoes por checks. A regra inicial e autonomia total para usuarios ativos; depois as alçadas podem ser reduzidas por perfil ou usuario.

Para ambientes futuros, o banco sera configurado por `ELITE_DATABASE_URL`. Exemplo local: `sqlite:///data/elite.sqlite`. Exemplo producao: `postgresql://...`.

## Politica de dados

O Git deve receber apenas codigo e documentacao tecnica sem dados reais. Workbooks, bancos locais, extracoes, relatorios gerados e qualquer evidencia com valores comerciais ficam fora do versionamento.
