from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import posixpath
import re
import zipfile
import xml.etree.ElementTree as ET


NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
}
RID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
CELL_RE = re.compile(r"^\$?([A-Z]+)\$?([0-9]+)$")
EXCEL_ERROR_VALUES = {
    "#REF!",
    "#N/A",
    "#VALUE!",
    "#DIV/0!",
    "#NAME?",
    "#NUM!",
    "#NULL!",
}


@dataclass(frozen=True)
class ExcelRow:
    excel_row_number: int
    row_index: int
    values: dict[str, object]
    formulas: dict[str, str]


@dataclass(frozen=True)
class ExcelTable:
    sheet_name: str
    table_name: str
    ref: str
    headers: list[str]
    header_row: int
    data_first_row: int
    data_last_row: int
    rows: list[ExcelRow]


@dataclass(frozen=True)
class ExcelColumnStructure:
    column: str
    nonempty_cells: int
    formula_cells: int
    error_cells: int
    first_row: int
    last_row: int
    outside_table_cells: int


@dataclass(frozen=True)
class ExcelTableStructure:
    table_name: str
    ref: str
    headers: list[str]
    header_row: int
    data_first_row: int
    data_last_row: int
    first_column: str
    last_column: str
    row_count: int
    populated_row_count: int
    warnings: list[str]


@dataclass(frozen=True)
class ExcelSheetStructure:
    order: int
    sheet_name: str
    state: str
    dimension: str
    nonempty_rows: int
    nonempty_cells: int
    formula_cells: int
    error_cells: int
    columns: list[ExcelColumnStructure]
    tables: list[ExcelTableStructure]
    warnings: list[str]


@dataclass(frozen=True)
class ExcelWorkbookStructure:
    sheet_count: int
    table_count: int
    named_range_count: int
    sheets: list[ExcelSheetStructure]


def extract_tables(workbook_path: str | Path, table_names: set[str] | None = None) -> list[ExcelTable]:
    path = Path(workbook_path)
    with zipfile.ZipFile(path) as zf:
        shared_strings = _load_shared_strings(zf)
        workbook = _xml(zf, "xl/workbook.xml")
        workbook_rels = _rels(zf, "xl/_rels/workbook.xml.rels")
        tables: list[ExcelTable] = []

        for sheet in workbook.findall("main:sheets/main:sheet", NS):
            sheet_name = sheet.attrib["name"]
            rel_id = sheet.attrib[RID]
            target = workbook_rels[rel_id]["Target"]
            sheet_xml = _workbook_target(target)
            sheet_rels = _rels(zf, _rels_path(sheet_xml))
            table_paths = _table_paths_for_sheet(sheet_xml, sheet_rels, zf)
            if not table_paths:
                continue

            cells = _read_sheet_cells(zf, sheet_xml, shared_strings)
            for table_path in table_paths:
                table = _read_table(zf, table_path)
                if table_names is not None and table["name"] not in table_names:
                    continue
                tables.append(_materialize_table(sheet_name, table, cells))

        return tables


