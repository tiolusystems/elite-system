import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OrdersBlockedCreationGateTest(unittest.TestCase):
    def test_legacy_rpc_cannot_create_released_order(self):
        sql = (ROOT / "supabase/migrations/0086_orders_blocked_creation_gate.sql").read_text(encoding="utf-8")
        self.assertIn("p_status text default 'blocked'", sql)
        self.assertIn("if p_status <> 'blocked' then raise exception 'order must start blocked'", sql)
        self.assertIn("'pendente_aprovacao', 'blocked', 'blocked'", sql)
        self.assertIn("if p_vendedor_id is null then raise exception 'responsible seller is required'", sql)

    def test_server_actions_always_send_blocked(self):
        actions = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
        self.assertGreaterEqual(actions.count('const status = "blocked";'), 2)
        self.assertNotIn('field(formData, "status_troca")', actions)
        self.assertNotIn('field(formData, "status") || "draft"', actions)

    def test_pdf_is_available_only_after_approval(self):
        page = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        loader = (ROOT / "apps/web/lib/orders.ts").read_text(encoding="utf-8")
        self.assertIn('["open", "fulfilled"].includes(order.status)', page)
        self.assertIn('["open", "fulfilled"].includes(String(orderResult.data.status))', loader)
        self.assertIn("Disponível após aprovação", page)


if __name__ == "__main__":
    unittest.main()
