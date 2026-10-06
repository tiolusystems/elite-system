from __future__ import annotations

import re
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "supabase" / "config.toml"
PRODUCTION_PROJECT_REF = "oncssgiocivoknwwcuuz"
PRODUCTION_SITE_URL = "https://elite-system-seven.vercel.app"
PRODUCTION_CONFIRM_URL = f"{PRODUCTION_SITE_URL}/auth/confirm"


class ProductionAuthPolicyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config_text = CONFIG_PATH.read_text(encoding="utf-8")
        cls.config = tomllib.loads(cls.config_text)
        cls.production = cls.config["remotes"]["production"]
        cls.auth = cls.production["auth"]
        cls.email = cls.auth["email"]

    def test_production_remote_identity_and_closed_auth_policy(self) -> None:
        self.assertEqual(self.production["project_id"], PRODUCTION_PROJECT_REF)
        self.assertTrue(self.auth["enabled"])
        self.assertEqual(self.auth["site_url"], PRODUCTION_SITE_URL)
        self.assertFalse(self.auth["enable_signup"])
        self.assertFalse(self.auth["enable_anonymous_sign_ins"])
        self.assertFalse(self.auth["enable_manual_linking"])
        self.assertFalse(self.email["enable_signup"])
        self.assertTrue(self.email["enable_confirmations"])

    def test_production_sessions_and_email_expiry_remain_governed(self) -> None:
        self.assertEqual(self.auth["jwt_expiry"], 3600)
        self.assertTrue(self.auth["enable_refresh_token_rotation"])
        self.assertEqual(self.auth["refresh_token_reuse_interval"], 10)
        self.assertEqual(self.email["otp_expiry"], 3600)

    def test_production_redirects_are_exact_and_have_no_wildcard(self) -> None:
        redirects = self.auth["additional_redirect_urls"]
        self.assertEqual(redirects, [PRODUCTION_CONFIRM_URL])
        self.assertTrue(all("*" not in redirect for redirect in redirects))
        self.assertTrue(all("?" not in redirect for redirect in redirects))

    def test_production_remote_contains_no_secret_or_unresolved_provider(self) -> None:
        start = self.config_text.index("[remotes.production]")
        following_root_table = re.search(
            r"(?m)^\[(?!remotes\.production(?:\.|\]))",
            self.config_text[start + 1 :],
        )
        end = len(self.config_text) if following_root_table is None else start + 1 + following_root_table.start()
        production_block = self.config_text[start:end]
        self.assertNotRegex(production_block, re.compile(r"(?im)^\s*(?:secret|pass|password|api[_-]?key)\s*="))
        self.assertNotIn("[remotes.production.auth.email.smtp]", production_block)
        self.assertNotIn("[remotes.production.auth.captcha]", production_block)

    def test_local_development_auth_url_is_unchanged(self) -> None:
        self.assertEqual(self.config["auth"]["site_url"], "http://127.0.0.1:3000")
        self.assertEqual(self.config["auth"]["additional_redirect_urls"], ["https://127.0.0.1:3000"])


if __name__ == "__main__":
    unittest.main()
