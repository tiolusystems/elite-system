from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0074_pcp_historical_guarantee_reconciliation.sql"
LOADER = ROOT / "apps" / "web" / "lib" / "pcp.ts"
WORKBENCH = ROOT / "apps" / "web" / "app" / "producao" / "garantias" / "guarantee-workbench.tsx"
ACTION = ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"
MANUAL = ROOT / "docs" / "manuais" / "producao" / "FORMULAS_GARANTIAS.md"


class HistoricalGuaranteeReconciliationContractTests(unittest.TestCase):
    def test_source_and_reviews_are_relational_append_only(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.pcp_garantia_fontes_historicas", sql)
        self.assertIn("create table public.pcp_garantia_reconciliacao_eventos", sql)
        self.assertIn("source_batch_id bigint not null", sql)
        self.assertIn("source_row_id bigint not null", sql)
        self.assertGreaterEqual(sql.count("prevent_production_guarantee_changes()"), 4)
        self.assertNotIn("jsonb not null", sql.lower())

    def test_review_is_audited_and_never_promotes_operational_data(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("public.begin_audited_rpc", sql)
        self.assertIn("public.log_audited_rpc_change", sql)
        self.assertIn("'promove_garantia_operacional', false", sql)
        function_body = sql.split("create or replace function public.revisar_pcp_garantia_historica", 1)[1]
        self.assertNotIn("insert into public.cad_garantias_produto_mapa", function_body)
        self.assertNotIn("insert into public.cad_garantias_lote_mp", function_body)
        self.assertNotIn("insert into public.pcp_op_garantia_resultados", function_body)

    def test_direct_writes_and_public_execution_are_denied(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("revoke insert, update, delete, truncate", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertIn("revoke all on function public.revisar_pcp_garantia_historica", sql)
        self.assertIn("from public, anon", sql)

    def test_ui_uses_governed_ids_and_clear_ptbr_labels(self) -> None:
        loader = LOADER.read_text(encoding="utf-8")
        workbench = WORKBENCH.read_text(encoding="utf-8")
        action = ACTION.read_text(encoding="utf-8")
        self.assertIn('.from("pcp_garantias_historicas_conciliacao_atual")', loader)
        self.assertIn('name="nutriente_id"', workbench)
        self.assertIn('name="unidade_pp_id"', workbench)
        self.assertIn('name="unidade_pv_id"', workbench)
        self.assertIn('"revisar_pcp_garantia_historica"', action)
        self.assertIn("não cria garantia MAPA", workbench)

    def test_manual_explains_non_promotion_rule(self) -> None:
        manual = MANUAL.read_text(encoding="utf-8")
        self.assertIn("Nenhum termo ambíguo é classificado automaticamente", manual)
        self.assertIn("não transforma o", manual)


if __name__ == "__main__":
    unittest.main()
