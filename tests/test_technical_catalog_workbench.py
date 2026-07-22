from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "apps" / "web"
CATALOG_LIB = WEB / "lib" / "technical-catalog.ts"
CADASTROS_ACTIONS = WEB / "app" / "cadastros" / "actions.ts"
MIGRATION = ROOT / "supabase" / "migrations" / "0056_technical_catalog_operational_workbench.sql"
GROUP_FIX_MIGRATION = ROOT / "supabase" / "migrations" / "0057_product_group_relational_resolution.sql"
SMOKE = ROOT / "tests" / "sql" / "technical_catalog_operational_workbench.sql"
OVERVIEW = WEB / "app" / "cadastros" / "tecnicos" / "page.tsx"
MATERIALS = WEB / "app" / "cadastros" / "materias-primas" / "page.tsx"
MATERIAL_CREATE = WEB / "app" / "cadastros" / "materias-primas" / "governed-material-create-form.tsx"
INPUT_TYPE_ACTIONS = WEB / "app" / "cadastros" / "tipos-insumo" / "actions.ts"
UNITS = WEB / "app" / "cadastros" / "unidades" / "page.tsx"
PACKAGES = WEB / "app" / "cadastros" / "embalagens" / "page.tsx"
PRODUCTS = WEB / "app" / "cadastros" / "produtos" / "page.tsx"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class TechnicalCatalogWorkbenchTests(unittest.TestCase):
    def test_workbench_has_focused_routes_for_the_industrial_sequence(self) -> None:
        for path in (OVERVIEW, MATERIALS, UNITS, PACKAGES, PRODUCTS):
            self.assertTrue(path.exists(), path)
            self.assertIn("getTechnicalCatalog", path.read_text(encoding="utf-8"))

        overview = OVERVIEW.read_text(encoding="utf-8")
        for href in (
            "/cadastros/unidades",
            "/cadastros/materias-primas",
            "/cadastros/embalagens",
            "/cadastros/produtos",
            "/producao/formulas",
            "/producao#ops",
        ):
            self.assertIn(href, overview)

    def test_catalog_loader_reads_normalized_relational_sources(self) -> None:
        text = CATALOG_LIB.read_text(encoding="utf-8")
        for table in (
            "cad_unidades_medida",
            "cad_nutrientes",
            "cad_materias_primas",
            "cad_conversoes_unidade_mp",
            "cad_produtos_base",
            "cad_grupos_produto",
            "cad_embalagens",
            "cad_produto_embalagens",
        ):
            self.assertIn(f'.from("{table}")', text)

        self.assertNotIn("service_role", text)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", text)

    def test_material_editor_exposes_every_existing_audited_axis(self) -> None:
        text = MATERIALS.read_text(encoding="utf-8")
        for action in (
            "updateMateriaPrimaIdentityAction",
            "updateMateriaPrimaSkuAction",
            "updateMateriaPrimaTechnicalAction",
            "updateMateriaPrimaStockPolicyAction",
            "updateMateriaPrimaRegulatoryAction",
            "deactivateMateriaPrimaAction",
        ):
            self.assertIn(action, text)

        self.assertIn("GovernedMaterialCreateForm", text)
        self.assertIn("reviewAndCreateGovernedMaterialAction", MATERIAL_CREATE.read_text(encoding="utf-8"))
        self.assertIn('"create_cad_materia_prima_governada"', INPUT_TYPE_ACTIONS.read_text(encoding="utf-8"))

        self.assertIn('name="return_to" value="/cadastros/materias-primas"', text)
        self.assertNotIn("<datalist", text)

    def test_other_catalog_forms_keep_governed_server_actions(self) -> None:
        expectations = {
            UNITS: ("createConversaoUnidadeMpAction", "/cadastros/unidades"),
            PACKAGES: ("createEmbalagemAction", "/cadastros/embalagens"),
            PRODUCTS: ("createProdutoBaseAction", "/cadastros/produtos"),
        }
        for path, (action, return_to) in expectations.items():
            text = path.read_text(encoding="utf-8")
            self.assertIn(action, text)
            self.assertIn(f'value="{return_to}"', text)
            self.assertNotIn(".rpc(", text)

    def test_action_redirects_accept_only_named_internal_catalog_routes(self) -> None:
        text = CADASTROS_ACTIONS.read_text(encoding="utf-8")
        self.assertIn("ALLOWED_CADASTRO_RETURN_PATHS", text)
        self.assertIn("redirectCadastroAction", text)
        self.assertIn("revalidateTechnicalCatalogs", text)
        self.assertNotIn('redirect(field(formData, "return_to"))', text)

    def test_product_and_initial_validity_are_created_atomically(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8")
        group_fix = GROUP_FIX_MIGRATION.read_text(encoding="utf-8")
        smoke = SMOKE.read_text(encoding="utf-8")
        actions = CADASTROS_ACTIONS.read_text(encoding="utf-8")
        product_action = actions.split("export async function createProdutoBaseAction", 1)[1].split(
            "export async function createEmbalagemAction", 1
        )[0]

        self.assertIn("p_prazo_validade_meses integer default null", migration)
        self.assertIn("prazo_validade_meses,", migration)
        self.assertIn("public.begin_audited_rpc(", migration)
        self.assertIn("public.log_audited_rpc_change(", migration)
        self.assertIn("'initial_validity_atomic', true", migration)
        self.assertIn("grupo_id,", group_fix)
        self.assertIn("unknown or inactive product group", group_fix)
        self.assertIn("'product_group_relational', true", group_fix)
        self.assertIn("p_prazo_validade_meses: prazoValidadeMeses", product_action)
        self.assertEqual(product_action.count('auditedRpc<number>(supabase, "create_cad_produto_base"'), 1)
        self.assertNotIn('auditedRpc(supabase, "set_cad_produto_prazo_validade"', product_action)
        self.assertIn("PG_TECHNICAL_CATALOG_WORKBENCH_OK", smoke)
        self.assertIn("invalid product survived the atomic rollback", smoke)
        self.assertIn("technical_catalog_operational_workbench.sql", CI.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
