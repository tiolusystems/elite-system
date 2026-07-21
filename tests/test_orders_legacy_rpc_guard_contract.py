from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LegacyOrdersRpcGuardTest(unittest.TestCase):
    def test_legacy_entry_points_are_scoped(self):
        sql = (ROOT / "supabase/migrations/0079_orders_legacy_rpc_scope_guard.sql").read_text(encoding="utf-8")
        self.assertIn("seller identity is derived from current session", sql)
        self.assertIn("client is outside seller portfolio", sql)
        self.assertIn("order is outside manager team", sql)
        self.assertIn("create_com_pedido_vendedor_core_0079", sql)
        self.assertIn("'venda', 'blocked'", sql)
        self.assertNotIn("grant execute on function public.create_com_pedido_vendedor_core_0079", sql)


if __name__ == "__main__":
    unittest.main()
