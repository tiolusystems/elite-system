from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]

OPERATIONAL_ROUTES = {
    "/", "/modulos", "/modulo-indisponivel", "/cadastros",
    "/cadastros/materias-primas", "/cadastros/tipos-insumo",
    "/cadastros/produtos", "/cadastros/grupos-produto",
    "/cadastros/embalagens", "/cadastros/unidades", "/cadastros/tecnicos",
    "/pedidos", "/pedidos/financeiro", "/kanban", "/producao",
    "/producao/formulas", "/producao/garantias", "/producao/ordens",
    "/producao/qualidade", "/producao/envase", "/producao/estoque",
    "/producao/transformacoes", "/romaneios", "/importacao-xml",
    "/importacao-historica/mp", "/relatorios", "/seguranca",
}


class ContextualManualCoverageTests(unittest.TestCase):
    def test_every_navigation_route_has_a_manual(self):
        navigation = (ROOT / "apps" / "web" / "lib" / "app-navigation.ts").read_text(encoding="utf-8")
        manuals = (ROOT / "apps" / "web" / "lib" / "manuals.ts").read_text(encoding="utf-8")
        routes = set(re.findall(r'href: "([^"]+)"', navigation))
        manual_routes = set(re.findall(r'manual\("([^"]+)"', manuals))
        self.assertEqual(set(), routes - manual_routes)

    def test_every_published_operational_route_has_a_manual(self):
        manuals = (ROOT / "apps" / "web" / "lib" / "manuals.ts").read_text(encoding="utf-8")
        manual_routes = set(re.findall(r'manual\("([^"]+)"', manuals))
        self.assertEqual(set(), OPERATIONAL_ROUTES - manual_routes)

    def test_manual_contract_has_all_operational_sections(self):
        text = (ROOT / "apps" / "web" / "app" / "manual-trigger.tsx").read_text(encoding="utf-8")
        for label in (
            "O que esta tela faz",
            "Antes de comecar",
            "Como executar",
            "O que acontece depois",
            "Quem pode executar",
            "Erros e bloqueios",
            "Dados e historico gerados",
        ):
            self.assertIn(label, text)


if __name__ == "__main__":
    unittest.main()
