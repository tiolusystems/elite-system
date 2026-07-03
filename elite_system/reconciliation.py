from __future__ import annotations

import json
import re
import sqlite3
from typing import Iterable
import unicodedata

from .mappings import number, text


VALUE_TOLERANCE = 0.01
QUANTITY_TOLERANCE = 0.001
STOCK_TOLERANCE = 0.1


def run_value_reconciliations(conn: sqlite3.Connection, batch_id: int) -> list[dict[str, object]]:
    conn.execute("DELETE FROM reconciliation_details WHERE batch_id = ?", (batch_id,))
    conn.execute("DELETE FROM value_reconciliations WHERE batch_id = ?", (batch_id,))

    metrics = [
        _distinct_pedidos(conn, batch_id),
        _sum_metric(
            conn,
            batch_id,
            metric_name="faturamento_total",
            source_table="GESTÃO_PEDIDOS",
            source_column="R$ TOTAL",
            system_table="pedidos_linhas",
            system_column="valor_total",
            tolerance=VALUE_TOLERANCE,
            source_filter=_non_empty_order,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="faturamento_vendas",
            source_table="GESTÃO_PEDIDOS",
            source_column="R$ TOTAL",
            system_table="pedidos_linhas",
            system_column="valor_total",
            system_filter="tipo = 'VENDA'",
            tolerance=VALUE_TOLERANCE,
            source_filter=lambda row: text(row.get("TIPO")) == "VENDA",
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="entradas_mp_quantidade",
            source_table="ENTRADAS_MP",
            source_column="QUANTIDADE",
            system_table="entradas_mp",
            system_column="quantidade",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="entradas_mp_valor",
            source_table="ENTRADAS_MP",
            source_column="VALOR",
            system_table="entradas_mp",
            system_column="valor",
            tolerance=VALUE_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="saidas_mp_quantidade",
            source_table="SAÍDAS_MP",
            source_column="QUANTIDADE",
            system_table="saidas_mp",
            system_column="quantidade",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="saidas_pa_quantidade",
            source_table="SAIDAS_PA",
            source_column="QUANTIDADE BAIXADA",
            system_table="saidas_pa",
            system_column="quantidade_baixada",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="producao_quantidade",
            source_table="PRODUCAO_LOTES",
            source_column="QUANTIDADE PRODUZIDA",
            system_table="lotes_producao",
            system_column="quantidade_produzida",
            tolerance=QUANTITY_TOLERANCE,
        ),
        _sum_metric(
            conn,
            batch_id,
            metric_name="producao_custo_mp",
            source_table="PRODUCAO_LOTES",
            source_column="CUSTO MP",
            system_table="lotes_producao",
            system_column="custo_mp",
            tolerance=VALUE_TOLERANCE,
        ),
        _estoque_mp(conn, batch_id),
        _estoque_pa(conn, batch_id),
    ]
    for metric in metrics:
        _insert_metric(conn, batch_id, metric)
    for detail in _stock_mp_details(conn, batch_id) + _stock_pa_details(conn, batch_id):
        _insert_detail(conn, batch_id, detail)
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
        f"""
        SELECT COUNT(DISTINCT id_pedido)
        FROM pedidos_linhas
        WHERE id_pedido IS NOT NULL
          AND id_pedido <> ''
          AND {_batch_source_row_filter()}
        """,
        (batch_id,),
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
    system_table: str,
    system_column: str,
    tolerance: float,
    source_filter=None,
    system_filter: str | None = None,
) -> dict[str, object]:
    rows = _source_rows(conn, batch_id, source_table)
    if source_filter is not None:
        rows = [row for row in rows if source_filter(row)]
    source_value = _sum_column(rows, source_column)
    system_value = _system_sum(conn, batch_id, system_table, system_column, system_filter)
    details = {
        "source_table": source_table,
        "source_column": source_column,
        "system_table": system_table,
        "system_column": system_column,
        "batch_scoped": True,
    }
    if system_filter:
        details["system_filter"] = system_filter
    return _metric(
        metric_name=metric_name,
        source_label=f"Excel {source_table}.{source_column}",
        source_value=source_value,
        system_value=system_value,
        tolerance=tolerance,
        details=details,
    )


