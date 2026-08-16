from pathlib import Path
import tempfile
import unittest
import zipfile

from elite_system.services.price_list_xlsx import (
    PriceListXlsxError,
    decimal_to_centavos_por_litro,
    parse_price_list_xlsx,
)


class PriceListXlsxParserTests(unittest.TestCase):
    def test_normalizes_visual_price_columns_without_losing_source_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workbook = Path(temporary_directory) / "lista-preco.xlsx"
            _write_price_workbook(workbook)

            payload = parse_price_list_xlsx(workbook)

        self.assertEqual(payload["file_name"], "lista-preco.xlsx")
        self.assertEqual(len(payload["tabelas"]), 1)
        self.assertEqual(len(payload["linhas_origem"]), 4)
        lines = payload["linhas_preco"]
        self.assertEqual(len(lines), 3)
        self.assertEqual(
            [(line["produto_bruto"], line["prazo_dias"], line["valor_bruto_normalizado"]) for line in lines],
            [
                ("Produto Alfa", 0, "31.255"),
                ("Produto Alfa", 30, "32.50"),
                ("Produto Beta", 0, "1234.567"),
            ],
        )
        self.assertEqual(lines[0]["valor_bruto_texto"], "31,255")
        self.assertEqual(lines[2]["valor_bruto_texto"], "R$ 1.234,567")

    def test_decimal_rounding_is_deterministic_and_never_uses_float(self) -> None:
        self.assertEqual(decimal_to_centavos_por_litro("31,255"), 3126)
        self.assertEqual(decimal_to_centavos_por_litro("1.234,565"), 123457)
        with self.assertRaises(PriceListXlsxError):
            decimal_to_centavos_por_litro("0,004")
        with self.assertRaises(PriceListXlsxError):
            decimal_to_centavos_por_litro("sem preco")

    def test_processes_only_the_first_worksheet_and_reports_the_others(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workbook = Path(temporary_directory) / "duas-abas.xlsx"
            _write_price_workbook(workbook, include_second_sheet=True)
            payload = parse_price_list_xlsx(workbook)

        self.assertEqual(len(payload["tabelas"]), 1)
        self.assertTrue(payload["alertas"])
        self.assertIn("Lista ignorada", payload["alertas"][0])
        self.assertTrue(all(line["source_table_key"] == "sheet:1" for line in payload["linhas_preco"]))
        self.assertEqual(payload["linhas_preco"][0]["celula_preco"], "D2")

    def test_rejects_empty_first_worksheet_without_falling_through_to_the_second(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workbook = Path(temporary_directory) / "primeira-vazia.xlsx"
            _write_price_workbook(workbook, include_second_sheet=True, first_sheet_empty=True)
            with self.assertRaisesRegex(PriceListXlsxError, "primeira worksheet esta vazia"):
                parse_price_list_xlsx(workbook)


def _write_price_workbook(
    destination: Path, *, include_second_sheet: bool = False, first_sheet_empty: bool = False
) -> None:
    rows = [
        ["Grupo", "Produto", "Embalagem", "A vista R$/L", "30 dias"],
        ["Linha A", "Produto Alfa", "Bomba 20 L", "31,255", "32,50"],
        ["Grupo", "Produto", "Embalagem", "A vista R$/L", "30 dias"],
        ["Linha B", "Produto Beta", "Bomba 1 L", "R$ 1.234,567", ""],
    ]
    worksheet_rows = []
    for row_number, row in enumerate(rows, start=1):
        cells = "".join(
            f'<c r="{_column_letter(column)}{row_number}" t="inlineStr"><is><t>{value}</t></is></c>'
            for column, value in enumerate(row, start=1)
            if value
        )
        worksheet_rows.append(f'<row r="{row_number}">{cells}</row>')

    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as package:
        package.writestr(
            "xl/workbook.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Lista geral" sheetId="1" r:id="rId1"/>'
            + ('<sheet name="Lista ignorada" sheetId="2" r:id="rId2"/>' if include_second_sheet else '')
            + '</sheets></workbook>',
        )
        package.writestr(
            "xl/_rels/workbook.xml.rels",
            (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
                + ('<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>' if include_second_sheet else '')
                + '</Relationships>'
            ),
        )
        first_sheet_data = "" if first_sheet_empty else "".join(worksheet_rows)
        package.writestr(
            "xl/worksheets/sheet1.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetData>' + first_sheet_data + '</sheetData></worksheet>',
        )
        if include_second_sheet:
            package.writestr(
                "xl/worksheets/sheet2.xml",
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<sheetData>' + "".join(worksheet_rows) + '</sheetData></worksheet>',
            )


def _column_letter(number: int) -> str:
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(65 + remainder) + result
    return result


if __name__ == "__main__":
    unittest.main()
