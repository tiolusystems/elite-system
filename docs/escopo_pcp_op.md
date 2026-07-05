# Escopo PCP e ordem de producao

Data da etapa: 2026-07-04

## Decisao

O PCP passa a ter fundacao propria no PostgreSQL para formula, ordem de producao, reserva de componentes, baixa de consumo, CQ e geracao de lotes PA/PI.

A OP MAPA e documental apenas. Ela registra a receita regulatoria/documental, mas nao reserva, nao baixa e nao gera estoque.

## Regras implementadas

1. Formula e versionada por produto e tipo de receita: `producao` ou `mapa`.
2. Cada nova formula gera nova versao append-only, com hash encadeado.
3. Formula de producao exige ao menos um componente.
4. Alteracao de formula passa por permissao `pcp.formula.change`; a autonomia inicial segue liberada por padrao, mas pode ser retirada por override.
5. OP operacional aceita tipos `estoque`, `experimental`, `desenvolvimento` e `reprocessamento`.
6. OP documental aceita apenas tipo `mapa_documental` e formula `mapa`.
7. OP operacional copia os componentes da formula para componentes planejados.
8. Reserva de componente pode usar MP, PA ou PI, conforme a formula.
9. Reserva reduz disponibilidade, mas nao baixa estoque fisico.
10. Inicio de OP exige reserva ativa completa dos componentes planejados.
11. Finalizacao de OP baixa MP/PA/PI consumido e exige CQ completo.
12. CQ exige `ph`, densidade, volume, massa, temperatura, separador MP, conferente MP e formuladores.
13. OP pode gerar PA, PI ou PA+PI na mesma finalizacao.
14. OP experimental/desenvolvimento gera lotes bloqueados, mesmo com CQ aprovado, ate liberacao posterior.
15. Reprocessamento pode consumir MP+PA+PI e gerar PA/PI como transformacao.
16. Movimentos de MP e PI sao append-only; correcao deve ser novo movimento auditavel.
17. Formula, itens de formula e ativacoes sao append-only; correcao deve ser nova versao.
18. PA e PI gerados por OP podem herdar validade automatica do produto quando o cadastro tiver `prazo_validade_meses`.

## Decisao para finalizacao auditada

A regra detalhada para migrar `finalizar_pcp_op` para o contrato auditado esta em `docs/decisao_finalizacao_pcp_op.md`.

Resumo:

- finalizacao continua em transacao unica;
- falha em qualquer etapa reverte toda a OP;
- CQ reprovado ou bloqueado gera lote bloqueado, nao apaga a producao fisica;
- OP experimental/desenvolvimento gera lote bloqueado mesmo com CQ aprovado;
- segunda finalizacao da mesma OP deve falhar sem duplicar consumo ou entrada;
- todos os logs da finalizacao devem compartilhar `correlation_id = 'pcp_op:' || p_op_id || ':finish'`.
- lote bloqueado deve ser liberado por CQ, qualidade ou gestor tecnico via `pcp.blocked_lot.release`; a OP permanece `completed`.

## Estrutura criada

Migration: `supabase/migrations/0009_pcp_op_foundation.sql`.

Estoque MP:

- `est_lotes_mp`: lote de materia-prima.
- `est_movimentos_mp`: livro fisico de entradas, consumo por OP e ajustes.
- `est_lotes_mp_saldos`: saldo fisico, reserva e disponivel por lote MP.

Estoque PI:

- `est_lotes_pi`: lote de produto intermediario.
- `est_movimentos_pi`: livro fisico de entradas, consumo por OP e ajustes.
- `est_lotes_pi_saldos`: saldo fisico, reserva e disponivel por lote PI.

PCP:

- `pcp_formula_versoes`: versoes de formula por produto/tipo de receita.
- `pcp_formula_itens`: componentes MP/PA/PI da formula.
- `pcp_formula_ativacoes`: historico de ativacao de formula.
- `pcp_formula_ativa`: view da ultima formula ativada por produto/tipo.
- `pcp_ordens_producao`: cabecalho da OP.
- `pcp_op_componentes_planejados`: snapshot dos componentes da OP.
- `pcp_op_reservas_componentes`: reservas de MP/PA/PI por OP.
- `pcp_op_consumos_componentes`: consumos baixados na finalizacao.
- `pcp_op_cq_resultados`: CQ da OP.
- `pcp_op_produtos_gerados`: PA/PI gerado pela OP.

Romaneio:

- `est_reservas_pa` passa a permitir mais de um lote ativo por item de romaneio.
- `confirmar_exp_romaneio` passa a confirmar baixas por cada lote reservado.
- `est_lotes_pa_saldos` passa a considerar reservas de romaneio e reservas PCP.

## Funcoes auditaveis

