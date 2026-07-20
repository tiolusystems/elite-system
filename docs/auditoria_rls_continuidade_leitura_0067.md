# Continuidade de leitura RLS - migration 0067

Data: 2026-07-20

## Incidente

A migration `0066_close_direct_write_and_rpc_exposure.sql` fechou corretamente
escritas diretas e a exposicao padrao de funcoes, mas removeu tambem o
`EXECUTE` de `authenticated` sobre `public.current_actor_id()`.

Essa funcao nao e uma RPC operacional. Ela e o helper interno usado pelas
politicas RLS de leitura para validar que `auth.uid()` pertence a um perfil
ativo. Sem o privilegio de execucao, consultas autenticadas falham antes de a
politica poder decidir se a linha e visivel.

O incidente foi detectado no smoke visual de Pessoas no staging: login e
health-check estavam saudaveis, mas Cadastros retornava indisponibilidade e
nenhum registro. O frontend novo foi revertido; a repeticao no frontend
anterior confirmou que a causa estava no contrato do banco.

## Correcao minima

`0067_restore_rls_read_helper_access.sql`:

- concede `EXECUTE` de `current_actor_id()` somente a `authenticated`;
- mantem `anon` e `PUBLIC` sem execucao;
- nao concede leitura ou escrita em tabela;
- nao altera policies, RLS, RPCs operacionais, regras de negocio ou dados;
- preserva a validacao interna de perfil ativo executada pelo helper.

## Fortalecimento do gate

O gate de seguranca passa a consultar dependencias de `pg_policy` em
`pg_depend`. Toda funcao do schema `public` usada por policy aplicavel a
`authenticated` deve continuar executavel pelo papel. Assim, uma futura
allowlist nao pode fechar escrita e quebrar silenciosamente a leitura.

O smoke dedicado comprova:

- perfil ativo autenticado resolve `current_actor_id()`;
- leituras representativas de Cadastros, Estoque e Pedidos funcionam;
- escrita direta autenticada continua negada;
- `anon` e `PUBLIC` continuam sem executar o helper.

## Limite de publicacao

A migration deve ser validada primeiro em instalacao limpa e upgrade
descartavel. Staging somente pode recebe-la depois do gate tecnico aprovado e
de dry-run que liste exclusivamente a `0067`.

## Validacao descartavel concluida

Foram usados dois recursos independentes, sem contato com o runtime ativo,
staging ou producao:

- `elite-validation-rls0067-clean`: cadeia completa de 65 migrations ate a
  `0067`;
- `elite-validation-rls0067-upgrade`: cadeia de 64 migrations ate a `0066`,
  seguida da aplicacao isolada da `0067`.

Cada projeto usou container, volume e porta proprios. Os dois alvos passaram
pela trava `assert-disposable-supabase-target.ps1` antes da execucao.

Resultados:

- instalacao limpa: aprovada;
- upgrade `0066 -> 0067`: aprovado;
- gate executado ainda em `0066`: falhou como esperado ao identificar policy
  dependente de `current_actor_id()` sem `EXECUTE` para `authenticated`;
- gate de escrita direta apos a `0067`: aprovado nos dois bancos;
- smoke de continuidade de leitura apos a `0067`: aprovado nos dois bancos;
- leitura autenticada de Cadastros, validacao, Estoque e Pedidos: aprovada;
- escrita direta por `authenticated`: permaneceu negada;
- `anon` e `PUBLIC`: permaneceram sem executar o helper;
- marcadores: `ELITE_SECURITY_ZERO_DIRECT_WRITE_GATE_OK` e
  `ELITE_SECURITY_RLS_READ_CONTINUITY_OK`.

O smoke usa somente ator sintetico dentro de transacao encerrada por
`ROLLBACK`. Nenhum dado operacional foi criado ou versionado.

O lint PostgreSQL foi executado nos dois alvos e apresentou a mesma baseline
de quatro achados em funcoes antigas de Seguranca dependentes do schema
completo do Auth/GoTrue (`auth.jwt()` e `email_confirmed_at`). A imagem
PostgreSQL isolada nao executa o servico GoTrue que completa esse contrato.
Nao surgiu achado novo ou divergente no upgrade, e a `0067` nao cria nem altera
funcao. Por isso, essa baseline nao foi ocultada nem atribuida falsamente a
correcao de RLS.
