from __future__ import annotations

from dataclasses import asdict, dataclass
from functools import lru_cache
import csv
import hashlib
import io
import json
from pathlib import Path
import re
from typing import Iterable
import unicodedata

from elite_system.excel_reader import ExcelTableStructure, ExcelWorkbookStructure
from elite_system.services.historical_workbook_mapping import normalize_label


SOURCE_CLASSIFICATIONS = (
    "source_master",
    "source_transaction",
    "source_formula",
    "reconciliation_report",
    "derived_calculation",
    "duplicate_source",
    "dashboard_or_summary",
    "deferred",
    "out_of_scope",
)

CATALOG_PATH = Path(__file__).resolve().parents[1] / "resources" / "historical_workbook_source_catalog.json"


@dataclass(frozen=True)
class SourcePolicy:
    classification: str
    owner_domain: str
    target_entity: str
    equivalent_primary_source: str | None
    preserve_rows: bool
    preserve_metadata_only: bool
    normalize_later: bool
    use_for_reconciliation: bool
    justification: str
    duplicate_risk: str
    dependencies: tuple[str, ...]
    quality_notes: tuple[str, ...]
    stock_relevant: bool = False
    affects_operational_stock: bool = False
    unconfirmed_lots_available: bool = False


def build_approved_source_catalog(structure: ExcelWorkbookStructure) -> dict[str, object]:
    """Build a sanitized catalog from workbook structure, never from cell values."""

    tables: list[dict[str, object]] = []
    table_number = 0
    for sheet in structure.sheets:
        for table_number_in_sheet, table in enumerate(sheet.tables, start=1):
            table_number += 1
            policy = propose_source_policy(sheet.sheet_name, table.table_name, table.headers)
            if policy is None:
                raise ValueError(
                    f"No approved source policy for sheet {sheet.order}, table {table_number_in_sheet}."
                )
            identity_hash = source_identity_hash(sheet.sheet_name, table.table_name)
            tables.append(
                {
                    "sourceTableId": f"src_{identity_hash[:16]}",
                    "identityHash": identity_hash,
                    "schemaFingerprint": source_schema_fingerprint(
                        sheet.sheet_name,
                        table.table_name,
                        table.headers,
                    ),
                    "sheetRef": f"S{sheet.order:03d}",
                    "tableRef": f"T{table_number:03d}",
                    "tableNumberInSheet": table_number_in_sheet,
                    "baselineRange": table.ref,
                    "baselineRowCount": table.row_count,
                    "baselineColumnCount": len(table.headers),
                    "canonicalHeaders": canonical_headers(table.headers, policy.classification),
                    "formulaCellCount": table.formula_cell_count,
                    "calculatedValueCount": table.calculated_value_count,
                    **_policy_dict(policy),
                }
            )

    if len(tables) != structure.table_count:
        raise ValueError("Source catalog table count does not match workbook structure.")
    schema_digest = hashlib.sha256(
        "\n".join(str(item["schemaFingerprint"]) for item in tables).encode("ascii")
    ).hexdigest()
    return {
        "catalogVersion": 1,
        "classificationCatalog": list(SOURCE_CLASSIFICATIONS),
        "workbookProfile": {
            "sheetCount": structure.sheet_count,
            "tableCount": structure.table_count,
            "namedRangeCount": structure.named_range_count,
            "schemaFingerprint": schema_digest,
        },
        "tables": tables,
    }


