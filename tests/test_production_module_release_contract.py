from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION = REPO_ROOT / "supabase" / "migrations" / "0044_production_module_release.sql"
SMOKE = REPO_ROOT / "tests" / "sql" / "production_module_release.sql"
PCP_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"
PCP_PAGE = REPO_ROOT / "apps" / "web" / "app" / "pcp" / "page.tsx"
PCP_EDITORS = REPO_ROOT / "apps" / "web" / "app" / "pcp" / "production-editors.tsx"
GUARANTEE_WORKBENCH = REPO_ROOT / "apps" / "web" / "app" / "producao" / "garantias" / "guarantee-workbench.tsx"
CADASTROS_PAGE = REPO_ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
PRODUCTION_ROUTE = REPO_ROOT / "apps" / "web" / "app" / "producao" / "page.tsx"
CI = REPO_ROOT / ".github" / "workflows" / "ci.yml"
DECISION = REPO_ROOT / "docs" / "decisao_publicacao_modulo_producao.md"


class ProductionModuleReleaseContractTests(unittest.TestCase):
    def test_guarantee_actions_are_owned_by_pcp_runtime(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        for action_key in (
            "pcp.guarantee.product.register",
            "pcp.guarantee.mp_lot.register",
            "pcp.guarantee.calculate",
        ):
            self.assertIn(action_key, text)

        self.assertGreaterEqual(text.count("'pcp', 'write'"), 3)
        self.assertIn("values ('/producao', 'pcp', true)", text)

    def test_guarantees_and_results_are_append_only(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        for table_name in (
            "cad_garantias_produto_mapa",
            "cad_garantias_lote_mp",
            "pcp_op_garantia_resultados",
        ):
            self.assertIn(f"before update or delete on public.{table_name}", text)
            self.assertIn(f"before truncate on public.{table_name}", text)

        self.assertIn("prevent_production_guarantee_changes", text)
        self.assertIn("supersedes_id", text)

    def test_calculation_uses_actual_consumption_and_fails_closed(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("guarantee.valor * consumption.quantidade_consumida", text)
        self.assertIn("nullif(sum(consumption.quantidade_consumida), 0)", text)
        self.assertIn("'sem_dados_lote'", text)
        self.assertIn("'unidade_incompativel'", text)
        self.assertIn("'sem_referencia_mapa'", text)
        self.assertIn("perform pg_advisory_xact_lock", text)
        self.assertGreaterEqual(text.count("'laboratorio', 'fornecedor', 'calculado'"), 2)
        self.assertGreaterEqual(text.count("documento_referencia is required for laboratorio or fornecedor"), 2)

    def test_guarantee_rpcs_start_with_audited_permission_contract(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        for function_name in (
            "registrar_pcp_garantia_produto",
            "registrar_pcp_garantia_lote_mp",
            "calcular_pcp_garantias_op",
        ):
            start = text.index(f"create or replace function public.{function_name}")
            end = text.index("$$;", start)
            body = text[start:end]
            self.assertIn("public.begin_audited_rpc(", body)
            self.assertIn("public.log_audited_rpc_change(", body)

    def test_web_exposes_audited_guarantee_and_release_operations(self) -> None:
        actions = PCP_ACTIONS.read_text(encoding="utf-8")
        page = PCP_PAGE.read_text(encoding="utf-8")
        guarantee_workbench = GUARANTEE_WORKBENCH.read_text(encoding="utf-8")

        for rpc_name in (
            "registrar_pcp_garantia_produto",
            "registrar_pcp_garantia_lote_mp",
            "calcular_pcp_garantias_op",
            "liberar_pcp_lote_bloqueado",
        ):
            self.assertIn(f'auditedRpc(supabase, "{rpc_name}"', actions)

        self.assertIn("<GuaranteeWorkbench", page)
        self.assertIn("registerProductGuaranteeAction", guarantee_workbench)
        self.assertIn("registerMpLotGuaranteeAction", guarantee_workbench)
        self.assertIn('id="transformacoes"', page)
        self.assertIn('id="lotes"', page)
        self.assertTrue(PRODUCTION_ROUTE.exists())

    def test_production_and_master_data_do_not_parse_free_text_lookups(self) -> None:
        text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (PCP_PAGE, PCP_EDITORS, CADASTROS_PAGE, PCP_ACTIONS)
        )

        self.assertNotIn("<datalist", text)
        self.assertNotIn("list=", text)
        self.assertNotIn("LookupDatalist", text)
        self.assertNotIn("lookupValue", text)
        self.assertNotIn("idPrefix", text)

    def test_smoke_ci_and_decision_are_versioned(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")
        ci = CI.read_text(encoding="utf-8")

        self.assertIn("PG_PRODUCTION_MODULE_RELEASE_OK", smoke)
        self.assertIn("production_module_release.sql", ci)
        self.assertTrue(DECISION.exists())


if __name__ == "__main__":
    unittest.main()
