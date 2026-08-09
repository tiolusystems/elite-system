from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0049_security_admin_privilege_boundary.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class SecurityAdminPrivilegeBoundaryTest(unittest.TestCase):
    def test_critical_actions_are_default_deny_with_explicit_admin_backfill(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        for action_key in (
            "system.admin",
            "security.manage_users",
            "security.manage_permissions",
            "security.email_change.review",
        ):
            self.assertIn(f"'{action_key}'", sql)

        self.assertIn("set default_allowed = false", sql)
        self.assertIn("insert into public.user_permission_overrides", sql)
        self.assertIn("profile.role = 'admin'", sql)
        self.assertIn("not coalesce(profile.is_system_actor, false)", sql)

    def test_admin_guard_requires_role_and_explicit_permission(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.require_current_user_security_admin", sql)
        self.assertIn("system administrator role required", sql)
        self.assertIn("perform public.require_current_user_permission(p_action_key)", sql)

        for public_function in (
            "upsert_security_user_profile",
            "set_security_permission_override",
            "clear_security_permission_override",
            "authorize_security_auth_user_provision",
            "record_security_auth_user_invitation_sent",
            "list_security_user_profiles",
            "list_security_effective_permissions",
            "set_system_runtime_environment",
            "set_system_module_rollout",
        ):
            self.assertIn(f"create or replace function public.{public_function}", sql)

        self.assertGreaterEqual(
            sql.count("perform public.require_current_user_security_admin("),
            11,
        )

    def test_impls_and_legacy_boundaries_are_not_executable(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn(
            "revoke all on function public.security_user_profile_snapshot(uuid) from authenticated",
            sql,
        )
        self.assertIn(
            "revoke all on function public.record_security_auth_user_temp_password_sent(uuid, text) from authenticated",
            sql,
        )
        for impl in (
            "upsert_security_user_profile_impl_0049(uuid, text, text, text)",
            "set_security_permission_override_impl_0049(uuid, text, boolean)",
            "authorize_security_auth_user_provision_impl_0049(text, text, text, text)",
            "set_system_runtime_environment_impl_0049(text, text, text)",
        ):
            self.assertIn(f"revoke all on function public.{impl} from authenticated", sql)

    def test_last_capable_admin_and_bootstrap_are_protected(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.security_admin_has_core_grants", sql)
        self.assertIn("last capable system administrator must retain core grants", sql)
        self.assertIn("last capable system administrator cannot be demoted or deactivated", sql)
        self.assertIn("core_admin_grants", sql)
        self.assertIn(
            "grant execute on function public.bootstrap_first_system_admin(uuid, text) to service_role",
            sql,
        )

    def test_attack_smoke_is_wired_into_ci(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/security_admin_privilege_boundary.sql", workflow)


if __name__ == "__main__":
    unittest.main()
