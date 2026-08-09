from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AuthenticatedShellTransversalContractTests(unittest.TestCase):
    def test_shell_is_the_only_authenticated_navigation_owner(self):
        pages = list((ROOT / "apps" / "web" / "app").rglob("*.tsx"))
        offenders = []
        allowed = {"authenticated-app-shell.tsx"}
        for path in pages:
            if path.name in allowed:
                continue
            text = path.read_text(encoding="utf-8")
            if 'className="topnav"' in text or 'aria-label="Modulos principais"' in text:
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual([], offenders, f"Menus principais locais encontrados: {offenders}")

    def test_css_does_not_hide_local_navigation_by_dom_hierarchy(self):
        css = (ROOT / "apps" / "web" / "app" / "globals.css").read_text(encoding="utf-8")
        self.assertNotIn("authenticated-shell-content > .app-shell > .topbar", css)

    def test_shell_keeps_unreleased_modules_visible_and_explained(self):
        shell = (ROOT / "apps" / "web" / "app" / "authenticated-app-shell.tsx").read_text(encoding="utf-8")
        self.assertIn("navigation-disabled", shell)
        self.assertIn("Indisponivel", shell)


if __name__ == "__main__":
    unittest.main()
