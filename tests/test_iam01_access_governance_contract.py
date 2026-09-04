from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0147_iam01_access_governance.sql"
SMOKE = ROOT / "tests/sql/iam01_access_governance.sql"
SECURITY_ACTIONS = ROOT / "apps/web/app/seguranca/actions.ts"
SECURITY_PAGE = ROOT / "apps/web/app/seguranca/page.tsx"
SECURITY_LIB = ROOT / "apps/web/lib/security.ts"
CI = ROOT / ".github/workflows/ci.yml"


class Iam01AccessGovernanceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.migration = MIGRATION.read_text(encoding="utf-8").lower()
        self.smoke = SMOKE.read_text(encoding="utf-8").lower()

    def test_schema_is_versioned_relational_and_default_deny(self) -> None:
        for required in (
            "security_access_profiles",
            "profile_key text not null",
            "version integer not null",
            "security_access_profile_permissions",
            "security_user_access_profiles",
            "primary key (user_id, profile_id)",
            "alter table public.security_access_profiles enable row level security",
            "revoke all on table public.security_user_access_profiles from public, anon, authenticated",
        ):
            self.assertIn(required, self.migration)

    def test_initial_catalog_and_explicit_profile_resolution(self) -> None:
        for profile_key in (
            "administrador_sistema", "diretoria", "comercial_vendedor", "gerencia_comercial",
            "pcp_producao", "estoque", "expedicao_faturamento", "financeiro", "qualidade", "consulta_auditoria",
        ):
            self.assertIn(f"('{profile_key}'", self.migration)
        self.assertIn("profile_permission", self.migration)
        self.assertIn("('administrador_sistema', 'security.manage_users')", self.migration)
        self.assertIn("security_user_has_profile_permission", self.migration)
        self.assertNotIn("like '%.view'", self.migration)
        self.assertNotIn("like 'security.%'", self.migration)
        for forbidden in (
            "cadastros.manage", "cadastros.credit.manage", "pedidos.credit.limit.adjust",
            "pedidos.price_lists.publish", "pedidos.price_lists.withdraw", "pedidos.commissions.assign",
            "audit.reconciliation.run",
        ):
            self.assertNotIn(f"('{forbidden}'", self.migration)

    def test_effective_precedence_and_transition_are_database_rules(self) -> None:
        self.assertIn("if found then return v_override_allowed", self.migration)
        self.assertIn("if v_has_profiles then", self.migration)
        self.assertIn("legacy resolution", self.migration)
        self.assertIn("individual deny did not override profile grant", self.smoke)
        self.assertIn("seguranca.access_profile_assigned", self.smoke)
        self.assertNotIn("profile.version = (select max", self.migration)
        self.assertIn("uq_security_user_access_profiles_key", self.migration)
        self.assertIn("on conflict (user_id, profile_key)", self.migration)
        self.assertIn("profile_id = excluded.profile_id", self.migration)
        self.assertIn("creating profile v2 revoked active v1 access", self.smoke)
        self.assertIn("explicit profile version migration", self.smoke)

    def test_governed_operations_are_audited_and_private_tables(self) -> None:
        for function in (
            "list_security_access_profiles",
            "list_security_user_access_profiles",
            "assign_security_access_profile",
            "remove_security_access_profile",
        ):
            self.assertRegex(self.migration, rf"revoke all on function public\.{function}.*from public, anon")
        self.assertIn("begin_audited_rpc('security.manage_permissions'", self.migration)
        self.assertIn("log_audited_rpc_change", self.migration)
        self.assertIn("self access profile changes are not allowed", self.migration)

    def test_application_uses_governed_profile_assignment(self) -> None:
        actions = SECURITY_ACTIONS.read_text(encoding="utf-8")
        page = SECURITY_PAGE.read_text(encoding="utf-8")
        lib = SECURITY_LIB.read_text(encoding="utf-8")
        self.assertIn('"assign_security_access_profile"', actions)
        self.assertIn('"remove_security_access_profile"', actions)
        self.assertIn('name="access_profile_id"', page)
        self.assertIn('name="pessoa_id"', page)
        self.assertIn("Criar identidade humana automaticamente", page)
        self.assertIn("<details", page)
        self.assertIn("Exceções avançadas", page)
        self.assertIn("list_security_access_profiles", lib)
        self.assertIn("list_security_user_access_profiles", lib)
        self.assertIn("Perfil de acesso inicial", page)
        self.assertIn('"provision_security_human_identity"', actions)
        self.assertIn('p_pessoa_id: pessoaId ? Number(pessoaId) : null', actions)

    def test_identity_provisioning_is_governed_and_audited(self) -> None:
        self.assertIn("provision_security_human_identity", self.migration)
        self.assertIn("cadastros_internal.create_security_human_person", self.migration)
        self.assertIn("revoke all on schema cadastros_internal from public, anon, authenticated", self.migration)
        self.assertIn("revoke all on function cadastros_internal.create_security_human_person(text, text) from public, anon, authenticated", self.migration)
        # The public create RPC remains the canonical Cadastros application contract.
        self.assertIn("create_cad_pessoa_comercial", self.migration)
        self.assertIn("link_security_user_commercial_person", self.migration)
        self.assertIn("seguranca.human_identity_provisioned", self.migration)
        self.assertIn("funcionario_elite", self.migration)
        self.assertIn("link_security_user_commercial_person", self.migration)
        self.assertIn("security smoke admin received generic cadastros create permission", self.smoke)
        self.assertIn("private identity helper is exposed to an application role", self.smoke)
        self.assertIn("new human identity was not created and linked atomically", self.smoke)

    def test_ci_executes_iam_smoke(self) -> None:
        self.assertIn("tests/sql/iam01_access_governance.sql", CI.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