def inspect_workbook_structure(workbook_path: str | Path) -> ExcelWorkbookStructure:
    """Read workbook structure without returning business cell values."""

    path = Path(workbook_path)
    with zipfile.ZipFile(path) as zf:
        required_parts = {"xl/workbook.xml", "xl/_rels/workbook.xml.rels"}
        missing_parts = sorted(required_parts.difference(zf.namelist()))
        if missing_parts:
            raise ValueError(f"Invalid XLSX package; missing: {', '.join(missing_parts)}")

        shared_strings = _load_shared_strings(zf)
        workbook = _xml(zf, "xl/workbook.xml")
        workbook_rels = _rels(zf, "xl/_rels/workbook.xml.rels")
        named_ranges = workbook.findall("main:definedNames/main:definedName", NS)
        sheets: list[ExcelSheetStructure] = []

        for order, sheet in enumerate(workbook.findall("main:sheets/main:sheet", NS), start=1):
            sheet_name = sheet.attrib["name"]
            rel_id = sheet.attrib.get(RID)
            if not rel_id or rel_id not in workbook_rels:
                raise ValueError(f"Worksheet relationship not found: {sheet_name}")
            sheet_xml = _workbook_target(workbook_rels[rel_id]["Target"])
            if sheet_xml not in zf.namelist():
                raise ValueError(f"Worksheet part not found: {sheet_name}")

            sheet_root = _xml(zf, sheet_xml)
            sheet_rels = _rels(zf, _rels_path(sheet_xml))
            table_paths = _table_paths_for_sheet(sheet_xml, sheet_rels, zf)
            cells = _read_sheet_cells(zf, sheet_xml, shared_strings)
            table_structures: list[ExcelTableStructure] = []
            table_bounds: list[tuple[int, int, int, int]] = []

            for table_path in table_paths:
                table = _read_table(zf, table_path)
                min_col, min_row, max_col, max_row = _range_bounds(str(table["ref"]))
                headers = [str(value) for value in table["columns"]]
                populated_rows = sum(
                    any(
                        f"{_column_letter(column_number)}{row_number}" in cells
                        for column_number in range(min_col, max_col + 1)
                    )
                    for row_number in range(min_row + 1, max_row + 1)
                )
                warnings: list[str] = []
                normalized_headers = [header.strip().casefold() for header in headers]
                if len(set(normalized_headers)) != len(normalized_headers):
                    warnings.append("Cabecalhos duplicados na tabela.")
                if max_row <= min_row:
                    warnings.append("Tabela sem linhas de dados declaradas.")

                table_structures.append(
                    ExcelTableStructure(
                        table_name=str(table["name"]),
                        ref=str(table["ref"]),
                        headers=headers,
                        header_row=min_row,
                        data_first_row=min_row + 1,
                        data_last_row=max_row,
                        first_column=_column_letter(min_col),
                        last_column=_column_letter(max_col),
                        row_count=max(max_row - min_row, 0),
                        populated_row_count=populated_rows,
                        warnings=warnings,
                    )
                )
                table_bounds.append((min_col, min_row, max_col, max_row))

            column_stats: dict[str, dict[str, int]] = {}
            nonempty_rows: set[int] = set()
            total_formula_cells = 0
            total_error_cells = 0
            for address, (value, formula) in cells.items():
                column, row_number = _cell_parts(address)
                column_number = _column_number(column)
                nonempty_rows.add(row_number)
                stats = column_stats.setdefault(
                    column,
                    {
                        "nonempty_cells": 0,
                        "formula_cells": 0,
                        "error_cells": 0,
                        "first_row": row_number,
                        "last_row": row_number,
                        "outside_table_cells": 0,
                    },
                )
                stats["nonempty_cells"] += 1
                stats["first_row"] = min(stats["first_row"], row_number)
                stats["last_row"] = max(stats["last_row"], row_number)
                if formula is not None:
                    stats["formula_cells"] += 1
                    total_formula_cells += 1
                if isinstance(value, str) and value in EXCEL_ERROR_VALUES:
                    stats["error_cells"] += 1
                    total_error_cells += 1
                if not any(
                    min_col <= column_number <= max_col and min_row <= row_number <= max_row
                    for min_col, min_row, max_col, max_row in table_bounds
                ):
                    stats["outside_table_cells"] += 1

            columns = [
                ExcelColumnStructure(column=column, **stats)
                for column, stats in sorted(column_stats.items(), key=lambda item: _column_number(item[0]))
            ]
            dimension_node = sheet_root.find("main:dimension", NS)
            dimension = dimension_node.attrib.get("ref", "A1") if dimension_node is not None else "A1"
            sheet_warnings: list[str] = []
            if not table_structures:
                sheet_warnings.append("Aba sem tabela estruturada; metadados externos serao preservados.")
            if not cells:
                sheet_warnings.append("Aba sem celulas preenchidas.")

            sheets.append(
                ExcelSheetStructure(
                    order=order,
                    sheet_name=sheet_name,
                    state=sheet.attrib.get("state", "visible"),
                    dimension=dimension,
                    nonempty_rows=len(nonempty_rows),
                    nonempty_cells=len(cells),
                    formula_cells=total_formula_cells,
                    error_cells=total_error_cells,
                    columns=columns,
                    tables=table_structures,
                    warnings=sheet_warnings,
                )
            )

        return ExcelWorkbookStructure(
            sheet_count=len(sheets),
            table_count=sum(len(sheet.tables) for sheet in sheets),
            named_range_count=len(named_ranges),
            sheets=sheets,
        )


def _xml(zf: zipfile.ZipFile, path: str) -> ET.Element:
    return ET.fromstring(zf.read(path))


def _rels(zf: zipfile.ZipFile, path: str) -> dict[str, dict[str, str]]:
    if path not in zf.namelist():
        return {}
    root = _xml(zf, path)
    return {rel.attrib["Id"]: rel.attrib for rel in root.findall("rel:Relationship", NS)}


def _workbook_target(target: str) -> str:
    if target.startswith("/"):
        return target.lstrip("/")
    if target.startswith("xl/"):
        return target
    return posixpath.normpath("xl/" + target)


def _rels_path(part_path: str) -> str:
    return posixpath.join(posixpath.dirname(part_path), "_rels", posixpath.basename(part_path) + ".rels")


def _part_target(base_part: str, target: str) -> str:
    return posixpath.normpath(posixpath.join(posixpath.dirname(base_part), target))


