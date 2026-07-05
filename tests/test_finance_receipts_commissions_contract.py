from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0026 = REPO_ROOT / "supabase" / "migrations" / "0026_finance_receipts_commissions_contract.sql"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"


class FinanceReceiptsCommissionsContractTests(unittest.TestCase):
    def test_0026_adds_financial_event_axis_and_action_keys(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")
        docs = f"{RECIPE_DOC.read_text(encoding='utf-8')}\n{SECURITY_MATRIX_DOC.read_text(encoding='utf-8')}"

        self.assertIn("alter type public.audit_axis add value if not exists 'financial_event'", text)
        self.assertIn("'financial_event'", text)
        self.assertIn("axis = financial_event", docs)

        for action_key in (
            "financeiro.receipts.view",
            "financeiro.receipts.register",
            "financeiro.receipts.reverse",
            "financeiro.commissions.view",
            "financeiro.commissions.release",
            "financeiro.commissions.pay",
            "financeiro.commissions.adjust",
        ):
            self.assertIn(action_key, text)
            self.assertIn(action_key, docs)

    def test_0026_creates_allocation_and_commission_ledgers(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")

        self.assertIn("create table if not exists public.fin_recebimento_alocacoes", text)
        self.assertIn("recebimento_id bigint not null references public.com_recebimentos", text)
        self.assertIn("pedido_id bigint not null references public.com_pedidos", text)
        self.assertIn("nota_fiscal_id bigint references public.fat_notas_fiscais", text)
        self.assertIn("create table if not exists public.fin_comissao_movimentos", text)
        self.assertIn("tipo_movimento in (", text)
        self.assertIn("'credito_liberacao'", text)
        self.assertIn("'debito_pagamento'", text)
        self.assertIn("'compensacao_futura'", text)
        self.assertIn("'ajuste_manual'", text)

    def test_financial_event_ledgers_are_append_only_and_direct_write_blocked(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8").lower()

        self.assertIn("prevent_financial_event_changes", text)
        self.assertIn("before update or delete on public.fin_recebimento_alocacoes", text)
        self.assertIn("before update or delete on public.fin_comissao_movimentos", text)
        self.assertIn("drop policy if exists \"authenticated full receipt access\"", text)
        self.assertIn("drop policy if exists \"authenticated full commission release access\"", text)
        self.assertIn("revoke insert, update, delete on public.com_recebimentos", text)
        self.assertNotIn("for all to authenticated using (true) with check (true)", text)

    def test_receipt_rpc_uses_audited_contract_and_releases_commission_proportionally(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.registrar_fin_recebimento_alocado", text)
        self.assertIn("'financeiro.receipts.register'", text)
        self.assertIn("'financial_event'", text)
        self.assertIn("p_alocacoes_json", text)
        self.assertIn("sum of allocations must match valor_recebido", text)
        self.assertIn("all receipt allocations must belong to the same cliente", text)
        self.assertIn("receipt exceeds order balance", text)
        self.assertIn("NF emitida nao libera comissao", COMMISSIONS_DOC.read_text(encoding="utf-8"))
        self.assertIn("v_percentual_recebido := least(v_total_recebido_atual / v_pedido.valor_total, 1);", text)
        self.assertIn("v_valor_liberar := v_valor_alvo_liberado - v_valor_ja_liberado;", text)
        self.assertIn("'financeiro.commissions.release'", text)
        self.assertIn("'receipt_action_key', 'financeiro.receipts.register'", text)
        self.assertIn("'financeiro.comissao_liberada'", text)
        self.assertIn("memoria_calculo_json", text)
        self.assertIn("insert into public.fin_comissao_movimentos", text)
        self.assertIn("'credito_liberacao'", text)
        self.assertIn("perform public.log_audited_rpc_change(", text)

    def test_receipt_rpc_keeps_legacy_order_receipt_signature(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.registrar_com_recebimento(", text)
        self.assertIn("return public.registrar_fin_recebimento_alocado(", text)
        self.assertIn("'pedido_id', p_pedido_id", text)
        self.assertIn("'valor_alocado', p_valor_recebido", text)

    def test_financial_rpc_rejects_linked_remittance_invoice_as_payment_base(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")
        doc = COMMISSIONS_DOC.read_text(encoding="utf-8")

        self.assertIn("if v_nota.tipo = 'remessa_vinculada' then", text)
        self.assertIn("linked remittance invoice cannot be commission payment base", text)
        self.assertIn("`remessa_vinculada` nao deve ser usada como base financeira", doc)

    def test_commission_payment_and_adjustment_are_audited_financial_events(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8")

        for function_name, action_key in (
            ("registrar_fin_comissao_pagamento", "financeiro.commissions.pay"),
            ("registrar_fin_comissao_ajuste", "financeiro.commissions.adjust"),
        ):
            self.assertIn(f"create or replace function public.{function_name}", text)
            self.assertIn(f"'{action_key}'", text)
            self.assertIn("'financial_event'", text)
            self.assertIn("perform public.log_audited_rpc_change(", text)

        self.assertIn("commission payment exceeds available balance", text)
        self.assertIn("motivo is required", text)

    def test_financial_tables_do_not_store_editable_commission_balance(self) -> None:
        text = MIGRATION_0026.read_text(encoding="utf-8").lower()

        table_match = re.search(
            r"create table if not exists public\.fin_comissao_movimentos\s*\((.*?)\n\);",
            text,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(table_match)
        table_body = table_match.group(1)

        self.assertNotIn("saldo", table_body)
        self.assertIn("create or replace view public.fin_comissao_saldos", text)
        self.assertIn("coalesce(sum(movimento.valor), 0)::numeric as saldo_comissao", text)


if __name__ == "__main__":
    unittest.main()
