from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
ACTIONS = (ROOT / "apps/web/app/custos-precos/actions.ts").read_text(encoding="utf-8")
INPUT = (ROOT / "apps/web/app/custos-precos/pricing-idempotency-key-input.tsx").read_text(encoding="utf-8")


class CostPricingIdempotencyFormContract(unittest.TestCase):
    def test_forms_use_a_client_stable_idempotency_key(self):
        self.assertNotIn('node:crypto', PAGE)
        self.assertNotIn('randomUUID()', PAGE)
        self.assertIn('import { PricingIdempotencyKeyInput }', PAGE)

        self.assertIn('"use client"', INPUT)
        self.assertIn('useState(() => crypto.randomUUID())', INPUT)
        self.assertIn('name="idempotency_key" value={key}', INPUT)

        for action in (
            "createPricingPolicyAction",
            "createPricingScenarioAction",
            "calculatePricingScenarioAction",
        ):
            self.assertIn(f'<form action={{{action}}}', PAGE)

        self.assertEqual(PAGE.count('<PricingIdempotencyKeyInput/>'), 4)
        self.assertIn('function ReviewForm', PAGE)
        self.assertIn('reviewPricingPolicyAction', PAGE)
        self.assertIn('reviewPricingCalculationAction', PAGE)

    def test_actions_keep_the_uuid_fail_closed_guard(self):
        self.assertIn('UUID.test(String(args.p_key ?? ""))', ACTIONS)
        self.assertIn('redirect("/custos-precos?result=invalid-request")', ACTIONS)


if __name__ == "__main__":
    unittest.main()
