from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PRODUCT_PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "produtos" / "page.tsx"
PRODUCT_PANEL = ROOT / "apps" / "web" / "app" / "cadastros" / "produtos" / "product-maintenance-panel.tsx"
PACKAGE_PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "embalagens" / "page.tsx"
PACKAGE_PANEL = ROOT / "apps" / "web" / "app" / "cadastros" / "embalagens" / "package-maintenance-panel.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
DATA = ROOT / "apps" / "web" / "lib" / "technical-catalog.ts"
GOVERNANCE = ROOT / "apps" / "web" / "lib" / "master-data-governance.ts"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"
ROUTE_STATES = ROOT / "apps" / "web" / "app" / "cadastros" / "tecnicos" / "catalog-route-states.tsx"


class ProductsPackagingUxContractTests(unittest.TestCase):
    def test_product_maintenance_uses_only_server_actions(self) -> None:
        text = PRODUCT_PANEL.read_text(encoding="utf-8")
        for action in (
            "updateProdutoIdentityAction",
            "updateProdutoTechnicalAction",
            "updateProdutoRegulatoryAction",
            "setProdutoActiveStateAction",
            "setApresentacaoActiveStateAction",
        ):
            self.assertIn(f"action={{{action}}}", text)
        self.assertNotIn(".rpc(", text)
        self.assertNotIn("service_role", text.lower())

    def test_packaging_composition_is_numeric_un_l_and_versioned(self) -> None:
        panel = PACKAGE_PANEL.read_text(encoding="utf-8")
        data = DATA.read_text(encoding="utf-8")
        for action in (
            "createEmbalagemVersaoAction",
            "addEmbalagemComponenteAction",
            "removeEmbalagemComponenteAction",
            "reviewEmbalagemVersaoAction",
            "activateEmbalagemVersaoAction",
        ):
            self.assertIn(f"action={{{action}}}", panel)
        self.assertIn('name="quantidade_un_l"', panel)
        self.assertIn("UN/L", panel)
        self.assertIn("unidades_embalagem_por_litro", data)
        self.assertIn("quantidade_un_l", data)
        self.assertNotIn('name="quantidade_texto"', panel)
        self.assertNotIn("1/5L", panel)

    def test_relations_are_ids_and_only_active_sources_are_selectable(self) -> None:
        product = PRODUCT_PANEL.read_text(encoding="utf-8")
        package = PACKAGE_PANEL.read_text(encoding="utf-8")
        self.assertIn('name="grupo_id"', product)
        self.assertIn('name="materia_prima_id"', package)
        self.assertIn('name="unidade_id"', package)
        self.assertIn('item.status === "active"', package)
        self.assertNotIn('name="grupo"', product)
        self.assertIn('item.code.toUpperCase() === "UN"', package)

    def test_internal_origin_and_unknown_status_are_not_exposed(self) -> None:
        page = PACKAGE_PAGE.read_text(encoding="utf-8")
        governance = GOVERNANCE.read_text(encoding="utf-8")
        shell = (ROOT / "apps" / "web" / "app" / "cadastros" / "tecnicos" / "catalog-shell.tsx").read_text(encoding="utf-8")
        self.assertIn("dataOriginLabel(item.source)", page)
        self.assertIn('excel_legado: "Excel legado"', governance)
        self.assertNotIn("<dd>{item.source}</dd>", page)
        self.assertIn("internalValueLabel(value)", shell)

    def test_catalog_supports_selection_without_multiple_simultaneous_flows(self) -> None:
        product = PRODUCT_PAGE.read_text(encoding="utf-8")
        package = PACKAGE_PAGE.read_text(encoding="utf-8")
        self.assertIn("selectedProduct", product)
        self.assertIn("ProductMaintenancePanel", product)
        self.assertIn("selectedPackage", package)
        self.assertIn("PackageMaintenancePanel", package)
        self.assertIn("Abrir produto", product)
        self.assertIn("Abrir embalagem", package)

    def test_actions_delegate_to_governed_rpcs(self) -> None:
        text = ACTIONS.read_text(encoding="utf-8")
        for rpc in (
            "update_cad_produto_identity",
            "update_cad_produto_technical",
            "update_cad_produto_regulatory",
            "set_cad_produto_active_state",
            "update_cad_embalagem_identity",
            "update_cad_embalagem_physical",
            "set_cad_embalagem_active_state",
            "set_cad_apresentacao_active_state",
            "create_cad_embalagem_versao_un_l",
            "add_cad_embalagem_componente_un_l",
            "remove_cad_embalagem_componente",
            "review_cad_embalagem_versao",
            "activate_cad_embalagem_versao",
        ):
            self.assertIn(f'"{rpc}"', text)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", text)

    def test_responsive_layout_has_mobile_reflow_and_no_fixed_wide_surface(self) -> None:
        css = CSS.read_text(encoding="utf-8")
        self.assertIn(".catalog-maintenance", css)
        self.assertIn(".package-composition", css)
        self.assertIn("@media (max-width: 900px)", css)
        self.assertIn("@media (max-width: 520px)", css)
        self.assertIn("grid-template-columns: 1fr;", css)
        for text in (PRODUCT_PANEL.read_text(encoding="utf-8"), PACKAGE_PANEL.read_text(encoding="utf-8")):
            self.assertNotIn("min-width: 900", text)

    def test_product_and_package_routes_have_human_loading_and_error_states(self) -> None:
        states = ROUTE_STATES.read_text(encoding="utf-8")
        for area in ("produtos", "embalagens"):
            route = ROOT / "apps" / "web" / "app" / "cadastros" / area
            self.assertTrue((route / "loading.tsx").is_file())
            self.assertTrue((route / "error.tsx").is_file())
        self.assertIn('aria-busy="true"', states)
        self.assertIn("Seus dados nao foram alterados", states)
        self.assertNotIn("Supabase", states)
        self.assertNotIn("RPC", states)
        self.assertIn(".catalog-state-skeleton", CSS.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
