from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0050_dec_007_technical_catalogs.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_007_technical_catalogs.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-007-catalogos-tecnicos-normalizados.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_007_pre_0050_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_007_post_0050_verify.sql"


class Dec007TechnicalCatalogsContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_catalogs_and_versioned_specifications_are_relational(self) -> None:
        for table in (
            "cad_unidades_medida",
            "cad_unidade_aliases",
            "cad_nutrientes",
            "cad_nutriente_aliases",
            "cad_parametros_tecnicos",
            "cad_especificacao_produto_versoes",
            "cad_especificacao_produto_parametros",
            "cad_especificacao_produto_ativacoes",
        ):
            self.assertIn(f"create table if not exists public.{table}", self.sql)

        parameter_block = re.search(
            r"create table if not exists public\.cad_especificacao_produto_parametros\s*\((.*?)\n\);",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(parameter_block)
        self.assertNotIn("json", parameter_block.group(1))
        self.assertIn("parametro_id bigint not null references", parameter_block.group(1))
        self.assertIn("unidade_id bigint references", parameter_block.group(1))

    def test_existing_text_facts_gain_typed_foreign_keys(self) -> None:
        for fragment in (
            "cad_materias_unidade_base_fk",
            "pcp_formula_itens_unidade_fk",
            "cad_garantias_produto_nutriente_fk",
            "cad_garantias_produto_unidade_fk",
            "cad_garantias_lote_nutriente_fk",
            "cad_garantias_lote_unidade_fk",
            "pcp_op_garantia_nutriente_fk",
            "pcp_op_garantia_unidade_fk",
        ):
            self.assertIn(fragment, self.sql)

        self.assertIn("resolve_cad_unidade_id", self.sql)
        self.assertIn("resolve_cad_nutriente_id", self.sql)

    def test_historical_lineage_actor_and_pending_review_are_enforced(self) -> None:
        for fragment in (
            "excel_legado requires source_batch_id and source_row_id",
            "excel_legado must be created by migracao historica system actor",
            "source_row_id does not belong to source_batch_id workbook",
            "enforce_historical_record_contract('review_status', 'pending_review')",
            "enforce_historical_record_contract(%l, %l)",
            "idx_cad_especificacao_source_once",
            "idx_cad_garantia_produto_source_once",
        ):
            self.assertIn(fragment, self.sql)

    def test_calculated_guarantee_is_not_promoted_as_mapa(self) -> None:
        self.assertIn("calculada_formula_legada", self.sql)
        self.assertIn("cad_garantias_produto_calculadas_pendentes", self.sql)
        self.assertIn("guarantee.natureza = 'mapa_documental'", self.sql)
        self.assertIn("guarantee.review_status = 'approved'", self.sql)

    def test_only_human_activation_reaches_current_specification_view(self) -> None:
        self.assertIn("prevent_system_actor_catalog_activation", self.sql)
        self.assertIn("only active human profiles can activate product specifications", self.sql)
        self.assertIn("join public.cad_especificacao_produto_ativacoes", self.sql)
        self.assertIn("migracao historica", self.adr)
        self.assertIn("impedido por trigger de criar esse evento", self.adr)

    def test_direct_writes_are_revoked_and_smoke_is_wired(self) -> None:
        self.assertIn(
            "revoke insert, update, delete, truncate on public.%i from public, anon, authenticated",
            self.sql,
        )
        self.assertTrue(SMOKE.exists())
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/dec_007_technical_catalogs.sql", workflow)
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())

    def test_adr_documents_ownership_keys_backfill_and_rollback(self) -> None:
        for heading in (
            "## ownership e dependencias",
            "## chaves naturais e idempotencia",
            "## obrigatorios, opcionais e pendentes",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)


if __name__ == "__main__":
    unittest.main()
