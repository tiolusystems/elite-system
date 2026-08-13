from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0121_commission_double_confirmation_ui.sql"
FINANCE = ROOT / "apps/web/app/pedidos/financeiro"


class FinanceCommissionWorkflowV2Contract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.actions = (FINANCE / "actions.ts").read_text(encoding="utf-8")
        cls.forms = (FINANCE / "finance-forms.tsx").read_text(encoding="utf-8")
        cls.page = (FINANCE / "comissionamento/page.tsx").read_text(encoding="utf-8")
        cls.finance = (ROOT / "apps/web/lib/finance.ts").read_text(encoding="utf-8")
        cls.lookups = (ROOT / "apps/web/lib/corporate-lookups.ts").read_text(encoding="utf-8")
        cls.manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        cls.doc = (ROOT / "docs/manuais/financeiro/COMISSIONAMENTO.md").read_text(encoding="utf-8")

    def test_contextual_order_lookup_replaces_generic_lookup(self):
        self.assertIn('"pedidos-comissionamento"', self.lookups)
        self.assertIn('entity="pedidos-comissionamento"', self.page)
        self.assertNotIn('entity="pedidos" name="pedido"', self.page)

    def test_selected_order_is_resolved_by_id_not_current_page(self):
        self.assertIn("getCommissionOrderById(selectedId)", self.page)
        self.assertIn('"consultar_fin_pedido_comissionamento"', self.finance)
        self.assertNotIn("orders.find((order) => order.id === selectedId)", self.page)

    def test_receipt_no_longer_blocks_commission_assignment_copy(self):
        combined = "\n".join([self.page, self.manuals, self.doc])
        self.assertNotIn("antes do primeiro recebimento", combined.lower())
        self.assertNotIn("ainda sem recebimento", combined.lower())
        self.assertIn("com ou sem recebimentos", combined.lower())

    def test_prepare_is_idempotent_and_old_unkeyed_entrypoint_is_hidden(self):
        self.assertIn("propor_com_pedido_comissao_idempotente", self.sql)
        self.assertIn("idx_com_comissao_alteracao_request_key", self.sql)
        self.assertIn("pg_advisory_xact_lock", self.sql)
        self.assertIn("commission request key reused with different payload", self.sql)
        self.assertIn(
            "revoke execute on function public.propor_com_pedido_comissao(",
            self.sql,
        )

    def test_confirmation_is_idempotent(self):
        self.assertIn("confirmar_com_pedido_comissao_idempotente", self.sql)
        self.assertIn("idempotent_replay", self.sql)
        self.assertIn(
            "revoke execute on function public.confirmar_com_pedido_comissao(uuid)",
            self.sql,
        )

    def test_ui_has_real_two_step_confirmation(self):
        self.assertIn('"propor_com_pedido_comissao_idempotente"', self.actions)
        self.assertIn('"confirmar_com_pedido_comissao_idempotente"', self.actions)
        self.assertIn("Revisar alteração", self.forms)
        self.assertIn("Confirmar alteração", self.forms)
        self.assertIn("Esta etapa ainda não gravou o novo direito de comissão.", self.forms)
        self.assertIn('<option value="tecnico_campo">Técnico de campo</option>', self.forms)

    def test_review_exposes_financial_impact(self):
        for fragment in (
            "orderTotal",
            "receivedValue",
            "expectedValue",
            "immediateRelease",
        ):
            self.assertIn(fragment, self.actions)
            self.assertIn(fragment, self.forms)


if __name__ == "__main__":
    unittest.main()
