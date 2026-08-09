from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0111_restore_governed_stock_adjustment_access.sql"
SMOKE = ROOT / "tests" / "sql" / "stock_adjustment_rpc_access.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class StockAdjustmentRpcAccessContractTests(unittest.TestCase):
    def test_migration_restores_only_governed_adjustment_rpcs(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for family in ("mp", "pi", "pa"):
            signature = f"public.registrar_est_ajuste_{family}(bigint, numeric, text)"
            self.assertIn(f"revoke all on function {signature}", text)
            self.assertIn(f"grant execute on function {signature}", text)
        self.assertEqual(text.count("to authenticated;"), 3)
        self.assertNotIn("grant execute on all functions", text.lower())
        self.assertNotIn("grant all", text.lower())

    def test_smoke_covers_permissions_audit_and_denial(self) -> None:
        text = SMOKE.read_text(encoding="utf-8")
        for contract in (
            "has_function_privilege",
            "has_table_privilege",
            "registrar_est_ajuste_pi",
            "estoque.pi_ajuste_registrado",
            "not allowed: estoque.pi.adjust",
            "partial stock effect",
            "rollback;",
        ):
            self.assertIn(contract, text)

    def test_ci_executes_stock_adjustment_smoke(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/stock_adjustment_rpc_access.sql", workflow)


if __name__ == "__main__":
    unittest.main()
