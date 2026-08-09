from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0054_dec_006_historical_formulas_ops_contract.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_006_historical_formulas_ops.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-011-formulas-op-historicas.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_006_pre_0054_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_006_post_0054_verify.sql"


class Dec006HistoricalFormulasOpsContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_yield_stages_and_historical_refs_are_relational(self) -> None:
        for table in (
            "pcp_formula_rendimentos",
            "pcp_formula_etapas",
            "pcp_formula_item_etapas",
            "pcp_formula_referencias_historicas",
            "pcp_op_saidas_historicas",
            "pcp_op_cq_historico_parcial",
        ):
            self.assertIn(f"create table public.{table}", self.sql)

        output_block = re.search(
            r"create table public\.pcp_op_saidas_historicas\s*\((.*?)\n\);",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(output_block)
        self.assertNotIn("json", output_block.group(1))

    def test_op_has_exactly_one_formula_reference(self) -> None:
        self.assertIn("pcp_ordens_formula_reference_check", self.sql)
        self.assertIn("formula_referencia_historica_id", self.sql)
        self.assertIn("historical op cannot reference a current system formula", self.sql)
        self.assertIn("live op cannot use an unknown historical formula reference", self.sql)

    def test_unknown_output_and_partial_cq_do_not_invent_data(self) -> None:
        self.assertIn("natureza_saida = 'nao_classificada'", self.sql)
        self.assertIn("nao_classificada nao possui lote e nao gera estoque", self.sql)
        self.assertIn("campos ausentes permanecem nulos", self.sql)
        self.assertIn("historical op state is immutable", self.sql)

    def test_lineage_and_activation_are_fail_closed(self) -> None:
        for fragment in (
            "formula child batch must match its version",
            "historical op child must match the op origin and batch",
            "historical or pending formula cannot be activated",
            "enforce_historical_record_contract",
            "idx_pcp_ordens_source_once",
        ):
            self.assertIn(fragment, self.sql)

    def test_new_facts_are_append_only_and_direct_write_is_revoked(self) -> None:
        self.assertIn("prevent_dec006_fact_changes", self.sql)
        self.assertIn(
            "revoke insert, update, delete, truncate on public.%i from public, anon, authenticated",
            self.sql,
        )

    def test_smoke_upgrade_and_ci_are_wired(self) -> None:
        self.assertTrue(SMOKE.exists())
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())
        self.assertIn(
            "tests/sql/dec_006_historical_formulas_ops.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_adr_documents_required_decision_elements(self) -> None:
        for heading in (
            "## ownership e dependencias",
            "## chaves naturais e idempotencia",
            "## campos obrigatorios",
            "## campos opcionais",
            "## pendentes de revisao",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)


if __name__ == "__main__":
    unittest.main()
