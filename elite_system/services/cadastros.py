from __future__ import annotations

import sqlite3
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
from elite_system.repositories import cadastros_repository
from elite_system.services.security import can_perform_action, log_action
from elite_system.validators.cadastros import ValidationIssue, validate_master_data


def criar_cliente(
    conn: sqlite3.Connection,
    cliente: Cliente,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    cliente_id = cadastros_repository.insert_cliente(
        conn,
        cliente,
        actor_user_id=actor_user_id,
        payload_origem=payload_origem,
    )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.cliente_created",
        entity_type="cad_clientes",
        entity_id=str(cliente_id),
        after={"nome": cliente.nome, "cidade": cliente.cidade, "uf": cliente.uf, "status": str(cliente.status)},
    )
    return cliente_id


def criar_pessoa_comercial(
    conn: sqlite3.Connection,
    pessoa: PessoaComercial,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    pessoa_id = cadastros_repository.insert_pessoa_comercial(
        conn,
        pessoa,
        actor_user_id=actor_user_id,
        payload_origem=payload_origem,
    )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.pessoa_comercial_created",
        entity_type="cad_pessoas_comerciais",
        entity_id=str(pessoa_id),
        after={"nome": pessoa.nome, "tipo_comercial": str(pessoa.tipo_comercial), "status": str(pessoa.status)},
    )
    return pessoa_id


def criar_materia_prima(
    conn: sqlite3.Connection,
    materia_prima: MateriaPrima,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    materia_prima_id = cadastros_repository.insert_materia_prima(
        conn,
        materia_prima,
        actor_user_id=actor_user_id,
        payload_origem=payload_origem,
    )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.materia_prima_created",
        entity_type="cad_materias_primas",
        entity_id=str(materia_prima_id),
        after={"nome": materia_prima.nome, "sku_corrigido": materia_prima.sku_corrigido},
    )
    return materia_prima_id


def criar_produto_base(
    conn: sqlite3.Connection,
    produto: ProdutoBase,
    *,
    actor_user_id: int | None,
    payload_origem: dict[str, Any] | None = None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    produto_id = cadastros_repository.insert_produto_base(
        conn,
        produto,
        actor_user_id=actor_user_id,
        payload_origem=payload_origem,
    )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.produto_base_created",
        entity_type="cad_produtos_base",
        entity_id=str(produto_id),
        after={
            "nome": produto.nome,
            "codigo_produto": produto.codigo_produto,
            "prazo_validade_meses": produto.prazo_validade_meses,
        },
    )
    return produto_id


def criar_embalagem(
    conn: sqlite3.Connection,
    embalagem: Embalagem,
    *,
    actor_user_id: int | None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    embalagem_id = cadastros_repository.insert_embalagem(conn, embalagem, actor_user_id=actor_user_id)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.embalagem_created",
        entity_type="cad_embalagens",
        entity_id=str(embalagem_id),
        after={"descricao": embalagem.descricao, "unidade": embalagem.unidade},
    )
    return embalagem_id


def criar_veiculo(
    conn: sqlite3.Connection,
    veiculo: Veiculo,
    *,
    actor_user_id: int | None,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.manage")
    veiculo_id = cadastros_repository.insert_veiculo(conn, veiculo, actor_user_id=actor_user_id)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.veiculo_created",
        entity_type="cad_veiculos",
        entity_id=str(veiculo_id),
        after={"descricao": veiculo.descricao, "placa": veiculo.placa},
    )
    return veiculo_id


def registrar_limite_credito(
    conn: sqlite3.Connection,
    limite: LimiteCreditoCliente,
    *,
    actor_user_id: int,
) -> int:
    _ensure_allowed(conn, actor_user_id, "cadastros.credit.manage")
    if limite.updated_by != actor_user_id:
        raise ValueError("limite.updated_by must match actor_user_id")
    limite_id = cadastros_repository.insert_limite_credito(conn, limite)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.credit_limit_recorded",
        entity_type="cad_limites_credito_cliente",
        entity_id=str(limite_id),
        after={
            "cliente_id": limite.cliente_id,
            "limite_disponivel": limite.limite_disponivel,
            "status_credito": str(limite.status_credito),
        },
    )
    return limite_id


def validar_e_registrar_cadastros(
    conn: sqlite3.Connection,
    *,
    actor_user_id: int | None,
    clientes: tuple[Cliente, ...] = (),
    pessoas: tuple[PessoaComercial, ...] = (),
    materias_primas: tuple[MateriaPrima, ...] = (),
    produtos: tuple[ProdutoBase, ...] = (),
    embalagens: tuple[Embalagem, ...] = (),
    veiculos: tuple[Veiculo, ...] = (),
    source_batch_id: int | None = None,
) -> tuple[ValidationIssue, ...]:
    _ensure_allowed(conn, actor_user_id, "cadastros.validate")
    issues = validate_master_data(
        clientes=clientes,
        pessoas=pessoas,
        materias_primas=materias_primas,
        produtos=produtos,
        embalagens=embalagens,
        veiculos=veiculos,
    )
    for issue in issues:
        cadastros_repository.insert_validation_issue(
            conn,
            issue,
            actor_user_id=actor_user_id,
            source_batch_id=source_batch_id,
        )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="cadastros.validation_executed",
        entity_type="cadastro_validation_issues",
        after={
            "issues": len(issues),
            "errors": sum(1 for issue in issues if issue.severity.value == "error"),
            "warnings": sum(1 for issue in issues if issue.severity.value == "warning"),
            "source_batch_id": source_batch_id,
        },
    )
    return issues


def listar_alertas_cadastros_pendentes(conn: sqlite3.Connection) -> list[dict[str, object]]:
    return [dict(row) for row in cadastros_repository.list_pending_validation_issues(conn)]


def _ensure_allowed(conn: sqlite3.Connection, actor_user_id: int | None, action_key: str) -> None:
    if actor_user_id is None:
        return
    decision = can_perform_action(conn, user_id=actor_user_id, action_key=action_key)
    if decision.allowed:
        return
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action=f"{action_key}.denied",
        entity_type="permission_actions",
        entity_id=action_key,
        status="denied",
        metadata={"source": decision.source, "reason": decision.reason},
    )
    raise PermissionError(f"not allowed: {action_key}")
