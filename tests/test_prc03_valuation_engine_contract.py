"""Executable contract for the governed PRC-03 valuation implementation."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0152_prc03_versioned_valuation_engine.sql"
ADR = ROOT / "docs/decisoes-arquiteturais/ADR-017_MOTOR_VALORACAO_VERSIONADO.md"
RUNTIME_SMOKE = ROOT / "tests/sql/prc03_versioned_valuation_engine.sql"
LIFECYCLE_SETUP = ROOT / "tests/sql/prc03_lifecycle_concurrency_setup.sql"
LIFECYCLE_WORKER = ROOT / "tests/sql/prc03_lifecycle_concurrency_worker.sql"
LIFECYCLE_ASSERT = ROOT / "tests/sql/prc03_lifecycle_concurrency_assert.sql"
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8").lower()


class Prc03ValuationEngineContract(unittest.TestCase):
    def migration_sql(self) -> str:
        self.assertTrue(
            MIGRATION.exists(),
            "PRC-03: migration 0152 and governed valuation runtime are absent",
        )
        return MIGRATION.read_text(encoding="utf-8").lower()

    def assert_contract(self, *required: str):
        sql = self.migration_sql()
        for term in required:
            self.assertIn(term.lower(), sql, f"PRC-03: missing {term}")

    def test_versioned_policy_and_segregated_review(self):
        self.assert_contract(
            "prc_valoracao_politicas", "prc_valoracao_versoes",
            "prc_valoracao_revisoes", "documento_sha256", "created_by",
        )

    def test_append_only_snapshot_and_layer_lineage(self):
        self.assert_contract(
            "prc_valoracao_snapshots", "result_sha256", "snapshot_camadas",
            "snapshot_exclusoes", "movimento_valor_id", "lote_mp_id",
        )

    def test_weighted_available_balance_and_reservations(self):
        self.assert_contract(
            "weighted_available_balance", "saldo_disponivel",
            "quantidade_reservada", "est_movimentos_mp_custo_alocacoes",
        )

    def test_latest_eligible_acquisition(self):
        self.assert_contract(
            "latest_eligible_acquisition", "data_validade",
            "custo_unitario_base", "est_movimentos_mp_valores",
        )
        sql = self.migration_sql()
        self.assertIn("'entrada_at',v_layer.entrada_at", sql)
        self.assertIn(
            "order by (layer->>'entrada_at')::timestamptz desc,",
            sql,
        )
        self.assertIn("(layer->>'movimento_mp_id')::bigint desc", sql)
        self.assertIn("(layer->>'movimento_valor_id')::bigint desc", sql)
        smoke = RUNTIME_SMOKE.read_text(encoding="utf-8").lower()
        self.assertIn("prc03-latest-global", smoke)
        self.assertIn("lote mais antigo", smoke)

    def test_lifecycle_is_serialized_by_owner_identity(self):
        sql = self.migration_sql()
        self.assertIn("prc-valuation-policy-lifecycle:", sql)
        self.assertIn("prc-valuation-reference-lifecycle:", sql)
        self.assertLess(
            sql.index("prc-valuation-policy-lifecycle:"),
            sql.index("select decisao into v_decisao from public.prc_valoracao_revisoes"),
        )
        self.assertLess(
            sql.index("prc-valuation-reference-lifecycle:"),
            sql.index("select decisao into v_decisao from public.prc_valoracao_referencia_revisoes"),
        )
        for path in (LIFECYCLE_SETUP, LIFECYCLE_WORKER, LIFECYCLE_ASSERT):
            self.assertTrue(path.exists(), f"PRC-03 lifecycle concurrency proof missing: {path.name}")
        self.assertIn("prc03_lifecycle_concurrency", LIFECYCLE_WORKER.read_text(encoding="utf-8"))
        self.assertIn("<>1", LIFECYCLE_ASSERT.read_text(encoding="utf-8"))

    def test_snapshot_document_hash_is_governed_and_verified(self):
        self.assert_contract(
            "documento_sha256 text not null", "prc_valoracao_snapshot_sha256",
            "consultar_prc_valoracao_snapshot", "hash integral do snapshot de valoracao diverge",
        )
        smoke = RUNTIME_SMOKE.read_text(encoding="utf-8").lower()
        self.assertIn("disable trigger trg_prc_valoracao_snapshots_append_only", smoke)
        self.assertIn("adulteracao de metadado do snapshot nao falhou fechado", smoke)

    def test_approved_manual_reference_and_segregation(self):
        self.assert_contract(
            "approved_manual_reference", "prc_valoracao_referencias",
            "referencia_revisoes", "documento_referencia", "motivo",
        )

    def test_units_and_currencies_fail_closed(self):
        self.assert_contract(
            "unidade_base_estoque", "cad_conversoes_unidade_mp",
            "moeda", "mixed_currency", "unidade da camada incompativel",
        )

    def test_pricing_cannot_write_stock_or_pcp(self):
        self.assert_contract(
            "precificacao.valuation.execute", "revoke all", "security definer",
            "est_movimentos_mp_valores", "est_lotes_mp_saldos",
        )
        sql = self.migration_sql()
        self.assertIsNone(
            re.search(r"\b(?:insert\s+into|update|delete\s+from)\s+public\.(?:est_|pcp_)", sql),
            "PRC-03 must not write Stock or PCP facts",
        )

    def test_packaging_reuses_component_source_once(self):
        adr = ADR.read_text(encoding="utf-8").lower()
        for term in (
            "cad_embalagem_componentes_atuais", "embalagem_versao_id",
            "materia_prima_id", "nao pode aparecer como fonte distinta",
        ):
            self.assertIn(
                term, adr,
                f"PRC-03: packaging integration contract missing {term}",
            )

    def test_runtime_proofs_are_registered_in_database_contract(self):
        for path in (
            "tests/sql/prc03_versioned_valuation_engine.sql",
            "tests/sql/prc03_lifecycle_concurrency_setup.sql",
            "tests/sql/prc03_lifecycle_concurrency_worker.sql",
            "tests/sql/prc03_lifecycle_concurrency_assert.sql",
        ):
            self.assertIn(path, CI)


if __name__ == "__main__":
    unittest.main()
