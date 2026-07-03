from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sqlite3

from .db import connect, init_db
from .excel_reader import ExcelTable, extract_tables
from .mappings import ENTITY_BY_TABLE, NORMALIZED_TABLES, normalize_table_row, number, text
from .reconciliation import run_value_reconciliations
from .services.security import log_action


def import_workbook(workbook_path: str | Path, db_path: str | Path, actor_user_id: int | None = None) -> dict[str, object]:
    workbook = Path(workbook_path).resolve()
    db = Path(db_path)
    init_db(db)

    with connect(db) as conn:
        workbook_id = _upsert_workbook(conn, workbook)
        batch_id = _create_batch(conn, workbook_id)
        summary = {
            "workbook": str(workbook),
            "db": str(db.resolve()),
            "workbook_id": workbook_id,
            "batch_id": batch_id,
            "raw_tables": 0,
            "raw_rows": 0,
            "normalized": {},
            "issues": 0,
        }
        log_action(
            conn,
            actor_user_id=actor_user_id,
            action="migration.import_started",
            entity_type="migration_batches",
            entity_id=str(batch_id),
            metadata={"workbook_id": workbook_id},
        )
        try:
            tables = extract_tables(workbook)
            summary["raw_tables"] = len(tables)
            for table in tables:
                table_id = _upsert_source_table(conn, workbook_id, table)
                for row in table.rows:
                    source_row_id = _insert_source_row(conn, table_id, row.excel_row_number, row.row_index, row.values, row.formulas)
                    summary["raw_rows"] += 1
                    if table.table_name in NORMALIZED_TABLES:
                        imported = _normalize_row(conn, batch_id, table.table_name, source_row_id, row.values)
                        if imported:
                            summary["normalized"][imported] = summary["normalized"].get(imported, 0) + 1
                        elif _has_business_payload(row.values):
                            _issue(
                                conn,
                                batch_id,
                                "warning",
                                "normalize",
                                table.table_name,
                                source_row_id,
                                "business_row_not_normalized",
                                "Linha contem dados, mas nao possui chave suficiente para entrar na tabela normalizada.",
                                {"excel_row_number": row.excel_row_number, "payload": row.values},
                            )

            _write_audit_snapshots(conn, batch_id)
            value_metrics = run_value_reconciliations(conn, batch_id)
            summary["value_reconciliations"] = {
                "ok": sum(1 for metric in value_metrics if metric["status"] == "ok"),
                "attention": sum(1 for metric in value_metrics if metric["status"] == "attention"),
                "missing": sum(1 for metric in value_metrics if metric["status"] == "missing"),
            }
            conn.execute(
                "UPDATE migration_batches SET status = 'completed', finished_at = CURRENT_TIMESTAMP WHERE id = ?",
                (batch_id,),
            )
            summary["issues"] = conn.execute(
                "SELECT COUNT(*) FROM migration_issues WHERE batch_id = ?", (batch_id,)
            ).fetchone()[0]
            log_action(
                conn,
                actor_user_id=actor_user_id,
                action="migration.import_completed",
                entity_type="migration_batches",
                entity_id=str(batch_id),
                after={
                    "raw_tables": summary["raw_tables"],
                    "raw_rows": summary["raw_rows"],
                    "issues": summary["issues"],
                    "value_reconciliations": summary["value_reconciliations"],
                },
            )
            conn.commit()
            return summary
        except Exception as exc:
            conn.execute(
                "UPDATE migration_batches SET status = 'failed', finished_at = CURRENT_TIMESTAMP, notes = ? WHERE id = ?",
                (str(exc), batch_id),
            )
            log_action(
                conn,
                actor_user_id=actor_user_id,
                action="migration.import_failed",
                entity_type="migration_batches",
                entity_id=str(batch_id),
                status="error",
                metadata={"error_type": type(exc).__name__},
            )
            conn.commit()
            raise


