from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

from elite_system.db import connect, init_db
from elite_system.domain.cadastros import (
    Cliente,
    LimiteCreditoCliente,
    MateriaPrima,
    StatusCredito,
)
from elite_system.services.cadastros import (
    criar_cliente,
    listar_alertas_cadastros_pendentes,
    registrar_limite_credito,
    validar_e_registrar_cadastros,
)
from elite_system.services.security import create_user, set_user_permission


class CadastroServiceTests(unittest.TestCase):
    def test_create_cliente_records_master_data_and_audit_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "cadastros.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="cadastros",
                    password="StrongPass123!",
                    display_name="Cadastros",
                    role="comercial",
                )
                cliente_id = criar_cliente(
                    conn,
                    Cliente(
                        nome="Cliente A",
                        cidade="Ribeirao Preto",
                        uf="SP",
                        codigo_legado="CLI001",
                        apelidos=("Cliente Apelido",),
                    ),
                    actor_user_id=user.id,
                    payload_origem={"origem": "teste"},
                )
                conn.commit()

                row = conn.execute("SELECT nome, nome_norm, uf, created_by FROM cad_clientes WHERE id = ?", (cliente_id,)).fetchone()
                actions = [
                    row[0]
                    for row in conn.execute(
                        """
                        SELECT action
                        FROM action_logs
                        WHERE action = 'cadastros.cliente_created'
                        """
                    )
                ]

        self.assertEqual(dict(row), {"nome": "Cliente A", "nome_norm": "CLIENTE A", "uf": "SP", "created_by": user.id})
        self.assertEqual(actions, ["cadastros.cliente_created"])

    def test_validation_issues_are_recorded_as_pending_queue(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "cadastros.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="auditor",
                    password="StrongPass123!",
                    display_name="Auditor",
                    role="auditoria",
                )
                issues = validar_e_registrar_cadastros(
                    conn,
                    actor_user_id=user.id,
                    clientes=(
                        Cliente(nome="Fazenda Boa Vista", cidade="Rio Verde", uf="GO", codigo_legado="CLI001"),
                        Cliente(nome="fazenda boa vista", cidade="Rio Verde", uf="GO", codigo_legado="CLI002"),
                    ),
                    materias_primas=(
                        MateriaPrima(
                            nome="Ureia Tecnica",
                            sku_corrigido="MP001",
                            unidade_base_estoque="kg",
                            codigo_legado="Ureia Tecnica",
                        ),
                    ),
                )
                conn.commit()
                pending = listar_alertas_cadastros_pendentes(conn)

        self.assertEqual(len(issues), 2)
        self.assertEqual(len(pending), 2)
        self.assertEqual({item["code"] for item in pending}, {"duplicate_nome_normalized", "legacy_sku_looks_like_name"})

    def test_credit_limit_records_snapshot_and_requires_same_actor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "cadastros.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="credito",
                    password="StrongPass123!",
                    display_name="Credito",
                    role="comercial",
                )
                cliente_id = criar_cliente(
                    conn,
                    Cliente(nome="Cliente Credito", cidade="Goiania", uf="GO"),
                    actor_user_id=user.id,
                )
                with self.assertRaisesRegex(ValueError, "updated_by must match"):
                    registrar_limite_credito(
                        conn,
                        LimiteCreditoCliente(
                            cliente_id=str(cliente_id),
                            limite_disponivel=0.0,
                            status_credito=StatusCredito.BLOQUEADO,
                            motivo="inadimplencia",
                            updated_by=999,
                        ),
                        actor_user_id=user.id,
                    )

                limite_id = registrar_limite_credito(
                    conn,
                    LimiteCreditoCliente(
                        cliente_id=str(cliente_id),
                        limite_disponivel=5000.0,
                        limite_manual=5000.0,
                        status_credito=StatusCredito.LIBERADO,
                        updated_by=user.id,
                    ),
                    actor_user_id=user.id,
                )
                conn.commit()
                row = conn.execute(
                    """
                    SELECT cliente_id, limite_disponivel, status_credito, updated_by
                    FROM cad_limites_credito_cliente
                    WHERE id = ?
                    """,
                    (limite_id,),
                ).fetchone()

        self.assertEqual(row["cliente_id"], cliente_id)
        self.assertEqual(row["limite_disponivel"], 5000.0)
        self.assertEqual(row["status_credito"], "liberado")
        self.assertEqual(row["updated_by"], user.id)

    def test_permission_override_blocks_master_data_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "cadastros.sqlite"
            init_db(db_path)
            with connect(db_path) as conn:
                user = create_user(
                    conn,
                    username="bloqueado",
                    password="StrongPass123!",
                    display_name="Bloqueado",
                    role="comercial",
                )
                set_user_permission(
                    conn,
                    actor_user_id=user.id,
                    user_id=user.id,
                    action_key="cadastros.manage",
                    allowed=False,
                )
                with self.assertRaises(PermissionError):
                    criar_cliente(
                        conn,
                        Cliente(nome="Cliente Bloqueado", cidade="Goiania", uf="GO"),
                        actor_user_id=user.id,
                    )
                conn.commit()
                denied = conn.execute(
                    """
                    SELECT status
                    FROM action_logs
                    WHERE action = 'cadastros.manage.denied'
                    """
                ).fetchone()

        self.assertEqual(denied["status"], "denied")


if __name__ == "__main__":
    unittest.main()
