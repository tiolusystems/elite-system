# Matriz de seguranca e alcadas

Esta matriz guia o endurecimento de RLS por dominio. A regra de construcao e:

1. Rotas operacionais exigem sessao valida e perfil ativo.
2. Escritas criticas devem passar por RPC `security definer`.
3. Cada RPC valida `require_current_user_permission(action_key)`.
4. Cada RPC registra auditoria em `action_logs` via `log_audit_event`.
5. Negativas de permissao capturadas pela aplicacao devem registrar `log_permission_denied` em transacao separada.
6. RLS restritivo entra por dominio, depois que as RPCs daquele dominio estiverem cobertas.

A receita operacional para escolher eixo de alcada, validar dominio no banco, escrever RPC auditada e rodar smoke esta em `docs/receita_rls_rpc_auditada.md`.

## Rotas publicas

| Rota | Motivo |
|---|---|
| `/login` | Entrada e saida de sessao |
| `/health` | Health-check tecnico |
| `/api/health` | Health-check tecnico |
| assets/Next.js | Arquivos estaticos, imagens, fontes e chunks |

Todas as demais rotas nascem protegidas por allowlist: rota nova exige sessao por padrao.

A partir da `0041`, exigir sessao nao basta: toda rota autenticada tambem precisa existir em `sys_module_routes`. Rota sem proprietario ou modulo indisponivel e redirecionada para `/modulo-indisponivel`. O proxy fecha o acesso se o contrato de runtime nao responder.

## Matriz por dominio

| Dominio | Leitura inicial | Escrita inicial | RPC existente? | Alcadas iniciais | Endurecimento RLS |
|---|---|---|---|---|---|
| seguranca | usuario autenticado ve proprio perfil e solicitacao; administrador ve email, confirmacao e fila de revisao | usuarios/permissoes por RPC; convite Auth server-only; usuario apenas solicita troca, admin define o endereco e titular confirma o valor aprovado | sim | `system.admin`, `security.manage_users`, `security.manage_permissions`, `security.change_own_password`, `security.email_change.request`, `security.email_change.review`, `security.email_change.dispatch_approved` | escrita direta restringida na 0035; 0038 permanece para conta legada; 0046 adiciona recuperacao; 0047 cria convite verificavel; 0048 governa troca de email; 0049 torna administracao default deny e exige papel admin + grant explicito, preservando o ultimo administrador capaz |
| cadastros | usuarios autenticados veem cadastros mestres necessarios a operacao | criacao/edicao por RPC auditada | sim | `cadastros.manage`, depois granular por tipo de cadastro | por subdominio: clientes, pessoas, MP, PA/PI, embalagens |
| pedidos | vendedor/gerente/administracao ve pedidos conforme carteira, area ou perfil | criar pedido, revisar credito, cancelar pedido sem efeitos ativos, registrar recebimento e comissao por RPC | sim | `pedidos.create`, `pedidos.create.own`, `pedidos.create.any`, `pedidos.credit.review`, `pedidos.status.transition`, `pedidos.cancel`, `financeiro.receipts.register` | tabela de transicoes criada na `0028`; escrita direta bloqueada; cancelamento nao desfaz romaneio/NF/recebimento ativo |
| importacao_xml | operadores veem fila de XML e matches pendentes | staged XML, match, ignore e geracao de lote MP por RPC | sim | `importacao.nfe_xml.stage`, `importacao.nfe_xml.match`, `importacao.nfe_xml.generate_mp_lot` | restringir escrita direta apos validar fluxo XML completo |
| estoque | operadores veem lotes, movimentos, reservas e saldos derivados necessarios ao trabalho | entrada, reserva, baixa, consumo, ajuste, transformacao e reversao por RPC de evento; saldo nunca e editado diretamente | sim | `estoque.manage`, `estoque.mp.lots.create`, `estoque.pa.reserve`, `estoque.pa.issue.romaneio`, `estoque.mp.adjust`, `estoque.pa.adjust`, `estoque.pi.adjust`; proximas granulares por evento/movimento | separar leitura por MP, PI, PA e movimentos; ajuste manual por familia de estoque; endurecer escrita direta preservando livro append-only |
| pcp | producao/CQ ve formulas, garantias, OPs, reservas, apontamentos, CQ e transformacoes | formula, garantia de produto/lote, calculo por OP, reserva, inicio, finalizacao, cancelamento e release por RPC | sim | `pcp.formula.create`, `pcp.formula.change`, `pcp.op.create`, `pcp.op.finish`, `pcp.cq.record`, `pcp.blocked_lot.release`, `pcp.guarantee.product.register`, `pcp.guarantee.mp_lot.register`, `pcp.guarantee.calculate` | formulas, garantias e resultados de calculo append-only; OP de reprocessamento governa PA/PI/MP; liberacao de lote bloqueado por CQ/qualidade/gestao tecnica |
| romaneios | expedicao/comercial ve rascunhos, separacao e historico | criar, reservar, confirmar, cancelar e estornar por RPC | sim | `romaneios.create`, `romaneios.confirm`, `romaneios.cancel` | leitura por expedicao/comercial; escrita so por RPC |
| faturamento | fiscal/financeiro/comercial autorizado ve dossie fiscal por pedido, romaneio e cliente | emissao por remessa total, simples faturamento, remessa vinculada, cancelamento, carta de correcao, complemento e substituicao por RPC/evento fiscal | sim | `faturamento.nf.view`, `faturamento.nf.issue`, `faturamento.nf.cancel`, `faturamento.nf.correct`, `faturamento.nf.complement`, `faturamento.nf.substitute` | tabela de documento fiscal, itens fiscais e eventos fiscais criada na `0025`; escrita direta bloqueada; NF nao e campo de pedido; `remessa_vinculada` referencia NF simples pai |
| financeiro_comissoes | comercial/financeiro ve recebimentos, alocacoes e conta corrente de comissoes conforme alcada | recebimento multi-alocacao, liberacao proporcional, pagamento e ajuste de comissao por RPC/evento financeiro | sim | `financeiro.receipts.view`, `financeiro.receipts.register`, `financeiro.receipts.reverse`, `financeiro.commissions.view`, `financeiro.commissions.release`, `financeiro.commissions.pay`, `financeiro.commissions.adjust` | tabelas de alocacao e conta corrente criadas na `0026`; escrita direta bloqueada; campanhas/metas e estorno por devolucao ficam como proximos subdominios |
| metas | comercial/gestao ve periodos, movimentos e saldos derivados de metas conforme alcada | periodo customizado, venda aberta, cancelamento, devolucao e ajuste manual por RPC de evento de meta | sim | `metas.view`, `metas.periods.manage`, `metas.sales.register`, `metas.cancellations.register`, `metas.returns.register`, `metas.adjust` | ledger append-only criado na `0032`; saldo por view; lock tecnico por pessoa + periodo para futuro motor de faixas; acoplamento automatico criado na `0033`: cancelamento com venda aberta exige `pedidos.cancel` + `metas.cancellations.register`; estorno pos-pagamento exige `pedidos.post_payment_reversal` + `metas.returns.register` |
| auditoria | auditoria/admin ve logs, reconciliacoes e relatorios | execucao de reconciliacao e registro de metricas por RPC | sim | `audit.view`, `audit.reconciliation.run` | logs append-only; leitura completa apenas auditoria/admin |
| relatorios | leitura conforme dados permitidos por dominio | sem escrita operacional, exceto parametros/snapshots auditados | parcial | `audit.view` e futuras alcadas de relatorio | views filtradas por perfil e escopo |

