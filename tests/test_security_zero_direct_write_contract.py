from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0066_close_direct_write_and_rpc_exposure.sql"
GATE = ROOT / "tests" / "sql" / "security_zero_direct_write_gate.sql"


class SecurityZeroDirectWriteContractTests(unittest.TestCase):
    def test_migration_revokes_current_and_future_direct_access(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("revoke insert, update, delete, truncate, references, trigger", migration)
        self.assertIn("revoke execute on function", migration)
        self.assertIn("alter default privileges for role postgres", migration)
        self.assertIn("revoke execute on functions from public, anon, authenticated", migration)

    def test_migration_grants_only_the_explicit_authenticated_rpc_allowlist(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("v_authenticated_rpc_names text[]", migration)
        self.assertIn("grant execute on function %s to authenticated", migration)
        self.assertNotIn("grant execute on all functions", migration)

    def test_runtime_gate_checks_tables_functions_and_default_privileges(self) -> None:
        gate = GATE.read_text(encoding="utf-8").lower()

        for required in (
            "pg_policies",
            "has_table_privilege('anon'",
            "has_table_privilege('authenticated'",
            "has_function_privilege('anon'",
            "security definer",
            "search_path",
            "pg_default_acl",
        ):
            self.assertIn(required, gate)


if __name__ == "__main__":
    unittest.main()
