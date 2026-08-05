from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/0104_separate_credit_limit_adjust_permission.sql").read_text(encoding="utf-8")
SMOKE = (ROOT / "tests/sql/credit_limit_atomic_permission.sql").read_text(encoding="utf-8")
MASTER_DATA = (ROOT / "apps/web/lib/master-data.ts").read_text(encoding="utf-8")
ORDER_ACTIONS = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
ORDER_PAGE = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
SECURITY_DATA = (ROOT / "apps/web/lib/security.ts").read_text(encoding="utf-8")
SECURITY_PAGE = (ROOT / "apps/web/app/seguranca/page.tsx").read_text(encoding="utf-8")
MANUALS = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
UPGRADE_BEFORE = (ROOT / "tests/sql/upgrade/credit_limit_pre_0104_fixture.sql").read_text(encoding="utf-8")
UPGRADE_AFTER = (ROOT / "tests/sql/upgrade/credit_limit_post_0104_verify.sql").read_text(encoding="utf-8")


class CreditLimitAtomicPermissionContractTests(unittest.TestCase):
    def test_new_permission_is_financial_and_default_deny(self) -> None:
        self.assertIn("'financeiro.credit_limits.adjust'", MIGRATION)
        self.assertIn("'financeiro'", MIGRATION)
        self.assertIn("'Alterar limite de crédito de cliente'", MIGRATION)
        self.assertRegex(MIGRATION, r"'Alterar limite de crédito de cliente',\s*false,\s*604,\s*'financeiro',\s*'write'")

    def test_legacy_permission_is_preserved_but_cannot_authorize(self) -> None:
        self.assertIn("description = 'LEGADA - não utilizar", MIGRATION)
        self.assertIn("where action_key = 'pedidos.credit.limit.adjust'", MIGRATION)
        self.assertNotIn("insert into public.user_permission_overrides", MIGRATION.lower())
        self.assertGreaterEqual(MIGRATION.count("require_current_user_permission('financeiro.credit_limits.adjust')"), 2)
        function_contract = MIGRATION.split("create or replace function public.ajustar_com_limite_credito_cliente(", 1)[1]
        self.assertNotIn("current_user_manages_seller", function_contract)

    def test_frontend_uses_only_the_effective_atomic_permission(self) -> None:
        self.assertIn('p_action_key: "financeiro.credit_limits.adjust"', MASTER_DATA)
        self.assertNotIn('p_action_key: "pedidos.credit.limit.adjust"', MASTER_DATA)
        self.assertIn('action_key: "financeiro.credit_limits.adjust"', ORDER_ACTIONS)
        self.assertIn('domain: "financeiro"', ORDER_ACTIONS)
        for inferred_role in ('role === "gerente"', 'role === "financeiro"', 'role === "admin"'):
            self.assertNotIn(inferred_role, MASTER_DATA)

    def test_order_review_does_not_render_permanent_limit_form(self) -> None:
        self.assertNotIn("ajustarLimiteCreditoAction", ORDER_PAGE)
        self.assertNotIn("Ajustar limite do cliente", ORDER_PAGE)
        self.assertIn("Consultar crédito do cliente", ORDER_PAGE)

    def test_security_screen_distinguishes_role_override_and_origin(self) -> None:
        self.assertIn('LEGACY_PERMISSION_KEYS = new Set(["pedidos.credit.limit.adjust"])', SECURITY_DATA)
        self.assertIn("Padrão da ação", SECURITY_PAGE)
        self.assertIn("Decisão individual", SECURITY_PAGE)
        self.assertIn("Remover decisão individual", SECURITY_PAGE)
        self.assertIn('permission.defaultAllowed ? "Permitido" : "Negado"', SECURITY_PAGE)
        self.assertNotIn("padrão do perfil", SECURITY_PAGE.lower())

    def test_smoke_covers_role_independence_revocation_and_audit(self) -> None:
        for marker in (
            "manager inherited credit limit authority",
            "financial operator changed limit without atomic permission",
            "administrator changed limit without atomic permission",
            "individual override did not grant credit limit authority",
            "credit limit authority implied order review",
            "revoked user changed credit limit",
            "idempotent retry returned another event",
            "direct credit event write was accepted",
            "credit limit audit event lost before/after, reason or actor",
        ):
            self.assertIn(marker, SMOKE)

    def test_upgrade_preserves_legacy_history_without_copying_grant(self) -> None:
        self.assertIn("pedidos.credit.limit.adjust", UPGRADE_BEFORE)
        self.assertIn("legacy positive override history was not preserved", UPGRADE_AFTER)
        self.assertIn("legacy positive override was copied automatically", UPGRADE_AFTER)
        self.assertIn("PG_VALIDATE_UPGRADE_0103_TO_0104_OK", UPGRADE_AFTER)

    def test_manual_separates_order_review_from_permanent_limit(self) -> None:
        self.assertIn("Uma aprovacao excepcional do pedido nao altera o limite cadastral do cliente.", MANUALS)
        self.assertIn("permissao financeira individual", MANUALS)

    def test_ci_runs_atomic_permission_smoke(self) -> None:
        self.assertIn("tests/sql/credit_limit_atomic_permission.sql", CI)


if __name__ == "__main__":
    unittest.main()
