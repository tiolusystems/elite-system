from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0095_pcp_formula_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/pcp/actions.ts"
FORM = ROOT / "apps/web/app/producao/formulas/formula-creation-form.tsx"


class PcpFormulaRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.pcp_formula_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("prevent_pcp_formula_request_changes", sql)

    def test_only_keyed_formula_entrypoint_is_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create_pcp_formula_versao_idempotente", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_formula_form_and_action_use_one_request_key(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        form = FORM.read_text(encoding="utf-8")
        self.assertIn('"create_pcp_formula_versao_idempotente"', actions)
        self.assertNotIn('"create_pcp_formula_versao"', actions)
        self.assertIn('name="idempotency_key"', form)
        self.assertIn("crypto.randomUUID()", form)

    def test_integrated_production_smoke_retries_formula_request(self) -> None:
        smoke = (ROOT / "tests/sql/production_end_to_end_chain.sql").read_text(encoding="utf-8")
        self.assertGreaterEqual(smoke.count("create_pcp_formula_versao_idempotente"), 4)
        self.assertIn("formula retry did not return the original version", smoke)


if __name__ == "__main__":
    unittest.main()
