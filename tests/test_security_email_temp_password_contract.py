from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0038 = REPO_ROOT / "supabase" / "migrations" / "0038_security_email_temp_password_contract.sql"
MIGRATION_0047 = REPO_ROOT / "supabase" / "migrations" / "0047_security_verified_email_invitation.sql"
SECURITY_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "seguranca" / "actions.ts"
LOGIN_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "login" / "actions.ts"
SECURITY_PAGE = REPO_ROOT / "apps" / "web" / "app" / "seguranca" / "page.tsx"
CHANGE_PASSWORD_PAGE = REPO_ROOT / "apps" / "web" / "app" / "login" / "trocar-senha" / "page.tsx"
PROXY = REPO_ROOT / "apps" / "web" / "proxy.ts"
ADMIN_CLIENT = REPO_ROOT / "apps" / "web" / "lib" / "supabase" / "admin.ts"
ENV_EXAMPLE = REPO_ROOT / "apps" / "web" / ".env.example"
DECISION_DOC = REPO_ROOT / "docs" / "decisao_seguranca_admin_rpcs.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_security_email_temp_password.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"


class SecurityEmailTemporaryPasswordContractTests(unittest.TestCase):
    def test_0038_authorizes_and_records_temp_password_delivery_without_credentials(self) -> None:
        sql = MIGRATION_0038.read_text(encoding="utf-8").lower()

        for function_name in (
            "authorize_security_auth_user_provision",
            "record_security_auth_user_temp_password_sent",
        ):
            with self.subTest(function=function_name):
                body = self._function_body(function_name).lower()
                self.assertIn("begin_audited_rpc(", body)
                self.assertIn("'security.manage_users'", body)
                self.assertIn("log_audited_rpc_change(", body)
                self.assertIn("email_hash", body)
                self.assertIn("contains_password", body)
                self.assertIn("credential_logged", body)
                self.assertNotRegex(body, r"\bp_password\b")
                self.assertNotIn("temporary_password", body.replace("temporary_password_email", ""))

        self.assertIn("grant execute on function public.authorize_security_auth_user_provision", sql)
        self.assertIn("grant execute on function public.record_security_auth_user_temp_password_sent", sql)

    def test_0038_records_forced_own_password_change_without_credentials(self) -> None:
        sql = MIGRATION_0038.read_text(encoding="utf-8").lower()
        body = self._function_body("record_security_own_password_changed").lower()

        self.assertIn("'security.change_own_password'", sql)
        self.assertIn("begin_audited_rpc(", body)
        self.assertIn("'security.change_own_password'", body)
        self.assertIn("log_audited_rpc_change(", body)
        self.assertIn("temporary_password_bootstrap", body)
        self.assertIn("contains_password", body)
        self.assertNotRegex(body, r"\bp_password\b")
        self.assertIn("grant execute on function public.record_security_own_password_changed", sql)

    def test_0038_centralizes_pre_guard_action_key_reads(self) -> None:
        sql = MIGRATION_0038.read_text(encoding="utf-8")

        self.assertIn("resolve_com_pedido_create_action_key", sql)
        self.assertIn("resolve_pcp_formula_action_key", sql)
        self.assertIn("v_action_key := public.resolve_com_pedido_create_action_key(p_vendedor_id);", sql)
        self.assertIn("v_action_key := public.resolve_pcp_formula_action_key(p_produto_id, p_tipo_receita);", sql)
        self.assertIn("perform public.require_current_user_permission(v_action_key);", sql)
        self.assertIn("revoke all on function public.resolve_com_pedido_create_action_key", sql)
        self.assertIn("revoke all on function public.resolve_pcp_formula_action_key", sql)

    def test_active_server_action_supersedes_temp_password_with_verified_invitation(self) -> None:
        text = SECURITY_ACTIONS.read_text(encoding="utf-8")

        authorization_index = text.index('auditedRpc<AuthProvisionAuthorization>(supabase, "authorize_security_auth_user_provision"')
        invite_index = text.index("admin.auth.admin.inviteUserByEmail")
        sent_log_index = text.index('auditedRpc(supabase, "record_security_auth_user_invitation_sent"')

        self.assertLess(authorization_index, invite_index)
        self.assertLess(invite_index, sent_log_index)
        self.assertNotIn("generateTemporaryPassword", text)
        self.assertNotIn("sendTemporaryPasswordEmail", text)
        self.assertNotIn("admin.auth.admin.createUser", text)
        self.assertIn("admin.auth.admin.deleteUser(userId)", text)
        self.assertNotIn(".rpc(", text)
        self.assertNotIn("console.log", text)

    def test_service_role_is_server_only_and_env_documented(self) -> None:
        admin_text = ADMIN_CLIENT.read_text(encoding="utf-8")
        env_text = ENV_EXAMPLE.read_text(encoding="utf-8")

        self.assertIn("SUPABASE_SERVICE_ROLE_KEY", admin_text)
        self.assertNotIn("NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY", admin_text)
        self.assertIn("SUPABASE_SERVICE_ROLE_KEY=", env_text)
        self.assertNotIn("ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL", env_text)

    def test_security_page_exposes_email_access_form_without_showing_password(self) -> None:
        page = SECURITY_PAGE.read_text(encoding="utf-8")

        self.assertIn("Convidar novo usuário", page)
        self.assertIn('name="email"', page)
        self.assertIn("inviteSecurityAuthUserAction", page)
        self.assertNotIn("temporaryPassword", page)
        self.assertNotIn("Senha gerada", page)

    def test_login_forces_temporary_password_change_before_operational_access(self) -> None:
        actions = LOGIN_ACTIONS.read_text(encoding="utf-8")
        proxy = PROXY.read_text(encoding="utf-8")
        page = CHANGE_PASSWORD_PAGE.read_text(encoding="utf-8")

        self.assertIn("temporary_password_bootstrap === true", actions)
        self.assertIn("/login/trocar-senha?mode=temporary", actions)
        self.assertIn("supabase.auth.updateUser", actions)
        self.assertIn('auditedRpc(supabase, "record_security_own_password_changed"', actions)
        self.assertLess(actions.index('normalized.includes("not allowed")'), actions.index('normalized.includes("weak")'))
        self.assertNotIn(".rpc(", actions)
        self.assertIn("temporary_password_bootstrap === true", proxy)
        self.assertIn("TEMP_PASSWORD_CHANGE_ROUTE", proxy)
        self.assertIn("Trocar senha temporária", page)
        self.assertIn("changeOwnPasswordAction", page)
        self.assertNotIn("temporaryPassword", page)

    def test_docs_mark_0038_as_legacy_and_0047_as_active_invitation(self) -> None:
        docs = "\n".join(
            (
                DECISION_DOC.read_text(encoding="utf-8"),
                VALIDATION_DOC.read_text(encoding="utf-8"),
                RECIPE_DOC.read_text(encoding="utf-8"),
            )
        )

        self.assertIn("0038", docs)
        self.assertIn("0047", docs)
        self.assertIn("historico", docs.lower())
        self.assertIn("convite", docs.lower())
        self.assertIn("SUPABASE_SERVICE_ROLE_KEY", docs)
        self.assertIn("Nenhuma senha temporaria, token, service role key ou credencial", docs)
        self.assertIn("inviteUserByEmail", docs)
        self.assertIn("verified_email_invitation", MIGRATION_0047.read_text(encoding="utf-8"))

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0038.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0)


if __name__ == "__main__":
    unittest.main()
