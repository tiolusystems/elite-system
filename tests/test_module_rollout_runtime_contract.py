from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0041_module_rollout_runtime.sql"
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"
PROXY = ROOT / "apps" / "web" / "proxy.ts"
MODULE_ACTIONS = ROOT / "apps" / "web" / "app" / "modulos" / "actions.ts"
HOME = ROOT / "apps" / "web" / "app" / "page.tsx"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"


class ModuleRolloutRuntimeContractTest(unittest.TestCase):
    def test_database_owns_environment_rollout_and_dependencies(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        for expected in (
            "create table if not exists public.sys_modules",
            "create table if not exists public.sys_module_routes",
            "create table if not exists public.sys_module_dependencies",
            "create table if not exists public.sys_runtime_environment_events",
            "create table if not exists public.sys_module_rollout_events",
            "create or replace function public.system_module_dependency_blockers",
            "create or replace function public.system_module_status",
            "p_environment text default null",
            "create or replace function public.set_system_runtime_environment",
            "create or replace function public.set_system_module_rollout",
        ):
            self.assertIn(expected, sql)

    def test_new_database_fails_closed_and_event_ledgers_are_immutable(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("'unconfigured'", sql)
        self.assertIn("Banco nasce fechado ate configuracao auditada", sql)
        self.assertIn("before update or delete on public.sys_runtime_environment_events", sql)
        self.assertIn("before truncate on public.sys_runtime_environment_events", sql)
        self.assertIn("before update or delete on public.sys_module_rollout_events", sql)
        self.assertIn("before truncate on public.sys_module_rollout_events", sql)
        self.assertIn("is append-only; create a new event", sql)

    def test_every_permission_action_gets_runtime_ownership_and_access_kind(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("add column if not exists runtime_module_key text", sql)
        self.assertIn("add column if not exists runtime_access_kind public.sys_action_access_kind", sql)
        self.assertIn("alter column runtime_module_key set not null", sql)
        self.assertIn("alter column runtime_access_kind set not null", sql)
        self.assertIn("permission actions without runtime module ownership", sql)
        self.assertIn("permission_actions_runtime_module_fk", sql)

    def test_permission_guard_enforces_module_runtime_centrally(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        guard = re.search(
            r"create or replace function public\.require_current_user_permission\(p_action_key text\)(.*?)\$\$;",
            sql,
            re.IGNORECASE | re.DOTALL,
        )

        self.assertIsNotNone(guard)
        body = guard.group(1) if guard else ""
        self.assertIn("public.can_current_user", body)
        self.assertIn("runtime_module_key", body)
        self.assertIn("runtime_access_kind", body)
        self.assertIn("public.current_system_environment", body)
        self.assertIn("public.system_module_status", body)
        self.assertIn("module unavailable:", body)

    def test_authenticated_app_routes_are_registered_or_explicitly_public(self) -> None:
        sql = "\n".join(
            migration.read_text(encoding="utf-8")
            for migration in sorted(MIGRATIONS_DIR.glob("*.sql"))
        )
        registered = set(re.findall(r"\('(/[a-z0-9/-]*)',\s*'[a-z_]+'", sql))
        proxy = PROXY.read_text(encoding="utf-8")
        public_routes_match = re.search(
            r"const PUBLIC_ROUTES = new Set\(\[(.*?)\]\);",
            proxy,
            re.DOTALL,
        )
        self.assertIsNotNone(public_routes_match, "proxy public route allowlist not found")
        public_routes = set(re.findall(r'"(/[a-z0-9/-]*)"', public_routes_match.group(1)))
        recovery_routes = {"/modulo-indisponivel"}
        app_routes: set[str] = set()

        for page in (ROOT / "apps" / "web" / "app").rglob("page.tsx"):
            relative = page.parent.relative_to(ROOT / "apps" / "web" / "app")
            route = "/" if str(relative) == "." else "/" + "/".join(relative.parts)
            app_routes.add(route)

        for route in sorted(app_routes - public_routes - recovery_routes):
            self.assertIn(route, registered, f"authenticated route without module registration: {route}")

    def test_proxy_fails_closed_for_unregistered_or_unavailable_route(self) -> None:
        proxy = PROXY.read_text(encoding="utf-8")

        self.assertIn('supabase.rpc("get_current_route_module_access"', proxy)
        self.assertIn('"runtime_contract_unavailable"', proxy)
        self.assertIn("redirectToModuleUnavailable", proxy)
        self.assertIn("if (!moduleAccess.available)", proxy)
        self.assertIn("MODULE_GUARD_RECOVERY_ROUTE", proxy)

    def test_module_admin_server_actions_use_audited_wrapper(self) -> None:
        actions = MODULE_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("auditedRpcCall", actions)
        self.assertIn('actionKey: "system.admin"', actions)
        self.assertIn('functionName: "set_system_runtime_environment"', actions)
        self.assertIn('functionName: "set_system_module_rollout"', actions)
        self.assertNotIn(".rpc(", actions)

    def test_home_uses_database_runtime_instead_of_manual_ready_labels(self) -> None:
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("getModuleRuntimeDashboard", home)
        self.assertIn("rolloutModules.map", home)
        self.assertNotIn("const FLOW_STEPS", home)

    def test_ci_runs_module_runtime_smoke(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("tests/sql/module_rollout_runtime.sql", workflow)


if __name__ == "__main__":
    unittest.main()
