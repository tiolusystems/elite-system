from __future__ import annotations

import json
import sqlite3
import tempfile
from pathlib import Path
import unittest

from elite_system.apps.admin_server import classify_database_condition
from elite_system.db import connect, init_db
from elite_system.mappings import excel_date, normalize_table_row, number, text
from elite_system.reconciliation import reconciliation_status, run_value_reconciliations
from elite_system.services.security import (
    authenticate_user,
    can_perform_action,
    create_session,
    create_user,
    log_action,
    revoke_session,
    set_role_permission,
    set_user_permission,
    user_from_session,
    verify_password,
)
from elite_system.settings import AppSettings


class CoreTests(unittest.TestCase):
    def test_init_db_creates_audit_tables(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            conn = sqlite3.connect(db_path)
            tables = {
                row[0]
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
            conn.close()
            self.assertIn("source_workbooks", tables)
            self.assertIn("source_rows", tables)
            self.assertIn("migration_issues", tables)
            self.assertIn("value_reconciliations", tables)
            self.assertIn("reconciliation_details", tables)
            self.assertIn("pedidos_linhas", tables)
            self.assertIn("users", tables)
            self.assertIn("user_sessions", tables)
            self.assertIn("action_logs", tables)
            self.assertIn("permission_actions", tables)
            self.assertIn("role_permission_overrides", tables)
            self.assertIn("user_permission_overrides", tables)

    def test_value_normalizers(self) -> None:
        self.assertEqual(text("  Cliente X  "), "Cliente X")
        self.assertIsNone(text("#REF!"))
        self.assertEqual(number("1.234,56"), 1234.56)
        self.assertEqual(excel_date(44562), "2022-01-01")

    def test_database_settings_identify_cloud_backend(self) -> None:
        local = AppSettings.from_env({})
        cloud = AppSettings.from_env({"ELITE_DATABASE_URL": "postgresql://user:pass@example.com/elite"})
        self.assertEqual(local.database_backend, "sqlite")
        self.assertFalse(local.is_cloud_database)
        self.assertEqual(local.sqlite_path, Path("data/elite.sqlite"))
        self.assertEqual(cloud.database_backend, "postgresql")
        self.assertTrue(cloud.is_cloud_database)

    def test_database_condition_flags_disposable_and_local_databases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            disposable = classify_database_condition(Path(tmp) / "etapa2_checks.sqlite")

        local = classify_database_condition(Path("data") / "elite.sqlite")
        operational = classify_database_condition(Path("elite_operacional.sqlite"))

        self.assertTrue(disposable["is_test"])
        self.assertEqual(disposable["mode"], "descartavel")
        self.assertIn("TESTE", str(disposable["label"]))
        self.assertTrue(local["is_test"])
        self.assertEqual(local["mode"], "local")
        self.assertFalse(operational["is_test"])
        self.assertEqual(operational["mode"], "operacional")

    def test_cliente_mapping(self) -> None:
        result = normalize_table_row(
            "CLIENTES",
            {
                "CLIENTES": "ABC LTDA",
                "CÓDIGO": "ABC01",
                "Vendedor que Cadastrou": "MARIA",
                "Vendedor que Atende": "JOAO",
                "A/I": "A",
                "CONTATO": "11999999999",
                "CIDADE": "RIBEIRAO PRETO",
                "UF": "SP",
                "VALOR TOTAL DE COMPRAS": 1500,
            },
        )
        self.assertIsNotNone(result)
        entity, data = result
        self.assertEqual(entity, "clientes")
        self.assertEqual(data["nome"], "ABC LTDA")
        self.assertEqual(data["valor_total_compras"], 1500.0)

    def test_reconciliation_status(self) -> None:
        self.assertEqual(reconciliation_status(100.0, 100.004, 0.01), ("ok", 0.0040000000000048885))
        self.assertEqual(reconciliation_status(100.0, 101.0, 0.01)[0], "attention")
        self.assertEqual(reconciliation_status(None, 100.0, 0.01), ("missing", None))

    def test_security_login_and_action_hash_chain(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="Admin",
                    password="StrongPass123!",
                    display_name="Admin",
                    role="admin",
                )
                stored_hash = conn.execute("SELECT password_hash FROM users WHERE id = ?", (user.id,)).fetchone()[0]
                self.assertNotIn("StrongPass123!", stored_hash)
                self.assertTrue(verify_password("StrongPass123!", stored_hash))

                denied = authenticate_user(conn, username="admin", password="wrong-password")
                accepted = authenticate_user(conn, username="admin", password="StrongPass123!")
                log_action(
                    conn,
                    actor_user_id=user.id,
                    action="cadastros.cliente_updated",
                    entity_type="clientes",
                    entity_id="1",
                    before={"status": "inactive"},
                    after={"status": "active"},
                )
                conn.commit()

                rows = [
                    dict(row)
                    for row in conn.execute(
                        """
                        SELECT id, action, status, previous_hash, entry_hash
                        FROM action_logs
                        ORDER BY id
                        """
                    )
                ]
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("UPDATE action_logs SET action = 'tampered' WHERE id = ?", (rows[0]["id"],))

            self.assertFalse(denied.ok)
            self.assertEqual(denied.reason, "bad_password")
            self.assertTrue(accepted.ok)
            self.assertEqual(accepted.user.id, user.id)
            self.assertEqual(
                [row["action"] for row in rows],
                [
                    "security.user_created",
                    "auth.login.failed",
                    "auth.login.success",
                    "cadastros.cliente_updated",
                ],
            )
            self.assertEqual(rows[1]["status"], "denied")
            self.assertIsNone(rows[0]["previous_hash"])
            self.assertEqual(rows[1]["previous_hash"], rows[0]["entry_hash"])
            self.assertEqual(rows[2]["previous_hash"], rows[1]["entry_hash"])
            self.assertEqual(rows[3]["previous_hash"], rows[2]["entry_hash"])

    def test_permissions_start_with_full_access_then_allow_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="operador",
                    password="StrongPass123!",
                    display_name="Operador",
                    role="comercial",
                )

                default_decision = can_perform_action(conn, user_id=user.id, action_key="comercial.manage")
                unknown_decision = can_perform_action(conn, user_id=user.id, action_key="nova.acao_futura")
                set_role_permission(
                    conn,
                    actor_user_id=user.id,
                    role="comercial",
                    action_key="comercial.manage",
                    allowed=False,
                )
                role_denied = can_perform_action(conn, user_id=user.id, action_key="comercial.manage")
                set_user_permission(
                    conn,
                    actor_user_id=user.id,
                    user_id=user.id,
                    action_key="comercial.manage",
                    allowed=True,
                )
                user_allowed = can_perform_action(conn, user_id=user.id, action_key="comercial.manage")
                logged_actions = [
                    row[0]
                    for row in conn.execute(
                        """
                        SELECT action
                        FROM action_logs
                        WHERE action IN ('security.role_permission_updated', 'security.user_permission_updated')
                        ORDER BY id
                        """
                    )
                ]

            self.assertTrue(default_decision.allowed)
            self.assertEqual(default_decision.source, "default")
            self.assertTrue(unknown_decision.allowed)
            self.assertEqual(unknown_decision.source, "implicit_default")
            self.assertFalse(role_denied.allowed)
            self.assertEqual(role_denied.source, "role_override")
            self.assertTrue(user_allowed.allowed)
            self.assertEqual(user_allowed.source, "user_override")
            self.assertEqual(
                logged_actions,
                ["security.role_permission_updated", "security.user_permission_updated"],
            )

    def test_session_create_lookup_and_revoke(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="sessao",
                    password="StrongPass123!",
                    display_name="Sessao",
                    role="admin",
                )
                token = create_session(conn, user_id=user.id)
                loaded = user_from_session(conn, token)
                revoke_session(conn, token=token, actor_user_id=user.id)
                revoked = user_from_session(conn, token)
                conn.commit()

                stored = conn.execute("SELECT token_hash FROM user_sessions").fetchone()[0]
                logged_actions = [
                    row[0]
                    for row in conn.execute(
                        """
                        SELECT action
                        FROM action_logs
                        WHERE action IN ('auth.session_created', 'auth.session_revoked')
                        ORDER BY id
                        """
                    )
                ]

            self.assertIsNotNone(loaded)
            self.assertEqual(loaded.id, user.id)
            self.assertIsNone(revoked)
            self.assertNotEqual(stored, token)
            self.assertEqual(logged_actions, ["auth.session_created", "auth.session_revoked"])

    def test_stock_detail_reconciliation_by_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row
            try:
                batch_id = _seed_stock_detail_fixture(conn)

                run_value_reconciliations(conn, batch_id)

                rows = [
                    dict(row)
                    for row in conn.execute(
                        """
                        SELECT metric_name, key_label, source_value, system_value, difference, status
                        FROM reconciliation_details
                        WHERE batch_id = ?
                        ORDER BY metric_name, key_label
                        """,
                        (batch_id,),
                    )
                ]
            finally:
                conn.close()

            mp_row = next(row for row in rows if row["metric_name"] == "estoque_mp_saldo_por_materia_prima")
            self.assertEqual(mp_row["key_label"], "MP A")
            self.assertEqual(mp_row["source_value"], 7.0)
            self.assertEqual(mp_row["system_value"], 7.0)
            self.assertEqual(mp_row["status"], "ok")

            pa_row = next(row for row in rows if row["metric_name"] == "estoque_pa_saldo_por_produto")
            self.assertEqual(pa_row["key_label"], "Produto A")
            self.assertEqual(pa_row["source_value"], 3.0)
            self.assertEqual(pa_row["system_value"], 5.0)
            self.assertEqual(pa_row["difference"], 2.0)
            self.assertEqual(pa_row["status"], "attention")


def _seed_stock_detail_fixture(conn: sqlite3.Connection) -> int:
    conn.execute(
        """
        INSERT INTO source_workbooks(source_path, file_name, sha256, size_bytes)
        VALUES ('local.xlsx', 'local.xlsx', 'abc', 1)
        """
    )
    workbook_id = conn.execute("SELECT id FROM source_workbooks").fetchone()[0]
    batch_id = conn.execute("INSERT INTO migration_batches(workbook_id) VALUES (?)", (workbook_id,)).lastrowid

    estoque_mp_row_id = _source_row(conn, workbook_id, "CONT_ESTOQUEMP", 2, {"MATÉRIA PRIMA": "MP A", "SALDO ATUAL": 7})
    estoque_pa_row_id = _source_row(conn, workbook_id, "CONT_ESTOQUE_PA", 3, {"PRODUTO": "Produto A", "SALDO LITROS": 3})
    entrada_row_id = _source_row(conn, workbook_id, "ENTRADAS_MP", 4, {"MATÉRIA PRIMA": "MP A", "QUANTIDADE": 10, "VALOR": 100})
    saida_mp_row_id = _source_row(conn, workbook_id, "SAÍDAS_MP", 5, {"MATÉRIA PRIMA": "MP A", "QUANTIDADE": 3})
    producao_row_id = _source_row(conn, workbook_id, "PRODUCAO_LOTES", 6, {"PRODUTO": "Produto A", "QUANTIDADE PRODUZIDA": 8, "CUSTO MP": 20})
    saida_pa_row_id = _source_row(conn, workbook_id, "SAIDAS_PA", 7, {"PRODUTO": "Produto A", "QUANTIDADE BAIXADA": 3})

    conn.execute(
        "INSERT INTO entradas_mp(source_row_id, materia_prima, quantidade, valor, payload_json) VALUES (?, 'MP A', 10, 100, '{}')",
        (entrada_row_id,),
    )
    conn.execute(
        "INSERT INTO saidas_mp(source_row_id, materia_prima, quantidade, payload_json) VALUES (?, 'MP A', 3, '{}')",
        (saida_mp_row_id,),
    )
    conn.execute(
        "INSERT INTO lotes_producao(source_row_id, produto, quantidade_produzida, custo_mp, payload_json) VALUES (?, 'Produto A', 8, 20, '{}')",
        (producao_row_id,),
    )
    conn.execute(
        "INSERT INTO saidas_pa(source_row_id, produto, quantidade_baixada, payload_json) VALUES (?, 'Produto A', 3, '{}')",
        (saida_pa_row_id,),
    )
    conn.commit()
    assert estoque_mp_row_id
    assert estoque_pa_row_id
    return int(batch_id)


def _source_row(conn: sqlite3.Connection, workbook_id: int, table_name: str, excel_row: int, payload: dict[str, object]) -> int:
    table_id = conn.execute(
        """
        INSERT INTO source_tables(
            workbook_id, sheet_name, table_name, ref, header_row,
            data_first_row, data_last_row, column_count, row_count
        )
        VALUES (?, 'Sheet1', ?, ?, 1, 2, 2, 2, 1)
        """,
        (workbook_id, table_name, f"A{excel_row}:B{excel_row}"),
    ).lastrowid
    return int(
        conn.execute(
            """
            INSERT INTO source_rows(table_id, excel_row_number, row_index, row_hash, payload_json)
            VALUES (?, ?, 1, ?, ?)
            """,
            (table_id, excel_row, f"hash-{excel_row}", json.dumps(payload, ensure_ascii=False)),
        ).lastrowid
    )


if __name__ == "__main__":
    unittest.main()
