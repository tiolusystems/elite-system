from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0100_exchange_order_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"
PAGE = ROOT / "apps/web/app/pedidos/page.tsx"
SMOKE = ROOT / "tests/sql/validate_0086_orders_blocked_creation.sql"


class ExchangeOrderRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.com_pedido_troca_requisicoes", sql)
        self.assertIn("before update or delete", sql)
        self.assertIn("before truncate", sql)
        self.assertIn("pg_advisory_xact_lock", sql)

    def test_only_keyed_exchange_entrypoint_is_exposed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create_com_pedido_troca_idempotente", sql)
        self.assertIn(
            "revoke all on function public.create_com_pedido_troca(bigint, bigint, bigint, numeric, text, date, text, text)",
            sql,
        )

    def test_existing_order_form_key_governs_exchange(self):
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        smoke = SMOKE.read_text(encoding="utf-8")
        self.assertIn('"create_com_pedido_troca_idempotente"', actions)
        self.assertIn("p_idempotency_key: idempotencyKey", actions)
        self.assertIn('name="idempotency_key"', page)
        self.assertGreaterEqual(smoke.count("create_com_pedido_troca_idempotente"), 3)


if __name__ == "__main__":
    unittest.main()
