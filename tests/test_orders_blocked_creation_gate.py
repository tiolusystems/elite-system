import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OrdersBlockedCreationGateTest(unittest.TestCase):
    def test_canonical_creation_smoke_requires_blocked_order(self):
        smoke = (ROOT / "tests/sql/validate_0086_orders_blocked_creation.sql").read_text(encoding="utf-8")
        self.assertIn("create_com_pedido_vendedor_programado_idempotente", smoke)
        self.assertIn("operational order did not start blocked", smoke)
        self.assertIn("operational order did not enter approval queue", smoke)
        self.assertIn("legacy operational order entrypoint remains executable", smoke)

    def test_server_actions_always_send_blocked(self):
        actions = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
        self.assertIn('"confirmar_com_revisao_comercial_venda_idempotente"', actions)
        self.assertIn('"create_com_pedido_vendedor_especial_idempotente"', actions)
        self.assertNotIn("createPedidoRascunhoAction", actions)
        self.assertNotIn('"create_com_pedido_operacional"', actions)
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
