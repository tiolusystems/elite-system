from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0097_manager_decision_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"
PAGE = ROOT / "apps/web/app/pedidos/page.tsx"


class ManagerDecisionRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.com_pedido_decisao_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("prevent_order_decision_request_changes", sql)

    def test_only_keyed_manager_entrypoint_is_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("registrar_com_pedido_decisao_gerencial_idempotente", sql)
        self.assertGreaterEqual(sql.count("from public, anon, authenticated"), 2)
        self.assertNotIn("to anon", sql)

    def test_manager_form_uses_key_and_legacy_action_is_absent(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('"registrar_com_pedido_decisao_gerencial_idempotente"', actions)
        self.assertNotIn('"registrar_com_pedido_decisao_gerencial"', actions)
        self.assertNotIn("registrarCreditoPedidoAction", actions)
        self.assertIn('name="idempotency_key" value={randomUUID()}', page)

    def test_integrated_commercial_smoke_retries_manager_request(self) -> None:
        smoke = (ROOT / "tests/sql/commercial_end_to_end_chain.sql").read_text(encoding="utf-8")
        self.assertGreaterEqual(smoke.count("registrar_com_pedido_decisao_gerencial_idempotente"), 4)
        self.assertIn("manager decision retry duplicated the event", smoke)


if __name__ == "__main__":
    unittest.main()
