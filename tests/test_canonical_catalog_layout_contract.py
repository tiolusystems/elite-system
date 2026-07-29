from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "apps" / "web"
CADASTROS = WEB / "app" / "cadastros"
CSS = WEB / "app" / "globals.css"


class CanonicalCatalogLayoutContractTests(unittest.TestCase):
    def test_canonical_routes_separate_list_detail_and_create_flows(self) -> None:
        route_expectations = {
            "materias-primas/page.tsx": ("isCreating", "isViewing"),
            "produtos/page.tsx": ("isListing", "isViewing"),
            "embalagens/page.tsx": ("isListing", "isViewing"),
            "grupos-produto/page.tsx": ("isListing", "isViewing"),
            "tipos-insumo/page.tsx": ("isListing", "isViewing"),
            "unidades/page.tsx": ("isCreating", "catalog-list-view"),
        }

        for relative_path, expected_tokens in route_expectations.items():
            text = (CADASTROS / relative_path).read_text(encoding="utf-8")
            self.assertIn('singleParam(params.modo)', text, relative_path)
            self.assertIn("Voltar à consulta", text, relative_path)
            for token in expected_tokens:
                self.assertIn(token, text, relative_path)

    def test_lists_and_forms_are_not_rendered_as_permanent_parallel_columns(self) -> None:
        for relative_path in (
            "materias-primas/page.tsx",
            "produtos/page.tsx",
            "embalagens/page.tsx",
            "grupos-produto/page.tsx",
            "tipos-insumo/page.tsx",
            "unidades/page.tsx",
        ):
            text = (CADASTROS / relative_path).read_text(encoding="utf-8")
            self.assertNotIn('className="catalog-split', text, relative_path)
            self.assertNotIn('className="two-column catalog-form-columns"', text, relative_path)

    def test_new_record_links_open_the_explicit_create_mode(self) -> None:
        hub = (CADASTROS / "page.tsx").read_text(encoding="utf-8")
        overview = (CADASTROS / "tecnicos" / "page.tsx").read_text(encoding="utf-8")
        for expected in (
            "/cadastros/materias-primas?modo=novo#nova-mp",
            "/cadastros/produtos?modo=novo#novo-produto",
            "/cadastros/embalagens?modo=novo#nova-embalagem",
        ):
            self.assertIn(expected, hub + overview)

    def test_shared_layout_uses_full_available_width(self) -> None:
        css = CSS.read_text(encoding="utf-8")
        for selector in (
            ".catalog-workbench",
            ".catalog-list-view",
            ".catalog-detail-view",
            ".catalog-create-view",
        ):
            self.assertIn(selector, css)
        self.assertIn("max-height: none;", css)
        self.assertIn("width: 100%;", css)

    def test_operator_copy_does_not_expose_canonical_unit_jargon(self) -> None:
        units = (CADASTROS / "unidades" / "page.tsx").read_text(encoding="utf-8")
        self.assertIn("Unidades de medida", units)
        self.assertNotIn("Unidades canonicas", units)
        self.assertNotIn("Catalogo canonico", units)


if __name__ == "__main__":
    unittest.main()
