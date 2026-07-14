from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRODUCTION = ROOT / "apps" / "web" / "app" / "producao"
OVERVIEW = PRODUCTION / "page.tsx"
SHELL = PRODUCTION / "production-shell.tsx"
FORMULAS_PAGE = PRODUCTION / "formulas" / "page.tsx"
FORMULAS_COMPONENT = PRODUCTION / "formulas" / "formula-workbench.tsx"
GUARANTEES_PAGE = PRODUCTION / "garantias" / "page.tsx"
GUARANTEES_COMPONENT = PRODUCTION / "garantias" / "guarantee-workbench.tsx"
PCP_PAGE = ROOT / "apps" / "web" / "app" / "pcp" / "page.tsx"
PCP_ACTIONS = ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"
STYLES = ROOT / "apps" / "web" / "app" / "globals.css"


class ProductionOperationalWorkbenchTests(unittest.TestCase):
    def test_production_has_a_single_shell_and_operational_routes(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        overview = OVERVIEW.read_text(encoding="utf-8")

        for route in (
            "/producao",
            "/producao/formulas",
            "/producao/garantias",
        ):
            self.assertIn(route, shell if route != "/producao" else overview + shell)

        self.assertIn("ProductionShell", overview)
        self.assertIn("Sequencia da producao", overview)
        self.assertIn("Ordens de producao e reservas", overview)

    def test_formula_and_guarantee_pages_reuse_shared_business_components(self) -> None:
        formulas_page = FORMULAS_PAGE.read_text(encoding="utf-8")
        guarantees_page = GUARANTEES_PAGE.read_text(encoding="utf-8")
        pcp_page = PCP_PAGE.read_text(encoding="utf-8")

        self.assertIn("<FormulaWorkbench", formulas_page)
        self.assertIn("<GuaranteeWorkbench", guarantees_page)
        self.assertIn("<FormulaWorkbench", pcp_page)
        self.assertIn("<GuaranteeWorkbench", pcp_page)

    def test_writes_stay_in_existing_audited_server_actions(self) -> None:
        formulas = FORMULAS_COMPONENT.read_text(encoding="utf-8")
        guarantees = GUARANTEES_COMPONENT.read_text(encoding="utf-8")
        actions = PCP_ACTIONS.read_text(encoding="utf-8")

        for action in (
            "createPcpFormulaAction",
            "activatePcpFormulaAction",
            "registerProductGuaranteeAction",
            "registerMpLotGuaranteeAction",
        ):
            self.assertIn(action, formulas + guarantees)

        for rpc in (
            "create_pcp_formula_versao",
            "activate_pcp_formula_versao",
            "registrar_pcp_garantia_produto",
            "registrar_pcp_garantia_lote_mp",
        ):
            self.assertIn(f'auditedRpc(supabase, "{rpc}"', actions)

        self.assertNotIn(".rpc(", formulas + guarantees)

    def test_actions_return_to_the_new_operational_routes(self) -> None:
        actions = PCP_ACTIONS.read_text(encoding="utf-8")

        self.assertIn('/producao/formulas?result=formula_created', actions)
        self.assertIn('/producao/formulas?result=formula_activated', actions)
        self.assertIn('/producao/garantias?result=product_guarantee_registered', actions)
        self.assertIn('/producao/garantias?result=mp_lot_guarantee_registered', actions)
        self.assertNotIn('/pcp?result=formula_', actions)
        self.assertNotIn('/producao?result=product_guarantee_', actions)

    def test_layout_has_explicit_responsive_contract(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")

        self.assertIn(".production-workspace", styles)
        self.assertIn(".operation-card-grid", styles)
        self.assertIn("grid-template-columns: repeat(3, minmax(0, 1fr))", styles)
        self.assertIn("grid-template-columns: 1fr", styles)
        self.assertIn(".production-tabs", styles)


if __name__ == "__main__":
    unittest.main()
