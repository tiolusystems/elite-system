from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    REPO_ROOT
    / "supabase"
    / "migrations"
    / "0108_default_deny_staging_rollout_actions.sql"
)
SQL_SMOKE = REPO_ROOT / "tests" / "sql" / "staging_rollout_default_deny.sql"

EXPECTED_ACTIONS = (
    "faturamento.external_references.correct",
    "faturamento.external_references.register",
    "faturamento.nf.issue",
    "financeiro.commissions.pay",
    "financeiro.commissions.release",
    "financeiro.credit_limits.adjust",
    "financeiro.receipts.register",
    "pedidos.receipts.create",
    "qualidade.rastreabilidade.export",
    "qualidade.rastreabilidade.recall_simulate",
    "qualidade.rastreabilidade.view",
    "reports.view",
)


class StagingRolloutDefaultDenyContractTests(unittest.TestCase):
    def test_migration_is_explicit_and_does_not_create_grants(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        for action_key in EXPECTED_ACTIONS:
            with self.subTest(action_key=action_key):
                self.assertIn(f"'{action_key}'", sql)

        self.assertIn("set default_allowed = false", sql)
        self.assertIn("0108 missing permission actions", sql)
        self.assertIn("0108 invalid runtime permission metadata", sql)
        self.assertNotIn("insert into public.user_permission_overrides", sql.lower())
        self.assertNotIn("delete from public.user_permission_overrides", sql.lower())

    def test_sql_smoke_proves_role_independence_and_atomic_override(self) -> None:
        sql = SQL_SMOKE.read_text(encoding="utf-8")

        self.assertIn("'admin'", sql)
        self.assertIn("'comercial'", sql)
        self.assertIn("'auditoria'", sql)
        self.assertIn("role inferred permission", sql)
        self.assertIn("explicit positive override", sql)
        self.assertIn("explicit revocation", sql)
        self.assertIn("one override granted an unrelated", sql)
        self.assertIn("STAGING_ROLLOUT_DEFAULT_DENY_OK", sql)
        self.assertIn("rollback;", sql.lower())


if __name__ == "__main__":
    unittest.main()