def render_sanitized_matrix_markdown(catalog: dict[str, object]) -> str:
    lines = [
        "# Matriz sanitizada de classificacao das 269 tabelas",
        "",
        "Esta matriz versionada nao contem nomes brutos de abas, tabelas ou produtos.",
        "`sheet_ref`, `table_ref`, hashes e cabecalhos canonicos permitem auditoria",
        "estrutural sem publicar dado comercial. O manifesto exato e gerado somente no",
        "diretorio local ignorado pelo Git.",
        "",
        "| tabela | aba | source_id | intervalo | linhas | colunas | cabecalhos canonicos | classificacao | dono | destino | fonte equivalente | raw | metadata | normalizar | reconciliar | formulas/cache | drift | duplicidade | estoque atual | dependencias | justificativa e qualidade |",
        "|---|---|---|---|---:|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in _catalog_tables(catalog):
        cells = [
            row["tableRef"],
            row["sheetRef"],
            row["sourceTableId"],
            row["baselineRange"],
            row["baselineRowCount"],
            row["baselineColumnCount"],
            ", ".join(str(value) for value in row["canonicalHeaders"]),
            row["classification"],
            row["ownerDomain"],
            row["targetEntity"],
            row.get("equivalentPrimarySource") or "-",
            _yes_no(bool(row["preserveRows"])),
            _yes_no(bool(row["preserveMetadataOnly"])),
            _yes_no(bool(row["normalizeLater"])),
            _yes_no(bool(row["useForReconciliation"])),
            f"{row['formulaCellCount']}/{row['calculatedValueCount']}",
            "fingerprint versionado",
            row["duplicateRisk"],
            "nao" if row["affectsOperationalStock"] is False else "sim",
            ", ".join(str(value) for value in row["dependencies"]) or "-",
            "; ".join(
                [str(row["justification"]), *(str(value) for value in row["qualityNotes"])]
            ),
        ]
        lines.append("| " + " | ".join(_markdown_cell(value) for value in cells) + " |")
    return "\n".join(lines) + "\n"


def render_exact_manifest_csv(
    structure: ExcelWorkbookStructure,
    catalog: dict[str, object],
) -> str:
    output = io.StringIO(newline="")
    fieldnames = [
        "table_ref",
        "sheet_ref",
        "source_table_id",
        "sheet_name",
        "table_name",
        "range",
        "row_count",
        "column_count",
        "headers",
        "classification",
        "owner_domain",
        "target_entity",
        "equivalent_primary_source",
        "preserve_rows",
        "preserve_metadata_only",
        "normalize_later",
        "use_for_reconciliation",
        "justification",
        "duplicate_risk",
        "dependencies",
        "formula_cell_count",
        "calculated_value_count",
        "schema_fingerprint",
        "schema_drift_detectable",
        "quality_notes",
        "affects_operational_stock",
        "unconfirmed_lots_available",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    catalog_rows = iter(_catalog_tables(catalog))
    for sheet in structure.sheets:
        for table in sheet.tables:
            row = next(catalog_rows)
            writer.writerow(
                {
                    "table_ref": row["tableRef"],
                    "sheet_ref": row["sheetRef"],
                    "source_table_id": row["sourceTableId"],
                    "sheet_name": sheet.sheet_name,
                    "table_name": table.table_name,
                    "range": table.ref,
                    "row_count": table.row_count,
                    "column_count": len(table.headers),
                    "headers": " | ".join(table.headers),
                    "classification": row["classification"],
                    "owner_domain": row["ownerDomain"],
                    "target_entity": row["targetEntity"],
                    "equivalent_primary_source": row.get("equivalentPrimarySource") or "",
                    "preserve_rows": row["preserveRows"],
                    "preserve_metadata_only": row["preserveMetadataOnly"],
                    "normalize_later": row["normalizeLater"],
                    "use_for_reconciliation": row["useForReconciliation"],
                    "justification": row["justification"],
                    "duplicate_risk": row["duplicateRisk"],
                    "dependencies": " | ".join(str(value) for value in row["dependencies"]),
                    "formula_cell_count": row["formulaCellCount"],
                    "calculated_value_count": row["calculatedValueCount"],
                    "schema_fingerprint": row["schemaFingerprint"],
                    "schema_drift_detectable": row["schemaDriftDetectable"],
                    "quality_notes": " | ".join(str(value) for value in row["qualityNotes"]),
                    "affects_operational_stock": row["affectsOperationalStock"],
                    "unconfirmed_lots_available": row["unconfirmedLotsAvailable"],
                }
            )
    return output.getvalue()


def resolve_approved_source(
    *,
    sheet_name: str,
    table_name: str,
    headers: list[str],
    catalog: dict[str, object] | None = None,
) -> dict[str, object]:
    approved_catalog = catalog or load_approved_source_catalog()
    identity_hash = source_identity_hash(sheet_name, table_name)
    schema_fingerprint = source_schema_fingerprint(sheet_name, table_name, headers)
    by_identity = {
        str(item["identityHash"]): item
        for item in _catalog_tables(approved_catalog)
    }
    approved = by_identity.get(identity_hash)
    if approved is None:
        return {
            "sourceTableId": f"src_{identity_hash[:16]}",
            "classification": None,
            "ownerDomain": None,
            "targetEntity": None,
            "schemaFingerprint": schema_fingerprint,
            "schemaDriftDetected": True,
            "reviewRequired": True,
            "normalizationBlocked": True,
            "driftReason": "Tabela nova ou identidade de aba/tabela alterada.",
        }

    result = dict(approved)
    drift_detected = str(approved["schemaFingerprint"]) != schema_fingerprint
    result.update(
        {
            "schemaFingerprint": schema_fingerprint,
            "schemaDriftDetected": drift_detected,
            "reviewRequired": drift_detected,
            "normalizationBlocked": drift_detected,
            "driftReason": (
                "Cabecalho adicionado, removido, renomeado ou reordenado."
                if drift_detected
                else None
            ),
        }
    )
    return result


def load_approved_source_catalog(path: Path = CATALOG_PATH) -> dict[str, object]:
    return _load_catalog(str(path.resolve()))


@lru_cache(maxsize=4)
def _load_catalog(path: str) -> dict[str, object]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    tables = _catalog_tables(payload)
    if len(tables) != 269:
        raise ValueError("Approved workbook source catalog must contain 269 tables.")
    return payload


def source_identity_hash(sheet_name: str, table_name: str) -> str:
    return _hash_payload([_exact_label(sheet_name), _exact_label(table_name)])


def source_schema_fingerprint(sheet_name: str, table_name: str, headers: Iterable[str]) -> str:
    return _hash_payload(
        [_exact_label(sheet_name), _exact_label(table_name), *(_exact_label(value) for value in headers)]
    )


def worksheet_metadata_source_id(sheet_name: str) -> str:
    return f"worksheet_{_hash_payload([_exact_label(sheet_name)])[:16]}"


def canonical_headers(headers: list[str], classification: str) -> list[str]:
    result: list[str] = []
    guarantee_table = _is_guarantee_source(headers)
    for index, header in enumerate(headers):
        if guarantee_table and index == 0:
            result.append("garantia_referencia")
            continue
        label = normalize_label(header)
        label = re.sub(r"[^a-z0-9%$/]+", "_", label).strip("_")
        result.append(label or f"coluna_{index + 1}")
    return result


def propose_source_policy(sheet_name: str, table_name: str, headers: list[str]) -> SourcePolicy | None:
    normalized_sheet = normalize_label(sheet_name)
    normalized_table = normalize_label(table_name)
    normalized_headers = {normalize_label(header) for header in headers}

    if _is_formula_source(normalized_headers):
        duplicate_candidate = normalized_sheet.endswith("(2)")
        return _source_policy(
            "source_formula",
            "pcp",
            "pcp_formula_versoes + pcp_formula_itens + pcp_formula_etapas",
            equivalent_primary_source=(
                "formula_base_sem_sufixo_2_candidata" if duplicate_candidate else None
            ),
            justification="Composicao e sequencia constitutivas da formula historica.",
            duplicate_risk="high" if duplicate_candidate else "medium",
            dependencies=("cad_produtos_base", "cad_materias_primas", "cad_unidades"),
            quality_notes=(
                "Quantidade de batelada, custos, estoque e percentuais calculados nao viram fatos.",
                "Sufixo (2) exige resolver versao ou duplicidade sem fusao automatica."
                if duplicate_candidate
                else "Resolver produto, base de rendimento e versao historica.",
            ),
        )

    if _is_guarantee_source(headers):
        duplicate_candidate = normalized_sheet.endswith("(2)")
        return _source_policy(
            "source_formula",
            "pcp",
            "pcp_formula_garantias + cad_produto_especificacoes",
            equivalent_primary_source=(
                "garantia_base_sem_sufixo_2_candidata" if duplicate_candidate else None
            ),
            justification="Garantia constitutiva associada a formula/produto historico.",
            duplicate_risk="high" if duplicate_candidate else "medium",
            dependencies=("cad_nutrientes", "pcp_formula_versoes", "cad_produto_especificacoes"),
            quality_notes=(
                "Separar garantia calculada, especificacao tecnica e documento MAPA.",
            ),
        )

    if normalized_sheet == "custo embalagem" and normalized_table.startswith("custo_"):
        return _source_policy(
            "source_formula",
            "cadastros",
            "cad_embalagem_bom_versoes + cad_embalagem_bom_itens",
            justification="Composicao historica da embalagem; custos sao derivados.",
            duplicate_risk="medium",
            dependencies=("cad_embalagens", "cad_materias_primas", "cad_unidades"),
            quality_notes=("Quantidade e vigencia precisam ser comprovadas antes da normalizacao.",),
        )

    key = (normalized_sheet, normalized_table)
    return _EXPLICIT_POLICIES.get(key)


def _source_policy(
    classification: str,
    owner_domain: str,
    target_entity: str,
    *,
    equivalent_primary_source: str | None = None,
    justification: str,
    duplicate_risk: str,
    dependencies: tuple[str, ...],
    quality_notes: tuple[str, ...],
    stock_relevant: bool = False,
) -> SourcePolicy:
    if classification not in SOURCE_CLASSIFICATIONS:
        raise ValueError(f"Invalid source classification: {classification}")
    preserve_rows = classification in {"source_master", "source_transaction", "source_formula", "deferred"}
    metadata_only = classification in {
        "reconciliation_report",
        "derived_calculation",
        "duplicate_source",
        "dashboard_or_summary",
        "out_of_scope",
    }
    normalize_later = classification in {"source_master", "source_transaction", "source_formula"}
    reconcile = classification in {"reconciliation_report", "derived_calculation"}
    return SourcePolicy(
        classification=classification,
        owner_domain=owner_domain,
        target_entity=target_entity,
        equivalent_primary_source=equivalent_primary_source,
        preserve_rows=preserve_rows,
        preserve_metadata_only=metadata_only,
        normalize_later=normalize_later,
        use_for_reconciliation=reconcile,
        justification=justification,
        duplicate_risk=duplicate_risk,
        dependencies=dependencies,
        quality_notes=quality_notes,
        stock_relevant=stock_relevant,
    )


def _explicit_policy(
    classification: str,
    owner: str,
    target: str,
    justification: str,
    *,
    primary: str | None = None,
    risk: str = "medium",
    dependencies: tuple[str, ...] = (),
    notes: tuple[str, ...] = (),
    stock: bool = False,
) -> SourcePolicy:
    return _source_policy(
        classification,
        owner,
        target,
        equivalent_primary_source=primary,
        justification=justification,
        duplicate_risk=risk,
        dependencies=dependencies,
        quality_notes=notes,
        stock_relevant=stock,
    )


_EXPLICIT_POLICIES = {
    ("analise resultados", "proj_fat167"): _explicit_policy(
        "dashboard_or_summary", "auditoria", "reconciliation.sales_projection",
        "Projecao e resumo calculado, nao fato historico.", primary="pedidos_resumo.gestao_pedidos",
        risk="high", dependencies=("com_pedidos",),
    ),
    ("analise resultados", "tabela167"): _explicit_policy(
        "reconciliation_report", "auditoria", "reconciliation.order_delivery",
        "Relatorio de prazo usado para conferir pedidos e expedicoes.",
        primary="pedidos_resumo.gestao_pedidos + saidas_pa.saidas_pa", risk="high",
        dependencies=("com_pedidos", "exp_romaneios"),
    ),
    ("analise resultados", "tabela212"): _explicit_policy(
        "dashboard_or_summary", "auditoria", "reconciliation.customer_ranking",
        "Ranking consolidado, recalculavel a partir dos pedidos.",
        primary="pedidos_resumo.gestao_pedidos", risk="high", dependencies=("com_pedidos",),
    ),
    ("controle de estoque pa", "cont_estoque_pa"): _explicit_policy(
        "reconciliation_report", "auditoria", "reconciliation.pa_balance",
        "Saldo calculado para comparar com movimentos e inventario fisico.",
        primary="lotes_producao.producao_lotes + saidas pa.saidas_pa", risk="high",
        dependencies=("est_movimentos_pa", "inventario_fisico_abertura"), stock=True,
    ),
    ("controle de estoque mp", "cont_estoquemp"): _explicit_policy(
        "reconciliation_report", "auditoria", "reconciliation.mp_balance",
        "Saldo calculado para comparar com movimentos e inventario fisico.",
        primary="entradas_mp.entradas_mp + saidas_mp.saidas_mp", risk="high",
        dependencies=("est_movimentos_mp", "inventario_fisico_abertura"), stock=True,
    ),
    ("custo embalagem", "peso_embalagens"): _explicit_policy(
        "source_master", "cadastros", "cad_embalagens + cad_embalagem_especificacoes",
        "Peso e cubagem sao especificacoes fisicas da embalagem.",
        dependencies=("cad_embalagens", "cad_unidades"),
    ),
    ("entradas_mp", "entradas_mp"): _explicit_policy(
        "source_transaction", "estoque", "migration.mp_receipts + est_movimentos_mp_valores",
        "Entrada historica de MP com documento, lote, quantidade e custo.",
        dependencies=("cad_materias_primas", "est_lotes_mp", "cad_unidades"),
        notes=("Difal de ICMS integra o custo quando aplicavel.",), stock=True,
    ),
    ("garantias", "tabela180"): _explicit_policy(
        "source_master", "cadastros", "cad_nutrientes",
        "Catalogo tecnico de garantias/nutrientes.", dependencies=("cad_unidades",),
    ),
    ("pedidos_resumo", "gestao_pedidos"): _explicit_policy(
        "source_transaction", "pedidos", "com_pedidos + com_pedido_itens + legacy_financial_fiscal",
        "Fonte comercial historica de pedidos, itens, fiscal, parcelas e comissoes.",
        dependencies=("cad_clientes", "cad_produtos_base", "cad_pessoas_comerciais"),
        notes=("Posicoes financeiras nao fabricam eventos de recebimento ou pagamento.",),
    ),
    ("pontuacao", "tabela278"): _explicit_policy(
        "source_transaction", "comercial", "com_campanha_movimentos_historicos",
        "Fato historico de pontuacao por documento e produto.",
        dependencies=("com_campanhas", "fat_referencias_fiscais_historicas"),
    ),
    ("pontuacao", "tabela279"): _explicit_policy(
        "source_master", "comercial", "com_campanhas + com_campanha_regras",
        "Regra/faixa de campanha, pontos e premio.", dependencies=("com_periodos_meta",),
    ),
    ("cadastro_materia prima", "cadastro_materia_prima"): _explicit_policy(
        "source_master", "cadastros", "cad_materias_primas + cad_materia_prima_aliases",
        "Cadastro mestre oficial de materias-primas.",
        dependencies=("cad_unidades", "cad_materia_prima_especificacoes"),
        notes=("SKU canonico deve ser criado sem apagar o codigo legado.",),
    ),
    ("lotes_producao", "producao_lotes"): _explicit_policy(
        "source_transaction", "pcp", "pcp_ordens_producao_historicas + pcp_resultados_historicos",
        "Fato historico de OP/producao e CQ parcial.",
        dependencies=("pcp_formula_referencias_historicas", "cad_produtos_base", "est_lotes_pa"),
        notes=("Historico pre-corte nao cria lote disponivel nem saldo atual.",), stock=True,
    ),
    ("posicao estoque mp periodo", "pos_esto_mp_period"): _explicit_policy(
        "reconciliation_report", "auditoria", "reconciliation.mp_period_balance",
        "Posicao derivada por periodo para reconciliar movimentos de MP.",
        primary="entradas_mp.entradas_mp + saidas_mp.saidas_mp", risk="high",
        dependencies=("est_movimentos_mp",), stock=True,
    ),
    ("posicao estoque pa periodo", "cont_estoque_pa245"): _explicit_policy(
        "reconciliation_report", "auditoria", "reconciliation.pa_period_balance",
        "Posicao derivada por periodo para reconciliar movimentos de PA.",
        primary="lotes_producao.producao_lotes + saidas pa.saidas_pa", risk="high",
        dependencies=("est_movimentos_pa",), stock=True,
    ),
    ("relacao clientes", "clientes"): _explicit_policy(
        "source_master", "cadastros", "cad_clientes + cad_cliente_contatos + cad_cliente_vendedores",
        "Cadastro mestre oficial de clientes e vinculos comerciais.",
        dependencies=("cad_municipios", "cad_pessoas_comerciais"),
        notes=("Contato e UF permanecem pendentes; nao inferir.",),
    ),
    ("tbl_cadastro_pa", "relacao_produtos"): _explicit_policy(
        "source_master", "cadastros", "cad_produtos_base + cad_produto_especificacoes",
        "Cadastro mestre oficial de PA/PI.",
        dependencies=("cad_grupos_produto", "cad_nutrientes"),
        notes=("Densidade e pH permanecem pendentes; nao inferir.",),
    ),
    ("romaneio (2)", "romaneio96"): _explicit_policy(
        "source_transaction", "expedicao", "exp_romaneios_historicos + exp_romaneio_itens_historicos",
        "Snapshot comprovado de romaneio e expedicao.",
        dependencies=("com_pedidos", "cad_produto_embalagens", "cad_veiculos"),
        notes=("Lotes e calculos logisticos exigem prova; nao reconstruir rastreabilidade.",), stock=True,
    ),
    ("saidas_mp", "saidas_mp"): _explicit_policy(
        "source_transaction", "estoque", "est_movimentos_mp_historicos",
        "Consumo historico de MP associado a OP/lote quando comprovado.",
        dependencies=("cad_materias_primas", "est_lotes_mp", "pcp_ordens_producao_historicas"),
        stock=True,
    ),
    ("saidas pa", "saidas_pa"): _explicit_policy(
        "source_transaction", "estoque", "est_movimentos_pa_historicos",
        "Saida historica de PA por pedido, produto e embalagem.",
        dependencies=("com_pedidos", "cad_produto_embalagens", "est_lotes_pa"),
        notes=("Historico pre-corte nao cria saldo ou disponibilidade operacional.",), stock=True,
    ),
    ("simulacao producao", "simula_producao"): _explicit_policy(
        "derived_calculation", "auditoria", "reconciliation.production_simulation",
        "Necessidades e custos simulados sao recalculaveis.",
        primary="formulas + pedidos + movimentos de estoque", risk="high",
        dependencies=("pcp_formula_versoes", "com_pedidos", "est_movimentos_mp"),
    ),
    ("simulacao producao", "simula_producao_parametro"): _explicit_policy(
        "derived_calculation", "auditoria", "reconciliation.production_simulation_parameters",
        "Parametros e resultados de simulacao nao sao fatos operacionais.",
        primary="formulas + pedidos + movimentos de estoque", risk="high",
        dependencies=("pcp_formula_versoes", "com_pedidos", "est_movimentos_pa"),
    ),
    ("vendedores", "tabela153241"): _explicit_policy(
        "source_master", "cadastros", "cad_pessoas_comerciais + cad_pessoa_papeis",
        "Cadastro mestre oficial de pessoas e papeis comerciais.",
        dependencies=("cad_pessoa_papeis",),
        notes=("Papel comercial nao concede privilegio de autenticacao.",),
    ),
    ("veiculos", "tabela153"): _explicit_policy(
        "source_master", "cadastros", "cad_veiculos",
        "Cadastro mestre oficial de veiculos.", dependencies=(),
    ),
}


def _is_formula_source(headers: set[str]) -> bool:
    return (
        "materia prima" in headers
        and "und/l" in headers
        and bool({"seq", "quantidade", "producao", "simula", "produzir"}.intersection(headers))
    )


def _is_guarantee_source(headers: list[str]) -> bool:
    normalized = {normalize_label(header) for header in headers}
    return any(header.startswith("pp") for header in normalized) and any(
        header.startswith("pv") for header in normalized
    )


def _policy_dict(policy: SourcePolicy) -> dict[str, object]:
    source = asdict(policy)
    return {
        "classification": source["classification"],
        "ownerDomain": source["owner_domain"],
        "targetEntity": source["target_entity"],
        "equivalentPrimarySource": source["equivalent_primary_source"],
        "preserveRows": source["preserve_rows"],
        "preserveMetadataOnly": source["preserve_metadata_only"],
        "normalizeLater": source["normalize_later"],
        "useForReconciliation": source["use_for_reconciliation"],
        "justification": source["justification"],
        "duplicateRisk": source["duplicate_risk"],
        "dependencies": list(source["dependencies"]),
        "qualityNotes": list(source["quality_notes"]),
        "stockRelevant": source["stock_relevant"],
        "affectsOperationalStock": source["affects_operational_stock"],
        "unconfirmedLotsAvailable": source["unconfirmed_lots_available"],
        "schemaDriftDetectable": True,
    }


def _catalog_tables(catalog: dict[str, object]) -> list[dict[str, object]]:
    tables = catalog.get("tables")
    if not isinstance(tables, list) or not all(isinstance(item, dict) for item in tables):
        raise ValueError("Invalid approved workbook source catalog.")
    return tables


def _hash_payload(values: list[str]) -> str:
    payload = json.dumps(values, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _exact_label(value: str) -> str:
    return unicodedata.normalize("NFC", value.strip())


def _yes_no(value: bool) -> str:
    return "sim" if value else "nao"


def _markdown_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", " ")