def _load_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = _xml(zf, "xl/sharedStrings.xml")
    values: list[str] = []
    for item in root.findall("main:si", NS):
        parts = [node.text or "" for node in item.iter(f"{{{NS['main']}}}t")]
        values.append("".join(parts))
    return values


def _table_paths_for_sheet(
    sheet_xml: str, sheet_rels: dict[str, dict[str, str]], zf: zipfile.ZipFile
) -> list[str]:
    sheet_root = _xml(zf, sheet_xml)
    paths: list[str] = []
    for part in sheet_root.findall("main:tableParts/main:tablePart", NS):
        rel_id = part.attrib.get(RID)
        if rel_id and rel_id in sheet_rels:
            paths.append(_part_target(sheet_xml, sheet_rels[rel_id]["Target"]))
    return paths


def _read_table(zf: zipfile.ZipFile, table_path: str) -> dict[str, object]:
    root = _xml(zf, table_path)
    columns = [
        column.attrib.get("name", f"Column{index}")
        for index, column in enumerate(root.findall("main:tableColumns/main:tableColumn", NS), start=1)
    ]
    return {
        "name": root.attrib["name"],
        "display_name": root.attrib.get("displayName"),
        "ref": root.attrib["ref"],
        "columns": columns,
    }


def _read_sheet_cells(
    zf: zipfile.ZipFile, sheet_xml: str, shared_strings: list[str]
) -> dict[str, tuple[object, str | None]]:
    root = _xml(zf, sheet_xml)
    cells: dict[str, tuple[object, str | None]] = {}
    for cell in root.findall(".//main:c", NS):
        address = cell.attrib.get("r")
        if not address:
            continue
        value, formula = _cell_value(cell, shared_strings)
        if value is not None or formula is not None:
            cells[address.replace("$", "")] = (value, formula)
    return cells


def _cell_value(cell: ET.Element, shared_strings: list[str]) -> tuple[object, str | None]:
    cell_type = cell.attrib.get("t")
    formula_node = cell.find("main:f", NS)
    value_node = cell.find("main:v", NS)

    formula = formula_node.text if formula_node is not None else None
    if formula_node is not None:
        if value_node is not None:
            return _coerce_scalar(value_node.text), formula or ""
        return None, formula or ""

    if cell_type == "s" and value_node is not None:
        try:
            return shared_strings[int(value_node.text or "0")], None
        except (ValueError, IndexError):
            return value_node.text, None

    if cell_type == "inlineStr":
        parts = [node.text or "" for node in cell.iter(f"{{{NS['main']}}}t")]
        return "".join(parts), None

    if value_node is not None:
        return _coerce_scalar(value_node.text), None
    return None, None


def _coerce_scalar(value: str | None) -> object:
    if value is None:
        return None
    if value in EXCEL_ERROR_VALUES:
        return value
    try:
        if "." in value or "E" in value.upper():
            return float(value)
        return int(value)
    except ValueError:
        return value


def _materialize_table(sheet_name: str, table: dict[str, object], cells: dict[str, tuple[object, str | None]]) -> ExcelTable:
    min_col, min_row, max_col, max_row = _range_bounds(str(table["ref"]))
    headers = list(table["columns"])
    rows: list[ExcelRow] = []

    for row_number in range(min_row + 1, max_row + 1):
        values: dict[str, object] = {}
        formulas: dict[str, str] = {}
        for offset, column_number in enumerate(range(min_col, max_col + 1)):
            if offset >= len(headers):
                break
            header = headers[offset]
            address = f"{_column_letter(column_number)}{row_number}"
            value, formula = cells.get(address, (None, None))
            values[header] = value
            if formula is not None:
                formulas[header] = formula
        rows.append(
            ExcelRow(
                excel_row_number=row_number,
                row_index=row_number - min_row,
                values=values,
                formulas=formulas,
            )
        )

    return ExcelTable(
        sheet_name=sheet_name,
        table_name=str(table["name"]),
        ref=str(table["ref"]),
        headers=headers,
        header_row=min_row,
        data_first_row=min_row + 1,
        data_last_row=max_row,
        rows=rows,
    )


def _range_bounds(ref: str) -> tuple[int, int, int, int]:
    start, end = ref.split(":") if ":" in ref else (ref, ref)
    start_col, start_row = _cell_parts(start)
    end_col, end_row = _cell_parts(end)
    return _column_number(start_col), start_row, _column_number(end_col), end_row


def _cell_parts(address: str) -> tuple[str, int]:
    match = CELL_RE.match(address.replace("$", ""))
    if not match:
        raise ValueError(f"Invalid cell address: {address}")
    return match.group(1), int(match.group(2))


def _column_number(column: str) -> int:
    value = 0
    for char in column:
        value = value * 26 + ord(char) - 64
    return value


def _column_letter(number: int) -> str:
    letters = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        letters = chr(65 + remainder) + letters
    return letters
