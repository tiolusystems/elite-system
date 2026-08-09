from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from elite_system.excel_reader import inspect_workbook_structure
from elite_system.services.historical_workbook_mapping import classify_reference
from elite_system.services.historical_workbook_sources import (
    SOURCE_CLASSIFICATIONS,
    resolve_approved_source,
    worksheet_metadata_source_id,
)


MAX_WORKBOOK_BYTES = 32 * 1024 * 1024
EXPECTED_PROFILE = {"sheets": 155, "tables": 269, "references": 3095}


class WorkbookAnalysisError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def analyze_historical_workbook(
    workbook_path: str | Path,
    *,
    original_name: str | None = None,
    modified_at: str | None = None,
) -> dict[str, object]:
    path = Path(workbook_path)
    display_name = Path(original_name or path.name).name
    if Path(display_name).suffix.casefold() != ".xlsx":
        raise WorkbookAnalysisError("invalid_extension", "Selecione um arquivo com extensao .xlsx.")
    if not path.is_file():
        raise WorkbookAnalysisError("file_not_found", "O arquivo selecionado nao foi encontrado.")
    size = path.stat().st_size
    if size == 0:
        raise WorkbookAnalysisError("empty_file", "O arquivo selecionado esta vazio.")
    if size > MAX_WORKBOOK_BYTES:
        raise WorkbookAnalysisError("file_too_large", "O arquivo excede o limite local de 32 MB.")

    try:
        structure = inspect_workbook_structure(path)
    except (zipfile.BadZipFile, KeyError, ValueError) as error:
        raise WorkbookAnalysisError("corrupt_workbook", "O arquivo nao e um workbook XLSX valido ou esta corrompido.") from error

    sheets: list[dict[str, object]] = []
    flat_references: list[dict[str, object]] = []
    source_classifications: list[dict[str, object]] = []
    total_table_rows = 0
    total_populated_table_rows = 0
    for sheet in structure.sheets:
        tables: list[dict[str, object]] = []
        for table in sheet.tables:
            source_classification = resolve_approved_source(
                sheet_name=sheet.sheet_name,
                table_name=table.table_name,
                headers=table.headers,
            )
            source_classifications.append(source_classification)
            mappings: list[dict[str, object]] = []
            for position, header in enumerate(table.headers, start=1):
                mapping = classify_reference(
                    sheet_name=sheet.sheet_name,
                    table_name=table.table_name,
                    header=header,
                    source_kind="structured_table",
                    table_headers=table.headers,
                )
                reference = {
                    "sheetOrder": sheet.order,
                    "sourceKind": "structured_table",
                    "sheet": sheet.sheet_name,
                    "table": table.table_name,
                    "ref": table.ref,
                    "columnPosition": position,
                    "excelColumn": header,
                    "sourceTableId": source_classification["sourceTableId"],
                    "sourceClassification": source_classification["classification"],
                    "sourceBindingKind": "structured_table",
                    **_camel_mapping(mapping.to_dict()),
                }
                mappings.append(reference)
                flat_references.append(reference)
            total_table_rows += table.row_count
            total_populated_table_rows += table.populated_row_count
            tables.append(
                {
                    "name": table.table_name,
                    "ref": table.ref,
                    "rowCount": table.row_count,
                    "populatedRowCount": table.populated_row_count,
                    "columnCount": len(table.headers),
                    "formulaCellCount": table.formula_cell_count,
                    "calculatedValueCount": table.calculated_value_count,
                    "headers": table.headers,
                    "warnings": table.warnings,
                    "mappings": mappings,
                    "sourceClassification": source_classification,
                }
            )

        outside_mappings: list[dict[str, object]] = []
        worksheet_source_id = worksheet_metadata_source_id(sheet.sheet_name)
        for column in sheet.columns:
            if column.outside_table_cells <= 0:
                continue
            mapping = classify_reference(
                sheet_name=sheet.sheet_name,
                table_name="__worksheet__",
                header=column.column,
                source_kind="worksheet_outside_table",
            )
            reference = {
                "sheetOrder": sheet.order,
                "sourceKind": "worksheet_outside_table",
                "sheet": sheet.sheet_name,
                "table": "__worksheet__",
                "ref": sheet.dimension,
                "columnPosition": None,
                "excelColumn": column.column,
                "outsideTableCells": column.outside_table_cells,
                "sourceTableId": worksheet_source_id,
                "sourceClassification": None,
                "sourceBindingKind": "worksheet_metadata",
                **_camel_mapping(mapping.to_dict()),
            }
            outside_mappings.append(reference)
            flat_references.append(reference)

        sheets.append(
            {
                "order": sheet.order,
                "name": sheet.sheet_name,
                "state": sheet.state,
                "dimension": sheet.dimension,
                "nonemptyRows": sheet.nonempty_rows,
                "nonemptyCells": sheet.nonempty_cells,
                "formulaCells": sheet.formula_cells,
                "errorCells": sheet.error_cells,
                "warnings": sheet.warnings,
                "tables": tables,
                "outsideColumns": outside_mappings,
            }
        )

    status_counts = {status: 0 for status in ("defined", "transform", "pending", "rejected", "out_of_scope")}
    domain_counts: dict[str, int] = {}
    for reference in flat_references:
        status = str(reference["status"])
        status_counts[status] = status_counts.get(status, 0) + 1
        domain = str(reference["domain"])
        domain_counts[domain] = domain_counts.get(domain, 0) + 1

    reference_count = len(flat_references)
    table_classification_counts = {classification: 0 for classification in SOURCE_CLASSIFICATIONS}
    unclassified_table_count = 0
    schema_drift_table_count = 0
    for source in source_classifications:
        classification = source.get("classification")
        if isinstance(classification, str) and classification in table_classification_counts:
            table_classification_counts[classification] += 1
        else:
            unclassified_table_count += 1
        if source.get("schemaDriftDetected") is True:
            schema_drift_table_count += 1
    bound_reference_count = sum(bool(reference.get("sourceTableId")) for reference in flat_references)
    unbound_reference_count = reference_count - bound_reference_count
    source_classification_complete = (
        unclassified_table_count == 0
        and schema_drift_table_count == 0
        and unbound_reference_count == 0
    )
    structural_profile_matches = (
        structure.sheet_count == EXPECTED_PROFILE["sheets"]
        and structure.table_count == EXPECTED_PROFILE["tables"]
        and reference_count == EXPECTED_PROFILE["references"]
    )
    profile_matches = structural_profile_matches and source_classification_complete
    profile_warnings: list[str] = []
    if not structural_profile_matches:
        profile_warnings.append(
            "O arquivo nao corresponde integralmente ao perfil estrutural de referencia 155/269/3.095."
        )
    elif not source_classification_complete:
        profile_warnings.append(
            "As contagens conferem, mas uma ou mais fontes possuem identidade ou schema nao aprovado."
        )

    return {
        "contractVersion": 2,
        "readOnly": True,
        "notice": "Esta etapa apenas analisa o arquivo. Nenhum dado sera gravado no banco.",
        "file": {
            "name": display_name,
            "sizeBytes": size,
            "modifiedAt": modified_at or _iso_timestamp(path.stat().st_mtime),
            "sha256": _sha256(path),
        },
        "summary": {
            "sheetCount": structure.sheet_count,
            "tableCount": structure.table_count,
            "namedRangeCount": structure.named_range_count,
            "tableRowCount": total_table_rows,
            "populatedTableRowCount": total_populated_table_rows,
            "referenceCount": reference_count,
            "boundReferenceCount": bound_reference_count,
            "unboundReferenceCount": unbound_reference_count,
            "classifiedTableCount": structure.table_count - unclassified_table_count,
            "unclassifiedTableCount": unclassified_table_count,
            "schemaDriftTableCount": schema_drift_table_count,
            "sourceClassificationComplete": source_classification_complete,
            "tableClassificationCounts": table_classification_counts,
            "statusCounts": status_counts,
            "domainCounts": dict(sorted(domain_counts.items())),
            "structuralProfileMatchesReference": structural_profile_matches,
            "profileMatchesReference": profile_matches,
            "profileWarnings": profile_warnings,
        },
        "sheets": sheets,
        "reportRows": flat_references,
        "analyzedAt": datetime.now(timezone.utc).isoformat(),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _iso_timestamp(value: float) -> str:
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat()


def _camel_mapping(mapping: dict[str, str | None]) -> dict[str, str | None]:
    return {
        "sourceCode": mapping["source_code"],
        "status": mapping["status"],
        "domain": mapping["domain"],
        "target": mapping["target"],
        "rule": mapping["rule"],
        "warning": mapping["warning"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze XLSX metadata without database writes.")
    parser.add_argument("--file", required=True)
    parser.add_argument("--original-name")
    parser.add_argument("--modified-at")
    args = parser.parse_args(argv)
    try:
        result = analyze_historical_workbook(
            args.file,
            original_name=args.original_name,
            modified_at=args.modified_at,
        )
    except WorkbookAnalysisError as error:
        print(json.dumps({"ok": False, "error": {"code": error.code, "message": str(error)}}))
        return 2
    # ASCII-safe JSON avoids dependence on the Windows console code page. JSON.parse
    # restores escaped workbook labels such as "Produ\u00e7\u00e3o" to Unicode.
    print(json.dumps({"ok": True, "analysis": result}, ensure_ascii=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
