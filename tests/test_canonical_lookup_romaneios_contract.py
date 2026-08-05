from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
LOOKUP = ROOT / "apps/web/app/corporate-search/entity-lookup.tsx"
CONTROLS = ROOT / "apps/web/app/corporate-search/search-controls.tsx"
STYLES = ROOT / "apps/web/app/corporate-search/search-controls.module.css"
ROUTE = ROOT / "apps/web/app/api/lookups/[entity]/route.ts"
PAGE = ROOT / "apps/web/app/romaneios/page.tsx"
DATA = ROOT / "apps/web/lib/romaneios.ts"
LOOKUP_DATA = ROOT / "apps/web/lib/corporate-lookups.ts"
MIGRATION = ROOT / "supabase/migrations/0119_corporate_search_and_romaneio_filters.sql"
DOCUMENTATION = ROOT / "docs/ux/PADRAO_DE_PESQUISA_E_FILTROS.md"


class CanonicalLookupRomaneiosContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.lookup = LOOKUP.read_text(encoding="utf-8")
        cls.controls = CONTROLS.read_text(encoding="utf-8")
        cls.styles = STYLES.read_text(encoding="utf-8")
        cls.route = ROUTE.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.data = DATA.read_text(encoding="utf-8")
        cls.lookup_data = LOOKUP_DATA.read_text(encoding="utf-8")
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.documentation = DOCUMENTATION.read_text(encoding="utf-8")

    def test_canonical_components_are_explicit_and_reusable(self) -> None:
        self.assertIn("export function EntityCombobox", self.lookup)
        self.assertIn("export function EntityLookup", self.lookup)
        self.assertIn("export function FilterToolbar", self.controls)
        self.assertIn("export function AdvancedFilterPanel", self.controls)
        self.assertIn("export function ActiveFilterChips", self.controls)
        self.assertIn("export const SearchToolbar = FilterToolbar", self.controls)

    def test_lookup_opens_on_first_page_and_pages_on_the_server(self) -> None:
        self.assertIn("if (!open || disabled) return", self.lookup)
        self.assertIn('new URLSearchParams({ q: selectedId ? "" : query, pagina: String(page) })', self.lookup)
        self.assertIn("setPage(1)", self.lookup)
        self.assertIn("result.hasMore", self.lookup)
        self.assertIn("await supabase.auth.getUser()", self.route)
        self.assertIn('"Cache-Control": "private, no-store"', self.route)

    def test_romaneio_consultation_covers_human_filters(self) -> None:
        for field in (
            'entity="clientes"',
            'entity="pedidos-romaneio"',
            'entity="propriedades"',
            'entity="produtos"',
            'entity="lotes-pa"',
            'name="entregador"',
            'entity="veiculos"',
            'name="referencia"',
            'name="inicio"',
            'name="fim"',
            'name="status"',
        ):
            self.assertIn(field, self.page)
        self.assertIn("Cliente, pedido ou Romaneio", self.page)
        self.assertIn("DataTable", self.page)
        self.assertIn("PaginationBar", self.page)
        self.assertIn("RomaneioConsultationTable", self.page)

    def test_order_lookup_shows_customer_date_status_and_relevant_balance(self) -> None:
        self.assertIn("cad_clientes(nome)", self.lookup_data)
        self.assertIn("formatDate(row.data_pedido)", self.lookup_data)
        self.assertIn("availableItemsLabel", self.lookup_data)
        self.assertIn("status: optional(row.status)", self.lookup_data)
        self.assertIn('from("exp_pedido_item_romaneio_saldos")', self.lookup_data)
        self.assertIn('if (input.entity === "pedidos")', self.lookup_data)

    def test_romaneio_results_are_server_paginated_under_rls(self) -> None:
        self.assertIn('rpc("buscar_exp_romaneios_paginada"', self.data)
        self.assertIn("p_limite: pageSize", self.data)
        self.assertIn("p_offset: from", self.data)
        self.assertIn("security invoker", self.migration.lower())
        self.assertIn("revoke all on function public.buscar_exp_romaneios_paginada", self.migration.lower())
        self.assertNotIn("insert into", self.migration.lower())
        self.assertNotIn("update public.", self.migration.lower())

    def test_mobile_and_keyboard_contract_is_documented_and_styled(self) -> None:
        self.assertIn("@media (max-width: 600px)", self.styles)
        self.assertIn("grid-template-columns: minmax(0, 1fr)", self.styles)
        for term in ("EntityCombobox", "EntityLookup", "44 px", "Paginação", "Mobile e teclado", "Segurança"):
            self.assertIn(term, self.documentation)


if __name__ == "__main__":
    unittest.main()
