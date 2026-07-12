from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0047_security_verified_email_invitation.sql"
ADMIN_WORKFLOW_MIGRATION = ROOT / "supabase" / "migrations" / "0048_security_admin_email_change_workflow.sql"
SECURITY_ACTIONS = ROOT / "apps" / "web" / "app" / "seguranca" / "actions.ts"
SECURITY_PAGE = ROOT / "apps" / "web" / "app" / "seguranca" / "page.tsx"
SECURITY_SERVICE = ROOT / "apps" / "web" / "lib" / "security.ts"
LOGIN_ACTIONS = ROOT / "apps" / "web" / "app" / "login" / "actions.ts"
LOGIN_PAGE = ROOT / "apps" / "web" / "app" / "login" / "page.tsx"
PASSWORD_PAGE = ROOT / "apps" / "web" / "app" / "login" / "trocar-senha" / "page.tsx"
CONFIRM_ROUTE = ROOT / "apps" / "web" / "app" / "auth" / "confirm" / "route.ts"
PROXY = ROOT / "apps" / "web" / "proxy.ts"
CONFIG = ROOT / "supabase" / "config.toml"
INVITE_TEMPLATE = ROOT / "supabase" / "templates" / "invite.html"
EMAIL_CHANGE_TEMPLATE = ROOT / "supabase" / "templates" / "email_change.html"
TEMP_PASSWORD_MODULE = ROOT / "apps" / "web" / "lib" / "security-temp-password.ts"
EMAIL_POLICY = ROOT / "apps" / "web" / "lib" / "email-address.ts"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class SecurityVerifiedEmailContractTests(unittest.TestCase):
    def test_0047_audits_invitation_and_email_change_without_credentials(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("'security.change_own_email'", sql)
        self.assertIn("'seguranca.auth_user_invitation_sent'", sql)
        self.assertIn("'seguranca.own_email_change_requested'", sql)
        self.assertIn("'seguranca.own_email_changed'", sql)
        self.assertIn("public.is_reserved_access_email(v_email)", sql)

        for function_name in (
            "authorize_security_auth_user_provision",
            "record_security_auth_user_invitation_sent",
            "authorize_security_own_email_change",
            "record_security_own_email_change_requested",
            "record_security_own_email_changed",
        ):
            body = self._function_body(function_name).lower()
            self.assertIn("begin_audited_rpc(", body)
            self.assertIn("log_audited_rpc_change(", body)
            self.assertIn("credential_logged", body)
            self.assertNotRegex(body, r"\bp_(new_)?password\b")
            self.assertNotIn("token_hash", body)

    def test_new_access_uses_invitation_after_audited_authorization(self) -> None:
        actions = SECURITY_ACTIONS.read_text(encoding="utf-8")

        authorization = actions.index('auditedRpc<AuthProvisionAuthorization>(supabase, "authorize_security_auth_user_provision"')
        invitation = actions.index("admin.auth.admin.inviteUserByEmail")
        profile = actions.index('auditedRpc(supabase, "upsert_security_user_profile"')
        delivery_log = actions.index('auditedRpc(supabase, "record_security_auth_user_invitation_sent"')

        self.assertLess(authorization, invitation)
        self.assertLess(invitation, profile)
        self.assertLess(profile, delivery_log)
        self.assertIn("invitation_pending: true", actions)
        self.assertIn("fictitious_email", actions)
        self.assertNotIn("temporaryPassword", actions)
        self.assertNotIn("admin.auth.admin.createUser", actions)
        self.assertNotIn(".rpc(", actions)
        self.assertFalse(TEMP_PASSWORD_MODULE.exists())

        policy = EMAIL_POLICY.read_text(encoding="utf-8")
        self.assertIn("isReservedEmailAddress", policy)
        self.assertIn("EMAIL_ADDRESS_PATTERN", policy)

    def test_security_directory_reads_auth_only_after_permissioned_profile_rpc(self) -> None:
        service = SECURITY_SERVICE.read_text(encoding="utf-8")
        page = SECURITY_PAGE.read_text(encoding="utf-8")

        self.assertLess(service.index('supabase.rpc("list_security_user_profiles"'), service.index("await listAllAuthUsers()"))
        self.assertIn("admin.auth.admin.listUsers", service)
        self.assertIn('return "placeholder"', service)
        self.assertIn("profile.email", page)
        self.assertIn("emailStatusLabel", page)
        self.assertIn("E-mails fictícios", page)
        self.assertNotIn("Auth user id", page)

    def test_email_change_requires_admin_approval_before_auth_update(self) -> None:
        actions = LOGIN_ACTIONS.read_text(encoding="utf-8")
        page = LOGIN_PAGE.read_text(encoding="utf-8")
        security_actions = SECURITY_ACTIONS.read_text(encoding="utf-8")
        security_page = SECURITY_PAGE.read_text(encoding="utf-8")
        sql = ADMIN_WORKFLOW_MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("requestOwnEmailChangeReviewAction", actions)
        self.assertIn("dispatchApprovedOwnEmailChangeAction", actions)
        approval = actions.index('"get_security_approved_own_email_change"')
        update = actions.index("supabase.auth.updateUser({ email: approvedRequest.new_email })")
        pending_log = actions.index('"mark_security_email_change_confirmation_pending"')
        self.assertLess(approval, update)
        self.assertLess(update, pending_log)
        self.assertNotIn('field(formData, "new_email")', actions)
        self.assertNotIn('name="new_email"', page)
        self.assertNotIn('name="new_email_confirmation"', page)
        self.assertIn('name="reason_code"', page)
        self.assertIn("requestOwnEmailChangeReviewAction", page)
        self.assertIn("reviewSecurityEmailChangeAction", security_actions)
        self.assertNotIn("admin.auth.admin.updateUserById", security_actions)
        self.assertIn('name="new_email"', security_page)
        self.assertIn("create table if not exists public.security_email_change_requests", sql)
        self.assertIn("security_email_change_request_events", sql)
        self.assertIn("events are append-only", sql)
        self.assertIn("public.require_current_user_admin_role()", sql)
        self.assertIn("revoke all on function public.authorize_security_own_email_change(text) from authenticated", sql)
        self.assertIn("tests/sql/security_admin_email_change_workflow.sql", CI.read_text(encoding="utf-8"))
        self.assertIn("E-mail técnico precisa ser substituído", page)

    def test_callback_and_proxy_support_invitation_and_email_change(self) -> None:
        callback = CONFIRM_ROUTE.read_text(encoding="utf-8")
        proxy = PROXY.read_text(encoding="utf-8")
        password_page = PASSWORD_PAGE.read_text(encoding="utf-8")

        self.assertIn('type === "invite"', callback)
        self.assertIn('type === "email_change"', callback)
        self.assertIn('complete_security_email_change_request', callback)
        self.assertIn('security.email_change.dispatch_approved', callback)
        self.assertIn('flow === "invite" ? "invitation" : "recovery"', callback)
        self.assertIn("invitation_pending", proxy)
        self.assertIn('invitationPending ? "invitation" : "temporary"', proxy)
        self.assertIn('mode === "invitation"', password_page)
        self.assertIn("Ativar conta", password_page)

    def test_local_auth_templates_are_explicit_and_single_confirmation_is_enabled(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        invite = INVITE_TEMPLATE.read_text(encoding="utf-8")
        email_change = EMAIL_CHANGE_TEMPLATE.read_text(encoding="utf-8")

        self.assertIn("double_confirm_changes = false", config)
        self.assertIn("enable_signup = false", config)
        self.assertIn("enable_confirmations = true", config)
        self.assertIn("email_sent = 20", config)
        self.assertIn("[auth.email.template.invite]", config)
        self.assertIn("[auth.email.template.email_change]", config)
        self.assertIn("{{ .TokenHash }}", invite)
        self.assertIn("type=invite", invite)
        self.assertIn("{{ .NewEmail }}", email_change)
        self.assertIn("type=email_change", email_change)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0)


if __name__ == "__main__":
    unittest.main()
