from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WEB_APP_ROOT = REPO_ROOT / "apps" / "web" / "app"
AUDITED_RPC_HELPER = REPO_ROOT / "apps" / "web" / "lib" / "supabase" / "rpc.ts"


class WebRpcAuditContractTests(unittest.TestCase):
    def test_server_actions_do_not_call_supabase_rpc_directly(self) -> None:
        offenders: list[str] = []

        for path in sorted(WEB_APP_ROOT.rglob("actions.ts")):
            text = path.read_text(encoding="utf-8")
            if re.search(r"\.\s*rpc\s*\(", text):
                offenders.append(str(path.relative_to(REPO_ROOT)))

        self.assertEqual(
            offenders,
            [],
            "Server Actions must use auditedRpc instead of direct .rpc(): " + ", ".join(offenders),
        )

    def test_audited_rpc_logs_permission_denials_in_separate_rpc(self) -> None:
        text = AUDITED_RPC_HELPER.read_text(encoding="utf-8")

        self.assertIn("log_permission_denied", text)
        self.assertIn("not allowed", text)
        self.assertIn("catch", text)
        self.assertIn("error_message", text)

    def test_server_actions_map_not_allowed_to_permission_denied(self) -> None:
        offenders: list[str] = []

        for path in sorted(WEB_APP_ROOT.rglob("actions.ts")):
            text = path.read_text(encoding="utf-8")
            if "auditedRpc" in text and "not allowed" not in text:
                offenders.append(str(path.relative_to(REPO_ROOT)))

        self.assertEqual(
            offenders,
            [],
            "Server Actions using auditedRpc must map 'not allowed' to permission_denied: " + ", ".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
