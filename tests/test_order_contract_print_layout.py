import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OrderContractPrintLayoutTest(unittest.TestCase):
    def setUp(self):
        self.css = (ROOT / "apps/web/app/globals.css").read_text(encoding="utf-8")

    def test_order_contract_uses_named_a4_landscape_page(self):
        self.assertIn("@page order-contract { size: A4 landscape; margin: 7mm; }", self.css)
        self.assertIn("page: order-contract;", self.css)
        self.assertIn(".order-contract-page:last-child { break-after: auto; }", self.css)

    def test_packaging_print_does_not_override_order_contract_orientation(self):
        self.assertIn("@page packaging-order { size: A4 portrait; margin: 10mm; }", self.css)
        self.assertIn(".packaging-print-sheet { page: packaging-order;", self.css)
        self.assertNotIn("@page { size: A4; margin: 10mm; }", self.css)

    def test_printed_contract_uses_available_page_width(self):
        self.assertIn("width: 100%;\n    max-width: none;", self.css)
        self.assertNotIn(".order-contract-page { width: 283mm;", self.css)


if __name__ == "__main__":
    unittest.main()
