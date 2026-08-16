from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import hashlib
import json
from pathlib import Path
import re

from elite_system.excel_reader import ExcelWorksheetRow, extract_worksheet_rows, inspect_workbook_structure
from elite_system.services.historical_workbook_mapping import normalize_label


PRICE_HEADER = re.compile(r"(?:r\$\s*/?\s*l\s*)?(\d+)\s*(?:dias?|d)?$")
PRODUCT_HEADERS = {"produto", "produtos", "descricao produto", "produto descricao"}
PACKAGE_HEADERS = {"embalagem", "embalagens", "apresentacao", "apresentacoes"}
GROUP_HEADERS = {"grupo", "grupo produto", "grupo de produto"}


class PriceListXlsxError(ValueError):
    pass


@dataclass(frozen=True)
class _SheetLayout:
    header_row: ExcelWorksheetRow
    product_column: str
    package_column: str
    group_column: str | None
    price_columns: dict[str, int]


def parse_price_list_xlsx(workbook_path: str | Path) -> dict[str, object]:
    """Build the RPC payload for visual XLSX price lists without database writes."""

    path = Path(workbook_path)
    if not path.is_file() or path.suffix.casefold() != ".xlsx":
        raise PriceListXlsxError("Arquivo XLSX valido e obrigatorio.")

    structure = inspect_workbook_structure(path)
    if not structure.sheets:
        raise PriceListXlsxError("O workbook nao possui worksheets.")
    first_worksheet = structure.sheets[0]
    if first_worksheet.nonempty_rows == 0:
        raise PriceListXlsxError("A primeira worksheet esta vazia e nao pode ser importada.")

    rows = extract_worksheet_rows(path)
    by_sheet: dict[tuple[int, str], list[ExcelWorksheetRow]] = {}
    for row in rows:
        by_sheet.setdefault((row.sheet_order, row.sheet_name), []).append(row)

    first_sheet_key = (first_worksheet.order, first_worksheet.sheet_name)
    sheet_rows = by_sheet.get(first_sheet_key)
    if not sheet_rows:
        raise PriceListXlsxError("A primeira worksheet nao possui linhas utilizaveis.")
    order, sheet_name = first_sheet_key
    layout = _find_layout(sheet_rows)
    if layout is None:
        raise PriceListXlsxError("A primeira worksheet nao possui cabecalho de lista de preco reconhecido.")

    ignored_sheets = [sheet.sheet_name for sheet in structure.sheets[1:]]
    alerts = (
        [
            "Somente a primeira worksheet foi processada; worksheets adicionais foram ignoradas: "
            + ", ".join(ignored_sheets)
        ]
        if ignored_sheets
        else []
    )
    tables: list[dict[str, object]] = []
    source_rows: list[dict[str, object]] = []
    price_lines: list[dict[str, object]] = []
    table_key = f"sheet:{order}"
    headers = _header_values(layout.header_row)
    last_column = max((column for row in sheet_rows for column in row.values), key=_column_number, default="A")
    tables.append(
        {
            "table_key": table_key,
            "sheet_name": sheet_name,
            "table_name": f"PRICE_LIST_SHEET_{order}",
            "ref": f"A{layout.header_row.excel_row_number}:{last_column}{sheet_rows[-1].excel_row_number}",
            "header_row": layout.header_row.excel_row_number,
            "data_first_row": layout.header_row.excel_row_number + 1,
            "data_last_row": sheet_rows[-1].excel_row_number,
            "column_count": len(headers),
            "row_count": len(sheet_rows),
            "metadata_json": {
                "headers": headers,
                "worksheets_ignoradas": ignored_sheets,
                "alertas": alerts,
            },
        }
    )
    for row in sheet_rows:
        row_key = f"{table_key}:row:{row.excel_row_number}"
        payload = {column: value for column, value in sorted(row.values.items())}
        source_rows.append(
            {
                "table_key": table_key,
                "row_key": row_key,
                "excel_row_number": row.excel_row_number,
                "row_index": row.excel_row_number,
                "row_hash": _sha256_json(payload),
                "payload_json": payload,
                "formulas_json": row.formulas,
            }
        )
        if row.excel_row_number <= layout.header_row.excel_row_number or _is_repeated_header(row, layout):
            continue
        product = _text(row.values.get(layout.product_column))
        package = _text(row.values.get(layout.package_column))
        group = _text(row.values.get(layout.group_column)) if layout.group_column else None
        for column, prazo_dias in layout.price_columns.items():
            raw_value = _text(row.values.get(column))
            if raw_value is None:
                continue
            normalized_value = _normalize_decimal(raw_value)
            price_lines.append(
                {
                    "source_table_key": table_key,
                    "source_row_key": row_key,
                    "coluna_produto": layout.product_column,
                    "coluna_embalagem": layout.package_column,
                    "coluna_grupo": layout.group_column,
                    "coluna_preco": column,
                    "celula_preco": f"{column}{row.excel_row_number}",
                    "grupo_bruto": group,
                    "produto_bruto": product,
                    "embalagem_bruta": package,
                    "prazo_dias": prazo_dias,
                    "valor_bruto_texto": raw_value,
                    "valor_bruto_normalizado": normalized_value,
                }
            )

    if not price_lines:
        raise PriceListXlsxError("Nenhuma linha de preco foi encontrada nas abas do workbook.")
    return {
        "file_name": path.name,
        "workbook_sha256": _sha256_file(path),
        "size_bytes": path.stat().st_size,
        "tabelas": tables,
        "linhas_origem": source_rows,
        "linhas_preco": price_lines,
        "alertas": alerts,
    }


