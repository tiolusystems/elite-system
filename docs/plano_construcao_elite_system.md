# Plano de construcao do Elite System

## Bloco 0 - Governanca, GitHub e seguranca

Objetivo: garantir que cada evolucao tenha backup e rastro.

Entregas:

- Repositorio Git local.
- Repositorio GitHub privado.
- Branch principal protegida.
- Commits pequenos por bloco.
- CI rodando testes em cada push.
- Regra: nao publicar dados comerciais no Git.

Status atual:

- Repositorio local sera inicializado nesta etapa.
- Workflow de CI sera criado em `.github/workflows/ci.yml`.

## Bloco 1 - Nucleo de migracao e auditoria

Objetivo: preservar historico do Excel e validar importacao.

Entregas:

- Camada bruta: workbook, tabelas e linhas originais.
- Camada normalizada inicial.
- Issues de migracao.
- Reconciliacoes de valores.

Status atual:

- Importador Excel implementado.
- Auditoria de contagem implementada.
- Auditoria de valores implementada.
- Auditoria de saldo por materia-prima e produto implementada em tabela de detalhes.
- Tabelas de usuarios, login por senha e log de acoes implementadas.
- Permissoes implementadas com autonomia total inicial e overrides por perfil/usuario.
- Tela administrativa local de usuarios/alcadas implementada com login, checks e aviso visual/analitico de banco local ou descartavel.
- Etapa 2 validada em banco descartavel, com evidencia em `docs/validacao_etapa_2_checks_db_descartavel.md`.
- Stack web/cloud definida: PostgreSQL, Supabase, Next.js e Vercel.
- Base inicial Next.js criada em `apps/web`.
- Migration inicial Supabase criada em `supabase/migrations`.
- Tela `/login` criada no Next.js para autenticar por Supabase Auth, consultar `user_profiles` e encerrar sessao.
- Painel inicial passou a exibir estado de sessao e link direto para login.
- Pendencia conhecida: classificar automaticamente a causa de cada diferenca.

## Bloco 2 - Cadastros mestres

Objetivo: transformar cadastros em telas e regras confiaveis.

Entregas:

- Clientes.
- Vendedores.
- Materias-primas.
- Produtos.
- Veiculos.
- Embalagens.
- Garantias.
- Validacoes de duplicidade, status e campos obrigatorios.

Auditorias:

- Contagem por cadastro.
- Duplicidade de codigos.
- Itens usados em pedidos/producao sem cadastro.

Status atual:

- Dicionario inicial de cadastros criado em `docs/dicionario_cadastros_mestres.md`.
- Dicionario evoluido para incluir papeis de vendedor/agente/tecnico/entregador, multiplos comissionados por pedido, cliente unico com propriedades/CNPJs, saneamento de SKU de MP, conversoes XML/NF, produto + embalagem, PA/PI, formulas versionadas e garantias MAPA.
- Regras de comissao, recebimento, devolucao, credito e pedido por vendedor documentadas em `docs/escopo_comissoes_recebimentos_credito.md`.
- Modelos de dominio de cadastros criados em `elite_system/domain/cadastros.py`.
- Validators puros de cadastros criados em `elite_system/validators/cadastros.py`.
- Schema SQLite operacional de cadastros criado com tabelas `cad_*`, preservando as tabelas historicas importadas do Excel.
- Migration Supabase/PostgreSQL de cadastros criada em `supabase/migrations/0002_master_data_foundation.sql`.
- Repositories e services auditaveis de cadastros criados em `elite_system/repositories/cadastros_repository.py` e `elite_system/services/cadastros.py`.
- Testes de cadastros preparados para rodar em banco temporario descartavel.
- Primeira tela de cadastros mestres criada em `apps/web/app/cadastros/page.tsx`, com condicao visual/analitica do banco, modulos `cad_*`, contagens Supabase quando configurado e fila de validacao.
- Preview HTML estatico criado em `apps/web/preview/cadastros.html` para validacao visual sem depender de Node.js.
- Formularios ativos preparados para cliente, pessoa comercial, materia-prima, produto-base, embalagem, item vendavel e conversao de MP, chamando Server Actions em `apps/web/app/cadastros/actions.ts` e funcoes PostgreSQL auditaveis `public.create_cad_cliente`, `public.create_cad_pessoa_comercial`, `public.create_cad_materia_prima`, `public.create_cad_produto_base`, `public.create_cad_embalagem`, `public.create_cad_produto_embalagem` e `public.create_cad_conversao_unidade_mp`.
- Seletores pesquisaveis preparados para vendedor responsavel, MP, produto e embalagem, usando listas carregadas do Supabase quando configurado.
- Migration `0011_importacao_xml_pedidos_kanban.sql` adicionou vinculo entre pessoa comercial e usuario de login, areas comerciais e vinculos vendedor/gerente/area.
- Escopo de importacao XML, pedidos por propriedade e Kanban registrado em `docs/escopo_importacao_xml_pedidos_kanban.md`.
- Tela `/importacao-xml` criada no Next.js para importar XML colado, lancar NF/item manualmente, conferir match de MP, informar conversao, ignorar item e gerar lote MP.
- Pendencia: homologar telas contra Supabase configurado antes de usar em dado operacional real.

