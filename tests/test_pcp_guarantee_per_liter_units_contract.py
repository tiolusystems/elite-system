from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0089_pcp_guarantee_per_liter_units.sql"


class PcpGuaranteePerLiterUnitsContractTests(unittest.TestCase):
    def test_calculator_accepts_physical_and_scaled_formula_units(self):
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("('kg', 'kg_l_produzido')", text)
        self.assertIn("('l', 'l_l_produzido')", text)
        self.assertIn("unidade_consumo_nao_suportada", text)

    def test_rpc_security_contract_is_preserved(self):
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("security definer", text.lower())
        self.assertIn("set search_path = public", text)
        self.assertIn("begin_audited_rpc", text)
        self.assertIn("from public, anon", text)
        self.assertIn("to authenticated", text)

    def test_production_smoke_requires_non_null_results(self):
        smoke = (ROOT / "tests/sql/production_module_release.sql").read_text(encoding="utf-8")
        self.assertIn("v_valor is distinct from 10", smoke)
        self.assertIn("v_status is distinct from 'atende'", smoke)


if __name__ == "__main__":
    unittest.main()
