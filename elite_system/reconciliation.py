from __future__ import annotations

import json
import sqlite3
from typing import Iterable

from .mappings import number, text


VALUE_TOLERANCE = 0.01
QUANTITY_TOLERANCE = 0.001


def run_value_reconciliations(conn: sqlite3.Connection, batch_id: int) -> list[dict[str, object]]:
    conn.execute("DELETE FROM value_reconciliations WHERE batch_id = ?", (batch_id,))
    metrics = [
        _distinct_pedidos(conn, batch_id),
        _sum_metric(
            conn,
            batch_id,
            metric_name="faturamento_total",
            source_table="GESTÃO_PEDIDOS",
            source_column="R$ TOTAL",
            system_sql="SELECT SUM(valor_total) FROM pedidos_linhas",
            tolerance=VALUE_TOLERANCE,
            source_filter=_non_empty_order,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="faturamento_vendas",
            source_table="GESTÃO_PEDIDOS",
            source_column="R$ TOTAL",
            system_sql="SELECT SUM(valor_total) FROM pedidos_linhas WHERE tipo = 'VENDA'",
            tolerance=VALUE_TOLERANCE,
            source_filter=lambda row: text(row.get("TIPO")) == "VENDA",
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="entradas_mp_quantidade",
            source_table="ENTRADAS_MP",
            source_column="QUANTIDADE",
            system_sql="SELECT SUM(quantidade) FROM entradas_mp",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="entradas_mp_valor",
            source_table="ENTRADAS_MP",
            source_column="VALOR",
            system_sql="SELECT SUM(valor) FROM entradas_mp",
            tolerance=VALUE_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="saidas_mp_quantidade",
            source_table="SAÍDAS_MP",
            source_column="QUANTIDADE",
            system_sql="SELECT SUM(quantidade) FROM saidas_mp",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="saidas_pa_quantidade",
            source_table="SAIDAS_PA",
            source_column="QUANTIDADE BAIXADA",
            system_sql="SELECT SUM(quantidade_baixada) FROM saidas_pa",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="producao_quantidade",
            source_table="PRODUCAO_LOTES",
            source_column="QUANTIDADE PRODUZIDA",
            system_sql="SELECT SUM(quantidade_produzida) FROM lotes_producao",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="producao_custo_mp",
            source_table="PRODUCAO_LOTES",
            source_column="CUSTO MP",
            system_sql="SELECT SUM(custo_mp) FROM lotes_producao",
            tolerance=VALUE_TOLERANCE,
        ),
        _estoque_mp(conn, batch_id),
        _estoque_pa(conn, batch_id),
    ]
    for metric in metrics:
        _insert_metric(conn, batch_id, metric)
    return metrics


def reconciliation_status(source_value: float | None, system_value: float | None, tolerance: float) -> tuple[str, float | None]:
    if source_value is None or system_value is None:
        return "missing", None
    difference = system_value - source_value
    if abs(difference) <= tolerance:
        return "ok", difference
    return "attention", difference


def _distinct_pedidos(conn: sqlite3.Connection, batch_id: int) -> dict[str, object]:
    source_ids = {
        value
        for value in (text(row.get("ID_pedido")) for row in _source_rows(conn, batch_id, "GESTÃO_PEDIDOS"))
        if value
    }
    system_count = conn.execute(
        "SELECT COUNT(DISTINCT id_pedido) FROM pedidos_linhas WHERE id_pedido IS NOT NULL AND id_pedido <> ''"
    ).fetchone()[0]
    return _metric(
        metric_name="total_pedidos_distintos",
        source_label="Excel GESTÃO_PEDIDOS.ID_pedido distinto",
        source_value=float(len(source_ids)),
        system_value=float(system_count or 0),
        tolerance=0,
        details={"source_table": "GESTÃO_PEDIDOS", "source_column": "ID_pedido"},
    )


def _sum_metric(
    conn: sqlite3.Connection,
    batch_id: int,
    *,
    metric_name: str,
    source_table: str,
    source_column: str,
    system_sql: str,
    tolerance: float,
    source_filter=None,
) -> dict[str, object]:
    rows = _source_rows(conn, batch_id, source_table)
    if source_filter is not None:
        rows = [row for row in rows if source_filter(row)]
    source_value = _sum_column(rows, source_column)
    system_value = _scalar(conn, system_sql)
    return _metric(
        metric_name=metric_name,
        source_label=f"Excel {source_table}.{source_column}",
        source_value=source_value,
        system_value=system_value,
        tolerance=tolerance,
        details={"source_table": source_table, "source_column": source_column, "system_sql": system_sql},
    )