- `create_est_lote_pa_auto`: cria lote PA com codigo automatico.
- `create_est_lote_mp`: cria lote MP com codigo automatico ou informado.
- `create_est_lote_pi`: cria lote PI com codigo automatico ou informado.
- `create_pcp_formula_versao`: cria versao append-only de formula.
- `activate_pcp_formula_versao`: ativa uma formula, preservando historico.
- `create_pcp_op`: cria OP operacional ou documental MAPA.
- `reservar_pcp_op_componente`: reserva MP/PA/PI para OP.
- `iniciar_pcp_op`: inicia OP com reserva completa.
- `finalizar_pcp_op`: registra CQ, baixa consumos e gera PA/PI.
- `cancelar_pcp_op`: cancela OP planejada e libera reservas.
- `liberar_pcp_lote_bloqueado`: libera lote PA/PI bloqueado por experimental/desenvolvimento/CQ.
- `registrar_est_reserva_pa`: reserva PA multilote para romaneio.
- `confirmar_exp_romaneio`: confirma romaneio e baixa cada lote reservado.

## Tela web implementada

Arquivos:

- `apps/web/lib/pcp.ts`
- `apps/web/app/pcp/actions.ts`
- `apps/web/app/pcp/page.tsx`

Funcionalidades da tela `/pcp`:

- Painel visual/analitico de formulas versionadas, formulas ativas, OP abertas, OP em processo e lotes bloqueados.
- Criacao de nova versao de formula por produto e tipo de receita, com ate seis componentes MP/PA/PI por lancamento.
- Ativacao de formula com motivo auditavel.
- Abertura de OP operacional ou OP MAPA documental.
- Consulta de componentes planejados por OP e reservas ja realizadas.
- Reserva de componentes por lote MP, PA ou PI, sem baixa fisica.
- Inicio da OP apenas por funcao SQL auditavel.
- Cancelamento de OP planejada com motivo.
- Finalizacao da OP com CQ completo, baixa de componentes reservados e geracao de ate tres outputs PA/PI com lote automatico.
- Tabela de lotes MP/PA/PI disponiveis para apoio a reserva.

Status: implementada no Next.js e validada por `pnpm run build`. Ainda precisa ser homologada contra Supabase configurado com usuario logado e dados de teste.

## Permissoes

As acoes foram registradas em `permission_actions` com `default_allowed = true`, mantendo a decisao de autonomia inicial:

- `estoque.mp.lots.create`
- `estoque.pi.lots.create`
- `pcp.formula.create`
- `pcp.formula.change`
- `pcp.op.create`
- `pcp.op.reserve_components`
- `pcp.op.start`
- `pcp.op.finish`
- `pcp.op.cancel`
- `pcp.cq.record`
- `pcp.blocked_lot.release`

`pcp.experimental.release` permanece apenas como action key legada de nomenclatura. A regra nova de liberacao de lote bloqueado usa `pcp.blocked_lot.release`, porque o bloqueio pode vir de CQ bloqueado/reprovado, experimental ou desenvolvimento.

As alcadas poderao ser restringidas depois por `user_permission_overrides`.

## Validacao descartavel

Banco local descartavel:

- PostgreSQL local.
- Porta: `55435`.
- Database de smoke: `elite_validate_0009_smoke`.
- Sem dados reais.
- Pasta local ignorada pelo Git: `.tools/`.

Smoke test `smoke_pcp_0009`:

1. Criou cadastros minimos falsos.
2. Criou lote MP.
3. Criou formula de producao com MP.
4. Criou OP para estoque, reservou MP, iniciou e finalizou com CQ.
5. Validou geracao de PA e PI disponiveis.
6. Validou baixa de MP por `consumo_op`.
7. Criou OP experimental, finalizou com CQ aprovado e validou lote PA bloqueado.
8. Liberou lote experimental e validou status `disponivel`.
9. Criou formula de reprocessamento com MP+PA+PI.
10. Validou consumo de MP, PA e PI no reprocessamento.
11. Criou OP MAPA documental e validou que ela nao criou componentes nem movimentos de estoque.
12. Criou romaneio total com duas reservas PA em lotes diferentes.
13. Confirmou romaneio e validou duas baixas PA.
14. Validou pedido `fulfilled`.
15. Validou erro esperado para finalizacao sem pH.
16. Validou bloqueio append-only em `est_movimentos_mp`.
17. Validou bloqueio append-only em `pcp_formula_itens`.

Resultado resumido:

- OPs criadas: 5.
- CQ registrados: 3.
- Produtos gerados: 5.
- Consumos MP por OP: 3.
- Consumos PA por OP: 1.
- Consumos PI por OP: 1.
- Baixas PA por romaneio: 2.

Resultado: passou.

## Fora desta etapa

- Calculo de custo de producao.
- Simulador de compra/necessidade MP.
- Garantias calculadas por lote de MP.
- Refinamento estetico final e usabilidade avancada do PCP.
- Integracao fiscal/faturamento completa.
- Deploy Supabase/Vercel.
