from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProductionManualContractTest(unittest.TestCase):
    def test_manual_covers_the_approved_operational_sequence(self) -> None:
        page = (ROOT / "apps/web/app/producao/manual/page.tsx").read_text(encoding="utf-8")

        for expected in (
            "Conferir os cadastros",
            "Registrar garantias",
            "fórmula de produção",
            "reservar lotes",
            "registrar CQ",
            "OP MAPA e Ordem de Envase",
            "lotes e estoque",
        ):
            self.assertIn(expected, page)

        self.assertIn("A fórmula de produção movimenta MP e gera PI", page)
        self.assertIn("A fórmula MAPA é documental", page)
        self.assertIn("Reserva não baixa saldo físico", page)

    def test_production_navigation_exposes_contextual_manual(self) -> None:
        shell = (ROOT / "apps/web/app/producao/production-shell.tsx").read_text(encoding="utf-8")

        self.assertIn('| "manual"', shell)
        self.assertIn('href: "/producao/manual"', shell)
        self.assertIn('label: "Como operar"', shell)


if __name__ == "__main__":
    unittest.main()