## Gate global de escrita direta

A migration `0039_rls_direct_write_gate.sql` fecha as policies legadas `FOR ALL` de PCP, romaneio, importacao e auditoria. Ela tambem revoga de `authenticated`, em todas as tabelas publicas, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` e `TRIGGER`.

Esse gate nao altera a decisao de autonomia inicial das action keys. Usuario pode ter a acao liberada por padrao ou checkbox, mas a executa por RPC auditada; nunca por DML direto. Tabelas novas herdam o mesmo default restritivo.

## Contrato de RPC auditada

Toda RPC de escrita critica deve seguir este formato:

```sql
perform public.require_current_user_permission('<action_key>');

-- validar entrada, status e transicao permitida
-- executar alteracao dentro da propria funcao

perform public.log_audit_event(
  '<dominio>',
  '<entidade>',
  v_entity_id::text,
  '<acao_auditavel>',
  '<action_key>',
  'success',
  v_before_json,
  v_after_json,
  jsonb_build_object('alcada_usada', '<action_key>'),
  'database_rpc',
  jsonb_build_object('origem_funcao', '<nome_da_rpc>')
);
```

Nao registrar permissao negada dentro de `require_current_user_permission` antes de `raise exception`: o PostgreSQL reverte o insert de auditoria junto com a excecao. Para negativa persistente, a camada de aplicacao deve capturar o erro `not allowed` e chamar `log_permission_denied(...)` em uma nova transacao. No web app, esse contrato fica centralizado em `apps/web/lib/supabase/rpc.ts`; Server Actions nao devem chamar `.rpc(...)` diretamente.

Acesso direto ao banco fora da aplicacao Next.js, como SQL editor, script administrativo ou integracao futura, nao e coberto pelo wrapper `auditedRpc`. Esses caminhos devem usar RPCs auditadas ou ter auditoria propria antes de serem considerados operacionais.

Para acoes com escopo, usar action keys separadas em vez de uma permissao generica. Exemplo: `.own` para registros do proprio ator e `.any` para registros fora do escopo. A RPC deve gravar em `permission_context` a alcada efetivamente usada e o escopo decidido.

O padrao `.own/.any` nao deve ser aplicado mecanicamente a todo cadastro. A decisao de eixo de alcada por subdominio esta documentada em `docs/decisao_alcadas_cadastros_mestres.md`.

`default_allowed=true` permanece apenas como decisao de fase inicial para acoes conhecidas. O endurecimento deve acontecer por dominio, nunca por flip global sem matriz revisada.
