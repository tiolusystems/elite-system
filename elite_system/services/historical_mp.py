from __future__ import annotations

from collections import defaultdict
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import unicodedata


def analyze_historical_mp(
    db_path: str | Path,
    batch_id: int | None = None,
    *,
    identity_limit: int = 500,
) -> dict[str, object]:
    """Analyze normalized MP history without changing the local migration database."""

    path = Path(db_path).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"Banco de migracao nao encontrado: {path}")
    if identity_limit < 1:
        raise ValueError("identity_limit must be positive")

    with closing(_connect_read_only(path)) as conn:
        batch = _load_batch(conn, batch_id)
        if batch is None:
            return {
                "status": "empty" if batch_id is None else "missing",
                "message": "Nenhum batch de migracao encontrado."
                if batch_id is None
                else f"Batch {batch_id} nao encontrado.",
            }

        effective_batch_id = int(batch["id"])
        master_rows = _load_scoped_rows(conn, effective_batch_id, "materias_primas")
        entry_rows = _load_scoped_rows(conn, effective_batch_id, "entradas_mp")
        issue_rows = _load_scoped_rows(conn, effective_batch_id, "saidas_mp")
        canonical_rows = [dict(row) for row in conn.execute(_CANONICAL_SQL)]

        identities = _build_identity_inventory(master_rows, entry_rows, issue_rows)
        mapping_counts = defaultdict(int)
        for identity in identities:
            mapping = _resolve_canonical(identity, canonical_rows)
            identity["mapping"] = mapping
            mapping_counts[mapping["status"]] += 1

        source_code_names: dict[str, set[str]] = defaultdict(set)
        source_name_codes: dict[str, set[str]] = defaultdict(set)
        for identity in identities:
            for code in identity["codigos_legados"]:
                if identity["nome_norm"]:
                    source_code_names[_normalize(code)].add(identity["nome_norm"])
            if identity["nome_norm"]:
                source_name_codes[identity["nome_norm"]].update(_normalize(code) for code in identity["codigos_legados"])

        duplicate_codes = sorted(code for code, names in source_code_names.items() if len(names) > 1)
        duplicate_names = sorted(name for name, codes in source_name_codes.items() if len(codes) > 1)
        acquisition = _acquisition_summary(entry_rows)
        quality = {
            "cadastros_sem_codigo": sum(not _clean(row["sku"]) for row in master_rows),
            "cadastros_sem_nome": sum(not _clean(row["nome"]) for row in master_rows),
            "cadastros_sem_unidade": sum(not _clean(row["unidade_adotada"]) for row in master_rows),
            "entradas_sem_lote": sum(not _clean(row["lote"]) for row in entry_rows),
            "saidas_sem_lote": sum(not _clean(row["lote"]) for row in issue_rows),
            "saidas_sem_op": sum(not _clean(row["lote_op"]) for row in issue_rows),
            "codigo_usado_como_nome": sum(_code_looks_like_name(row["sku"], row["nome"]) for row in master_rows),
            "codigos_duplicados": len(duplicate_codes),
            "nomes_com_multiplos_codigos": len(duplicate_names),
            "mapeamentos_pendentes": mapping_counts["new_required"] + mapping_counts["conflict"],
        }

        return {
            "status": "attention" if any(quality.values()) else "ok",
            "mode": "read_only_dry_run",
            "batch": dict(batch),
            "counts": {
                "cadastros_mp": len(master_rows),
                "entradas_mp": len(entry_rows),
                "saidas_mp": len(issue_rows),
                "identidades_distintas": len(identities),
                "mapeamentos_sugeridos": mapping_counts["suggested"],
                "mapeamentos_em_conflito": mapping_counts["conflict"],
                "novos_cadastros_necessarios": mapping_counts["new_required"],
            },
            "quantities": {
                "entrada": _sum(entry_rows, "quantidade"),
                "saida": _sum(issue_rows, "quantidade"),
                "saldo_derivado": _sum(entry_rows, "quantidade") - _sum(issue_rows, "quantidade"),
            },
            "acquisition_values": acquisition,
            "data_quality": quality,
            "duplicate_code_examples": duplicate_codes[:20],
            "duplicate_name_examples": duplicate_names[:20],
            "identities": identities[:identity_limit],
            "identity_limit": identity_limit,
            "identities_truncated": len(identities) > identity_limit,
        }


