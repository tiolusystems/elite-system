from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "apps" / "web" / "app" / "layout.tsx"
SHELL = ROOT / "apps" / "web" / "app" / "authenticated-app-shell.tsx"
NAVIGATION = ROOT / "apps" / "web" / "lib" / "app-navigation.ts"
BLOCKED = ROOT / "apps" / "web" / "app" / "modulo-indisponivel" / "page.tsx"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"
BRAND = ROOT / "apps" / "web" / "public" / "brand" / "elite-agrociencias-logo.png"
BRAND_DOC = ROOT / "docs" / "UX_BRAND_IDENTITY.md"


class Ux01bAuthenticatedShellContractTests(unittest.TestCase):
    def test_root_layout_uses_session_aware_shell(self) -> None:
        text = LAYOUT.read_text(encoding="utf-8")
        self.assertIn("AuthenticatedAppShell", text)
        self.assertIn("getAuthStatus", text)
        self.assertIn("getModuleRuntimeDashboard", text)

    def test_shell_reuses_identity_and_session_actions(self) -> None:
        text = SHELL.read_text(encoding="utf-8")
        for contract in (
            "logoutAction",
            "switchUserAction",
            "build.version",
            "build.release",
            "runtime.databaseMode",
            "auth.profile",
        ):
            self.assertIn(contract, text)

    def test_shell_uses_the_official_brand_asset_and_tokens(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        css = CSS.read_text(encoding="utf-8")
        documentation = BRAND_DOC.read_text(encoding="utf-8")
        self.assertTrue(BRAND.exists())
        self.assertIn("/brand/elite-agrociencias-logo.png", shell)
        self.assertIn('alt="Elite Agrociências"', shell)
        for token in (
            "--brand-primary",
            "--brand-primary-strong",
            "--brand-secondary",
            "--brand-accent",
            "--brand-focus",
        ):
            self.assertIn(token, css)
        self.assertIn("Não existe símbolo compacto oficial separado", documentation)

    def test_public_routes_never_receive_authenticated_navigation(self) -> None:
        text = SHELL.read_text(encoding="utf-8")
        self.assertIn('"/login"', text)
        self.assertIn('"/auth/confirm"', text)
        self.assertIn("!auth.isAuthenticated", text)

    def test_navigation_is_module_aware_and_marks_current_route(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        navigation = NAVIGATION.read_text(encoding="utf-8")
        self.assertIn("module.available || module.isCore", shell)
        self.assertIn('aria-current={active ? "page" : undefined}', shell)
        self.assertIn("navigationItemForPath", navigation)

    def test_mobile_navigation_is_a_drawer_without_horizontal_overflow(self) -> None:
        text = CSS.read_text(encoding="utf-8")
        self.assertIn(".navigation-trigger", text)
        self.assertIn("translateX(-104%)", text)
        self.assertIn("overflow-x: clip", text)
        self.assertIn("@media (max-width: 820px)", text)

    def test_authenticated_workspace_uses_wide_screens_without_breaking_mobile(self) -> None:
        text = CSS.read_text(encoding="utf-8")
        self.assertIn("max-width: 1480px", text)
        self.assertIn("padding: 24px clamp(20px, 2vw, 36px) 40px", text)
        self.assertIn("padding: 20px 16px 32px", text)

    def test_blocked_state_has_useful_actions_without_retry(self) -> None:
        text = BLOCKED.read_text(encoding="utf-8")
        self.assertIn("Ver modulos disponiveis", text)
        self.assertIn("Ir para o inicio", text)
        self.assertIn("moduleName", text)
        self.assertNotIn("Tentar novamente", text)


if __name__ == "__main__":
    unittest.main()
