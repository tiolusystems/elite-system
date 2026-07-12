from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from elite_system.db import init_db
from elite_system.services.historical_mp import analyze_historical_mp


class HistoricalMpAnalysisTests(unittest.TestCase):
    def test_analyzer_is_read_only_and_preserves_cost_components(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            batch_id = _seed_history(db_path)
            before = _row_counts(db_path)

            result = analyze_historical_mp(db_path, batch_id)

            self.assertEqual(result["mode"], "read_only_dry_run")
            self.assertEqual(result["counts"]["cadastros_mp"], 2)
            self.assertEqual(result["counts"]["entradas_mp"], 2)
            self.assertEqual(result["counts"]["saidas_mp"], 1)
            self.assertEqual(result["quantities"]["saldo_derivado"], 13.0)
            self.assertEqual(result["acquisition_values"]["valor_materia_prima"], 200.0)
            self.assertEqual(result["acquisition_values"]["frete"], 20.0)
            self.assertEqual(result["acquisition_values"]["difal_icms"], 12.0)
            self.assertEqual(result["acquisition_values"]["custo_total_legado"], 232.0)
            self.assertEqual(result["acquisition_values"]["diferenca_total_legado"], 0.0)
            self.assertEqual(before, _row_counts(db_path))

    def test_mapping_prefers_unique_code_and_never_silently_unifies_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)
            batch_id = _seed_history(db_path)

            result = analyze_historical_mp(db_path, batch_id)
            identities = {row["nome_legado"]: row for row in result["identities"]}

            self.assertEqual(identities["Acido A"]["mapping"]["status"], "suggested")
            self.assertEqual(identities["Acido A"]["mapping"]["method"], "exact_legacy_code")
            self.assertEqual(identities["Acido A"]["mapping"]["materia_prima_id"], 1)
            self.assertEqual(identities["Base B"]["mapping"]["status"], "new_required")
            self.assertEqual(result["data_quality"]["codigo_usado_como_nome"], 1)

    def test_missing_batch_and_invalid_limit_are_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "elite.sqlite"
            init_db(db_path)

            self.assertEqual(analyze_historical_mp(db_path, 999)["status"], "missing")
            with self.assertRaisesRegex(ValueError, "identity_limit"):
                analyze_historical_mp(db_path, identity_limit=0)


def _seed_history(db_path: Path) -> int:
    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            "INSERT INTO source_workbooks(source_path, file_name, sha256, size_bytes) VALUES (?, ?, ?, ?)",
            ("fixture-historico-mp.xlsx", "fixture-historico-mp.xlsx", "fixture-hash", 10),
        )
        workbook_id = int(conn.execute("SELECT id FROM source_workbooks").fetchone()[0])
        batch_id = int(conn.execute("INSERT INTO migration_batches(workbook_id) VALUES (?)", (workbook_id,)).lastrowid)

        mp_a = _source_row(conn, workbook_id, "CADASTRO_MATERIA_PRIMA", 2, {"id_sku_mp": "LEG-A", "MP": "Acido A"})
        mp_b = _source_row(conn, workbook_id, "CADASTRO_MATERIA_PRIMA", 3, {"id_sku_mp": "Base B", "MP": "Base B"})
        entry_a = _source_row(conn, workbook_id, "ENTRADAS_MP", 4, {"MP": "Acido A", "Dif. ICMS": 12})
        entry_b = _source_row(conn, workbook_id, "ENTRADAS_MP", 5, {"MP": "Base B", "Dif. ICMS": 0})
        issue_a = _source_row(conn, workbook_id, "SAIDAS_MP", 6, {"MP": "Acido A", "LOTE OP": "OP-1"})

        conn.execute(
            """
            INSERT INTO materias_primas(source_row_id, nome, sku, unidade_adotada, payload_json)
            VALUES (?, 'Acido A', 'LEG-A', 'kg', '{}'), (?, 'Base B', 'Base B', 'kg', '{}')
            """,
            (mp_a, mp_b),
        )
        conn.execute(
            """
            INSERT INTO entradas_mp(
                source_row_id, materia_prima, lote, quantidade, unidade_padrao,
                frete, dif_icms, valor, custo_total, payload_json
            ) VALUES
              (?, 'Acido A', 'LA-1', 10, 'kg', 15, 12, 150, 177, '{}'),
              (?, 'Base B', NULL, 5, 'kg', 5, 0, 50, 55, '{}')
            """,
            (entry_a, entry_b),
        )
        conn.execute(
            """
            INSERT INTO saidas_mp(source_row_id, materia_prima, quantidade, lote, lote_op, nome_produto, payload_json)
            VALUES (?, 'Acido A', 2, 'LA-1', 'OP-1', 'Produto A', '{}')
            """,
            (issue_a,),
        )
        conn.execute(
            """
            INSERT INTO cad_materias_primas(codigo_legado, sku_corrigido, nome, nome_norm, unidade_base_estoque)
            VALUES ('LEG-A', 'MP-0001', 'Acido A', 'acido a', 'kg')
            """
        )
        conn.commit()
        return batch_id
    finally:
        conn.close()


def _source_row(
    conn: sqlite3.Connection,
    workbook_id: int,
    table_name: str,
    excel_row: int,
    payload: dict[str, object],
) -> int:
    table_id = conn.execute(
        """
        INSERT INTO source_tables(
          workbook_id, sheet_name, table_name, ref, header_row,
          data_first_row, data_last_row, column_count, row_count
        ) VALUES (?, 'Planilha', ?, ?, 1, 2, 6, 2, 1)
        """,
        (workbook_id, table_name, f"A{excel_row}:B{excel_row}"),
    ).lastrowid
    return int(
        conn.execute(
            """
            INSERT INTO source_rows(table_id, excel_row_number, row_index, row_hash, payload_json)
            VALUES (?, ?, 1, ?, ?)
            """,
            (table_id, excel_row, f"hash-{excel_row}", json.dumps(payload)),
        ).lastrowid
    )


def _row_counts(db_path: Path) -> tuple[int, int, int, int]:
    conn = sqlite3.connect(db_path)
    try:
        return tuple(
            int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
            for table in ("migration_batches", "materias_primas", "entradas_mp", "saidas_mp")
        )
    finally:
        conn.close()


if __name__ == "__main__":
    unittest.main()