def _estoque_mp(conn: sqlite3.Connection, batch_id: int) -> dict[str, object]:
    source_value = _sum_column(_source_rows(conn, batch_id, "CONT_ESTOQUEMP"), "SALDO ATUAL")
    system_value = _system_stock_balance(
        conn,
        batch_id,
        additions_table="entradas_mp",
        additions_column="quantidade",
        removals_table="saidas_mp",
        removals_column="quantidade",
    )
    return _metric(
        metric_name="estoque_mp_saldo",
        source_label="Excel CONT_ESTOQUEMP.SALDO ATUAL",
        source_value=source_value,
        system_value=system_value,
        tolerance=STOCK_TOLERANCE,
        details={
            "formula": "SUM(entradas_mp.quantidade) - SUM(saidas_mp.quantidade)",
            "batch_scoped": True,
        },
    )


def _estoque_pa(conn: sqlite3.Connection, batch_id: int) -> dict[str, object]:
    source_value = _sum_column(_source_rows(conn, batch_id, "CONT_ESTOQUE_PA"), "SALDO LITROS")
    system_value = _system_stock_balance(
        conn,
        batch_id,
        additions_table="lotes_producao",
        additions_column="quantidade_produzida",
        removals_table="saidas_pa",
        removals_column="quantidade_baixada",
    )
    return _metric(
        metric_name="estoque_pa_saldo",
        source_label="Excel CONT_ESTOQUE_PA.SALDO LITROS",
        source_value=source_value,
        system_value=system_value,
        tolerance=STOCK_TOLERANCE,
        details={
            "formula": "SUM(lotes_producao.quantidade_produzida) - SUM(saidas_pa.quantidade_baixada)",
            "batch_scoped": True,
        },
    )


def _stock_mp_details(conn: sqlite3.Connection, batch_id: int) -> list[dict[str, object]]:
    source = _group_source_sum(
        _source_rows(conn, batch_id, "CONT_ESTOQUEMP"),
        key_columns=("MATÉRIA PRIMA", "MATERIA PRIMA", "PRODUTO", "ITEM"),
        value_column="SALDO ATUAL",
    )
    additions = _group_system_sum(conn, batch_id, "entradas_mp", "materia_prima", "quantidade")
    removals = _group_system_sum(conn, batch_id, "saidas_mp", "materia_prima", "quantidade")
    system = _subtract_groups(additions, removals)
    return _detail_rows(
        metric_name="estoque_mp_saldo_por_materia_prima",
        key_type="materia_prima",
        source=source,
        system=system,
        tolerance=STOCK_TOLERANCE,
        details={"formula": "entradas_mp.quantidade - saidas_mp.quantidade"},
    )


def _stock_pa_details(conn: sqlite3.Connection, batch_id: int) -> list[dict[str, object]]:
    source = _group_source_sum(
        _source_rows(conn, batch_id, "CONT_ESTOQUE_PA"),
        key_columns=("PRODUTO", "NOME PRODUTO", "RELAÇÃO DE PRODUTOS", "ITEM"),
        value_column="SALDO LITROS",
    )
    additions = _group_system_sum(conn, batch_id, "lotes_producao", "produto", "quantidade_produzida")
    removals = _group_system_sum(conn, batch_id, "saidas_pa", "produto", "quantidade_baixada")
    system = _subtract_groups(additions, removals)
    return _detail_rows(
        metric_name="estoque_pa_saldo_por_produto",
        key_type="produto",
        source=source,
        system=system,
        tolerance=STOCK_TOLERANCE,
        details={"formula": "lotes_producao.quantidade_produzida - saidas_pa.quantidade_baixada"},
    )


def _detail_rows(
    *,
    metric_name: str,
    key_type: str,
    source: dict[str, dict[str, object]],
    system: dict[str, dict[str, object]],
    tolerance: float,
    details: dict[str, object],
) -> list[dict[str, object]]:
    rows = []
    for key_norm in sorted(set(source) | set(system)):
        source_item = source.get(key_norm, {"label": key_norm, "value": 0.0})
        system_item = system.get(key_norm, {"label": source_item["label"], "value": 0.0})
        source_value = float(source_item["value"] or 0)
        system_value = float(system_item["value"] or 0)
        status, difference = reconciliation_status(source_value, system_value, tolerance)
        rows.append(
            {
                "metric_name": metric_name,
                "key_type": key_type,
                "key_norm": key_norm,
                "key_label": source_item.get("label") or system_item.get("label") or key_norm,
                "source_value": source_value,
                "system_value": system_value,
                "difference": difference,
                "tolerance": tolerance,
                "status": status,
                "details": {
                    **details,
                    "source_present": key_norm in source,
                    "system_present": key_norm in system,
                },
            }
        )
    return rows


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


