from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/0145_harden_prc_sources_snapshots_and_idempotency.sql").read_text(encoding="utf-8")
SMOKE = (ROOT / "tests/sql/cost_pricing_iso_foundation.sql").read_text(encoding="utf-8")

class Prc0145Contract(unittest.TestCase):
    def test_system_source_is_fail_closed(self):
        self.assertIn("v_source='system' then raise exception 'fonte system sem adapter canonico'", MIGRATION)
        self.assertIn("v_source='fixture_validacao' and public.current_system_environment()<>'test'", MIGRATION)

    def test_snapshot_v2_is_complete_and_hashed_after_inputs_are_built(self):
        self.assertIn("'prc-calculation-v2'", MIGRATION)
        for phrase in ("'components'", "'formula'", "'outputs'", "'terms'", "for v_n in 1..18 loop", "result_sha256", "calculated_at"):
            self.assertIn(phrase, MIGRATION)
        self.assertLess(MIGRATION.index("v_terms:=v_terms||"), MIGRATION.index("v_hash:=public.prc_sha256(v_doc)"))
        self.assertLess(MIGRATION.index("v_hash:=public.prc_sha256(v_doc)"), MIGRATION.index("insert into public.prc_calculos"))

    def test_idempotency_serializes_before_lookup(self):
        self.assertIn("pg_advisory_xact_lock(hashtextextended('prc-idempotency:'||p_key::text,0))", MIGRATION)
        self.assertIn("v_existing:=public.prc_idempotent_result", MIGRATION)
        self.assertIn("insert into public.prc_requisicoes", MIGRATION)

    def test_smoke_keeps_business_and_security_assertions(self):
        self.assertIn("fonte system sem adapter canonico", SMOKE + MIGRATION)
        self.assertIn("result_sha256", SMOKE)
        self.assertIn("retry de decisao duplicou fato", SMOKE)

if __name__ == '__main__':
    unittest.main()