from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]

SELF_CONTAINED_OR_TECHNICAL_ROUTES = {
    "/health",
    "/login",
    "/login/recuperar-senha",
    "/login/trocar-senha",
    "/pcp",
    "/producao/manual",
    "/romaneios/manual",
}


def published_page_routes() -> set[str]:
    app_root = ROOT / "apps" / "web" / "app"
    routes = set()
    for page in app_root.rglob("page.tsx"):
        relative = page.relative_to(app_root)
        parts = relative.parts[:-1]
        route = "/" + "/".join(parts) if parts else "/"
        routes.add(route)
    return routes


def route_is_covered(route: str, manual_routes: set[str]) -> bool:
    static_route = re.sub(r"/\[[^/]+\]", "", route)
    return any(
        static_route == manual_route
        or (manual_route != "/" and static_route.startswith(f"{manual_route}/"))
        for manual_route in manual_routes
    )


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
        operational_routes = published_page_routes() - SELF_CONTAINED_OR_TECHNICAL_ROUTES
        uncovered = {
            route for route in operational_routes
            if not route_is_covered(route, manual_routes)
        }
        self.assertEqual(set(), uncovered)

    def test_operational_routes_do_not_use_the_generic_manual_only(self):
        manuals = (ROOT / "apps" / "web" / "lib" / "manuals.ts").read_text(encoding="utf-8")
        generic_calls = set(
            re.findall(
                r'manual\("([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*"[^"]+"\),',
                manuals,
            )
        )
        self.assertEqual(
            {"/", "/modulos"},
            generic_calls,
            "Only non-transactional core portals may use the generic guide.",
        )

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
