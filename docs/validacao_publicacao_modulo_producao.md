# Validacao da publicacao do modulo Producao

Data: 2026-07-11
Migration: `0044_production_module_release.sql`
Destino desta entrega: ambiente local/teste para validacao de negocio

## Escopo publicado

- cadastros compartilhados de MP, produto-base, embalagem e produto+embalagem;
- formulas de producao e MAPA com versoes imutaveis;
- garantias declaradas por produto e analisadas por lote de MP;
- OP operacional/documental, reservas por lote, inicio, CQ e finalizacao;
- entradas PA/PI e consumos MP/PA/PI pelo livro de movimentos;
- transformacao e reprocessamento por OP, sem edicao direta de saldo;
- calculo ponderado de garantias pelos lotes realmente consumidos;
- bloqueio e liberacao auditada de lotes PA/PI;
- rota responsiva `/producao`, mantendo `/pcp` como alias.

## Invariantes verificadas

1. Garantias e resultados de calculo sao append-only.
2. Nova referencia substitui logicamente a anterior por `supersedes_id`; nao a sobrescreve.
3. Calculo usa `quantidade_consumida` real por lote e guarda a memoria de calculo.
4. Falta de garantia e unidade incompativel produzem status explicito; o sistema nao inventa valor.
5. CQ reprovado/bloqueado preserva o fato fisico e gera lote bloqueado.
6. Transformacao usa OP de `reprocessamento` e movimentos de saida/entrada correlacionados.
7. A tela usa IDs estruturados; nao usa `datalist` nem parsing de `123 | nome`.
8. Toda escrita nova passa pelo wrapper `auditedRpc` e por RPC governada no banco.

## Evidencias executadas

- smoke SQL `tests/sql/production_module_release.sql`: `PG_PRODUCTION_MODULE_RELEASE_OK`;
- `supabase db lint --local --level warning`: zero avisos apos aplicar a 0044;
- reconstrucao limpa: migrations `0001` a `0044` aplicadas do zero;
- sweep de permissao: `ZERO_GRANT_SWEEP_OK`, 61/61 RPCs negadas ao ator sem grants;
- smokes de arquitetura, rollout, primeiro admin e schema lint: OK;
- ESLint direcionado aos arquivos alterados: OK;
- ESLint global: OK;
- `next build`: OK, incluindo TypeScript e rota `/producao`;
- runtime local: `cadastros`, `estoque` e `pcp` em `business_validation` + `read_write`, ambiente `test`, sem bloqueadores;
- login local validado ate o gate obrigatorio de troca da senha temporaria.

## Smoke de negocio coberto

O smoke cria MP, produto, lote e garantias; cria/ativa formula; abre, reserva, inicia e finaliza OP com saida PI; calcula valor ponderado; registra nova versao MAPA; recalcula e confirma mudanca de `atende` para `nao_atende`; tenta alterar/excluir fatos e confirma bloqueio append-only. A transacao termina em `ROLLBACK`.

## Aceite humano ainda necessario

- validar nomenclatura, ordem dos campos e ergonomia em desktop e mobile;
- concluir a troca pessoal da senha temporaria para abrir a rota autenticada no navegador;
- conferir fluxo real com mais de um lote da mesma MP;
- confirmar laudos/documentos usados como fonte de garantia;
- validar transformacoes PA para PI, PI para PA e reenvasamento;
- assinar reconciliacao de estoque e rastreabilidade antes de qualquer promocao para `operational`.

Esta publicacao nao libera banco de producao e nao migra dados historicos reais.
