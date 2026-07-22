from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ContextualManualCoverageTests(unittest.TestCase):
    def test_every_navigation_route_has_a_manual(self):
        navigation = (ROOT / "apps" / "web" / "lib" / "app-navigation.ts").read_text(encoding="utf-8")
        manuals = (ROOT / "apps" / "web" / "lib" / "manuals.ts").read_text(encoding="utf-8")
        routes = set(re.findall(r'href: "([^"]+)"', navigation))
        manual_routes = set(re.findall(r'manual\("([^"]+)"', manuals))
        self.assertEqual(set(), routes - manual_routes)

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