def _insert_detail(conn: sqlite3.Connection, batch_id: int, detail: dict[str, object]) -> None:
    conn.execute(
        """
        INSERT INTO reconciliation_details(
            batch_id, metric_name, key_type, key_norm, key_label,
            source_value, system_value, difference, tolerance, status, details_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(batch_id, metric_name, key_type, key_norm) DO UPDATE SET
            key_label = excluded.key_label,
            source_value = excluded.source_value,
            system_value = excluded.system_value,
            difference = excluded.difference,
            tolerance = excluded.tolerance,
            status = excluded.status,
            details_json = excluded.details_json
        """,
        (
            batch_id,
            detail["metric_name"],
            detail["key_type"],
            detail["key_norm"],
            detail["key_label"],
            detail["source_value"],
            detail["system_value"],
            detail["difference"],
            detail["tolerance"],
            detail["status"],
            json.dumps(detail["details"], ensure_ascii=False, sort_keys=True),
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


def _system_sum(
    conn: sqlite3.Connection,
    batch_id: int,
    table_name: str,
    column_name: str,
    extra_filter: str | None = None,
) -> float:
    filters = [_batch_source_row_filter()]
    if extra_filter:
        filters.append(f"({extra_filter})")
    sql = f"SELECT SUM({column_name}) FROM {table_name} WHERE {' AND '.join(filters)}"
    return _scalar(conn, sql, (batch_id,))


def _system_stock_balance(
    conn: sqlite3.Connection,
    batch_id: int,
    *,
    additions_table: str,
    additions_column: str,
    removals_table: str,
    removals_column: str,
) -> float:
    additions = _system_sum(conn, batch_id, additions_table, additions_column)
    removals = _system_sum(conn, batch_id, removals_table, removals_column)
    return additions - removals


def _group_source_sum(
    rows: Iterable[dict[str, object]],
    *,
    key_columns: tuple[str, ...],
    value_column: str,
) -> dict[str, dict[str, object]]:
    grouped: dict[str, dict[str, object]] = {}
    for row in rows:
        key_label = _first_text(row, key_columns)
        value = number(row.get(value_column))
        if key_label is None or value is None:
            continue
        _add_group_value(grouped, key_label, value)
    return grouped


def _group_system_sum(
    conn: sqlite3.Connection,
    batch_id: int,
    table_name: str,
    key_column: str,
    value_column: str,
) -> dict[str, dict[str, object]]:
    rows = conn.execute(
        f"""
        SELECT {key_column} AS key_label, SUM({value_column}) AS total
        FROM {table_name}
        WHERE {key_column} IS NOT NULL
          AND {key_column} <> ''
          AND {_batch_source_row_filter()}
        GROUP BY {key_column}
        """,
        (batch_id,),
    ).fetchall()
    grouped: dict[str, dict[str, object]] = {}
    for row in rows:
        key_label = text(row["key_label"])
        if key_label:
            _add_group_value(grouped, key_label, float(row["total"] or 0))
    return grouped


def _subtract_groups(
    additions: dict[str, dict[str, object]],
    removals: dict[str, dict[str, object]],
) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for key_norm in set(additions) | set(removals):
        add = additions.get(key_norm, {"label": key_norm, "value": 0.0})
        remove = removals.get(key_norm, {"label": add["label"], "value": 0.0})
        label = add.get("label") or remove.get("label") or key_norm
        result[key_norm] = {"label": label, "value": float(add["value"] or 0) - float(remove["value"] or 0)}
    return result


def _add_group_value(grouped: dict[str, dict[str, object]], key_label: str, value: float) -> None:
    key_norm = _norm_key(key_label)
    current = grouped.setdefault(key_norm, {"label": key_label, "value": 0.0})
    current["value"] = float(current["value"] or 0) + value


def _first_text(row: dict[str, object], columns: tuple[str, ...]) -> str | None:
    for column in columns:
        value = text(row.get(column))
        if value:
            return value
    return None


def _norm_key(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_text = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", ascii_text).strip().casefold()


def _scalar(conn: sqlite3.Connection, sql: str, params: tuple[object, ...] = ()) -> float:
    value = conn.execute(sql, params).fetchone()[0]
    return float(value or 0)


def _batch_source_row_filter() -> str:
    return """
    source_row_id IN (
        SELECT sr.id
        FROM source_rows sr
        JOIN source_tables st ON st.id = sr.table_id
        JOIN migration_batches mb ON mb.workbook_id = st.workbook_id
        WHERE mb.id = ?
    )
    """


def _non_empty_order(row: dict[str, object]) -> bool:
    return bool(text(row.get("ID_pedido")) or text(row.get("CLIENTE")) or text(row.get("PRODUTO")))
