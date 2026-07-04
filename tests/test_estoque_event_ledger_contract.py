from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = REPO_ROOT / "supabase" / "migrations"
MIGRATION_0007 = MIGRATIONS / "0007_pa_stock_lots_foundation.sql"
MIGRATION_0009 = MIGRATIONS / "0009_pcp_op_foundation.sql"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"


def _create_table_body(sql: str, table_name: str) -> str:
    pattern = rf"create table if not exists public\.{table_name}\s*\((.*?)\n\);"
    match = re.search(pattern, sql, flags=re.IGNORECASE | re.DOTALL)
    if match is None:
        raise AssertionError(f"table definition not found: {table_name}")
    return match.group(1).lower()


class EstoqueEventLedgerContractTests(unittest.TestCase):
    def test_stock_lots_do_not_store_editable_balances(self) -> None:
        pa_sql = MIGRATION_0007.read_text(encoding="utf-8")
        pcp_sql = MIGRATION_0009.read_text(encoding="utf-8")

        for table_name, sql in (
            ("est_lotes_pa", pa_sql),
            ("est_lotes_mp", pcp_sql),
            ("est_lotes_pi", pcp_sql),
        ):
            body = _create_table_body(sql, table_name)
            self.assertNotIn("saldo", body)
            self.assertNotIn("quantidade_atual", body)
            self.assertNotIn("quantidade_disponivel", body)

    def test_stock_balances_are_derived_from_movement_ledgers(self) -> None:
        sql = MIGRATION_0009.read_text(encoding="utf-8").lower()

        for stock_type in ("pa", "mp", "pi"):
            self.assertIn(f"create or replace view public.est_lotes_{stock_type}_saldos", sql)
            self.assertIn(f"from public.est_movimentos_{stock_type}", sql)
            self.assertIn("sum(quantidade) as saldo_fisico", sql)
            self.assertIn("saldo_disponivel", sql)

    def test_stock_movement_ledgers_are_append_only(self) -> None:
        pa_sql = MIGRATION_0007.read_text(encoding="utf-8").lower()
        pcp_sql = MIGRATION_0009.read_text(encoding="utf-8").lower()

        self.assertIn("prevent_est_movimentos_pa_changes", pa_sql)
        self.assertIn("before update or delete on public.est_movimentos_pa", pa_sql)

        for stock_type in ("mp", "pi"):
            self.assertIn(f"prevent_est_movimentos_{stock_type}_changes", pcp_sql)
            self.assertIn(f"before update or delete on public.est_movimentos_{stock_type}", pcp_sql)

    def test_recipe_documents_event_movement_axis(self) -> None:
        text = RECIPE_DOC.read_text(encoding="utf-8").lower()

        self.assertIn("tipo de evento/movimento", text)
        self.assertIn("nunca criar rpc do tipo `update_saldo`", text)
        self.assertIn("saldo fisico deve ser derivado da soma de movimentos append-only", text)
        self.assertIn("ajuste manual de inventario exige motivo obrigatorio", text)


if __name__ == "__main__":
    unittest.main()
