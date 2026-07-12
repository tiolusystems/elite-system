from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0042_first_admin_operational_bootstrap.sql"
START_SCRIPT = ROOT / "scripts" / "start-local.ps1"
STOP_SCRIPT = ROOT / "scripts" / "stop-local.ps1"
BOOTSTRAP_SCRIPT = ROOT / "scripts" / "bootstrap-local-admin.ps1"
START_WRAPPER = ROOT / "iniciar-elite-local.cmd"
STOP_WRAPPER = ROOT / "parar-elite-local.cmd"
DOC = ROOT / "docs" / "operacao_local_modulos.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class OperationalBootstrapContractTest(unittest.TestCase):
    def test_first_admin_is_service_role_only_and_one_time(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("coalesce(auth.role(), '') <> 'service_role'", sql)
        self.assertIn("where not profile.is_system_actor", sql)
        self.assertIn("first administrator bootstrap already closed", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("idx_sys_runtime_environment_actor", sql)
        self.assertIn("idx_sys_module_rollout_actor", sql)
        self.assertIn("idx_sys_module_rollout_module", sql)
        self.assertIn("grant execute on function public.bootstrap_first_system_admin(uuid, text) to service_role", sql)
        self.assertIn("revoke all on function public.bootstrap_first_system_admin(uuid, text) from authenticated", sql)

        guard_position = sql.index("coalesce(auth.role(), '') <> 'service_role'")
        profile_read_position = sql.index("from public.user_profiles profile")
        self.assertLess(guard_position, profile_read_position)

    def test_bootstrap_is_audited_without_credentials(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("seguranca.first_system_admin_bootstrapped", sql)
        self.assertIn("'contains_credentials', false", sql)
        self.assertNotRegex(sql, r"select\s+.*email")
        self.assertNotIn("password", sql)

    def test_local_bootstrap_refuses_cloud_and_rolls_back_auth_user(self) -> None:
        script = BOOTSTRAP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Este script aceita somente Supabase local", script)
        self.assertIn("/auth/v1/invite", script)
        self.assertIn("invitation_pending = $true", script)
        self.assertIn("Dominios ficticios ou reservados nao podem criar acesso", script)
        self.assertIn("-Method Delete", script)
        self.assertIn("bootstrap_first_system_admin", script)
        self.assertNotIn("email_confirm = $true", script)
        self.assertNotIn("New-TemporaryPassword", script)
        self.assertNotRegex(script, r"(?i)(service_role_key|password)\s*=\s*['\"][A-Za-z0-9._-]{20,}")

    def test_start_script_generates_ignored_environment_and_health_checks(self) -> None:
        script = START_SCRIPT.read_text(encoding="utf-8")
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

        self.assertIn(".env.local", script)
        self.assertIn("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", script)
        self.assertIn("ELITE_DATABASE_MODE=local", script)
        self.assertIn("/api/health", script)
        self.assertIn("ELITE_LOCAL_RUNTIME_OK", script)
        self.assertIn(".env.*", gitignore)
        self.assertNotIn("--no-backup", STOP_SCRIPT.read_text(encoding="utf-8"))
        self.assertIn("-ExecutionPolicy Bypass", START_WRAPPER.read_text(encoding="utf-8"))
        self.assertIn("-ExecutionPolicy Bypass", STOP_WRAPPER.read_text(encoding="utf-8"))

    def test_database_smoke_and_runbook_are_wired(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        doc = DOC.read_text(encoding="utf-8").lower()

        self.assertIn("tests/sql/first_admin_operational_bootstrap.sql", workflow)
        self.assertIn("iniciar-elite-local.cmd", doc)
        self.assertIn("scripts\\bootstrap-local-admin.ps1", doc)
        self.assertIn("banco local", doc)
        self.assertIn("nao e producao", doc)


if __name__ == "__main__":
    unittest.main()
