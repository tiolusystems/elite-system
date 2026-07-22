from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "web" / "app" / "pedidos" / "[id]" / "contrato" / "page.tsx"
BUTTON = ROOT / "apps" / "web" / "app" / "pedidos" / "[id]" / "contrato" / "print-button.tsx"
ORDERS = ROOT / "apps" / "web" / "app" / "pedidos" / "page.tsx"
DATA = ROOT / "apps" / "web" / "lib" / "orders.ts"
STYLES = ROOT / "apps" / "web" / "app" / "globals.css"
MANUAL = ROOT / "docs" / "manuais" / "PEDIDOS.md"


class OrderContractPdfContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.button = BUTTON.read_text(encoding="utf-8")
        cls.orders = ORDERS.read_text(encoding="utf-8")
        cls.data = DATA.read_text(encoding="utf-8")
        cls.styles = STYLES.read_text(encoding="utf-8")
        cls.manual = MANUAL.read_text(encoding="utf-8")

    def test_export_is_available_only_after_approval(self) -> None:
        self.assertIn('["open", "fulfilled"].includes(order.status)', self.orders)
        self.assertIn('["open", "fulfilled"].includes(String(orderResult.data.status))', self.data)
        self.assertIn("Disponível após aprovação", self.orders)

    def test_document_uses_scoped_order_reads_without_admin_client(self) -> None:
        self.assertIn('from("com_pedidos")', self.data)
        self.assertIn('from("com_pedido_itens")', self.data)
        self.assertIn('from("com_pedido_credito_decisoes")', self.data)
        self.assertNotIn("createSupabaseAdminClient", self.data)
        self.assertNotIn("service_role", self.data)

    def test_contract_has_two_pages_and_official_sections(self) -> None:
        self.assertEqual(self.page.count('<section className="order-contract-page">'), 2)
        for label in (
            "Contrato de Compra e Venda de Insumos Agrícolas",
            "Detalhamento dos produtos do contrato",
            "Assinatura do comprador/proprietário",
            "Cancelamento de pedidos",
            "Atrasos em pagamentos",
        ):
            self.assertIn(label, self.page)

    def test_print_contract_is_a4_landscape_and_has_pdf_action(self) -> None:
        self.assertIn("window.print()", self.button)
        self.assertIn("Imprimir ou salvar em PDF", self.button)
        self.assertIn("size: A4 landscape", self.styles)
        self.assertIn("page-break-after: always", self.styles)

    def test_missing_master_data_is_explicit_and_internal_data_is_absent(self) -> None:
        self.assertIn("Não informado", self.page)
        for forbidden in ("limite_disponivel", "inadimplencia", "percentual_comissao", "valor_previsto"):
            self.assertNotIn(forbidden, self.page)
        self.assertIn("não inventa endereço", self.manual)


if __name__ == "__main__":
    unittest.main()
