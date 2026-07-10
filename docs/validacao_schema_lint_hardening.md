# Validacao do endurecimento de lint do schema

Data: 2026-07-10

## Escopo

- migration `0043_schema_lint_hardening.sql`;
- persistencia da observacao da reserva de componente da OP;
- classificacao de volatilidade coerente com identidade e estado de sessao;
- fluxo terminal explicito do alocador interno de sequencia de pedido;
- perfil minimo repetivel do Supabase local no Windows.

## Decisoes

- `p_observacao` deixa de ser parametro descartado e passa a ser dado operacional limitado a 2.000 caracteres, persistido e incluido no evento de auditoria;
- observacao vazia nao apaga texto existente durante atualizacao de uma reserva;
- `normalize_audit_axis` e `STABLE`, pois resolve o valor contra o tipo enum no catalogo;
- funcoes de consulta do runtime modular sao `VOLATILE`, pois dependem do ator e do estado da sessao;
- `next_com_pedido_sequencia` permanece helper interno sem `EXECUTE` para roles web e ganha falha terminal explicita para verificacao estatica;
- o inicio local usa apenas PostgreSQL, Auth, PostgREST e gateway; servicos opcionais continuam cobertos pelo stack completo do CI.
- a leitura de `supabase status` ignora somente o canal informativo dos servicos opcionais parados e continua falhando quando o processo retorna codigo diferente de zero.

## Evidencias executadas

- cadeia limpa de migrations `0001` a `0043`: aprovada com seed;
- `supabase db lint --local --level warning`: zero advertencias;
- `PG_SCHEMA_LINT_HARDENING_OK`: aprovado;
- `PG_ARCHITECTURE_INTEGRITY_GATE_OK`: aprovado;
- `PG_MODULE_ROLLOUT_RUNTIME_OK`: aprovado;
- `PG_FIRST_ADMIN_OPERATIONAL_BOOTSTRAP_OK`: aprovado;
- suite Python: `Ran 201 tests`, `OK`;
- parser dos tres scripts PowerShell: aprovado;
- lint web: aprovado;
- build Next.js 16.2.10 e TypeScript: aprovado;
- health-check: `status=ok`, `backendConfigured=true`;
- login real: aceito e redirecionado para troca obrigatoria da senha;
- runtime: ambiente `test`, com 13 modulos disponiveis e modulos de negocio em `technical_validation`.

Nenhum dado real ou segredo pertence a esta documentacao.
