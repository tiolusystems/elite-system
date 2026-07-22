from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0094_pcp_op_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pcp/actions.ts"
FORMS = [
    ROOT / "apps/web/app/producao/ordens/orders-workbench.tsx",
    ROOT / "apps/web/app/producao/transformacoes/transformation-workbench.tsx",
]


class PcpOpRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.pcp_op_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("prevent_pcp_op_request_changes", sql)

    def test_only_keyed_operational_entrypoint_is_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create_pcp_op_idempotente", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_all_ui_op_forms_use_request_keys(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn('"create_pcp_op_idempotente"', actions)
        self.assertNotIn('"create_pcp_op"', actions)
        for form in FORMS:
            text = form.read_text(encoding="utf-8")
            self.assertEqual(text.count("<form action={createPcpOpAction}"), text.count('name="idempotency_key"'))
        transformation = FORMS[1].read_text(encoding="utf-8")
        self.assertIn('name="quantidade_planejada"', transformation)
        self.assertIn("Volume planejado (L)", transformation)

    def test_integrated_production_smoke_retries_same_request(self) -> None:
        smoke = (ROOT / "tests/sql/production_end_to_end_chain.sql").read_text(encoding="utf-8")
        self.assertGreaterEqual(smoke.count("create_pcp_op_idempotente"), 3)
        self.assertIn("OP retry did not return the original production order", smoke)


if __name__ == "__main__":
    unittest.main()
