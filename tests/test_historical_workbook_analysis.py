from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from xml.sax.saxutils import escape
import zipfile

from elite_system.services.historical_workbook import WorkbookAnalysisError, analyze_historical_workbook


ROOT = Path(__file__).resolve().parents[1]


class HistoricalWorkbookAnalysisTests(unittest.TestCase):
    def test_valid_workbook_returns_only_structural_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbook = Path(temporary) / "historico.xlsx"
            create_synthetic_workbook(workbook, sheet_count=2, table_count=3, structured_columns=20, outside_columns=7)

            result = analyze_historical_workbook(workbook, modified_at="2026-07-13T10:00:00.000Z")

            self.assertTrue(result["readOnly"])
            self.assertEqual(result["summary"]["sheetCount"], 2)
            self.assertEqual(result["summary"]["tableCount"], 3)
            self.assertEqual(result["summary"]["referenceCount"], 27)
            self.assertEqual(len(result["file"]["sha256"]), 64)
            self.assertEqual(len(result["reportRows"]), 27)
            self.assertNotIn("cellValues", str(result))

    def test_invalid_extension_is_rejected_before_reading(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbook = Path(temporary) / "historico.xls"
            workbook.write_bytes(b"not-an-xlsx")
            with self.assertRaises(WorkbookAnalysisError) as raised:
                analyze_historical_workbook(workbook)
            self.assertEqual(raised.exception.code, "invalid_extension")

    def test_missing_and_corrupt_workbooks_have_stable_error_codes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "missing.xlsx"
            with self.assertRaises(WorkbookAnalysisError) as missing_error:
                analyze_historical_workbook(missing)
            self.assertEqual(missing_error.exception.code, "file_not_found")

            corrupt = Path(temporary) / "corrupt.xlsx"
            corrupt.write_bytes(b"PK-not-a-valid-workbook")
            with self.assertRaises(WorkbookAnalysisError) as corrupt_error:
                analyze_historical_workbook(corrupt)
            self.assertEqual(corrupt_error.exception.code, "corrupt_workbook")

    def test_reference_profile_155_269_3095_has_no_omitted_column(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbook = Path(temporary) / "perfil-integral.xlsx"
            create_synthetic_workbook(
                workbook,
                sheet_count=155,
                table_count=269,
                structured_columns=2160,
                outside_columns=935,
            )

            result = analyze_historical_workbook(workbook)
            summary = result["summary"]
            self.assertEqual(summary["sheetCount"], 155)
            self.assertEqual(summary["tableCount"], 269)
            self.assertEqual(summary["referenceCount"], 3095)
            self.assertTrue(summary["profileMatchesReference"])
            self.assertEqual(sum(summary["statusCounts"].values()), 3095)
            self.assertEqual(len(result["reportRows"]), 3095)
            self.assertTrue(all(row["status"] for row in result["reportRows"]))
            self.assertTrue(all(row["target"] for row in result["reportRows"]))
            self.assertTrue(all(row["rule"] for row in result["reportRows"]))

    def test_analyzer_has_no_postgresql_write_dependency(self) -> None:
        sources = "\n".join(
            (ROOT / relative).read_text(encoding="utf-8").casefold()
            for relative in (
                "elite_system/excel_reader.py",
                "elite_system/services/historical_workbook.py",
                "elite_system/services/historical_workbook_mapping.py",
            )
        )
        for forbidden in ("psycopg", "supabase", "insert into", "update ", "delete from", "service_role"):
            self.assertNotIn(forbidden, sources)

    def test_cli_emits_machine_readable_error_for_corrupt_workbook(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbook = Path(temporary) / "corrupt.xlsx"
            workbook.write_bytes(b"corrupt")
            completed = subprocess.run(
                [
                    str(Path(__import__("sys").executable)),
                    "-m",
                    "elite_system.services.historical_workbook",
                    "--file",
                    str(workbook),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 2)
            self.assertIn('"code": "corrupt_workbook"', completed.stdout)

    def test_cli_output_is_ascii_safe_and_round_trips_unicode_labels(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbook = Path(temporary) / "historico.xlsx"
            create_synthetic_workbook(
                workbook,
                sheet_count=1,
                table_count=1,
                structured_columns=1,
                outside_columns=0,
                sheet_name_prefix="Produção",
            )
            completed = subprocess.run(
                [
                    str(Path(__import__("sys").executable)),
                    "-m",
                    "elite_system.services.historical_workbook",
                    "--file",
                    str(workbook),
                ],
                cwd=ROOT,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0)
            self.assertTrue(completed.stdout.isascii())
            payload = json.loads(completed.stdout.decode("ascii"))
            self.assertEqual(payload["analysis"]["sheets"][0]["name"], "Produção 1")


def create_synthetic_workbook(
    destination: Path,
    *,
    sheet_count: int,
    table_count: int,
    structured_columns: int,
    outside_columns: int,
    sheet_name_prefix: str = "Aba",
) -> None:
    if table_count < sheet_count:
        raise ValueError("Each synthetic sheet needs at least one table.")
    tables_per_sheet = [1] * sheet_count
    for index in range(table_count - sheet_count):
        tables_per_sheet[index % sheet_count] += 1
    columns_per_table = _distribute(structured_columns, table_count)
    outside_per_sheet = _distribute(outside_columns, sheet_count)

    workbook_sheets: list[str] = []
    workbook_relationships: list[str] = []
    table_id = 0
    table_column_offset = 0
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for sheet_index in range(1, sheet_count + 1):
            sheet_name = f"{sheet_name_prefix} {sheet_index}"
            workbook_sheets.append(
                f'<sheet name="{escape(sheet_name)}" sheetId="{sheet_index}" r:id="rId{sheet_index}"/>'
            )
            workbook_relationships.append(
                f'<Relationship Id="rId{sheet_index}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{sheet_index}.xml"/>'
            )
            cells = [
                f'<c r="{column_letter(column)}1" t="inlineStr"><is><t>metadado</t></is></c>'
                for column in range(1, outside_per_sheet[sheet_index - 1] + 1)
            ]
            table_parts: list[str] = []
            table_relationships: list[str] = []
            start_column = 1
            for local_table_index in range(tables_per_sheet[sheet_index - 1]):
                table_id += 1
                column_count = columns_per_table[table_column_offset]
                table_column_offset += 1
                end_column = start_column + column_count - 1
                ref = f"{column_letter(start_column)}2:{column_letter(end_column)}3"
                for column in range(start_column, end_column + 1):
                    cells.append(f'<c r="{column_letter(column)}3"><v>{column}</v></c>')
                headers = "".join(
                    f'<tableColumn id="{position}" name="Campo {table_id}-{position}"/>'
                    for position in range(1, column_count + 1)
                )
                package.writestr(
                    f"xl/tables/table{table_id}.xml",
                    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                    '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                    f'id="{table_id}" name="Tabela{table_id}" displayName="Tabela{table_id}" ref="{ref}">'
                    f'<tableColumns count="{column_count}">{headers}</tableColumns></table>',
                )
                relation_id = f"rId{local_table_index + 1}"
                table_parts.append(f'<tablePart r:id="{relation_id}"/>')
                table_relationships.append(
                    f'<Relationship Id="{relation_id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table" Target="../tables/table{table_id}.xml"/>'
                )
                start_column = end_column + 2

            max_column = max(start_column - 2, outside_per_sheet[sheet_index - 1], 1)
            worksheet = (
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                f'<dimension ref="A1:{column_letter(max_column)}3"/><sheetData><row r="1">{"".join(cells[:outside_per_sheet[sheet_index - 1]])}</row>'
                f'<row r="3">{"".join(cells[outside_per_sheet[sheet_index - 1]:])}</row></sheetData>'
                f'<tableParts count="{len(table_parts)}">{"".join(table_parts)}</tableParts></worksheet>'
            )
            package.writestr(f"xl/worksheets/sheet{sheet_index}.xml", worksheet)
            package.writestr(
                f"xl/worksheets/_rels/sheet{sheet_index}.xml.rels",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                f'{"".join(table_relationships)}</Relationships>',
            )

        package.writestr(
            "xl/workbook.xml",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            f'<sheets>{"".join(workbook_sheets)}</sheets></workbook>',
        )
        package.writestr(
            "xl/_rels/workbook.xml.rels",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'{"".join(workbook_relationships)}</Relationships>',
        )


def _distribute(total: int, buckets: int) -> list[int]:
    quotient, remainder = divmod(total, buckets)
    return [quotient + (1 if index < remainder else 0) for index in range(buckets)]


def column_letter(number: int) -> str:
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(65 + remainder) + result
    return result


if __name__ == "__main__":
    unittest.main()
