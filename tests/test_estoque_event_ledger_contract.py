from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = REPO_ROOT / "supabase" / "migrations"
MIGRATION_0007 = MIGRATIONS / "0007_pa_stock_lots_foundation.sql"
MIGRATION_0009 = MIGRATIONS / "0009_pcp_op_foundation.sql"
MIGRATION_0018 = MIGRATIONS / "0018_estoque_rls_adjustment_axes.sql"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"


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

    def test_manual_inventory_adjustment_is_family_scoped(self) -> None:
        recipe_text = RECIPE_DOC.read_text(encoding="utf-8")
        matrix_text = SECURITY_MATRIX_DOC.read_text(encoding="utf-8")
        combined = f"{recipe_text}\n{matrix_text}"

        for action_key in ("estoque.mp.adjust", "estoque.pa.adjust", "estoque.pi.adjust"):
            self.assertIn(action_key, combined)

        self.assertIn("Nao usar uma action key generica `estoque.adjust`", recipe_text)
        self.assertNotRegex(matrix_text, r"`estoque\.adjust`")

    def test_0018_replaces_permissive_stock_policies_with_read_only_policies(self) -> None:
        text = MIGRATION_0018.read_text(encoding="utf-8").lower()

        for policy_name in (
            "authenticated full pa lot access",
            "authenticated full pa movement access",
            "authenticated full pa reservation access",
            "authenticated full mp lot access",
            "authenticated full mp movement access",
            "authenticated full pi lot access",
            "authenticated full pi movement access",
        ):
            self.assertIn(f'drop policy if exists "{policy_name}"', text)

        self.assertIn("revoke insert, update, delete on", text)
        self.assertIn("for select to authenticated using (public.current_actor_id() is not null)", text)
        self.assertNotIn("for all to authenticated using (true) with check (true)", text)

    def test_0018_adjustment_rpcs_require_family_specific_permission(self) -> None:
        text = MIGRATION_0018.read_text(encoding="utf-8")

        expected = {
            "registrar_est_ajuste_mp": "estoque.mp.adjust",
            "registrar_est_ajuste_pa": "estoque.pa.adjust",
            "registrar_est_ajuste_pi": "estoque.pi.adjust",
        }
        for function_name, action_key in expected.items():
            self.assertIn(f"create or replace function public.{function_name}", text)
            self.assertIn(f"perform public.require_current_user_permission('{action_key}');", text)
            self.assertIn(f"grant execute on function public.{function_name}", text)
            self.assertIn(f"'{action_key}'", text)

        self.assertIn("create or replace function public.create_est_lote_pa", text)
        self.assertIn("perform public.require_current_user_permission('estoque.pa.lots.create');", text)
        self.assertIn("'estoque.pa.lots.create'", text)
        self.assertIn("grant execute on function public.create_est_lote_pa", text)

    def test_0018_adjustment_audit_uses_derived_before_after_snapshot(self) -> None:
        text = MIGRATION_0018.read_text(encoding="utf-8")

        for view_name in ("est_lotes_mp_saldos", "est_lotes_pa_saldos", "est_lotes_pi_saldos"):
            self.assertIn(f"from public.{view_name} saldo", text)

        self.assertGreaterEqual(text.count("into v_before"), 3)
        self.assertGreaterEqual(text.count("into v_after"), 3)
        self.assertGreaterEqual(text.count("public.log_audit_event("), 3)
        self.assertIn("'axis', 'event_movement'", text)
        self.assertIn("'event', 'adjust'", text)


if __name__ == "__main__":
    unittest.main()
