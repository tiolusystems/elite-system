from __future__ import annotations

import sqlite3
import tempfile
from pathlib import Path
import unittest

from elite_system.db import init_db
from elite_system.mappings import excel_date, normalize_table_row, number, text
from elite_system.reconciliation import reconciliation_status


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
            self.assertIn("pedidos_linhas", tables)

    def test_value_normalizers(self) -> None:
        self.assertEqual(text("  Cliente X  "), "Cliente X")
        self.assertIsNone(text("#REF!"))
        self.assertEqual(number("1.234,56"), 1234.56)
        self.assertEqual(excel_date(44562), "2022-01-01")

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


if __name__ == "__main__":
    unittest.main()
