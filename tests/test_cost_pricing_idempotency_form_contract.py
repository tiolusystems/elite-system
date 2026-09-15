from pathlib import Path
import re
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

    def test_uuid_guard_matches_standard_uuid_behavior(self):
        match = re.search(r"const UUID = /([^/]+)/i;", ACTIONS)
        self.assertIsNotNone(match)
        uuid_guard = re.compile(match.group(1), re.IGNORECASE)

        for value in (
            "550e8400-e29b-41d4-a716-446655440000",
            "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
            "00000000-0000-2000-8000-000000000000",
            "6fa459ea-ee8a-3ca4-894e-db77e160355e",
            "987fbc97-4bed-5078-9f07-9141ba07c9f3",
        ):
            with self.subTest(value=value):
                self.assertIsNotNone(uuid_guard.fullmatch(value))

        for value in (
            "550e8400e29b41d4a716446655440000",
            "550e8400-e29b-41d4-a716446655440000",
            "550e8400-e29b-41d4-c716-446655440000",
            "",
        ):
            with self.subTest(value=value):
                self.assertIsNone(uuid_guard.fullmatch(value))

        random_uuid_shape = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
        self.assertIsNotNone(uuid_guard.fullmatch(random_uuid_shape))

    def test_actions_keep_the_uuid_fail_closed_guard(self):
        self.assertIn('UUID.test(String(args.p_key ?? ""))', ACTIONS)
        self.assertIn('redirect("/custos-precos?result=invalid-request")', ACTIONS)


if __name__ == "__main__":
    unittest.main()
