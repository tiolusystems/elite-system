from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0088_order_commission_assignment.sql"


class OrderCommissionAssignmentContractTests(unittest.TestCase):
    def test_assignment_is_permissioned_locked_and_audited(self):
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("'pedidos.commissions.assign'", text)
        self.assertIn("'pedidos', 'write'", text)
        self.assertIn("pg_advisory_xact_lock", text)
        self.assertIn("commission assignment must precede the first receipt", text)
        self.assertIn("public.log_audited_rpc_change", text)
        self.assertIn("from public, anon", text)
        self.assertIn("to authenticated", text)

    def test_roles_include_agent_without_removing_existing_roles(self):
        text = MIGRATION.read_text(encoding="utf-8")
        for role in ("vendedor", "agente", "gerente", "tecnico_campo", "campanha", "outro"):
            self.assertIn(f"'{role}'", text)

    def test_assignment_preserves_direct_write_denial(self):
        smoke = (ROOT / "tests/sql/order_commission_assignment.sql").read_text(encoding="utf-8")
        self.assertIn("has_table_privilege('authenticated','public.com_pedido_comissionados','INSERT')", smoke)
        self.assertIn("not allowed: pedidos.commissions.assign", smoke)
        self.assertIn("PG_ORDER_COMMISSION_ASSIGNMENT_OK", smoke)


if __name__ == "__main__":
    unittest.main()
