from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re
import unittest

from elite_system.services.historical_workbook_sources import (
    CATALOG_PATH,
    SOURCE_CLASSIFICATIONS,
    load_approved_source_catalog,
    resolve_approved_source,
    source_identity_hash,
    source_schema_fingerprint,
)
from elite_system.services.historical_workbook_mapping import classify_reference


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "docs" / "importacao-historica" / "03_MATRIZ_CLASSIFICACAO_269_TABELAS.md"


class HistoricalWorkbookSourceClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = load_approved_source_catalog()
        cls.tables = cls.catalog["tables"]

    def test_catalog_classifies_all_269_tables_exactly_once(self) -> None:
        self.assertEqual(len(self.tables), 269)
        self.assertEqual(len({row["sourceTableId"] for row in self.tables}), 269)
        self.assertEqual(len({row["identityHash"] for row in self.tables}), 269)
        self.assertEqual(len({row["tableRef"] for row in self.tables}), 269)
        self.assertEqual(
            Counter(row["classification"] for row in self.tables),
            Counter(
                {
                    "source_formula": 245,
                    "source_master": 8,
                    "source_transaction": 7,
                    "reconciliation_report": 5,
                    "derived_calculation": 2,
                    "dashboard_or_summary": 2,
                }
            ),
        )

    def test_every_classification_is_allowed_and_complete(self) -> None:
        required = {
            "sheetRef",
            "tableRef",
            "baselineRange",
            "baselineRowCount",
            "baselineColumnCount",
            "canonicalHeaders",
            "classification",
            "ownerDomain",
            "targetEntity",
            "preserveRows",
            "preserveMetadataOnly",
            "normalizeLater",
            "useForReconciliation",
            "justification",
            "duplicateRisk",
            "dependencies",
            "formulaCellCount",
            "calculatedValueCount",
            "schemaFingerprint",
            "schemaDriftDetectable",
            "qualityNotes",
            "affectsOperationalStock",
            "unconfirmedLotsAvailable",
        }
        for row in self.tables:
            self.assertIn(row["classification"], SOURCE_CLASSIFICATIONS)
            self.assertTrue(required.issubset(row), row["tableRef"])
            self.assertTrue(row["ownerDomain"], row["tableRef"])
            self.assertTrue(row["targetEntity"], row["tableRef"])
            self.assertTrue(row["justification"], row["tableRef"])
            self.assertTrue(row["canonicalHeaders"], row["tableRef"])

    def test_primary_sources_have_owner_target_and_raw_preservation(self) -> None:
        primary = {"source_master", "source_transaction", "source_formula"}
        for row in self.tables:
            if row["classification"] not in primary:
                continue
            self.assertTrue(row["ownerDomain"])
            self.assertTrue(row["targetEntity"])
            self.assertTrue(row["preserveRows"])
            self.assertTrue(row["normalizeLater"])
            self.assertFalse(row["preserveMetadataOnly"])

    def test_derived_and_report_sources_never_normalize(self) -> None:
        non_operational = {
            "reconciliation_report",
            "derived_calculation",
            "duplicate_source",
            "dashboard_or_summary",
        }
        for row in self.tables:
            if row["classification"] not in non_operational:
                continue
            self.assertFalse(row["normalizeLater"], row["tableRef"])
            self.assertTrue(row["preserveMetadataOnly"], row["tableRef"])

    def test_historical_stock_and_unconfirmed_lots_never_form_current_balance(self) -> None:
        stock_sources = [row for row in self.tables if row["stockRelevant"]]
        self.assertGreater(len(stock_sources), 0)
        for row in stock_sources:
            self.assertFalse(row["affectsOperationalStock"], row["tableRef"])
            self.assertFalse(row["unconfirmedLotsAvailable"], row["tableRef"])

    def test_row_growth_keeps_classification_but_schema_change_blocks_table(self) -> None:
        sheet = "Aba controlada"
        table = "Tabela controlada"
        headers = ["Campo A", "Campo B"]
        approved = dict(self.tables[0])
        approved.update(
            {
                "sourceTableId": "src_test",
                "identityHash": source_identity_hash(sheet, table),
                "schemaFingerprint": source_schema_fingerprint(sheet, table, headers),
                "classification": "source_master",
            }
        )
        catalog = {"tables": [approved]}

        unchanged = resolve_approved_source(
            sheet_name=sheet,
            table_name=table,
            headers=headers,
            catalog=catalog,
        )
        self.assertFalse(unchanged["schemaDriftDetected"])
        self.assertFalse(unchanged["normalizationBlocked"])

        changed = resolve_approved_source(
            sheet_name=sheet,
            table_name=table,
            headers=[*headers, "Campo C"],
            catalog=catalog,
        )
        self.assertTrue(changed["schemaDriftDetected"])
        self.assertTrue(changed["normalizationBlocked"])

        renamed = resolve_approved_source(
            sheet_name=sheet,
            table_name="Tabela renomeada",
            headers=headers,
            catalog=catalog,
        )
        self.assertIsNone(renamed["classification"])
        self.assertTrue(renamed["normalizationBlocked"])

    def test_versioned_matrix_has_269_sanitized_rows(self) -> None:
        text = MATRIX.read_text(encoding="utf-8")
        rows = re.findall(r"^\| T\d{3} \|", text, flags=re.MULTILINE)
        self.assertEqual(len(rows), 269)
        self.assertNotIn("\ufffd", text)

    def test_catalog_contains_no_raw_sheet_or_table_name_fields(self) -> None:
        payload = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        serialized = json.dumps(payload, ensure_ascii=False)
        self.assertNotIn("\ufffd", serialized)
        for row in payload["tables"]:
            self.assertNotIn("sheetName", row)
            self.assertNotIn("tableName", row)
            self.assertNotIn("rawHeaders", row)

    def test_four_known_column_decisions_remain_pending(self) -> None:
        references = (
            ("LOTES PRODUCAO", "PRODUCAO_LOTES", "Densidade OP"),
            ("LOTES PRODUCAO", "PRODUCAO_LOTES", "Ph"),
            ("RELACAO CLIENTES", "CLIENTES", "CONTATO"),
            ("RELACAO CLIENTES", "CLIENTES", "UF"),
        )
        mappings = [
            classify_reference(
                sheet_name=sheet,
                table_name=table,
                header=header,
                source_kind="structured_table",
                table_headers=[header],
            )
            for sheet, table, header in references
        ]
        self.assertEqual([mapping.status for mapping in mappings], ["pending"] * 4)


if __name__ == "__main__":
    unittest.main()
