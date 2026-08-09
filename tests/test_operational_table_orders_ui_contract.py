from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ORDERS = ROOT / "apps/web/app/producao/ordens/page.tsx"
COMPONENTS = ROOT / "apps/web/app/operational-table/operational-table.tsx"
STYLES = ROOT / "apps/web/app/operational-table/operational-table.module.css"


class OperationalTableOrdersUiContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.orders = ORDERS.read_text(encoding="utf-8")
        cls.components = COMPONENTS.read_text(encoding="utf-8")
        cls.styles = STYLES.read_text(encoding="utf-8")

    def test_orders_uses_the_reusable_operational_table_contract(self) -> None:
        for component in (
            "OperationalPageShell",
            "FilterToolbar",
            "DataTable",
            "PrimarySecondaryCell",
            "StatusBadge",
            "PaginationBar",
        ):
            self.assertIn(component, self.orders)
            self.assertIn(f"function {component}", self.components)
        self.assertNotIn('className="record-table"', self.orders)
        self.assertNotIn('className="catalog-filter production-order-filter"', self.orders)

    def test_order_product_formula_and_quantity_are_visually_separate(self) -> None:
        self.assertIn('label: "OP e fórmula"', self.orders)
        self.assertIn("formulaSummary(op.formulaLabel, op.produtoLabel)", self.orders)
        self.assertIn('label: "Produto"', self.orders)
        self.assertIn("splitPrimarySecondary(op.produtoLabel)", self.orders)
        self.assertIn('label: "Finalidade"', self.orders)
        self.assertIn('label: "Volume planejado"', self.orders)
        self.assertIn("`${formatNumber(op.quantidadePlanejada)} L`", self.orders)

    def test_table_has_fixed_columns_and_responsive_cards_without_body_overflow(self) -> None:
        self.assertIn("table-layout: fixed", self.styles)
        self.assertIn("width: var(--column-width)", self.styles)
        self.assertIn("overflow-wrap: anywhere", self.styles)
        self.assertIn("@media (max-width: 820px)", self.styles)
        self.assertIn("content: attr(data-label)", self.styles)
        self.assertIn("@media (max-width: 600px)", self.styles)
        self.assertNotIn("overflow-x: auto", self.styles)

    def test_filters_and_pagination_preserve_existing_query_contract(self) -> None:
        for field in ('name="q"', 'name="status"', 'name="tipo"'):
            self.assertIn(field, self.orders)
        self.assertIn("getPcpOrderQueue({ query, status, type, page })", self.orders)
        self.assertIn("pageHref(page - 1, query, status, type)", self.orders)
        self.assertIn("pageHref(page + 1, query, status, type)", self.orders)


if __name__ == "__main__":
    unittest.main()
