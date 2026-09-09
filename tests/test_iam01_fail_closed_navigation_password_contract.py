from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0148_iam01_fail_closed_navigation_and_password.sql"
SMOKE = ROOT / "tests" / "sql" / "iam01_fail_closed_navigation_password.sql"
SHELL = ROOT / "apps" / "web" / "app" / "authenticated-app-shell.tsx"
LAYOUT = ROOT / "apps" / "web" / "app" / "layout.tsx"
PROXY = ROOT / "apps" / "web" / "proxy.ts"
LOGIN_ACTIONS = ROOT / "apps" / "web" / "app" / "login" / "actions.ts"
PASSWORD_PAGE = ROOT / "apps" / "web" / "app" / "login" / "trocar-senha" / "page.tsx"
LOOKUPS = ROOT / "apps" / "web" / "app" / "api" / "lookups" / "[entity]" / "route.ts"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class Iam01FailClosedNavigationPasswordContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.migration = MIGRATION.read_text(encoding="utf-8")
        self.smoke = SMOKE.read_text(encoding="utf-8")

    def test_all_active_profiles_receive_only_the_self_service_password_capability(self) -> None:
        self.assertIn("where profile.status = 'active'", self.migration)
        self.assertIn("'security.change_own_password'", self.migration)
        self.assertNotIn("security.manage_users", self.migration.split("delete from public.security_access_profile_permissions", 1)[0])
        self.assertNotIn("security.manage_permissions", self.migration.split("delete from public.security_access_profile_permissions", 1)[0])

    def test_seller_loses_price_lists_and_domain_routes_fail_closed(self) -> None:
        self.assertIn("profile.profile_key = 'comercial_vendedor'", self.migration)
        self.assertIn("permission.action_key = 'pedidos.price_lists.view'", self.migration)
        for route in (
            "/producao", "/romaneios", "/importacao-xml", "/qualidade/pops",
            "/qualidade/rastreabilidade", "/relatorios", "/seguranca", "/pedidos/listas-precos",
        ):
            self.assertIn(route, self.migration)
            self.assertIn(route, self.smoke)
        self.assertIn("seller route did not fail closed", self.smoke)

    def test_navigation_and_direct_routes_use_effective_capability_not_module_availability(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        layout = LAYOUT.read_text(encoding="utf-8")
        proxy = PROXY.read_text(encoding="utf-8")
        lookups = LOOKUPS.read_text(encoding="utf-8")
        self.assertIn("getNavigationAccess", layout)
        self.assertIn("navigationAccess?.[item.href] !== true", shell)
        self.assertIn('supabase.rpc("get_current_route_capability_access"', proxy)
        self.assertIn("if (!capabilityAccess.allowed)", proxy)
        self.assertIn('supabase.rpc("get_current_route_capability_access"', lookups)
        self.assertNotIn("module.available || module.isCore", shell)

    def test_password_authorization_precedes_auth_change_and_audit_failure_never_requests_retry(self) -> None:
        actions = LOGIN_ACTIONS.read_text(encoding="utf-8")
        page = PASSWORD_PAGE.read_text(encoding="utf-8")
        self.assertLess(actions.index('"can_current_user"'), actions.index("supabase.auth.updateUser"))
        self.assertIn('p_action_key: "security.change_own_password"', actions)
        self.assertIn("password_changed_audit_pending", actions)
        self.assertIn("Sua senha já foi alterada", page)
        self.assertIn("não tente trocá-la novamente", page)

    def test_order_and_kanban_scope_remain_effective_permission_based(self) -> None:
        self.assertIn("public.can_current_user('pedidos.view.own')", self.migration)
        self.assertIn("public.can_current_user('pedidos.view.team')", self.migration)
        self.assertIn("public.can_current_user('pedidos.view')", self.migration)
        self.assertIn("security_invoker = true", self.migration)
        self.assertIn("RLS exposed another seller order", self.smoke)
        self.assertIn("kanban exposed another seller order", self.smoke)

    def test_pcp_and_stock_reads_are_capability_gated_with_invoker_views(self) -> None:
        for action in ("pcp.formula.view", "pcp.op.view", "pcp.guarantee.view"):
            self.assertIn(action, self.migration)
        for action in ("estoque.mp.view", "estoque.pi.view", "estoque.pa.view"):
            self.assertIn(action, self.migration)
        for legacy_policy in (
            '"active user read pcp_ordens_producao"',
            '"active user read pcp_op_componentes_planejados"',
            '"authenticated read est_lotes_mp"',
            '"authenticated read est_movimentos_mp"',
        ):
            self.assertIn(f"drop policy if exists {legacy_policy}", self.migration)
        for view in ("pcp_formula_ativa", "est_lotes_pa_saldos", "est_lotes_mp_saldos", "est_lotes_pi_saldos"):
            self.assertIn(f"alter view public.{view} set (security_invoker = true)", self.migration)
        for marker in (
            "seller direct PCP read was not denied",
            "seller direct MP stock read was not denied",
            "seller OP print route did not fail closed",
            "PCP profile lost OP read access",
            "PCP profile lost MP stock read access",
        ):
            self.assertIn(marker, self.smoke)

    def test_print_requires_the_same_op_read_capability(self) -> None:
        pcp = (ROOT / "apps" / "web" / "lib" / "pcp.ts").read_text(encoding="utf-8")
        self.assertIn('p_action_key: "pcp.op.view"', pcp)
        self.assertIn("('/producao/ordens', 'pcp', array['pcp.op.view']::text[], true)", self.migration)

    def test_ci_executes_the_runtime_smoke(self) -> None:
        self.assertIn("tests/sql/iam01_fail_closed_navigation_password.sql", CI.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
