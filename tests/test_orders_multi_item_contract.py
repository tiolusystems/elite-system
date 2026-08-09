from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OrdersMultiItemContractTest(unittest.TestCase):
    def test_multi_item_rpc_and_editor_share_contract(self):
        sql = (ROOT / "supabase/migrations/0080_orders_multi_item_seller_entry.sql").read_text(encoding="utf-8")
        editor = (ROOT / "apps/web/app/pedidos/order-items-editor.tsx").read_text(encoding="utf-8")
        entry = (ROOT / "apps/web/app/pedidos/order-entry-editor.tsx").read_text(encoding="utf-8")
        action = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
        self.assertIn("create_com_pedido_vendedor_itens", sql)
        self.assertIn("between 1 and 100 items", sql)
        self.assertIn("sale item is inactive or unknown at position 1", sql)
        self.assertIn("order date is required", sql)
        self.assertIn("Adicionar item", editor)
        self.assertIn('name="itens_json"', entry)
        self.assertIn("Array.isArray(parsed)", action)
        self.assertIn('"create_com_pedido_vendedor_programado_idempotente"', action)

    def test_database_smoke_covers_atomic_order_contract(self):
        smoke = (ROOT / "tests/sql/validate_0080_orders_multi_item.sql").read_text(encoding="utf-8")
        self.assertIn("count(*) from public.com_pedido_itens", smoke)
        self.assertIn("<> 1055", smoke)
        self.assertIn("pendente_aprovacao", smoke)
        self.assertIn("inactive sale item was accepted", smoke)
        self.assertIn("seller order retry did not return the original order", smoke)


if __name__ == "__main__":
    unittest.main()