def _connect_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    return connection


def _load_batch(conn: sqlite3.Connection, batch_id: int | None) -> sqlite3.Row | None:
    where = "WHERE mb.id = ?" if batch_id is not None else ""
    params: tuple[object, ...] = (batch_id,) if batch_id is not None else ()
    return conn.execute(
        f"""
        SELECT mb.id, mb.status, mb.started_at, mb.finished_at,
               sw.id AS workbook_id, sw.file_name, sw.sha256
        FROM migration_batches mb
        JOIN source_workbooks sw ON sw.id = mb.workbook_id
        {where}
        ORDER BY mb.id DESC
        LIMIT 1
        """,
        params,
    ).fetchone()


def _load_scoped_rows(conn: sqlite3.Connection, batch_id: int, table_name: str) -> list[dict[str, object]]:
    allowed_tables = {"materias_primas", "entradas_mp", "saidas_mp"}
    if table_name not in allowed_tables:
        raise ValueError(f"Unsupported MP history table: {table_name}")
    rows = conn.execute(
        f"""
        SELECT entity.*, sr.excel_row_number, st.table_name AS source_table
        FROM {table_name} entity
        JOIN source_rows sr ON sr.id = entity.source_row_id
        JOIN source_tables st ON st.id = sr.table_id
        JOIN migration_batches mb ON mb.workbook_id = st.workbook_id
        WHERE mb.id = ?
        ORDER BY entity.id
        """,
        (batch_id,),
    )
    return [dict(row) for row in rows]