def _upsert_workbook(conn: sqlite3.Connection, workbook: Path) -> int:
    digest = file_sha256(workbook)
    stat = workbook.stat()
    conn.execute(
        """
        INSERT OR IGNORE INTO source_workbooks(source_path, file_name, sha256, size_bytes, metadata_json)
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            str(workbook),
            workbook.name,
            digest,
            stat.st_size,
            json.dumps({"suffix": workbook.suffix}, ensure_ascii=False),
        ),
    )
    return conn.execute("SELECT id FROM source_workbooks WHERE sha256 = ?", (digest,)).fetchone()[0]


def _create_batch(conn: sqlite3.Connection, workbook_id: int) -> int:
    cur = conn.execute("INSERT INTO migration_batches(workbook_id) VALUES (?)", (workbook_id,))
    return int(cur.lastrowid)


def _upsert_source_table(conn: sqlite3.Connection, workbook_id: int, table: ExcelTable) -> int:
    conn.execute(
        """
        INSERT INTO source_tables(
            workbook_id, sheet_name, table_name, ref, header_row, data_first_row, data_last_row, column_count, row_count
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(workbook_id, sheet_name, table_name, ref) DO UPDATE SET
            header_row = excluded.header_row,
            data_first_row = excluded.data_first_row,
            data_last_row = excluded.data_last_row,
            column_count = excluded.column_count,
            row_count = excluded.row_count
        """,
        (
            workbook_id,
            table.sheet_name,
            table.table_name,
            table.ref,
            table.header_row,
            table.data_first_row,
            table.data_last_row,
            len(table.headers),
            len(table.rows),
        ),
    )
    return conn.execute(
        """
        SELECT id FROM source_tables
        WHERE workbook_id = ? AND sheet_name = ? AND table_name = ? AND ref = ?
        """,
        (workbook_id, table.sheet_name, table.table_name, table.ref),
    ).fetchone()[0]


def _insert_source_row(
    conn: sqlite3.Connection,
    table_id: int,
    excel_row_number: int,
    row_index: int,
    payload: dict[str, object],
    formulas: dict[str, str],
) -> int:
    payload_json = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    formulas_json = json.dumps(formulas, ensure_ascii=False, sort_keys=True)
    row_hash = hashlib.sha256((payload_json + "\n" + formulas_json).encode("utf-8")).hexdigest()
    conn.execute(
        """
        INSERT OR IGNORE INTO source_rows(table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json),
    )
    return int(
        conn.execute(
        """
        SELECT id FROM source_rows
        WHERE table_id = ? AND excel_row_number = ? AND row_hash = ?
        """,
            (table_id, excel_row_number, row_hash),
        ).fetchone()[0]
    )


def _normalize_row(
    conn: sqlite3.Connection,
    batch_id: int,
    table_name: str,
    source_row_id: int,
    raw_row: dict[str, object],
) -> str | None:
    normalized = normalize_table_row(table_name, raw_row)
    if normalized is None:
        return None

    entity, data = normalized
    data_with_payload = {**data, "source_row_id": source_row_id, "payload_json": json.dumps(raw_row, ensure_ascii=False, sort_keys=True)}
    columns = list(data_with_payload)
    placeholders = ", ".join("?" for _ in columns)
    column_sql = ", ".join(columns)
    update_sql = ", ".join(f"{column} = excluded.{column}" for column in columns if column != "source_row_id")
    conn.execute(
        f"""
        INSERT INTO {entity}({column_sql})
        VALUES ({placeholders})
        ON CONFLICT(source_row_id) DO UPDATE SET {update_sql}
        """,
        [data_with_payload[column] for column in columns],
    )

    entity_key_column = ENTITY_BY_TABLE[table_name][1]
    entity_key = data.get(entity_key_column)
    payload_hash = hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()
    conn.execute(
        """
        INSERT OR IGNORE INTO imported_records(batch_id, source_row_id, entity_name, entity_key, payload_hash)
        VALUES (?, ?, ?, ?, ?)
        """,
        (batch_id, source_row_id, entity, entity_key, payload_hash),
    )
    return entity


def _write_audit_snapshots(conn: sqlite3.Connection, batch_id: int) -> None:
    for table_name, (entity, _key) in ENTITY_BY_TABLE.items():
        row = conn.execute(
            """
            SELECT st.id AS table_id, st.row_count AS expected_count
            FROM source_tables st
            JOIN source_workbooks sw ON sw.id = st.workbook_id
            JOIN migration_batches mb ON mb.workbook_id = sw.id
            WHERE mb.id = ? AND st.table_name = ?
            ORDER BY st.id DESC
            LIMIT 1
            """,
            (batch_id, table_name),
        ).fetchone()
        if row is None:
            _issue(conn, batch_id, "warning", "audit", table_name, None, "source_table_missing", "Tabela fonte nao encontrada", {})
            continue

        raw_rows = conn.execute("SELECT COUNT(*) FROM source_rows WHERE table_id = ?", (row["table_id"],)).fetchone()[0]
        actual = conn.execute(
            f"""
            SELECT COUNT(*)
            FROM {entity}
            WHERE source_row_id IN (SELECT id FROM source_rows WHERE table_id = ?)
            """,
            (row["table_id"],),
        ).fetchone()[0]
        status = "ok" if actual <= raw_rows else "error"
        conn.execute(
            """
            INSERT INTO audit_snapshots(batch_id, audit_name, source_table, expected_count, actual_count, status, payload_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                batch_id,
                "normalized_count_not_above_raw",
                table_name,
                raw_rows,
                actual,
                status,
                json.dumps({"entity": entity}, ensure_ascii=False),
            ),
        )
        if status != "ok":
            _issue(conn, batch_id, "error", "audit", table_name, None, "count_above_raw", "Tabela normalizada tem mais linhas que a origem", {"entity": entity})


def _issue(
    conn: sqlite3.Connection,
    batch_id: int,
    severity: str,
    scope: str,
    source_table: str | None,
    source_row_id: int | None,
    code: str,
    message: str,
    payload: dict[str, object],
) -> None:
    conn.execute(
        """
        INSERT INTO migration_issues(batch_id, severity, scope, source_table, source_row_id, code, message, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (batch_id, severity, scope, source_table, source_row_id, code, message, json.dumps(payload, ensure_ascii=False)),
    )


def _has_business_payload(raw_row: dict[str, object]) -> bool:
    for value in raw_row.values():
        numeric = number(value)
        if numeric is not None and abs(numeric) > 0:
            return True
        if text(value):
            return True
    return False


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
