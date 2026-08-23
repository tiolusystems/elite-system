from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0132_govern_order_discount_review.sql"
SQL = ROOT / "tests/sql/order_discount_review.sql"
PAGE = ROOT / "apps/web/app/pedidos/page.tsx"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"


class OrderDiscountReviewContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.sql = SQL.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")

    def test_permission_is_individual_and_default_deny(self):
        self.assertIn("pedidos.commercial_discount.review", self.migration)
        self.assertIn("false, 139", self.migration)

    def test_fact_is_append_only_and_idempotent(self):
        self.assertIn("com_pedido_decisoes_desconto", self.migration)
        self.assertIn("com_pedido_decisao_desconto_requisicoes", self.migration)
        self.assertIn("BEFORE UPDATE OR DELETE", self.migration.upper())
        self.assertIn("payload divergente", self.migration)

    def test_exact_f2b_and_fingerprint_binding(self):
        self.assertIn("versao comercial vigente", self.migration)
        self.assertIn("fingerprint da comparacao comercial divergente", self.migration)
        self.assertIn("confirmacao_comercial_id", self.migration)
        self.assertIn("comparacao_sha256", self.migration)

    def test_pending_queue_excludes_terminal_rejection(self):
        self.assertIn("and decision.id is null", self.migration)
        self.assertNotIn("or decision.decisao = 'REJECTED'", self.migration)
        self.assertIn("decisao rejeitada voltou a aparecer como pendencia", self.sql)

    def test_discount_is_separate_from_credit_and_gate_is_database_side(self):
        self.assertIn("validate_com_pedido_credito_desconto_gate", self.migration)
        self.assertIn("desconto comercial exige aprovacao independente", self.migration)
        self.assertNotIn("pedidos.credit.review", self.migration)
        self.assertIn("pedido_permanece_bloqueado", self.migration)

    def test_required_cases_are_present_in_sql_smoke(self):
        for phrase in ("BELOW_REFERENCE", "mixed below and above", "idempotency", "outside order scope", "append-only", "L and kg/un", "direct write", "pedido sem desconto", "gate sem aprovacao", "fingerprint divergente", "retry divergente", "segunda chave", "pedido fora do escopo"):
            self.assertIn(phrase, self.sql)

    def test_web_uses_the_governed_review_entrypoint_and_keeps_credit_separate(self):
        for phrase in ("revisao-desconto", "Aprovar desconto", "Rejeitar desconto", "commercialReviewSummary", "confirmacao_comercial_id"):
            self.assertIn(phrase, self.page)
        self.assertIn("decidirDescontoPedidoAction", self.actions)
        self.assertIn('pedidos.commercial_discount.review', self.actions)
        self.assertIn("A decisao nao abre o pedido", self.page)


if __name__ == "__main__":
    unittest.main()
