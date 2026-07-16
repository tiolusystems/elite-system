from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOGIN = ROOT / "apps" / "web" / "app" / "login" / "page.tsx"
RECOVERY = ROOT / "apps" / "web" / "app" / "login" / "recuperar-senha" / "page.tsx"
CHANGE = ROOT / "apps" / "web" / "app" / "login" / "trocar-senha" / "page.tsx"
SHELL = ROOT / "apps" / "web" / "app" / "login" / "auth-public-shell.tsx"
PASSWORD = ROOT / "apps" / "web" / "app" / "login" / "password-input.tsx"
AUTH = ROOT / "apps" / "web" / "lib" / "auth.ts"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"


class Ux01aPublicAuthContractTests(unittest.TestCase):
    def test_public_auth_pages_use_the_isolated_shell(self) -> None:
        for page in (LOGIN, RECOVERY, CHANGE):
            text = page.read_text(encoding="utf-8")
            self.assertIn("AuthPublicShell", text)
            self.assertNotIn('className="topnav"', text)
            self.assertNotIn('className="app-shell"', text)

    def test_login_exposes_required_public_and_authenticated_actions(self) -> None:
        text = LOGIN.read_text(encoding="utf-8")
        for label in (
            "Entrar",
            "Esqueci minha senha",
            "Continuar no sistema",
            "Trocar usuário",
            "Sair",
        ):
            self.assertIn(label, text)
        self.assertIn("PasswordInput", text)

    def test_identity_release_and_environment_are_centralized(self) -> None:
        text = SHELL.read_text(encoding="utf-8")
        self.assertIn("Elite Agrociências", text)
        self.assertIn("Desenvolvido por TioLu Systems", text)
        self.assertIn("getBuildInfo", text)
        self.assertIn("new Date().getFullYear()", text)
        self.assertIn("environmentName", text)

    def test_password_visibility_is_accessible(self) -> None:
        text = PASSWORD.read_text(encoding="utf-8")
        self.assertIn('aria-pressed={visible}', text)
        self.assertIn('type={visible ? "text" : "password"}', text)
        self.assertIn('visible ? "Ocultar" : "Mostrar"', text)

    def test_auth_errors_never_expose_provider_details(self) -> None:
        text = AUTH.read_text(encoding="utf-8")
        self.assertNotIn("error.message", text)
        self.assertIn("O serviço de acesso não respondeu", text)

    def test_public_shell_has_mobile_specific_layout_without_horizontal_menu(self) -> None:
        text = CSS.read_text(encoding="utf-8")
        self.assertIn(".auth-public-shell", text)
        self.assertIn("@media (max-width: 600px)", text)
        self.assertIn("@media (max-width: 420px)", text)


if __name__ == "__main__":
    unittest.main()
