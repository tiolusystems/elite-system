# Validacao da migration 0026 - recebimentos e comissoes

Data da validacao: 2026-07-05

## Objetivo

Validar a migration `0026_finance_receipts_commissions_contract.sql`.

Escopo validado:

- criar `axis = financial_event`;
- amadurecer `com_recebimentos` sem quebrar a RPC legada `registrar_com_recebimento(...)`;
- criar `fin_recebimento_alocacoes` para pagamento unico cobrindo varios pedidos/NFs;
- criar `fin_comissao_movimentos` como conta corrente append-only de comissoes;
- liberar comissao proporcional ao recebimento alocado;
- registrar pagamento e ajuste manual de comissao como movimentos financeiros;
- bloquear escrita direta nas tabelas financeiras sensiveis;
- manter auditoria via `begin_audited_rpc(...)` e `log_audited_rpc_change(...)`.

## Ambiente usado

- PostgreSQL 18 local descartavel.
- Porta local: `127.0.0.1:55464`.
- Cluster temporario: `.tools/pg-validate-0026-20260705-125333`.
- Sem dados reais, Supabase cloud, planilhas ou banco operacional.

## Prelude Supabase simulado

Foram criados apenas os itens minimos para executar as migrations fora do Supabase local:

- roles `anon`, `authenticated`, `service_role`;
- schema `auth`;
- tabela `auth.users`;
- funcao `auth.uid()` lendo `request.jwt.claim.sub`.

## Resultado das migrations

Todas as migrations `0001` a `0026` aplicaram com sucesso no banco descartavel limpo.

As mensagens de `DROP TRIGGER ... nao existe` e `DROP POLICY ... nao existe` foram esperadas, pois o banco estava limpo.

## Smoke test executado

Arquivo: `.tools/smoke_finance_0026.sql`.

Casos validados:

1. Criou usuario ativo permitido.
2. Criou cliente, vendedor/comissionado, produto, embalagem e tres pedidos falsos.
3. Registrou um recebimento de `750` alocado entre dois pedidos do mesmo cliente.
4. Validou duas linhas em `fin_recebimento_alocacoes`.
5. Validou liberacao proporcional de comissao: saldo inicial `62.5`.
6. Registrou pagamento parcial de comissao de `20`.
7. Registrou ajuste manual de comissao de `-2.5` com motivo obrigatorio.
8. Validou saldo final de comissao `40`.
9. Tentou pagamento acima do saldo e recebeu erro esperado.
10. Tentou recebimento acima do saldo do pedido e recebeu erro esperado.
11. Tentou `UPDATE` direto em alocacao financeira e recebeu erro append-only esperado.
12. Validou compatibilidade da RPC antiga `registrar_com_recebimento(...)`.
13. Validou logs `success` com `permission_context.axis = financial_event`.
14. Validou que liberacao de comissao exige `financeiro.commissions.release` alem de `financeiro.receipts.register`.

Resultado final:

```text
PG_VALIDATE_0026_WITH_SMOKE_OK
```

## Decisoes confirmadas

- NF emitida continua nao liberando comissao sozinha.
- Recebimento pode apontar para pedido/NF, mas comissao nasce da alocacao financeira.
- `remessa_vinculada` nao e base financeira de pagamento/comissao.
- Pagamento de comissao nao edita a liberacao original; cria debito na conta corrente.
- Ajuste manual exige motivo e action key propria.

## Fora desta etapa

- Motor de campanhas, metas e travas.
- Estorno completo de recebimento por devolucao/cancelamento.
- Conciliacao bancaria automatica.
- Visibilidade granular por carteira de vendedor/gerente.