## Bloco 3 - Comercial

Objetivo: substituir `GESTÃO_PEDIDOS` por modulo operacional.

Entregas:

- Pedido.
- Itens do pedido.
- Tipo: venda, bonificacao, devolucao.
- Status de entrega.
- Vendedores e comissoes.
- Faturamento.
- Lancamento de recebimentos.
- Calculo de comissoes por recebimento.
- Pedido preenchido por vendedor com alcadas.
- Analise de credito e inadimplencia no pedido.

Auditorias:

- Total de pedidos.
- Faturamento total.
- Faturamento vendas.
- Pedidos em aberto.
- Entregue x a entregar.
- Comissao prevista x liberada x paga.
- Devolucao abatendo comissao.
- Comissao negativa compensada em futuras.
- Pedido bloqueado por credito/inadimplencia.

Status atual:

- Migration Supabase/PostgreSQL inicial criada em `supabase/migrations/0003_commercial_orders_foundation.sql`.
- Tabelas `com_pedidos`, `com_pedido_itens` e `com_pedido_comissionados` criadas para pedido, item vendavel e comissao prevista.
- Funcao PostgreSQL auditavel `public.create_com_pedido_rascunho` criada para abrir o primeiro fluxo sem insert direto pela UI.
- Tela `/pedidos` criada em `apps/web/app/pedidos/page.tsx`, com condicao visual/analitica do banco, formulario de pedido e lista de pedidos recentes.
- Preview HTML estatico criado em `apps/web/preview/pedidos.html` para validacao visual sem depender de Node.js.
- Regra preservada: pedido em rascunho nao baixa estoque; bonificacao nao gera comissao; devolucao gera valor negativo auditado.
- Gate de credito criado em `supabase/migrations/0004_order_credit_gate.sql`, com tabela `com_pedido_credito_decisoes` e funcao auditavel `public.registrar_com_pedido_decisao_credito`.
- Tela `/pedidos` evoluida para registrar liberacao, bloqueio ou aprovacao pendente antes de faturamento.
- Recebimentos parciais e liberacao proporcional de comissao criados em `supabase/migrations/0005_order_receipts_commissions.sql`, com tabelas `com_recebimentos` e `com_comissao_liberacoes`.
- Tela `/pedidos` evoluida para registrar recebimento de pedido aberto e listar comissoes liberadas por recebimento.
- Migration `0011_importacao_xml_pedidos_kanban.sql` adicionou pedido por propriedade, sequencia propria por propriedade/cliente, vendedor gerador do pedido e view `com_pedidos_kanban`.
- Funcao auditavel `public.create_com_pedido_operacional` criada para novo fluxo de pedido com cliente, propriedade, item vendavel, comissao e codigo sequencial.
- Tela `/pedidos` passou a capturar propriedade e gravar via `public.create_com_pedido_operacional`.
- Tela `/kanban` criada para visualizar pedidos por status, cliente, propriedade, vendedor, gerente vinculado e area comercial.

