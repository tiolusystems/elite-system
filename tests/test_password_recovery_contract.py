from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
LOGIN_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "login" / "actions.ts"
LOGIN_PAGE = REPO_ROOT / "apps" / "web" / "app" / "login" / "page.tsx"
RECOVERY_PAGE = REPO_ROOT / "apps" / "web" / "app" / "login" / "recuperar-senha" / "page.tsx"
CHANGE_PAGE = REPO_ROOT / "apps" / "web" / "app" / "login" / "trocar-senha" / "page.tsx"
CONFIRM_ROUTE = REPO_ROOT / "apps" / "web" / "app" / "auth" / "confirm" / "route.ts"
PROXY = REPO_ROOT / "apps" / "web" / "proxy.ts"
MIGRATION = REPO_ROOT / "supabase" / "migrations" / "0046_password_recovery_contract.sql"
CONFIG = REPO_ROOT / "supabase" / "config.toml"
EMAIL_TEMPLATE = REPO_ROOT / "supabase" / "templates" / "recovery.html"
ENV_EXAMPLE = REPO_ROOT / "apps" / "web" / ".env.example"
START_LOCAL = REPO_ROOT / "scripts" / "start-local.ps1"


class PasswordRecoveryContractTests(unittest.TestCase):
    def test_public_recovery_request_is_generic_and_uses_supabase_auth(self) -> None:
        actions = LOGIN_ACTIONS.read_text(encoding="utf-8")
        page = RECOVERY_PAGE.read_text(encoding="utf-8")

        self.assertIn("resetPasswordForEmail", actions)
        self.assertIn('applicationUrl("/auth/confirm").toString()', actions)
        self.assertNotIn("auth.admin.listUsers", actions)
        self.assertNotIn(".rpc(", actions)
        self.assertIn("Se existe uma conta ativa", page)
        self.assertIn("não revela se existe ou não uma conta", page)
        self.assertNotIn("usuario nao encontrado", page.lower())

    def test_callback_accepts_only_recovery_and_removes_secret_from_url(self) -> None:
        route = CONFIRM_ROUTE.read_text(encoding="utf-8")

        self.assertIn('type === "recovery"', route)
        self.assertIn("supabase.auth.verifyOtp", route)
        self.assertIn("supabase.auth.exchangeCodeForSession", route)
        self.assertIn('applicationUrl("/")', route)
        self.assertNotIn("request.nextUrl.clone()", route)
        self.assertNotRegex(route, re.compile(r"redirectUrl\.pathname\s*=\s*request", re.IGNORECASE))

    def test_login_exposes_recovery_and_authenticated_change_paths(self) -> None:
        login = LOGIN_PAGE.read_text(encoding="utf-8")
        change = CHANGE_PAGE.read_text(encoding="utf-8")
        proxy = PROXY.read_text(encoding="utf-8")

        self.assertIn("/login/recuperar-senha", login)
        self.assertIn("/login/trocar-senha?mode=authenticated", login)
        self.assertIn("changeOwnPasswordAction", change)
        self.assertIn("temporary_password_bootstrap === true", proxy)
        self.assertIn('"/auth/confirm"', proxy)
        self.assertIn('"/login/recuperar-senha"', proxy)

    def test_completed_change_is_audited_without_credentials(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        actions = LOGIN_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("begin_audited_rpc(", sql)
        self.assertIn("log_audited_rpc_change(", sql)
        self.assertIn("'security.change_own_password'", sql)
        self.assertIn("'seguranca.own_password_changed'", sql)
        self.assertIn("'contains_password', false", sql)
        self.assertNotRegex(sql, r"\bp_(new_)?password\b")
        self.assertNotIn("token_hash", sql)
        self.assertIn('auditedRpc(supabase, "record_security_own_password_changed"', actions)

    def test_local_and_deploy_configuration_are_explicit(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        template = EMAIL_TEMPLATE.read_text(encoding="utf-8")
        env = ENV_EXAMPLE.read_text(encoding="utf-8")
        start_local = START_LOCAL.read_text(encoding="utf-8")

        self.assertIn("[auth.email.template.recovery]", config)
        self.assertIn("./supabase/templates/recovery.html", config)
        self.assertIn("{{ .TokenHash }}", template)
        self.assertIn("type=recovery", template)
        self.assertIn("NEXT_PUBLIC_APP_URL=", env)
        excluded_services = re.search(r"SupabaseExcludedServices = '([^']+)'", start_local)
        self.assertIsNotNone(excluded_services)
        self.assertNotIn("mailpit", excluded_services.group(1).split(","))


if __name__ == "__main__":
    unittest.main()
