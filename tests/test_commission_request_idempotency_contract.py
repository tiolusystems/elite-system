from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0092_commission_request_idempotency.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "pedidos" / "financeiro" / "actions.ts"
FORMS = ROOT / "apps" / "web" / "app" / "pedidos" / "financeiro" / "finance-forms.tsx"


class CommissionRequestIdempotencyContractTests(unittest.TestCase):
    def test_database_serializes_balance_and_request_keys(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create table public.fin_comissao_requisicoes", sql)
        self.assertGreaterEqual(sql.count("commission-person:"), 2)
        self.assertGreaterEqual(sql.count("pg_advisory_xact_lock"), 4)
        self.assertIn("prevent_financial_event_changes", sql)
        self.assertIn("idempotency key reused with different commission request", sql)

    def test_only_idempotent_entrypoints_are_exposed(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        for operation in ("pagamento", "ajuste"):
            self.assertIn(f"registrar_fin_comissao_{operation}_idempotente", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertNotIn("to anon", sql)

    def test_web_uses_hidden_keys_and_no_unkeyed_calls(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        forms = FORMS.read_text(encoding="utf-8")
        self.assertGreaterEqual(forms.count('name="idempotency_key"'), 4)
        self.assertIn('"registrar_fin_comissao_pagamento_idempotente"', actions)
        self.assertIn('"registrar_fin_comissao_ajuste_idempotente"', actions)
        self.assertNotIn('"registrar_fin_comissao_pagamento"', actions)
        self.assertNotIn('"registrar_fin_comissao_ajuste"', actions)


if __name__ == "__main__":
    unittest.main()
