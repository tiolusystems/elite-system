from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0036 = REPO_ROOT / "supabase" / "migrations" / "0036_security_admin_read_rpcs.sql"
SECURITY_PAGE = REPO_ROOT / "apps" / "web" / "app" / "seguranca" / "page.tsx"
SECURITY_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "seguranca" / "actions.ts"
SECURITY_LIB = REPO_ROOT / "apps" / "web" / "lib" / "security.ts"
HOME_PAGE = REPO_ROOT / "apps" / "web" / "app" / "page.tsx"


class SecurityAdminUiContractTests(unittest.TestCase):
    def test_read_rpcs_require_security_permissions(self) -> None:
        sql = MIGRATION_0036.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.list_security_user_profiles()", sql)
        self.assertIn("create or replace function public.list_security_effective_permissions", sql)
        self.assertIn("require_current_user_permission('security.manage_users')", sql)
        self.assertIn("require_current_user_permission('security.manage_permissions')", sql)
        self.assertIn("revoke all on function public.list_security_user_profiles() from public", sql)
        self.assertIn("grant execute on function public.list_security_effective_permissions(uuid) to authenticated", sql)

    def test_security_server_actions_use_audited_rpc(self) -> None:
        text = SECURITY_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("auditedRpc", text)
        self.assertIn('"upsert_security_user_profile"', text)
        self.assertIn('"set_security_permission_override"', text)
        self.assertIn('"clear_security_permission_override"', text)
        self.assertNotIn(".rpc(", text)

    def test_security_page_and_home_expose_route(self) -> None:
        page = SECURITY_PAGE.read_text(encoding="utf-8")
        home = HOME_PAGE.read_text(encoding="utf-8")

        self.assertIn("Seguranca e alcadas", page)
        self.assertIn("getSecurityDashboard", page)
        self.assertIn("setSecurityPermissionOverrideAction", page)
        self.assertIn('href="/seguranca"', home)
        self.assertIn("Seguranca", home)

    def test_security_dashboard_reads_via_admin_rpcs(self) -> None:
        text = SECURITY_LIB.read_text(encoding="utf-8")

        self.assertIn('supabase.rpc("list_security_user_profiles")', text)
        self.assertIn('supabase.rpc("list_security_effective_permissions"', text)
        self.assertNotIn('.from("user_profiles")', text)
        self.assertNotIn('.from("user_permission_overrides")', text)


if __name__ == "__main__":
    unittest.main()
