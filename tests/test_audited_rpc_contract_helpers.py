from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0020 = REPO_ROOT / "supabase" / "migrations" / "0020_audited_rpc_contract_helpers.sql"


class AuditedRpcContractHelperTests(unittest.TestCase):
    def test_0020_defines_closed_audit_axis_contract(self) -> None:
        text = MIGRATION_0020.read_text(encoding="utf-8")

        self.assertIn("create type public.audit_axis as enum", text)
        for axis in ("own_any", "change_type", "field_risk", "movement_event", "status_transition"):
            self.assertIn(f"'{axis}'", text)
        self.assertIn("create or replace function public.normalize_audit_axis", text)
        self.assertIn("if v_axis = 'event_movement' then", text)
        self.assertIn("v_axis := 'movement_event';", text)

    def test_0020_begin_helper_requires_permission_and_reserved_context(self) -> None:
        text = MIGRATION_0020.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.begin_audited_rpc", text)
        self.assertIn("perform public.require_current_user_permission(v_action_key);", text)
        self.assertIn("audit context contains reserved key", text)
        self.assertIn("'alcada_usada', v_action_key", text)
        self.assertIn("'axis', v_axis::text", text)
        self.assertIn("'domain', v_domain", text)
        self.assertIn("'entity_type', v_entity_type", text)

    def test_0020_log_helper_validates_context_before_log_audit_event(self) -> None:
        text = MIGRATION_0020.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.log_audited_rpc_change", text)
        self.assertIn("permission_context.alcada_usada is required", text)
        self.assertIn("permission_context.alcada_usada does not match action_key", text)
        self.assertIn("permission_context.axis is required", text)
        self.assertIn("permission_context.domain does not match audit domain", text)
        self.assertIn("permission_context.entity_type does not match audit entity_type", text)
        self.assertIn("return public.log_audit_event(", text)

    def test_0020_helpers_are_not_granted_to_public(self) -> None:
        text = MIGRATION_0020.read_text(encoding="utf-8")

        self.assertIn("revoke all on function public.normalize_audit_axis(text) from public", text)
        self.assertIn("revoke all on function public.begin_audited_rpc(text, text, text, text, jsonb) from public", text)
        self.assertIn(
            "revoke all on function public.log_audited_rpc_change(text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, text) from public",
            text,
        )


if __name__ == "__main__":
    unittest.main()
