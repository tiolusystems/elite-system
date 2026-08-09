from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0093_order_request_idempotency.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "pedidos" / "actions.ts"
PAGE = ROOT / "apps" / "web" / "app" / "pedidos" / "page.tsx"


class OrderRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.com_pedido_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertGreaterEqual(sql.count("pg_advisory_xact_lock"), 2)
        self.assertIn("prevent_order_request_changes", sql)
        self.assertIn("idempotency key reused with different order request", sql)

    def test_only_keyed_seller_entrypoints_are_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create_com_pedido_vendedor_itens_idempotente", sql)
        self.assertIn("create_com_pedido_vendedor_especial_idempotente", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_order_form_and_actions_use_one_request_key(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('name="idempotency_key"', page)
        self.assertIn('"create_com_pedido_vendedor_programado_idempotente"', actions)
        self.assertIn('"create_com_pedido_vendedor_especial_idempotente"', actions)
        self.assertNotIn('"create_com_pedido_vendedor_itens"', actions)
        self.assertNotIn('"create_com_pedido_vendedor_especial"', actions)


if __name__ == "__main__":
    unittest.main()
