from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0096_credit_limit_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"
PAGE = ROOT / "apps/web/app/pedidos/page.tsx"


class CreditLimitRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.fin_limite_credito_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("prevent_credit_limit_request_changes", sql)

    def test_only_keyed_credit_limit_entrypoint_is_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("ajustar_com_limite_credito_cliente_idempotente", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_manager_form_and_action_use_request_key(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('"ajustar_com_limite_credito_cliente_idempotente"', actions)
        self.assertNotIn('"ajustar_com_limite_credito_cliente"', actions)
        self.assertIn('name="idempotency_key" value={randomUUID()}', page)

    def test_integrated_commercial_smoke_retries_credit_request(self) -> None:
        smoke = (ROOT / "tests/sql/commercial_end_to_end_chain.sql").read_text(encoding="utf-8")
        self.assertGreaterEqual(smoke.count("ajustar_com_limite_credito_cliente_idempotente"), 4)
        self.assertIn("credit limit retry duplicated the event", smoke)


if __name__ == "__main__":
    unittest.main()
