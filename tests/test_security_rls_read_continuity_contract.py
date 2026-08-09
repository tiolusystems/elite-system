from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0067_restore_rls_read_helper_access.sql"
READ_SMOKE = ROOT / "tests" / "sql" / "security_rls_read_continuity.sql"
ZERO_WRITE_GATE = ROOT / "tests" / "sql" / "security_zero_direct_write_gate.sql"


class SecurityRlsReadContinuityContractTests(unittest.TestCase):
    def test_migration_restores_only_authenticated_helper_execution(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("grant execute on function public.current_actor_id() to authenticated", migration)
        self.assertIn("revoke all on function public.current_actor_id() from public", migration)
        self.assertIn("revoke execute on function public.current_actor_id() from anon", migration)
        self.assertNotIn("grant select", migration)
        self.assertNotIn("grant execute on all functions", migration)

    def test_smoke_proves_reads_and_preserves_direct_write_denial(self) -> None:
        smoke = READ_SMOKE.read_text(encoding="utf-8").lower()

        self.assertIn("set local role authenticated", smoke)
        self.assertIn("select public.current_actor_id()", smoke)
        self.assertIn("from public.cad_pessoas_comerciais", smoke)
        self.assertIn("from public.cadastro_validation_issues", smoke)
        self.assertIn("from public.est_lotes_pa", smoke)
        self.assertIn("from public.com_pedidos", smoke)
        self.assertIn("when insufficient_privilege then null", smoke)
        self.assertIn("elite_security_rls_read_continuity_ok", smoke)

    def test_zero_write_gate_checks_policy_function_dependencies(self) -> None:
        gate = ZERO_WRITE_GATE.read_text(encoding="utf-8").lower()

        self.assertIn("dep.classid = 'pg_policy'::regclass", gate)
        self.assertIn("dep.refclassid = 'pg_proc'::regclass", gate)
        self.assertIn("0::oid = any(pol.polroles)", gate)
        self.assertIn("depends on non-executable function", gate)


if __name__ == "__main__":
    unittest.main()
