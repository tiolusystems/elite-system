from __future__ import annotations

from pathlib import Path
import json

from .db import connect, init_db


def run_audit(db_path: str | Path, batch_id: int | None = None) -> dict[str, object]:
    init_db(db_path)
    with connect(db_path) as conn:
        if batch_id is None:
            row = conn.execute("SELECT id FROM migration_batches ORDER BY id DESC LIMIT 1").fetchone()
            if row is None:
                return {"status": "empty", "message": "Nenhuma importacao encontrada."}
            batch_id = int(row["id"])

        batch = conn.execute(
            """
            SELECT mb.id, mb.status, mb.started_at, mb.finished_at, sw.file_name, sw.sha256
            FROM migration_batches mb
            JOIN source_workbooks sw ON sw.id = mb.workbook_id
            WHERE mb.id = ?
            """,
            (batch_id,),
        ).fetchone()
        if batch is None:
            return {"status": "missing", "message": f"Batch {batch_id} nao encontrado."}

        source_tables = [
            dict(row)
            for row in conn.execute(
                """
                SELECT st.table_name, st.sheet_name, st.ref, st.row_count,
                       (SELECT COUNT(*) FROM source_rows sr WHERE sr.table_id = st.id) AS imported_raw_rows
                FROM source_tables st
                JOIN migration_batches mb ON mb.workbook_id = st.workbook_id
                WHERE mb.id = ?
                ORDER BY st.table_name
                """,
                (batch_id,),
            )
        ]
        normalized_counts = {
            name: conn.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
            for name in [
                "materias_primas",
                "produtos",
                "clientes",
                "vendedores",
                "veiculos",
                "pedidos_linhas",
                "entradas_mp",
                "lotes_producao",
                "saidas_mp",
                "saidas_pa",
            ]
        }
        issues = [
            dict(row)
            for row in conn.execute(
                """
                SELECT severity, scope, source_table, code, message, COUNT(*) AS count
                FROM migration_issues
                WHERE batch_id = ?
                GROUP BY severity, scope, source_table, code, message
                ORDER BY severity, source_table, code
                """,
                (batch_id,),
            )
        ]
        issue_examples = [
            {**dict(row), "payload": _loads(row["payload_json"])}
            for row in conn.execute(
                """
                SELECT mi.severity, mi.scope, mi.source_table, mi.code, mi.message,
                       sr.excel_row_number, mi.payload_json
                FROM migration_issues mi
                LEFT JOIN source_rows sr ON sr.id = mi.source_row_id
                WHERE mi.batch_id = ?
                ORDER BY mi.id
                LIMIT 20
                """,
                (batch_id,),
            )
        ]
        snapshots = [
            {**dict(row), "payload": _loads(row["payload_json"])}
            for row in conn.execute(
                """
                SELECT audit_name, source_table, expected_count, actual_count, status, payload_json
                FROM audit_snapshots
                WHERE batch_id = ?
                ORDER BY source_table, audit_name
                """,
                (batch_id,),
            )
        ]
        value_reconciliations = [
            {**dict(row), "details": _loads(row["details_json"])}
            for row in conn.execute(
                """
                SELECT metric_name, source_label, source_value, system_value, difference, tolerance, status, details_json
                FROM value_reconciliations
                WHERE batch_id = ?
                ORDER BY
                    CASE status WHEN 'attention' THEN 0 WHEN 'missing' THEN 1 ELSE 2 END,
                    metric_name
                """,
                (batch_id,),
            )
        ]
        detail_reconciliation_summary = [
            dict(row)
            for row in conn.execute(
                """
                SELECT metric_name, status, COUNT(*) AS count,
                       SUM(ABS(COALESCE(difference, 0))) AS total_abs_difference
                FROM reconciliation_details
                WHERE batch_id = ?
                GROUP BY metric_name, status
                ORDER BY metric_name, status
                """,
                (batch_id,),
            )
        ]
        detail_reconciliation_examples = [
            {**dict(row), "details": _loads(row["details_json"])}
            for row in conn.execute(
                """
                SELECT metric_name, key_type, key_label, source_value, system_value,
                       difference, tolerance, status, details_json
                FROM reconciliation_details
                WHERE batch_id = ? AND status <> 'ok'
                ORDER BY ABS(COALESCE(difference, 0)) DESC, metric_name, key_label
                LIMIT 20
                """,
                (batch_id,),
            )
        ]
        raw_total = sum(row["imported_raw_rows"] for row in source_tables)
        failed_snapshots = [row for row in snapshots if row["status"] != "ok"]
        value_attention = [row for row in value_reconciliations if row["status"] != "ok"]
        detail_attention = [row for row in detail_reconciliation_summary if row["status"] != "ok"]
        return {
            "status": "ok" if not failed_snapshots and not value_attention and not detail_attention else "attention",
            "batch": dict(batch),
            "source_table_count": len(source_tables),
            "source_raw_row_count": raw_total,
            "normalized_counts": normalized_counts,
            "value_reconciliations": value_reconciliations,
            "detail_reconciliation_summary": detail_reconciliation_summary,
            "detail_reconciliation_examples": detail_reconciliation_examples,
            "issues": issues,
            "issue_examples": issue_examples,
            "failed_audits": failed_snapshots,
        }


def _loads(value: str) -> object:
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value
