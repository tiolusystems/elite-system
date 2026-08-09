from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0051_dec_008_packaging_logistics_contract.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_008_packaging_logistics.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-008-embalagens-logistica-transformacoes.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_008_pre_0051_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_008_post_0051_verify.sql"


class Dec008PackagingLogisticsContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_packaging_bom_logistics_and_transformations_are_relational(self) -> None:
        tables = (
            "cad_embalagem_versoes",
            "cad_embalagem_componentes",
            "cad_embalagem_versao_ativacoes",
            "exp_romaneio_logistica_eventos",
            "est_transformacoes",
            "est_transformacao_origens",
            "est_transformacao_destinos",
            "est_transformacao_perdas",
        )
        for table in tables:
            self.assertIn(f"create table public.{table}", self.sql)

        for table in ("cad_embalagem_componentes", "est_transformacao_origens"):
            block = re.search(
                rf"create table public\.{table}\s*\((.*?)\n\);",
                self.sql,
                re.DOTALL,
            )
            self.assertIsNotNone(block)
            self.assertNotIn("json", block.group(1))

    def test_existing_text_units_gain_canonical_foreign_keys(self) -> None:
        for fragment in (
            "cad_embalagens_unidade_fk",
            "cad_conversoes_unidade_origem_fk",
            "cad_conversoes_unidade_destino_fk",
            "capacidade_unidade_id bigint references public.cad_unidades_medida",
            "sync_dec008_canonical_units",
        ):
            self.assertIn(fragment, self.sql)

    def test_historical_contract_is_fail_closed_and_idempotent(self) -> None:
        for fragment in (
            "source_batch_id bigint references public.migration_batches",
            "source_row_id bigint references public.source_rows",
            "idx_cad_embalagem_versoes_source_once",
            "idx_exp_romaneio_logistica_source_once",
            "idx_est_transformacoes_source_once",
            "enforce_historical_record_contract",
            "packaging component batch must match its version",
            "pending_review",
            "historical romaneio state is immutable",
        ):
            self.assertIn(fragment, self.sql)

    def test_inference_never_becomes_operational_automatically(self) -> None:
        self.assertIn("evidencia_tipo in ('comprovada', 'inferida')", self.sql)
        self.assertIn("evidencia_tipo <> 'inferida' or review_status = 'pending_review'", self.sql)
        self.assertIn("transformation.evidencia_tipo = 'comprovada'", self.sql)
        self.assertIn("nao gera movimento de estoque automaticamente", self.sql)
        self.assertIn("gera movimento de estoque automaticamente", self.adr)

    def test_versions_and_events_are_append_only_and_direct_write_is_revoked(self) -> None:
        for table in (
            "cad_embalagem_versoes",
            "exp_romaneio_logistica_eventos",
            "est_transformacoes",
        ):
            self.assertIn(f"'{table}'", self.sql)
        self.assertIn("prevent_dec008_fact_changes", self.sql)
        self.assertIn(
            "revoke insert, update, delete, truncate on public.%i from anon, authenticated",
            self.sql,
        )
        self.assertIn("only active human profiles can activate packaging versions", self.sql)

    def test_smoke_upgrade_and_ci_are_wired(self) -> None:
        self.assertTrue(SMOKE.exists())
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())
        self.assertIn(
            "tests/sql/dec_008_packaging_logistics.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_adr_covers_required_governance_sections(self) -> None:
        for heading in (
            "## decisao",
            "## chaves naturais e idempotencia",
            "## campos obrigatorios",
            "## campos opcionais",
            "## pendentes de revisao",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)
        for owner in ("`cadastros`", "`expedicao`", "`estoque`"):
            self.assertIn(owner, self.adr)


if __name__ == "__main__":
    unittest.main()
