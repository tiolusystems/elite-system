from __future__ import annotations

import json
import re
import sqlite3
from enum import StrEnum
from typing import Any

from elite_system.domain.cadastros import (
    Cliente,
    Embalagem,
    LimiteCreditoCliente,
    MateriaPrima,
    PessoaComercial,
    ProdutoBase,
    Veiculo,
)
from elite_system.validators.cadastros import ValidationIssue, normalize_key


def insert_cliente(
    conn: sqlite3.Connection,
    cliente: Cliente,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_clientes(
            codigo_legado, nome, nome_norm, cidade, uf, status, apelidos_json,
            valor_total_compras, source_row_id, source_batch_id,
            payload_origem_json, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            cliente.codigo_legado,
            cliente.nome,
            normalize_key(cliente.nome),
            cliente.cidade,
            cliente.uf,
            _enum_value(cliente.status),
            _json_dump(list(cliente.apelidos)),
            cliente.valor_total_compras,
            cliente.source_row_id,
            cliente.source_batch_id,
            _json_dump(payload_origem),
            actor_user_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def get_cliente(conn: sqlite3.Connection, cliente_id: int) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM cad_clientes WHERE id = ?", (cliente_id,)).fetchone()


def insert_pessoa_comercial(
    conn: sqlite3.Connection,
    pessoa: PessoaComercial,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_pessoas_comerciais(
            codigo_legado, nome, nome_norm, tipo_comercial, papeis_json, status,
            vendedor_responsavel_id, apelidos_json, grafias_incorretas_json,
            payload_origem_json, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            pessoa.codigo_legado,
            pessoa.nome,
            normalize_key(pessoa.nome),
            _enum_value(pessoa.tipo_comercial),
            _json_dump([_enum_value(papel) for papel in pessoa.papeis]),
            _enum_value(pessoa.status),
            _int_or_none(pessoa.vendedor_responsavel_id),
            _json_dump(list(pessoa.apelidos)),
            _json_dump(list(pessoa.grafias_incorretas)),
            _json_dump(payload_origem),
            actor_user_id,
            actor_user_id,
        ),
    )
    pessoa_id = int(cur.lastrowid)
    insert_pessoa_alias(conn, pessoa_id=pessoa_id, alias=pessoa.nome, tipo="nome")
    for alias in pessoa.apelidos:
        insert_pessoa_alias(conn, pessoa_id=pessoa_id, alias=alias, tipo="apelido")
    for alias in pessoa.grafias_incorretas:
        insert_pessoa_alias(conn, pessoa_id=pessoa_id, alias=alias, tipo="grafia_incorreta")
    return pessoa_id


def insert_pessoa_alias(conn: sqlite3.Connection, *, pessoa_id: int, alias: str, tipo: str) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
        VALUES (?, ?, ?, ?)
        """,
        (pessoa_id, alias, normalize_key(alias), tipo),
    )
    return int(cur.lastrowid)


def insert_materia_prima(
    conn: sqlite3.Connection,
    materia_prima: MateriaPrima,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_materias_primas(
            codigo_legado, sku_corrigido, nome, nome_norm, unidade_base_estoque,
            status, tipo, densidade, estoque_minimo, ncm, ibama, codigo_ads,
            payload_origem_json, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            materia_prima.codigo_legado,
            materia_prima.sku_corrigido,
            materia_prima.nome,
            normalize_key(materia_prima.nome),
            materia_prima.unidade_base_estoque,
            _enum_value(materia_prima.status),
            materia_prima.tipo,
            materia_prima.densidade,
            materia_prima.estoque_minimo,
            materia_prima.ncm,
            materia_prima.ibama,
            materia_prima.codigo_ads,
            _json_dump(payload_origem),
            actor_user_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def insert_produto_base(
    conn: sqlite3.Connection,
    produto: ProdutoBase,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_produtos_base(
            codigo_produto, nome, nome_norm, status, grupo, densidade_kg_l,
            reg_mapa, ncm, ibama, ads, payload_origem_json, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            produto.codigo_produto,
            produto.nome,
            normalize_key(produto.nome),
            _enum_value(produto.status),
            produto.grupo,
            produto.densidade_kg_l,
            produto.reg_mapa,
            produto.ncm,
            produto.ibama,
            produto.ads,
            _json_dump(payload_origem),
            actor_user_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def insert_embalagem(
    conn: sqlite3.Connection,
    embalagem: Embalagem,
    *,
    actor_user_id: int | None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_embalagens(
            codigo_legado, descricao, descricao_norm, unidade, volume_litros,
            controla_estoque, materia_prima_id, status, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            embalagem.codigo_legado,
            embalagem.descricao,
            normalize_key(embalagem.descricao),
            embalagem.unidade,
            embalagem.volume_litros,
            int(embalagem.controla_estoque),
            _int_or_none(embalagem.materia_prima_id),
            _enum_value(embalagem.status),
            actor_user_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def insert_veiculo(
    conn: sqlite3.Connection,
    veiculo: Veiculo,
    *,
    actor_user_id: int | None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_veiculos(
            codigo_legado, descricao, descricao_norm, placa, placa_norm,
            status, capacidade, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            veiculo.codigo_legado,
            veiculo.descricao,
            normalize_key(veiculo.descricao),
            veiculo.placa,
            _normalize_identifier(veiculo.placa),
            _enum_value(veiculo.status),
            veiculo.capacidade,
            actor_user_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def insert_limite_credito(
    conn: sqlite3.Connection,
    limite: LimiteCreditoCliente,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cad_limites_credito_cliente(
            cliente_id, limite_manual, limite_calculado, limite_disponivel,
            status_credito, motivo, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            _int_or_none(limite.cliente_id),
            limite.limite_manual,
            limite.limite_calculado,
            limite.limite_disponivel,
            _enum_value(limite.status_credito),
            limite.motivo,
            limite.updated_by,
        ),
    )
    return int(cur.lastrowid)


def insert_validation_issue(
    conn: sqlite3.Connection,
    issue: ValidationIssue,
    *,
    actor_user_id: int | None = None,
    source_batch_id: int | None = None,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO cadastro_validation_issues(
            entity, entity_key, severity, code, message, field,
            payload_json, source_batch_id, created_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            issue.entity,
            issue.entity_key,
            _enum_value(issue.severity),
            issue.code,
            issue.message,
            issue.field,
            _json_dump(issue.payload),
            source_batch_id,
            actor_user_id,
        ),
    )
    return int(cur.lastrowid)


def list_pending_validation_issues(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    return list(
        conn.execute(
            """
            SELECT id, entity, entity_key, severity, code, message, field, payload_json, created_at
            FROM cadastro_validation_issues
            WHERE status = 'pending'
            ORDER BY severity, entity, id
            """
        )
    )


def _json_dump(value: Any | None) -> str:
    return json.dumps(value if value is not None else {}, ensure_ascii=False, sort_keys=True)


def _enum_value(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, StrEnum):
        return value.value
    return str(value)


def _int_or_none(value: str | int | None) -> int | None:
    if value is None:
        return None
    return int(value)


def _normalize_identifier(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    return re.sub(r"[^A-Za-z0-9]+", "", value).upper()