def decimal_to_centavos_por_litro(value: str) -> int:
    normalized = _normalize_decimal(value)
    if normalized is None:
        raise PriceListXlsxError("Preco bruto invalido.")
    decimal_value = Decimal(normalized)
    if decimal_value <= 0:
        raise PriceListXlsxError("Preco bruto deve ser maior que zero.")
    cents = int((decimal_value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP) * 100))
    if cents <= 0:
        raise PriceListXlsxError("Preco bruto deve resultar em ao menos um centavo por litro.")
    return cents


def _find_layout(rows: list[ExcelWorksheetRow]) -> _SheetLayout | None:
    for row in rows:
        normalized = {column: normalize_label(value or "") for column, value in row.values.items()}
        product_column = next((column for column, value in normalized.items() if value in PRODUCT_HEADERS), None)
        package_column = next((column for column, value in normalized.items() if value in PACKAGE_HEADERS), None)
        price_columns = {column: prazo for column, value in normalized.items() if (prazo := _deadline_from_header(value)) is not None}
        if product_column and package_column and price_columns:
            group_column = next((column for column, value in normalized.items() if value in GROUP_HEADERS), None)
            return _SheetLayout(row, product_column, package_column, group_column, price_columns)
    return None


def _deadline_from_header(value: str) -> int | None:
    compact = value.replace(" ", "")
    if value == "0" or compact in {"avista", "r$/l0"} or (
        "vista" in value and "r$" in value
    ):
        return 0
    match = PRICE_HEADER.fullmatch(value)
    return int(match.group(1)) if match else None


def _is_repeated_header(row: ExcelWorksheetRow, layout: _SheetLayout) -> bool:
    return (
        normalize_label(row.values.get(layout.product_column) or "") in PRODUCT_HEADERS
        and normalize_label(row.values.get(layout.package_column) or "") in PACKAGE_HEADERS
        and all(_deadline_from_header(normalize_label(row.values.get(column) or "")) == prazo for column, prazo in layout.price_columns.items())
    )


def _header_values(row: ExcelWorksheetRow) -> list[str]:
    return [value or "" for _, value in sorted(row.values.items())]


def _normalize_decimal(value: str) -> str | None:
    text = value.strip().replace("R$", "").replace(" ", "")
    if not text:
        return None
    if text.count(",") == 1 and text.count(".") >= 1:
        text = text.replace(".", "").replace(",", ".")
    elif text.count(",") == 1:
        text = text.replace(",", ".")
    elif text.count(",") > 1:
        return None
    try:
        decimal = Decimal(text)
    except InvalidOperation:
        return None
    return format(decimal, "f")


def _text(value: str | None) -> str | None:
    return value.strip() if value is not None and value.strip() else None


def _sha256_json(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _column_number(column: str) -> int:
    value = 0
    for character in column:
        value = value * 26 + ord(character) - ord("A") + 1
    return value
