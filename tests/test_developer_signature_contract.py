from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMPONENT = ROOT / "apps" / "web" / "app" / "developer-signature.tsx"
LOGIN_SHELL = ROOT / "apps" / "web" / "app" / "login" / "auth-public-shell.tsx"
APP_SHELL = ROOT / "apps" / "web" / "app" / "authenticated-app-shell.tsx"


class DeveloperSignatureContractTests(unittest.TestCase):
    def test_signature_is_reusable_and_uses_the_approved_visible_text(self) -> None:
        component = COMPONENT.read_text(encoding="utf-8")

        self.assertIn('"developer-signature"', component)
        self.assertIn('aria-label="by ☧ SYSTEMS"', component)
        self.assertIn('by <span aria-hidden="true">☧</span> SYSTEMS', component)

    def test_signature_replaces_only_the_existing_developer_credits(self) -> None:
        login_shell = LOGIN_SHELL.read_text(encoding="utf-8")
        app_shell = APP_SHELL.read_text(encoding="utf-8")

        self.assertIn("<DeveloperSignature />", login_shell)
        self.assertIn("<DeveloperSignature />", app_shell)
        self.assertNotIn("<DeveloperSignature />\n        </Link>", login_shell)
        self.assertNotIn("TioLu Systems", login_shell)
        self.assertNotIn("TioLu Systems", app_shell)

    def test_forbidden_visible_variants_are_absent_from_web_interface(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "apps" / "web").rglob("*.tsx")
        )

        self.assertNotIn("PX Systems", source)
        self.assertNotIn(">Chi Rho<", source)


if __name__ == "__main__":
    unittest.main()
