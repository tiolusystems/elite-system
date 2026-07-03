# Arquitetura online, multiusuario e auditavel

Data da decisao: 2026-07-03

## Decisao central

O Elite System deve ser construido para operar com banco online, multiplos usuarios, login por senha e registro de cada acao relevante.

SQLite continua permitido apenas como banco local de desenvolvimento, migracao e testes descartaveis. A arquitetura de producao mira PostgreSQL gerenciado em nuvem.

## Banco online

Direcao de producao:

- PostgreSQL gerenciado.
- Backups automaticos.
- Restore testado.
- Credenciais por ambiente.
- Acesso via services e repositories, nunca direto pelas telas.
- Sem dados reais no Git.

O pacote ja reserva dependencia opcional `elite-system[cloud]` para driver PostgreSQL. A troca completa para cloud sera feita no bloco de banco em nuvem, com migracoes versionadas e validacao em banco de testes.

A configuracao do banco deve vir de `ELITE_DATABASE_URL`:

- local: `sqlite:///data/elite.sqlite`;
- producao: `postgresql://...`.

## Usuarios e login

Tabelas-base:

- `users`: cadastro de usuarios, perfil, status e hash de senha.
- `user_sessions`: sessoes futuras do app web.
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

## Pendencias tecnicas

- Implementar sessoes reais para app web.
- Criar camada de permissao por acao.
- Criar migracoes PostgreSQL equivalentes ao schema SQLite.
- Adicionar usuario em cada modulo operacional novo.
- Criar tela de auditoria com filtros por usuario, periodo, modulo e entidade.
