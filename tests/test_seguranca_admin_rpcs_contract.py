from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0035 = REPO_ROOT / "supabase" / "migrations" / "0035_security_admin_rpcs.sql"
DECISION_DOC = REPO_ROOT / "docs" / "decisao_seguranca_admin_rpcs.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_seguranca_admin_rpcs.md"
MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"


class SecurityAdminRpcsContractTests(unittest.TestCase):
    def test_security_tables_are_write_restricted_for_authenticated(self) -> None:
        sql = MIGRATION_0035.read_text(encoding="utf-8").lower()

        for table in ("user_profiles", "permission_actions", "user_permission_overrides"):
            with self.subTest(table=table):
                self.assertIn(f"revoke insert, update, delete on public.{table} from authenticated", sql)

    def test_user_profile_rpc_is_audited_and_does_not_manage_passwords(self) -> None:
        body = self._function_body("upsert_security_user_profile")

        self.assertIn("begin_audited_rpc(", body)
        self.assertIn("'security.manage_users'", body)
        self.assertIn("log_audited_rpc_change(", body)
        self.assertIn("auth.users", body)
        self.assertIn("auth user must exist before creating profile", body)
        self.assertIn("system actor profile cannot be managed by user profile rpc", body)
        self.assertNotIn("encrypted_password", body)
        self.assertNotIn("email_confirmed_at", body)

    def test_permission_override_rpcs_are_audited_and_block_system_actor(self) -> None:
        for function_name in ("set_security_permission_override", "clear_security_permission_override"):
            body = self._function_body(function_name)
            with self.subTest(function=function_name):
                self.assertIn("begin_audited_rpc(", body)
                self.assertIn("'security.manage_permissions'", body)
                self.assertIn("log_audited_rpc_change(", body)
                self.assertIn("system actor permissions cannot be changed by override rpc", body)
                self.assertIn("permission action not found", body)

    def test_docs_record_auth_boundary_and_pending_decisions(self) -> None:
        docs = "\n".join(
            (
                DECISION_DOC.read_text(encoding="utf-8"),
                VALIDATION_DOC.read_text(encoding="utf-8"),
                MATRIX_DOC.read_text(encoding="utf-8"),
            )
        ).lower()

        self.assertIn("supabase auth continua sendo a origem do login", docs)
        self.assertIn("senha/login", docs)
        self.assertIn("decisoes pendentes para luciano", docs)
        self.assertIn("default_allowed", docs)
        self.assertIn("0035", docs)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0035.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
