from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = REPO_ROOT / "supabase" / "migrations"
MIGRATION_0007 = MIGRATIONS / "0007_pa_stock_lots_foundation.sql"
MIGRATION_0009 = MIGRATIONS / "0009_pcp_op_foundation.sql"
MIGRATION_0018 = MIGRATIONS / "0018_estoque_rls_adjustment_axes.sql"
MIGRATION_0019 = MIGRATIONS / "0019_estoque_romaneio_reverse_contract.sql"
MIGRATION_0021 = MIGRATIONS / "0021_estoque_lot_entry_rpc_contract.sql"
MIGRATION_0022 = MIGRATIONS / "0022_estoque_romaneio_confirm_contract.sql"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"

PRE_HELPER_STOCK_MOVEMENT_RPCS = {
    "create_est_lote_pa",
    "estornar_exp_romaneio",
    "registrar_est_ajuste_mp",
    "registrar_est_ajuste_pa",
    "registrar_est_ajuste_pi",
}

PENDING_STOCK_MOVEMENT_RPCS: set[str] = set()

ALLOWED_STOCK_MOVEMENT_RPC_DEBT = PRE_HELPER_STOCK_MOVEMENT_RPCS | PENDING_STOCK_MOVEMENT_RPCS


def _create_table_body(sql: str, table_name: str) -> str:
    pattern = rf"create table if not exists public\.{table_name}\s*\((.*?)\n\);"
    match = re.search(pattern, sql, flags=re.IGNORECASE | re.DOTALL)
    if match is None:
        raise AssertionError(f"table definition not found: {table_name}")
    return match.group(1).lower()


def _latest_sql_function_bodies() -> dict[str, str]:
    functions: dict[str, str] = {}
    pattern = re.compile(
        r"create or replace function public\.([a-z0-9_]+)\s*\(.*?\)\s*returns\b.*?\bas \$\$(.*?)\$\$;",
        flags=re.IGNORECASE | re.DOTALL,
    )

    for path in sorted(MIGRATIONS.glob("*.sql")):
        text = path.read_text(encoding="utf-8")
        for match in pattern.finditer(text):
            functions[match.group(1)] = match.group(2)

    return functions


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

    def test_0019_romaneio_reverse_requires_business_and_stock_permissions(self) -> None:
        text = MIGRATION_0019.read_text(encoding="utf-8")

        self.assertIn("'estoque.pa.reverse.romaneio'", text)
        self.assertIn("create or replace function public.estornar_exp_romaneio", text)
        self.assertIn("perform public.require_current_user_permission('romaneios.cancel');", text)
        self.assertIn("perform public.require_current_user_permission('estoque.pa.reverse.romaneio');", text)
        self.assertIn("public.log_audit_event(", text)
        self.assertIn("'business_action_key', 'romaneios.cancel'", text)
        self.assertIn("'axis', 'event_movement'", text)
        self.assertIn("'event', 'reverse'", text)
        self.assertIn("'origem', 'romaneio'", text)

    def test_0019_cancel_romaneio_requires_permission_and_logs_audit_event(self) -> None:
        text = MIGRATION_0019.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.cancelar_exp_romaneio", text)
        self.assertIn("perform public.require_current_user_permission('romaneios.cancel');", text)
        self.assertIn("'expedicao.romaneio_cancelado'", text)
        self.assertIn("'romaneios.cancel'", text)
        self.assertIn("'estoque_pa_reserva_liberada', true", text)
        self.assertNotIn("perform public.log_action(", text)

    def test_0019_reverse_audit_uses_stock_balance_and_reservation_snapshots(self) -> None:
        text = MIGRATION_0019.read_text(encoding="utf-8")

        self.assertIn("from public.est_lotes_pa_saldos saldo", text)
        self.assertIn("from public.est_reservas_pa reserva", text)
        self.assertIn("v_before", text)
        self.assertIn("v_after", text)
        self.assertIn("'estorno_saida'", text)
        self.assertIn("returning id into v_est_movimento_id", text)

    def test_stock_movement_insert_rpcs_use_audited_helper_or_declared_debt(self) -> None:
        function_bodies = _latest_sql_function_bodies()
        movement_functions = {
            name: body
            for name, body in function_bodies.items()
            if re.search(r"insert\s+into\s+public\.est_movimentos_(mp|pa|pi)\b", body, flags=re.IGNORECASE)
        }

        untracked = sorted(
            name
            for name, body in movement_functions.items()
            if "begin_audited_rpc(" not in body and name not in ALLOWED_STOCK_MOVEMENT_RPC_DEBT
        )

        self.assertEqual(
            untracked,
            [],
            "Stock movement RPCs must call begin_audited_rpc before movement insert or be declared as debt",
        )
        self.assertTrue(
            ALLOWED_STOCK_MOVEMENT_RPC_DEBT.issubset(movement_functions),
            "Declared stock movement RPC debt must still point to real movement-writing functions",
        )

    def test_0021_lot_entry_rpcs_use_audited_contract_helpers(self) -> None:
        text = MIGRATION_0021.read_text(encoding="utf-8")

        expected = {
            "create_est_lote_pa_auto": ("est_lotes_pa", "estoque.pa.lots.create", "PA"),
            "create_est_lote_mp": ("est_lotes_mp", "estoque.mp.lots.create", "MP"),
            "create_est_lote_pi": ("est_lotes_pi", "estoque.pi.lots.create", "PI"),
        }

        for function_name, (entity_type, action_key, family) in expected.items():
            self.assertIn(f"create or replace function public.{function_name}", text)
            self.assertIn("v_permission_context := public.begin_audited_rpc(", text)
            self.assertIn(f"'{action_key}'", text)
            self.assertIn(f"'{entity_type}'", text)
            self.assertIn("'movement_event'", text)
            self.assertIn(f"'familia', '{family}'", text)
            self.assertIn("perform public.log_audited_rpc_change(", text)
            self.assertIn(f"'source', '{function_name}'", text)

        self.assertNotIn("perform public.log_action(", text)

    def test_0022_confirm_romaneio_uses_stock_issue_contract_and_composite_snapshots(self) -> None:
        text = MIGRATION_0022.read_text(encoding="utf-8")

        self.assertIn("'estoque.pa.issue.romaneio'", text)
        self.assertIn("perform public.require_current_user_permission('romaneios.confirm');", text)
        self.assertIn("v_permission_context := public.begin_audited_rpc(", text)
        self.assertIn("'business_action_key', 'romaneios.confirm'", text)
        self.assertIn("'event', 'issue'", text)
        self.assertIn("'origem', 'romaneio'", text)
        self.assertIn("insert into public.est_movimentos_pa", text)
        self.assertIn("'saida_romaneio'", text)
        self.assertIn("update public.est_reservas_pa", text)
        self.assertIn("set status = 'baixada'", text)
        self.assertIn("'reservas_pa'", text)
        self.assertIn("from public.est_reservas_pa reserva", text)
        self.assertIn("'pa_saldos'", text)
        self.assertIn("from public.est_lotes_pa_saldos saldo", text)
        self.assertIn("'exp_movimentos_pa'", text)
        self.assertIn("'est_movimentos_pa'", text)
        self.assertIn("perform public.log_audited_rpc_change(", text)
        self.assertIn("'estoque.pa_romaneio_confirmado'", text)
        self.assertIn("'movimentos_saida'", text)
        self.assertNotIn("perform public.log_action(", text)


if __name__ == "__main__":
    unittest.main()
