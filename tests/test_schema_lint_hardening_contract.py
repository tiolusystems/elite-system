from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0043_schema_lint_hardening.sql"
SMOKE = ROOT / "tests" / "sql" / "schema_lint_hardening.sql"
START_SCRIPT = ROOT / "scripts" / "start-local.ps1"
BOOTSTRAP_SCRIPT = ROOT / "scripts" / "bootstrap-local-admin.ps1"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class SchemaLintHardeningContractTest(unittest.TestCase):
    def test_reservation_observation_is_persisted_and_audited(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("add column if not exists observacao text", sql)
        self.assertIn("char_length(observacao) <= 2000", sql)
        self.assertIn("v_observacao := nullif(btrim(p_observacao), '')", sql)
        self.assertIn("observacao = coalesce(v_observacao, reserva.observacao)", sql)
        self.assertIn("'observacao', v_observacao_final", sql)
        self.assertNotIn("v_op record", sql)

    def test_lint_volatility_and_terminal_flow_are_explicit(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("alter function public.normalize_audit_axis(text) stable", sql)
        self.assertIn("alter function public.list_system_module_runtime(text) volatile", sql)
        self.assertIn("alter function public.get_current_route_module_access(text) volatile", sql)
        self.assertIn("order sequence allocation reached an invalid state", sql)
        self.assertIn(
            "revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from authenticated",
            sql,
        )

    def test_local_runtime_uses_required_supabase_services_only(self) -> None:
        script = START_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("$SupabaseExcludedServices", script)
        self.assertIn("& $Supabase start -x $SupabaseExcludedServices", script)
        self.assertIn("logflare", script)
        self.assertIn("storage-api", script)
        self.assertIn("$statusExitCode = $LASTEXITCODE", script)
        self.assertIn("$ErrorActionPreference = 'Continue'", script)
        self.assertIn("$dockerExitCode = $LASTEXITCODE", script)
        self.assertIn("function Wait-SupabaseEnvironment", script)
        self.assertIn("$supabaseStartExitCode = $LASTEXITCODE", script)
        self.assertIn("$supabaseEnvironment = Wait-SupabaseEnvironment -StartExitCode $supabaseStartExitCode", script)
        self.assertNotIn("throw 'Falha ao iniciar Supabase local.'", script)

        bootstrap_script = BOOTSTRAP_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("$statusExitCode = $LASTEXITCODE", bootstrap_script)
        self.assertIn("$ErrorActionPreference = 'Continue'", bootstrap_script)

    def test_database_smoke_is_wired_in_ci(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        smoke = SMOKE.read_text(encoding="utf-8").lower()

        self.assertTrue(SMOKE.exists())
        self.assertIn("tests/sql/schema_lint_hardening.sql", workflow)
        self.assertIn("reserva observada no smoke 0043", smoke)
        self.assertIn("pcp reservation observation was not persisted", smoke)
        self.assertIn("pcp reservation observation was not audited", smoke)
        self.assertIn("repeat('x', 2001)", smoke)


if __name__ == "__main__":
    unittest.main()
