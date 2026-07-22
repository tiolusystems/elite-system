from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ContextualManualOperationalContentTests(unittest.TestCase):
    def test_priority_workflows_have_specific_instructions(self):
        manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        for instruction in (
            "Todo pedido nasce bloqueado",
            "Exportar PDF",
            "formula operacional usa base de 1 litro",
            "criar um unico lote PI",
            "OP MAPA permanece documental",
            "Abra a lista de pedidos com saldo",
            "SKU repetido",
            "unidades por volume logistico",
        ):
            self.assertIn(instruction, manuals)

    def test_manuals_do_not_claim_automatic_estimates(self):
        manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        self.assertIn("o sistema nao estima valores", manuals)
        self.assertNotIn("preencha automaticamente", manuals.lower())


if __name__ == "__main__":
    unittest.main()
