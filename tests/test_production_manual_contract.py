from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProductionManualContractTest(unittest.TestCase):
    def test_manual_covers_the_approved_operational_sequence(self) -> None:
        page = (ROOT / "apps/web/app/producao/manual/page.tsx").read_text(encoding="utf-8")

        for expected in (
            "Cadastros e garantias",
            "Crie a versão, confira e depois ative",
            "reserve os lotes necessários",
            "Registre processo, pessoas e CQ",
            "Use PI liberado, fórmula MAPA e embalagens",
            "Consulte físico, reservado e disponível",
        ):
            self.assertIn(expected, page)

        self.assertIn("A OP multiplica essas quantidades pelo volume planejado.", page)
        self.assertIn("Essa fórmula não movimenta estoque sozinha.", page)
        self.assertIn("Reservar reduz o disponível, mas o saldo físico só é baixado", page)
        self.assertIn("A produção gera PI. O envase consome PI e embalagens e gera PA.", page)

    def test_production_navigation_exposes_contextual_manual(self) -> None:
        shell = (ROOT / "apps/web/app/producao/production-shell.tsx").read_text(encoding="utf-8")

        self.assertIn('| "manual"', shell)
        self.assertIn('href: "/producao/manual"', shell)
        self.assertIn('label: "Como operar"', shell)


if __name__ == "__main__":
    unittest.main()
