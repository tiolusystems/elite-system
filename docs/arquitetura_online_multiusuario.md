# Arquitetura online, multiusuario e auditavel

Data da decisao: 2026-07-03

## Decisao central

O Elite System deve ser construido para operar com banco online, multiplos usuarios, login por senha e registro de cada acao relevante.

SQLite continua permitido apenas como banco local de desenvolvimento, migracao e testes descartaveis. A arquitetura de producao passa a mirar PostgreSQL no Supabase, com frontend em Next.js e deploy na Vercel.

## Banco online

Direcao de producao:

- PostgreSQL gerenciado no Supabase.
- Autenticacao inicial pelo Supabase Auth.
- Frontend operacional em Next.js.
- Deploy do frontend na Vercel.
- Backups automaticos.
- Restore testado.
- Credenciais por ambiente.
- Acesso via camada controlada do app, policies, services e auditoria.
- Sem dados reais no Git.

O pacote Python ja reserva dependencia opcional `elite-system[cloud]` para driver PostgreSQL. A troca completa para cloud sera feita no bloco de banco em nuvem, com migrations Supabase versionadas e validacao em banco de testes.

A configuracao do banco deve vir de `ELITE_DATABASE_URL`:

- local: `sqlite:///data/elite.sqlite`;
- producao: `postgresql://...`.

A configuracao do app Next.js deve vir de variaveis de ambiente:

- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`;
- `ELITE_DATABASE_MODE`: `local`, `test`, `staging` ou `production`;
- `ELITE_DATABASE_LABEL`: rotulo visual do ambiente.

Segredos administrativos, service role keys, dumps e backups nao podem ser versionados.

## Aviso de ambiente de banco

Qualquer tela visual ou analitica que rode contra banco local, temporario ou descartavel deve avisar claramente essa condicao antes de qualquer acao.

Padrao obrigatorio:

- banner visual no topo ou dentro da tela;
- resumo analitico com a classificacao do banco;
- nao exibir caminho completo com pastas do usuario;
- banco descartavel nao pode ser apresentado como producao;
- validacoes automatizadas de escrita devem usar banco descartavel.

A tela administrativa de usuarios e alcadas ja classifica e exibe:

- `BANCO DE TESTE/DESCARTAVEL` para bancos temporarios, de teste ou etapa 2;
- `BANCO LOCAL/DESENVOLVIMENTO` para `data/elite.sqlite`;
- `BANCO OPERACIONAL` somente quando nao houver marcador local ou descartavel.

## Usuarios e login

Tabelas-base:

- `users`: cadastro de usuarios, perfil, status e hash de senha.
- `user_sessions`: sessoes futuras do app web.
- `permission_actions`: catalogo de acoes que aparecerao na tela de checks.
- `role_permission_overrides`: excecoes por perfil.
- `user_permission_overrides`: excecoes por usuario.
- `action_logs`: trilha de auditoria das acoes.

Senha:

- Nunca armazenar senha em texto puro.
- Usar hash PBKDF2-SHA256 com salt unico por usuario.
- Tentativas de login com sucesso e falha sao registradas em `action_logs`.

Perfis iniciais:

- `admin`
- `comercial`
- `producao`
- `estoque`
- `expedicao`
- `auditoria`

## Auditoria de acoes

Toda acao operacional deve registrar:

- usuario executor, quando houver;
- data/hora UTC;
- acao executada;
- entidade afetada;
- status;
- snapshot antes/depois quando aplicavel;
- metadados tecnicos sem senha ou segredo;
- hash da entrada anterior;
- hash da entrada atual.

`action_logs` e append-only: o banco bloqueia `UPDATE` e `DELETE` nessa tabela. Isso nao substitui backup nem permissao correta no banco cloud, mas reduz risco de adulteracao local e cria trilha verificavel.

## Alçadas e checks

Regra inicial: todo usuario ativo com login valido tem autonomia total.

A tela de alçadas sera construida com checkboxes. Cada checkbox representa uma `permission_action`.

Modelo de decisao:

1. usuario inativo nao acessa;
2. override por usuario decide primeiro;
3. se nao houver override por usuario, override por perfil decide;
4. se nao houver override, vale o padrao da acao;
5. acoes novas ou ainda nao cadastradas ficam liberadas ate serem restringidas.

Isso permite iniciar a operacao sem travar usuarios e, depois, reduzir acessos por modulo, perfil ou pessoa.

## Regra para novos modulos

Nenhuma tela deve escrever direto no banco.

Fluxo obrigatorio:

```text
apps/views -> services -> repositories -> banco
```

Toda funcao de service que altera estado deve receber `actor_user_id` ou contexto equivalente e chamar `log_action()` na mesma transacao da mudanca.

## Comandos locais

Criar usuario:

```powershell
python -m elite_system.cli create-user --db .\data\elite.sqlite --username admin --role admin
```

Login:

```powershell
python -m elite_system.cli login --db .\data\elite.sqlite --username admin
```

Listar ultimas acoes:

```powershell
python -m elite_system.cli audit-log --db .\data\elite.sqlite --limit 20
```

Listar checks/permissoes:

```powershell
python -m elite_system.cli permissions --db .\data\elite.sqlite --user-id 1
```

Abrir a tela administrativa local:

```powershell
python -m elite_system.cli admin --db .\data\elite.sqlite --port 8765
```

Retirar uma permissao de um perfil:

```powershell
python -m elite_system.cli set-role-permission --db .\data\elite.sqlite --actor-user-id 1 --role comercial --action estoque.manage --deny
```

Liberar uma permissao especifica para um usuario:

```powershell
python -m elite_system.cli set-user-permission --db .\data\elite.sqlite --actor-user-id 1 --user-id 2 --action estoque.manage --allow
```

## Pendencias tecnicas

- Implementar sessoes reais para app web.
- Expandir tela de checks para manutencao completa de usuarios e perfis.
- Criar migracoes PostgreSQL equivalentes ao schema SQLite.
- Adicionar usuario em cada modulo operacional novo.
- Criar tela de auditoria com filtros por usuario, periodo, modulo e entidade.
