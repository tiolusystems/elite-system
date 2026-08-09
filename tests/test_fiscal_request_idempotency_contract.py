from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION = REPO_ROOT / "supabase" / "migrations" / "0102_fiscal_request_idempotency.sql"


class FiscalRequestIdempotencyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = MIGRATION.read_text(encoding="utf-8").lower()

    def test_request_tables_are_append_only_and_private(self) -> None:
        for table in ("fat_nota_fiscal_emissao_requisicoes", "com_pedido_estorno_requisicoes"):
            self.assertIn(f"create table public.{table}", self.text)
            self.assertIn(f"alter table public.{table} enable row level security", self.text)
            self.assertIn(f"revoke all on table public.{table} from public, anon, authenticated", self.text)
        self.assertIn("before update or delete", self.text)
        self.assertIn("before truncate", self.text)

    def test_entrypoints_lock_and_validate_request_payload(self) -> None:
        for function in (
            "emitir_fat_nota_fiscal_idempotente",
            "registrar_com_pedido_estorno_pos_pagamento_idempotente",
        ):
            self.assertIn(f"create or replace function public.{function}", self.text)
        self.assertGreaterEqual(self.text.count("pg_advisory_xact_lock"), 2)
        self.assertGreaterEqual(self.text.count("actor_id is distinct from v_actor"), 2)
        self.assertGreaterEqual(self.text.count("payload_hash is distinct from v_payload_hash"), 2)

    def test_legacy_unkeyed_entrypoints_are_not_api_executable(self) -> None:
        self.assertIn("revoke all on function public.emitir_fat_nota_fiscal(", self.text)
        self.assertIn("revoke all on function public.registrar_com_pedido_estorno_pos_pagamento(", self.text)
        self.assertIn("from public, anon, authenticated", self.text)
        self.assertIn("grant execute on function public.emitir_fat_nota_fiscal_idempotente", self.text)
        self.assertIn("grant execute on function public.registrar_com_pedido_estorno_pos_pagamento_idempotente", self.text)

    def test_retry_returns_original_fiscal_result(self) -> None:
        self.assertIn("return v_existing.nota_fiscal_id", self.text)
        self.assertIn("return v_existing.nota_fiscal_devolucao_id", self.text)
        self.assertIn("one request key creates at most one invoice", self.text)
        self.assertIn("one request key creates at most one return invoice and stock reversal", self.text)


if __name__ == "__main__":
    unittest.main()
