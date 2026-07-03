from __future__ import annotations

from dataclasses import dataclass, field as dataclass_field
from enum import StrEnum
import re
import unicodedata
from collections.abc import Callable, Sequence

from elite_system.domain.cadastros import (
    Cliente,
    Embalagem,
    MateriaPrima,
    PessoaComercial,
    ProdutoBase,
    Veiculo,
)


class ValidationSeverity(StrEnum):
    ERROR = "error"
    WARNING = "warning"


@dataclass(frozen=True)
class ValidationIssue:
    severity: ValidationSeverity
    entity: str
    code: str
    message: str
    field: str | None = None
    entity_key: str | None = None
    payload: dict[str, object] = dataclass_field(default_factory=dict)


def validate_master_data(
    *,
    clientes: Sequence[Cliente] = (),
    pessoas: Sequence[PessoaComercial] = (),
    materias_primas: Sequence[MateriaPrima] = (),
    produtos: Sequence[ProdutoBase] = (),
    embalagens: Sequence[Embalagem] = (),
    veiculos: Sequence[Veiculo] = (),
) -> tuple[ValidationIssue, ...]:
    issues: list[ValidationIssue] = []
    issues.extend(find_duplicate_values("clientes", clientes, "codigo_legado", code="duplicate_legacy_code"))
    issues.extend(find_duplicate_normalized_names("clientes", clientes))
    issues.extend(validate_pessoas_comerciais(pessoas))
    issues.extend(find_duplicate_values("materias_primas", materias_primas, "sku_corrigido", code="duplicate_sku"))
    issues.extend(validate_materias_primas(materias_primas))
    issues.extend(find_duplicate_values("produtos", produtos, "codigo_produto", code="duplicate_product_code"))
    issues.extend(find_duplicate_normalized_names("produtos", produtos))
    issues.extend(find_duplicate_normalized_names("embalagens", embalagens, field_name="descricao"))
    issues.extend(find_duplicate_values("veiculos", veiculos, "placa", code="duplicate_plate"))
    return tuple(issues)


def find_duplicate_normalized_names(
    entity: str,
    records: Sequence[object],
    field_name: str = "nome",
) -> tuple[ValidationIssue, ...]:
    return find_duplicate_values(
        entity,
        records,
        field_name,
        code=f"duplicate_{field_name}_normalized",
        normalizer=normalize_key,
    )


def find_duplicate_values(
    entity: str,
    records: Sequence[object],
    field_name: str,
    *,
    code: str,
    normalizer: Callable[[str], str] | None = None,
) -> tuple[ValidationIssue, ...]:
    grouped: dict[str, list[str]] = {}
    for index, record in enumerate(records):
        value = getattr(record, field_name, None)
        if value is None:
            continue
        text = str(value).strip()
        if not text:
            continue
        key = normalizer(text) if normalizer else text.upper()
        grouped.setdefault(key, []).append(_record_key(record, index))

    issues: list[ValidationIssue] = []
    for key, record_keys in sorted(grouped.items()):
        if len(record_keys) < 2:
            continue
        issues.append(
            ValidationIssue(
                severity=ValidationSeverity.ERROR,
                entity=entity,
                field=field_name,
                code=code,
                entity_key=", ".join(record_keys),
                message=f"{entity}.{field_name} has duplicated value",
                payload={"normalized_value": key, "records": record_keys},
            )
        )
    return tuple(issues)


def validate_pessoas_comerciais(pessoas: Sequence[PessoaComercial]) -> tuple[ValidationIssue, ...]:
    issues: list[ValidationIssue] = []
    issues.extend(find_duplicate_normalized_names("pessoas_comerciais", pessoas))

    aliases: list[_AliasRecord] = []
    for index, pessoa in enumerate(pessoas):
        pessoa_key = _record_key(pessoa, index)
        for value in (pessoa.nome, *pessoa.apelidos, *pessoa.grafias_incorretas):
            aliases.append(_AliasRecord(pessoa_key=pessoa_key, alias=value))

    grouped: dict[str, set[str]] = {}
    for item in aliases:
        grouped.setdefault(normalize_key(item.alias), set()).add(item.pessoa_key)

    for alias, pessoa_keys in sorted(grouped.items()):
        if len(pessoa_keys) < 2:
            continue
        issues.append(
            ValidationIssue(
                severity=ValidationSeverity.ERROR,
                entity="pessoas_comerciais",
                field="apelidos",
                code="alias_points_to_multiple_people",
                entity_key=", ".join(sorted(pessoa_keys)),
                message="Alias or incorrect spelling points to more than one commercial person",
                payload={"alias": alias, "records": sorted(pessoa_keys)},
            )
        )
    return tuple(issues)


def validate_materias_primas(materias_primas: Sequence[MateriaPrima]) -> tuple[ValidationIssue, ...]:
    issues: list[ValidationIssue] = []
    for index, materia_prima in enumerate(materias_primas):
        record_key = _record_key(materia_prima, index)
        if materia_prima.codigo_legado and normalize_key(materia_prima.codigo_legado) == normalize_key(materia_prima.nome):
            issues.append(
                ValidationIssue(
                    severity=ValidationSeverity.WARNING,
                    entity="materias_primas",
                    field="codigo_legado",
                    code="legacy_sku_looks_like_name",
                    entity_key=record_key,
                    message="Legacy MP SKU appears to contain the material name and needs review",
                )
            )
        if re.search(r"\s", materia_prima.sku_corrigido):
            issues.append(
                ValidationIssue(
                    severity=ValidationSeverity.ERROR,
                    entity="materias_primas",
                    field="sku_corrigido",
                    code="sku_corrigido_has_spaces",
                    entity_key=record_key,
                    message="Corrected MP SKU cannot contain spaces",
                )
            )
    return tuple(issues)


def normalize_key(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_text = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    ascii_text = re.sub(r"[^a-zA-Z0-9]+", " ", ascii_text).strip().upper()
    ascii_text = re.sub(r"\s+", " ", ascii_text)
    return re.sub(r"(?<=\d)\s+(?=[A-Z])", "", ascii_text)


def _record_key(record: object, index: int) -> str:
    for field_name in ("codigo_legado", "codigo_produto", "sku_corrigido", "placa", "nome", "descricao"):
        value = getattr(record, field_name, None)
        if value is not None and str(value).strip():
            return str(value).strip()
    return f"record#{index + 1}"


@dataclass(frozen=True)
class _AliasRecord:
    pessoa_key: str
    alias: str
