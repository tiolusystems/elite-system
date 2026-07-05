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

    def test_typed_audited_rpc_call_requires_contract_metadata(self) -> None:
        text = AUDITED_RPC_HELPER.read_text(encoding="utf-8")

        self.assertIn('export type AuditAxis = "own_any" | "change_type" | "field_risk" | "movement_event" | "status_transition"', text)
        self.assertIn("const AUDIT_AXES = new Set<AuditAxis>", text)
        self.assertIn("export type AuditedRpcContract", text)
        self.assertIn("export class AuditedRpcCall", text)
        self.assertIn("actionKey: string", text)
        self.assertIn("domain: string", text)
        self.assertIn("entity: string", text)
        self.assertIn("axis: AuditAxis", text)
        self.assertIn("execute(args", text)
        self.assertIn("validateContract", text)
        self.assertIn("Audited RPC contract requires", text)
        self.assertIn("AUDIT_AXES.has(contract.axis)", text)
        self.assertIn("Audited RPC contract requires valid axis", text)

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