## Bloco 4 - Estoque MP e PA

Objetivo: fechar saldos e movimentos.

Entregas:

- Entradas MP.
- Saidas MP.
- Saidas PA.
- Lotes MP.
- Lotes PA.
- Inventario.
- Ajustes manuais auditados.

Auditorias:

- Saldo MP por materia-prima.
- Saldo PA por produto.
- Saldo por lote.
- Diferencas de inventario.

Status atual:

- Migration `0007_pa_stock_lots_foundation.sql` criada para fundacao de estoque PA por lote.
- Tabelas `est_lotes_pa`, `est_movimentos_pa` e `est_reservas_pa` criadas.
- View `est_lotes_pa_saldos` criada para saldo fisico, reserva ativa e saldo disponivel.
- Funcoes auditaveis criadas: `create_est_lote_pa`, `registrar_est_reserva_pa` e `registrar_est_ajuste_pa`.
- Movimentos de PA protegidos contra edicao e exclusao; correcao deve gerar novo movimento auditavel.
- Validacao descartavel executada com entrada PA, reserva, baixa por romaneio, estorno e bloqueio por saldo insuficiente.
- Migration `0009_pcp_op_foundation.sql` adicionou lotes e movimentos de MP e PI.
- Views `est_lotes_mp_saldos` e `est_lotes_pi_saldos` criadas para saldo fisico, reserva e disponibilidade.
- Estoque PA passou a considerar reservas de romaneio e reservas PCP na view `est_lotes_pa_saldos`.
- Migration `0010_product_validity_reports_foundation.sql` adicionou prazo de validade em meses ao produto-base e relatorios de vencimento/reprocessamento para PA, PI e MP.
- Migration `0011_importacao_xml_pedidos_kanban.sql` adicionou a fundacao da importacao semiautomatica de NF XML para entrada de MP, com staging, candidatos de match, confirmacao auditada, conversao de unidade e geracao de lote MP somente apos conferencia.
- Frontend da importacao XML criado com fluxo de staging e geracao de lote MP via RPC auditavel, sem insert direto pela UI.

## Bloco 5 - Producao

Objetivo: transformar fichas e lotes em processo de producao.

Entregas:

- Ficha tecnica.
- Formula por produto.
- Ordem de producao.
- Baixa automatica de MP.
- Custo de producao.
- Simulacao de producao e compras.

Auditorias:

- Quantidade produzida.
- Custo MP.
- Consumo teorico x consumo baixado.
- Produtos sem formula valida.

Status atual:

- Escopo tecnico documentado em `docs/escopo_pcp_op.md`.
- Migration `0009_pcp_op_foundation.sql` criada para fundacao PCP/PostgreSQL.
- Tabelas de formula versionada criadas: `pcp_formula_versoes`, `pcp_formula_itens` e `pcp_formula_ativacoes`.
- View `pcp_formula_ativa` criada para a ultima formula ativada por produto e tipo de receita.
- Tabelas de OP criadas: `pcp_ordens_producao`, `pcp_op_componentes_planejados`, `pcp_op_reservas_componentes`, `pcp_op_consumos_componentes`, `pcp_op_cq_resultados` e `pcp_op_produtos_gerados`.
- OP MAPA documental implementada sem reserva, sem baixa e sem geracao de estoque.
- OP operacional implementada com reserva de MP/PA/PI, inicio com reserva completa, CQ obrigatorio e baixa na finalizacao.
- OP pode gerar PA, PI ou PA+PI.
- OP experimental/desenvolvimento gera lotes bloqueados ate liberacao auditada.
- Reprocessamento pode consumir MP+PA+PI e gerar PA/PI.
- Formula, movimentos MP e movimentos PI protegidos como append-only.
- Validacao descartavel passou com OP estoque, OP experimental, OP reprocessamento, OP MAPA documental, CQ obrigatorio, append-only e romaneio multilote.
- PA e PI podem herdar validade automatica do `prazo_validade_meses` do produto quando o lote tem data de fabricacao e nao recebeu validade manual.
- Camada web PCP criada em `apps/web/lib/pcp.ts`, `apps/web/app/pcp/actions.ts` e `apps/web/app/pcp/page.tsx`.
- Tela `/pcp` criada para consultar formulas, formulas ativas, OPs, componentes planejados, reservas, produtos gerados e lotes disponiveis de MP/PA/PI.
- Tela `/pcp` permite criar nova versao de formula, ativar formula, abrir OP, reservar componente, iniciar OP, cancelar OP planejada e finalizar OP com dados de CQ e geracao de PA/PI via funcoes PostgreSQL auditaveis.
- Pendencia: homologar `/pcp` contra Supabase configurado com usuario logado e dados de teste antes de uso operacional.

