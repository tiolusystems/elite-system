from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0091_receipt_request_idempotency.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "pedidos" / "financeiro" / "actions.ts"
PAGE = ROOT / "apps" / "web" / "app" / "pedidos" / "financeiro" / "page.tsx"
SMOKE = ROOT / "tests" / "sql" / "commercial_end_to_end_chain.sql"


class ReceiptRequestIdempotencyContractTests(unittest.TestCase):
    def test_database_serializes_and_reuses_request_key(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.fin_recebimento_requisicoes", sql)
        self.assertIn("idempotency_key uuid primary key", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("payload_hash is distinct from v_payload_hash", sql)
        self.assertIn("return v_existing.recebimento_id", sql)
        self.assertIn("prevent_financial_event_changes", sql)

    def test_only_keyed_entrypoint_is_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("revoke all on function public.registrar_com_recebimento(", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertIn("grant execute on function public.registrar_com_recebimento_idempotente", sql)
        self.assertIn("to authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_web_form_keeps_one_key_for_retries(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('name="idempotency_key"', page)
        self.assertIn("randomUUID()", page)
        self.assertIn('auditedRpc(supabase, "registrar_com_recebimento_idempotente"', actions)
        self.assertIn("p_idempotency_key: idempotencyKey", actions)
        self.assertNotIn('auditedRpc(supabase, "registrar_com_recebimento",', actions)

    def test_frontend_cannot_call_unkeyed_receipt_rpc(self) -> None:
        web_root = ROOT / "apps" / "web"
        calls = []
        for path in web_root.rglob("*.ts*"):
            text = path.read_text(encoding="utf-8")
            if '"registrar_com_recebimento"' in text:
                calls.append(str(path.relative_to(ROOT)))
        self.assertEqual([], calls, f"unkeyed receipt RPC used by: {calls}")

    def test_integrated_smoke_retries_and_rejects_changed_payload(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8").lower()
        self.assertGreaterEqual(smoke.count("registrar_com_recebimento_idempotente("), 3)
        self.assertIn("receipt retry did not return the original event", smoke)
        self.assertIn("idempotency key reused with different receipt request", smoke)


if __name__ == "__main__":
    unittest.main()
