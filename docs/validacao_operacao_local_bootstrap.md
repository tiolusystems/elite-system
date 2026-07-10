# Validacao da operacao local e primeiro administrador

Data: 2026-07-10

## Escopo

- migration `0042_first_admin_operational_bootstrap.sql`;
- indices das FKs do runtime modular;
- bootstrap unico do primeiro administrador;
- scripts de inicio, parada e bootstrap local;
- documentacao e CI do fluxo operacional.

## Validacoes aprovadas

- `pnpm lint`: aprovado antes deste bloco de scripts, sem mudanca posterior em TypeScript;
- `pnpm build`: aprovado com Next.js 16.2.10 e TypeScript;
- parser PowerShell: `start-local.ps1`, `stop-local.ps1` e `bootstrap-local-admin.ps1` sem erro sintatico;
- smoke `PG_MODULE_ROLLOUT_RUNTIME_OK` aprovado;
- smoke isolado `PG_FIRST_ADMIN_OPERATIONAL_BOOTSTRAP_OK` aprovado;
- marcador `PG_0042_REUSED_DB_ISOLATED_SMOKE_OK` aprovado.

O smoke 0042 confirmou:

- `anon` e `authenticated` sem `EXECUTE`;
- chamada sem claim `service_role` negada antes de ler perfis;
- primeiro perfil humano criado como `admin`, `active` e nao-sistema;
- auditoria sem email, senha ou outra credencial;
- segunda inicializacao recusada;
- nenhum perfil gravado pela segunda tentativa;
- tres indices novos cobrindo FKs dos ledgers da migration 0041.

## Suite Python

A suite existente passou antes da edicao deste bloco:

```text
Ran 192 tests
OK
```

O novo teste `test_operational_bootstrap_contract.py` foi adicionado ao discovery e ao CI. A repeticao local depois da edicao ficou pendente porque a ferramenta externa atingiu limite temporario de execucao; isso nao deve ser descrito como teste aprovado ate uma nova execucao real.

## Supabase local

Todas as imagens do stack foram baixadas. Duas tentativas longas e concorrentes deixaram o container local `supabase_db_elite-system` com nome reservado, e a CLI recusou substituir esse container automaticamente.

O container deve ser inspecionado e removido somente depois de confirmar que pertence ao stack local incompleto. Nao foi usado comando de remocao destrutiva e nenhum volume foi descartado nesta validacao.

## Reconstrucao limpa pendente

A cadeia exata `0001` a `0042` ainda precisa ser reconstruida em Supabase descartavel limpo depois da limpeza controlada do container. A instancia PostgreSQL antiga disponivel em `.tools` nao e prova substituta: ela ja estava incompleta em relacao aos indices da 0040.

So apos essa reconstrucao podem ser marcados:

- `PG_FULL_CHAIN_WITH_SEED_OK` para `0001` a `0042`;
- smoke do primeiro admin no Supabase completo;
- login real e troca obrigatoria de senha;
- aplicacao local com `/api/health` e `/modulos` autenticados.

## Dados e segredos

Nenhum dado comercial, workbook, dump, chave, email real ou senha foi adicionado ao Git. `.env.local`, logs, PIDs e runtimes continuam ignorados.