## Bloco 6 - Romaneio

Objetivo: substituir a planilha `ROMANEIO` canonica por fluxo operacional, sem transformar outras planilhas com nome parecido em codigo desnecessario.

Entregas:

- Escolha de pedido a separar.
- Separacao total ou parcial.
- Busca de lotes disponiveis de PA.
- Reserva de lote quando aplicavel.
- Confirmacao de romaneio.
- Baixa de PA gerada por romaneio confirmado.
- Comunicacao do romaneio para faturamento.
- Comunicacao do romaneio para expedicao.

Auditorias:

- Pedido x romaneio x saida PA.
- Lote x produto.
- Quantidade romaneada.
- Quantidade pendente por pedido.
- Baixa de estoque PA por romaneio confirmado.

Fora do escopo inicial:

- montagem completa de carga;
- roteirizacao;
- frota;
- fiscal completo;
- outras planilhas chamadas romaneio sem mapeamento aprovado.

Status atual:

- Migration `0006_romaneio_foundation.sql` criada para fundacao PostgreSQL do romaneio.
- Tabelas `exp_romaneios`, `exp_romaneio_itens` e `exp_romaneio_movimentos_pa` criadas.
- View `exp_pedido_item_romaneio_saldos` criada para pedido x quantidade confirmada x saldo pendente.
- Funcoes auditaveis criadas: `create_exp_romaneio`, `registrar_exp_romaneio_separacao`, `confirmar_exp_romaneio`, `cancelar_exp_romaneio` e `estornar_exp_romaneio`.
- Regra preservada: pedido aberto nao baixa estoque; romaneio confirmado gera movimento de baixa PA; estorno gera movimento inverso auditado.
- Migration `0007_pa_stock_lots_foundation.sql` integrou o romaneio ao estoque PA real por lote.
- Confirmacao do romaneio agora exige reserva ativa em `est_reservas_pa` no fluxo novo e gera `saida_romaneio` em `est_movimentos_pa`.
- Cancelamento libera reservas ativas e estorno devolve saldo fisico ao mesmo lote PA.
- Migration `0009_pcp_op_foundation.sql` removeu a limitacao de um unico lote por item de romaneio.
- O mesmo item de romaneio agora pode ter varias reservas PA ativas, uma por lote.
- Confirmacao do romaneio valida que a soma das reservas ativas fecha a quantidade romaneada e baixa cada lote separadamente.
- Migration `0012_romaneio_multi_item_web.sql` adicionou `add_exp_romaneio_item` para permitir varios itens no mesmo romaneio por RPC auditavel.
- Camada web de romaneio criada em `apps/web/lib/romaneios.ts`, `apps/web/app/romaneios/actions.ts` e `apps/web/app/romaneios/page.tsx`.
- Tela `/romaneios` criada para consultar itens pendentes, criar romaneio, adicionar item, reservar lote PA, confirmar, cancelar e estornar.
- Pendencia: homologar `/romaneios` contra Supabase configurado com usuario logado e dados de teste antes de uso operacional.

## Bloco 7 - Relatorios e dashboards

Objetivo: recriar analises do Excel com consultas rastreaveis.

Entregas:

- Dashboard comercial.
- Dashboard estoque.
- Dashboard producao.
- Ranking de clientes.
- Relatorio de pedidos pendentes.
- Relatorio de compras/necessidade MP.

