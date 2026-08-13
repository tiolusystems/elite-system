from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0101_commission_assignment_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pedidos/financeiro/actions.ts"
FORMS = ROOT / "apps/web/app/pedidos/financeiro/finance-forms.tsx"
SMOKE = ROOT / "tests/sql/order_commission_assignment.sql"


class CommissionAssignmentRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.com_pedido_comissao_requisicoes", sql)
        self.assertIn("before update or delete", sql)
        self.assertIn("before truncate", sql)
        self.assertIn("pg_advisory_xact_lock", sql)

    def test_only_keyed_assignment_entrypoint_is_exposed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("definir_com_pedido_comissao_idempotente", sql)
        self.assertIn(
            "revoke all on function public.definir_com_pedido_comissao(bigint, bigint, text, numeric, text)",
            sql,
        )

    def test_finance_form_and_smoke_use_request_key(self):
        actions = ACTIONS.read_text(encoding="utf-8")
        forms = FORMS.read_text(encoding="utf-8")
        smoke = SMOKE.read_text(encoding="utf-8")
        self.assertIn('"propor_com_pedido_comissao_idempotente"', actions)
        self.assertIn("p_request_key: idempotencyKey", actions)
        self.assertIn('name="idempotency_key"', forms)
        self.assertGreaterEqual(smoke.count("propor_com_pedido_comissao_idempotente"), 5)
        self.assertGreaterEqual(smoke.count("confirmar_com_pedido_comissao_idempotente"), 4)
        self.assertIn("commission request key reused with different payload", smoke)
        self.assertIn("idempotent_replay", smoke)


if __name__ == "__main__":
    unittest.main()
