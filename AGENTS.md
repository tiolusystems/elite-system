# Elite System - contrato de trabalho

Este arquivo define a linha de trabalho obrigatoria para agentes e desenvolvedores no Elite System.

## Orientacao minima

1. Comece por `docs/00_MAPA_EXECUTIVO.md`.
2. Leia `docs/01_ESTADO_ATUAL.md` e `docs/02_DECISOES_PENDENTES.md`.
3. Execute `git status --short --branch` e identifique apenas arquivos alterados desde a baseline.
4. Consulte `docs/arquitetura/ARQUITETURA_GERAL.md` apenas na profundidade exigida pelo nivel da tarefa.
5. Leia somente a rota, o servico/RPC, a migration vigente e os testes diretamente relacionados.
6. Amplie a leitura apenas quando houver evidencia de impacto transversal ou divergencia com o mapa.

Nao refaca inventario geral do repositorio para tarefas locais. Nao releia migrations antigas em cadeia quando o contrato atual e os testes de schema respondem a pergunta.

## Linha de implementacao

1. Reutilize o padrao aprovado no modulo proprietario.
2. Mantenha a direcao `tela -> aplicacao -> RPC auditada -> dominio proprietario`.
3. Escrita entre dominios passa pela API/RPC interna do dominio dono; nunca por escrita direta em tabela alheia.
4. Regras historicas e movimentos fisicos/financeiros permanecem append-only quando o mapa assim determina.
5. Mudanca arquitetural exige autorizacao previa do usuario; depois, atualizar o mapa e registrar a decisao curta em `docs/`.
6. Mudanca de maturidade deve aparecer na tela `/modulos`; nao invente percentual visual paralelo.

## Atualizacao obrigatoria do estado

Ao concluir cada tarefa, atualize `docs/01_ESTADO_ATUAL.md` na mesma entrega com:

1. tarefa concluida;
2. arquivos ou modulos afetados;
3. validacao executada e resultado;
4. proxima tarefa objetiva;
5. decisao que bloqueia a proxima tarefa, quando existir.

O arquivo mostra somente o estado vigente. Git preserva o historico; nao acumule diario extenso no documento.

## Validacao proporcional

- Documentacao: teste de contrato documental e `git diff --check`.
- Mudanca Python: teste direcionado primeiro; suite Python completa uma vez no fechamento.
- Mudanca web: teste de contrato direcionado, `pnpm lint` e `pnpm build` uma vez no fechamento.
- Mudanca SQL: testes estaticos direcionados; reset/lint/smokes do PostgreSQL descartavel uma vez no fechamento.
- Mudanca transversal, seguranca ou release: gate completo do CI.

Nao repita comando quando codigo, configuracao, banco e `HEAD` nao mudaram. Uma repeticao deve ter motivo objetivo: entrada alterada, ambiente reiniciado, falha anterior investigada ou gate final de publicacao.

## Telas para validacao de negocio

1. A tela deve usar linguagem do processo da Elite; termos internos de banco e desenvolvimento ficam no codigo, log ou detalhe tecnico.
2. Antes de indicadores, mostrar finalidade, etapa atual, o que ja aconteceu e o que ainda nao aconteceu.
3. Estado vazio deve diferenciar explicitamente `nenhum dado carregado` de `nenhuma pendencia encontrada`.
4. Informar quem executa o proximo passo. Nao apresentar uma decisao ao usuario quando a acao ainda pertence a equipe tecnica.
5. IDs internos, nomes de tabela, `batch`, `staging`, RPC e action key nao aparecem como rotulo principal.
6. Antes de apresentar a tela, validar desktop e mobile, texto completo, ausencia de sobreposicao e coerencia entre mensagem e estado real do banco.
7. Uma tela tecnicamente correta que nao permita ao usuario formar uma imagem mental do progresso nao esta pronta para validacao.

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

- Entrada operacional e classificacao da tarefa: `docs/00_MAPA_EXECUTIVO.md`.
- Estado vigente e proxima tarefa: `docs/01_ESTADO_ATUAL.md`.
- Autorizacoes e decisoes abertas: `docs/02_DECISOES_PENDENTES.md`.
- Arquitetura humana e navegacao: `docs/arquitetura/ARQUITETURA_GERAL.md`.
- Catalogo executavel dos modulos: `apps/web/lib/system-map.ts`.
- Dependencias e maturidade efetiva: PostgreSQL (`sys_modules`, `sys_module_dependencies` e ledgers de rollout).
- Evidencia de integridade: testes e CI associados ao commit atual.