def _build_identity_inventory(
    master_rows: list[dict[str, object]],
    entry_rows: list[dict[str, object]],
    issue_rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    by_key: dict[str, dict[str, object]] = {}

    def ensure(name: object, code: object = None) -> dict[str, object]:
        name_text = _clean(name)
        code_text = _clean(code)
        name_norm = _normalize(name_text)
        code_norm = _normalize(code_text)
        key = f"name:{name_norm}" if name_norm else f"code:{code_norm}"
        identity = by_key.setdefault(
            key,
            {
                "nome_legado": name_text,
                "nome_norm": name_norm,
                "codigos_legados": set(),
                "unidades": set(),
                "lotes_entrada": set(),
                "lotes_consumidos": set(),
                "ops_destino": set(),
                "produtos_destino": set(),
                "cadastro_rows": 0,
                "entrada_rows": 0,
                "saida_rows": 0,
                "quantidade_entrada": 0.0,
                "quantidade_saida": 0.0,
            },
        )
        if not identity["nome_legado"] and name_text:
            identity["nome_legado"] = name_text
            identity["nome_norm"] = name_norm
        if code_text:
            identity["codigos_legados"].add(code_text)
        return identity

    for row in master_rows:
        identity = ensure(row["nome"], row["sku"])
        identity["cadastro_rows"] += 1
        if _clean(row["unidade_adotada"]):
            identity["unidades"].add(_clean(row["unidade_adotada"]))

    for row in entry_rows:
        identity = ensure(row["materia_prima"])
        identity["entrada_rows"] += 1
        identity["quantidade_entrada"] += _number(row["quantidade"])
        if _clean(row["unidade_padrao"]):
            identity["unidades"].add(_clean(row["unidade_padrao"]))
        if _clean(row["lote"]):
            identity["lotes_entrada"].add(_clean(row["lote"]))

    for row in issue_rows:
        identity = ensure(row["materia_prima"])
        identity["saida_rows"] += 1
        identity["quantidade_saida"] += _number(row["quantidade"])
        if _clean(row["lote"]):
            identity["lotes_consumidos"].add(_clean(row["lote"]))
        if _clean(row["lote_op"]):
            identity["ops_destino"].add(_clean(row["lote_op"]))
        if _clean(row["nome_produto"]):
            identity["produtos_destino"].add(_clean(row["nome_produto"]))

    output: list[dict[str, object]] = []
    for identity in by_key.values():
        identity["saldo_derivado"] = identity["quantidade_entrada"] - identity["quantidade_saida"]
        for field in (
            "codigos_legados",
            "unidades",
            "lotes_entrada",
            "lotes_consumidos",
            "ops_destino",
            "produtos_destino",
        ):
            identity[field] = sorted(identity[field])
        output.append(identity)
    return sorted(output, key=lambda item: (str(item["nome_norm"]), item["codigos_legados"]))


def _resolve_canonical(identity: dict[str, object], canonical_rows: list[dict[str, object]]) -> dict[str, object]:
    code_matches: dict[int, tuple[dict[str, object], str]] = {}
    for code in identity["codigos_legados"]:
        code_norm = _normalize(code)
        for row in canonical_rows:
            if code_norm and code_norm == _normalize(row["sku_corrigido"]):
                code_matches[int(row["id"])] = (row, "exact_sku")
            elif code_norm and code_norm == _normalize(row["codigo_legado"]):
                code_matches[int(row["id"])] = (row, "exact_legacy_code")
    if len(code_matches) == 1:
        row, method = next(iter(code_matches.values()))
        return _mapping("suggested", method, row)
    if len(code_matches) > 1:
        return _mapping("conflict", "duplicate_code", None, sorted(code_matches))

    name_matches = [row for row in canonical_rows if identity["nome_norm"] and identity["nome_norm"] == _normalize(row["nome"])]
    if len(name_matches) == 1:
        return _mapping("suggested", "exact_name", name_matches[0])
    if len(name_matches) > 1:
        return _mapping("conflict", "duplicate_name", None, [int(row["id"]) for row in name_matches])
    return _mapping("new_required", "no_match", None)


def _mapping(
    status: str,
    method: str,
    row: dict[str, object] | None,
    candidate_ids: list[int] | None = None,
) -> dict[str, object]:
    return {
        "status": status,
        "method": method,
        "materia_prima_id": int(row["id"]) if row else None,
        "sku_corrigido": _clean(row["sku_corrigido"]) if row else None,
        "nome": _clean(row["nome"]) if row else None,
        "candidate_ids": candidate_ids or ([int(row["id"])] if row else []),
    }


def _acquisition_summary(rows: list[dict[str, object]]) -> dict[str, object]:
    valor_mp = _sum(rows, "valor")
    frete = _sum(rows, "frete")
    difal = _sum(rows, "dif_icms")
    calculated = valor_mp + frete + difal
    legacy_total = _sum(rows, "custo_total")
    return {
        "valor_materia_prima": valor_mp,
        "frete": frete,
        "difal_icms": difal,
        "outros_componentes": 0.0,
        "total_componentes_conhecidos": calculated,
        "custo_total_legado": legacy_total,
        "diferenca_total_legado": calculated - legacy_total,
        "linhas_com_difal": sum(_number(row["dif_icms"]) > 0 for row in rows),
        "linhas_sem_total_legado": sum(row["custo_total"] is None for row in rows),
        "note": "Comparacao analitica; nao calcula obrigacao tributaria nem altera custo.",
    }


def _code_looks_like_name(code: object, name: object) -> bool:
    code_text = _clean(code)
    if not code_text:
        return False
    if _normalize(code_text) == _normalize(name) and _normalize(name):
        return True
    return bool(re.search(r"\s", code_text) and re.search(r"[A-Za-z]", code_text) and not re.search(r"\d", code_text))


def _normalize(value: object) -> str:
    text = _clean(value)
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFKD", text)
    ascii_text = "".join(char for char in decomposed if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", " ", ascii_text.lower()).strip()


def _clean(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _number(value: object) -> float:
    return float(value) if value is not None else 0.0


def _sum(rows: list[dict[str, object]], field: str) -> float:
    return sum(_number(row[field]) for row in rows)


_CANONICAL_SQL = """
SELECT id, codigo_legado, sku_corrigido, nome
FROM cad_materias_primas
WHERE status <> 'inactive'
ORDER BY id
"""
