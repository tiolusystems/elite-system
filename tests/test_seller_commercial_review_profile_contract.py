from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase" / "migrations" / "0149_grant_seller_commercial_review.sql").read_text(encoding="utf-8")
F2B = (ROOT / "supabase" / "migrations" / "0131_govern_seller_commercial_confirmation.sql").read_text(encoding="utf-8")
RUNTIME_SMOKE = (ROOT / "tests" / "sql" / "seller_commercial_review_profile.sql").read_text(encoding="utf-8")


class SellerCommercialReviewProfileContractTests(unittest.TestCase):
    def test_profile_has_only_rpc_required_f2b_actions(self) -> None:
        required = [
            "pedidos.price_reference.resolve", "pedidos.payment_terms.manage",
            "pedidos.commercial_context.manage", "pedidos.practiced_price.record",
            "pedidos.commercial_review.preview", "pedidos.commercial_review.confirm",
        ]
        for action in required:
            self.assertIn(action, MIGRATION)
        for forbidden in [
            "pedidos.commercial_discount.review", "pedidos.credit.review", "system.admin",
            "pedidos.commercial_comparison.view", "('pcp.", "('estoque.", "('financeiro.", "('security.",
        ]:
            self.assertNotIn(forbidden, MIGRATION)

    def test_confirm_rpc_requires_the_granted_set(self) -> None:
        for action in [
            "pedidos.create.own", "pedidos.price_reference.resolve", "pedidos.payment_terms.manage",
            "pedidos.commercial_context.manage", "pedidos.practiced_price.record",
        ]:
            self.assertIn(f"require_current_user_permission('{action}')", F2B)
        self.assertIn("pedidos.commercial_review.confirm", F2B)

    def test_runtime_smoke_proves_profile_resolution_without_positive_override(self) -> None:
        self.assertIn("security_user_access_profiles", RUNTIME_SMOKE)
        self.assertIn("seller F2B action % leaked through an individual override", RUNTIME_SMOKE)
        self.assertIn("foreign portfolio preview was accepted", RUNTIME_SMOKE)
        self.assertIn("foreign portfolio confirmation was accepted", RUNTIME_SMOKE)
        self.assertIn("seller approved a commercial discount", RUNTIME_SMOKE)
        self.assertIn("seller reviewed commercial credit", RUNTIME_SMOKE)
        self.assertIn("discount decision persisted despite denied seller authorization", RUNTIME_SMOKE)
        self.assertIn("credit decision persisted despite denied seller authorization", RUNTIME_SMOKE)
        self.assertIn("PG_SELLER_COMMERCIAL_REVIEW_PROFILE_OK", RUNTIME_SMOKE)


if __name__ == "__main__":
    unittest.main()