Status atual:

- Migration `0008_audit_reconciliation_foundation.sql` criou a camada cloud de fonte, batch, linhas brutas, issues e reconciliacoes.
- View `aud_operational_metric_values` expõe metricas operacionais atuais de pedidos, faturamento, recebimentos, comissoes, romaneios e estoque PA.
- Funcao `record_aud_source_expected_metric` registra valores esperados vindos do Excel ou de resumo validado.
- Funcao `run_aud_reconciliacao_operacional` compara sistema x fonte esperada e grava status `ok`, `attention` ou `missing`.
- Camada bruta `source_workbooks`, `source_tables`, `source_rows` e `imported_records` foi protegida contra edicao/exclusao direta.
- Validacao descartavel confirmou rodada `ok`, rodada divergente `attention` e bloqueio append-only em `source_rows`.
- Escopo de relatorios registrado em `docs/escopo_relatorios.md`.
- Migration `0010_product_validity_reports_foundation.sql` criou `relatorio_catalogo`, `rel_estoque_lotes_vencimento` e `rel_estoque_reprocessamento_candidatos`.
- Relatorios foram classificados como modulo essencial, herdando a importancia das dezenas de telas de relatorios do Tio Lu System XLSX.
- Primeira tela `/relatorios` criada no Next.js para catalogo, vencimentos e candidatos a reprocessamento.
- Preview estatico criado em `apps/web/preview/relatorios.html` para validacao visual sem depender de Node.js.

## Bloco 8 - Banco em nuvem

Objetivo: sair de SQLite local para PostgreSQL/Supabase sem perder auditoria.

Entregas:

- Projeto Supabase de teste.
- Schema PostgreSQL em migrations versionadas.
- Supabase Auth ligado aos perfis do sistema.
- Row Level Security revisado por tabela.
- Migração de dados.
- Backup automatizado.
- Credenciais por ambiente.
- Restore testado.
- Login multiusuario validado contra ambiente cloud.
- `action_logs` protegido por permissao e backup.

## Bloco 9 - App operacional

Objetivo: entregar o sistema para uso diario.

Entregas:

- App web Next.js.
- Deploy Vercel.
- Integracao Supabase.
- Login e perfis.
- Telas completas.
- Empacotamento inicial via Edge app mode.
- Manual operacional.
- Homologacao visual e funcional.

Direcao visual:

- Diretriz registrada em `docs/direcao_visual_ux.md`.
- Layout principal deve ser moderno, operacional e previsivel, com menus, icones nomeados, busca, filtros e tabelas.
- Recursos 3D com estruturas moleculares sao viaveis como identidade visual, dashboard, visualizacao de formulas/PCP e modo apresentacao.
- O 3D nao deve ser a navegacao principal de rotinas criticas como pedido, romaneio, CQ, estoque, recebimento e auditoria.

## Sequencia imediata

Referencia de ordem: `docs/fluxo_operacional_elite_system.md`.

1. Homologar `/login` contra Supabase Auth configurado e usuario com `user_profiles` ativo.
2. Criar telas operacionais de cadastros tecnicos: MP, embalagens, PA e PI.
3. Homologar tela `/pcp` de formulas PA/PI contra Supabase configurado.
4. Homologar tela `/pcp` para formulacao, reserva de insumos, CQ e baixa de insumos.
5. Homologar tela `/romaneios` com separacao por lote e baixa de produtos.
6. Definir e implementar entregador no romaneio, se o campo existir na planilha canonica.
7. Implementar atualizacao encadeada de status de pedido, OP, estoque, romaneio, financeiro e comissoes.
8. Consolidar recebimentos e comissoes, incluindo devolucao e abatimento futuro.
9. Criar simulador de producao com base em historico ou alimentacao manual.
10. Criar estoque regulador de PA, PI e MP.
11. Evoluir relatorios de vendas por vendedor, periodo, cliente e produto.
12. Evoluir rastreabilidade de lotes MP, PA e PI.
13. Validar Next.js local com Supabase configurado e login Supabase.