def _estoque_mp(conn: sqlite3.Connection, batch_id: int) -> dict[str, object]:
    source_value = _sum_column(_source_rows(conn, batch_id, "CONT_ESTOQUEMP"), "SALDO ATUAL")
    system_value = _scalar(
        conn,
        """
        SELECT
            COALESCE((SELECT SUM(quantidade) FROM entradas_mp), 0)
            - COALESCE((SELECT SUM(quantidade) FROM saidas_mp), 0)
        """,
    )
    return _metric(
        metric_name="estoque_mp_saldo",
        source_label="Excel CONT_ESTOQUEMP.SALDO ATUAL",
        source_value=source_value,
        system_value=system_value,
        tolerance=0.1,
        details={"formula": "SUM(entradas_mp.quantidade) - SUM(saidas_mp.quantidade)"},
    )


def _estoque_pa(conn: sqlite3.Connection, batch_id: int) -> dict[str, object]:
    source_value = _sum_column(_source_rows(conn, batch_id, "CONT_ESTOQUE_PA"), "SALDO LITROS")
    system_value = _scalar(
        conn,
        """
        SELECT
            COALESCE((SELECT SUM(quantidade_produzida) FROM lotes_producao), 0)
            - COALESCE((SELECT SUM(quantidade_baixada) FROM saidas_pa), 0)
        """,
    )
    return _metric(
        metric_name="estoque_pa_saldo",
        source_label="Excel CONT_ESTOQUE_PA.SALDO LITROS",
        source_value=source_value,
        system_value=system_value,
        tolerance=0.1,
        details={"formula": "SUM(lotes_producao.quantidade_produzida) - SUM(saidas_pa.quantidade_baixada)"},
    )


def _metric(
    *,
    metric_name: str,
    source_label: str,
    source_value: float | None,
    system_value: float | None,
    tolerance: float,
    details: dict[str, object],
) -> dict[str, object]:
    status, difference = reconciliation_status(source_value, system_value, tolerance)
    return {
        "metric_name": metric_name,
        "source_label": source_label,
        "source_value": source_value,
        "system_value": system_value,
        "difference": difference,
        "tolerance": tolerance,
        "status": status,
        "details": details,
    }


def _insert_metric(conn: sqlite3.Connection, batch_id: int, metric: dict[str, object]) -> None:
    conn.execute(
        """
        INSERT INTO value_reconciliations(
            batch_id, metric_name, source_label, source_value, system_value, difference, tolerance, status, details_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(batch_id, metric_name) DO UPDATE SET
            source_label = excluded.source_label,
            source_value = excluded.source_value,
            system_value = excluded.system_value,
            difference = excluded.difference,
            tolerance = excluded.tolerance,
            status = excluded.status,
            details_json = excluded.details_json
        """,
        (
            batch_id,
            metric["metric_name"],
            metric["source_label"],
            metric["source_value"],
            metric["system_value"],
            metric["difference"],
            metric["tolerance"],
            metric["status"],
            json.dumps(metric["details"], ensure_ascii=False, sort_keys=True),
        ),
    )


def _source_rows(conn: sqlite3.Connection, batch_id: int, table_name: str) -> list[dict[str, object]]:
    rows = conn.execute(
        """
        SELECT sr.payload_json
        FROM source_rows sr
        JOIN source_tables st ON st.id = sr.table_id
        JOIN migration_batches mb ON mb.workbook_id = st.workbook_id
        WHERE mb.id = ? AND st.table_name = ?
        ORDER BY sr.excel_row_number
        """,
        (batch_id, table_name),
    ).fetchall()
    return [json.loads(row["payload_json"]) for row in rows]


def _sum_column(rows: Iterable[dict[str, object]], column: str) -> float:
    total = 0.0
    for row in rows:
        value = number(row.get(column))
        if value is not None:
            total += value
    return total


def _scalar(conn: sqlite3.Connection, sql: str) -> float:
    value = conn.execute(sql).fetchone()[0]
    return float(value or 0)


def _non_empty_order(row: dict[str, object]) -> bool:
    return bool(text(row.get("ID_pedido")) or text(row.get("CLIENTE")) or text(row.get("PRODUTO")))
