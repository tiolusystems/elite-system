# Elite System - contrato de trabalho

Este arquivo define a linha de trabalho obrigatoria para agentes e desenvolvedores no Elite System.

## Orientacao minima

1. Comece por `docs/arquitetura/ARQUITETURA_GERAL.md`.
2. Execute `git status --short --branch` e identifique apenas arquivos alterados desde a baseline.
3. Localize o modulo, o dominio proprietario e suas dependencias no mapa arquitetural.
4. Leia somente a rota, o servico/RPC, a migration vigente e os testes diretamente relacionados.
5. Amplie a leitura apenas quando houver evidencia de impacto transversal ou divergencia com o mapa.

Nao refaca inventario geral do repositorio para tarefas locais. Nao releia migrations antigas em cadeia quando o contrato atual e os testes de schema respondem a pergunta.

## Linha de implementacao

1. Reutilize o padrao aprovado no modulo proprietario.
2. Mantenha a direcao `tela -> aplicacao -> RPC auditada -> dominio proprietario`.
3. Escrita entre dominios passa pela API/RPC interna do dominio dono; nunca por escrita direta em tabela alheia.
4. Regras historicas e movimentos fisicos/financeiros permanecem append-only quando o mapa assim determina.
5. Mudanca arquitetural exige atualizar o mapa e, quando aplicavel, registrar uma decisao curta em `docs/`.
6. Mudanca de maturidade deve aparecer na tela `/modulos`; nao invente percentual visual paralelo.

## Validacao proporcional

- Documentacao: teste de contrato documental e `git diff --check`.
- Mudanca Python: teste direcionado primeiro; suite Python completa uma vez no fechamento.
- Mudanca web: teste de contrato direcionado, `pnpm lint` e `pnpm build` uma vez no fechamento.
- Mudanca SQL: testes estaticos direcionados; reset/lint/smokes do PostgreSQL descartavel uma vez no fechamento.
- Mudanca transversal, seguranca ou release: gate completo do CI.

Nao repita comando quando codigo, configuracao, banco e `HEAD` nao mudaram. Uma repeticao deve ter motivo objetivo: entrada alterada, ambiente reiniciado, falha anterior investigada ou gate final de publicacao.

## Economia de contexto

- Prefira `rg` com termo e caminho especificos a listagens recursivas amplas.
- Leia trechos relevantes, nao arquivos inteiros repetidamente.
- Use saidas resumidas (`git status --short`, `git diff --stat`, JSON filtrado do CI).
- Nao acompanhe CI com atualizacao verbosa continua; consulte estado e conclusao.
- Depois de uma tentativa falhar, investigue a causa antes de trocar de ferramenta ou repetir.

## Dados e seguranca

- Git recebe somente codigo e documentacao sem dados operacionais.
- Nunca versionar workbook, banco, exportacao, chave, senha ou evidencia comercial real.
- Testes de escrita usam banco descartavel ou copia temporaria, nunca banco operacional.
- Nao reduzir RLS, auditoria, constraints ou guards para facilitar teste ou interface.

## Fonte de verdade

- Arquitetura humana e navegacao: `docs/arquitetura/ARQUITETURA_GERAL.md`.
- Catalogo executavel dos modulos: `apps/web/lib/system-map.ts`.
- Dependencias e maturidade efetiva: PostgreSQL (`sys_modules`, `sys_module_dependencies` e ledgers de rollout).
- Evidencia de integridade: testes e CI associados ao commit atual.
