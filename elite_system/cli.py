from __future__ import annotations

import argparse
from dataclasses import asdict, is_dataclass
from getpass import getpass
import json
from pathlib import Path

from .audit import run_audit
from .db import connect, init_db
from .migration import import_workbook
from .services.security import authenticate_user, create_user


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="elite", description="Elite System")
    sub = parser.add_subparsers(dest="command", required=True)

    init_parser = sub.add_parser("init", help="Inicializa o banco local")
    init_parser.add_argument("--db", required=True, type=Path)

    import_parser = sub.add_parser("import-excel", help="Importa uma workbook Excel para o banco auditavel")
    import_parser.add_argument("--db", required=True, type=Path)
    import_parser.add_argument("--workbook", required=True, type=Path)
    import_parser.add_argument("--actor-user-id", type=int)

    audit_parser = sub.add_parser("audit", help="Roda auditoria da ultima importacao")
    audit_parser.add_argument("--db", required=True, type=Path)
    audit_parser.add_argument("--batch-id", type=int)

    user_parser = sub.add_parser("create-user", help="Cria usuario operacional")
    user_parser.add_argument("--db", required=True, type=Path)
    user_parser.add_argument("--username", required=True)
    user_parser.add_argument("--display-name")
    user_parser.add_argument("--role", default="comercial")
    user_parser.add_argument("--password")
    user_parser.add_argument("--must-change-password", action="store_true")

    login_parser = sub.add_parser("login", help="Valida login e registra a tentativa")
    login_parser.add_argument("--db", required=True, type=Path)
    login_parser.add_argument("--username", required=True)
    login_parser.add_argument("--password")

    audit_log_parser = sub.add_parser("audit-log", help="Lista ultimas acoes registradas")
    audit_log_parser.add_argument("--db", required=True, type=Path)
    audit_log_parser.add_argument("--limit", type=int, default=20)

    args = parser.parse_args(argv)
    if args.command == "init":
        init_db(args.db)
        _print({"status": "ok", "db": str(args.db.resolve())})
        return 0
    if args.command == "import-excel":
        _print(import_workbook(args.workbook, args.db, actor_user_id=args.actor_user_id))
        return 0
    if args.command == "audit":
        _print(run_audit(args.db, args.batch_id))
        return 0
    if args.command == "create-user":
        init_db(args.db)
        password = args.password or getpass("Senha: ")
        with connect(args.db) as conn:
            user = create_user(
                conn,
                username=args.username,
                password=password,
                display_name=args.display_name,
                role=args.role,
                must_change_password=args.must_change_password,
            )
            conn.commit()
        _print({"status": "ok", "user": user})
        return 0
    if args.command == "login":
        init_db(args.db)
        password = args.password or getpass("Senha: ")
        with connect(args.db) as conn:
            result = authenticate_user(conn, username=args.username, password=password)
            conn.commit()
        _print({"status": "ok" if result.ok else "denied", "user": result.user, "reason": result.reason})
        return 0 if result.ok else 1
    if args.command == "audit-log":
        init_db(args.db)
        with connect(args.db) as conn:
            rows = [
                dict(row)
                for row in conn.execute(
                    """
                    SELECT id, actor_user_id, occurred_at, action, entity_type, entity_id, status, entry_hash
                    FROM action_logs
                    ORDER BY id DESC
                    LIMIT ?
                    """,
                    (args.limit,),
                )
            ]
        _print({"status": "ok", "actions": rows})
        return 0
    parser.error("Comando invalido")
    return 2


def _print(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, default=_json_default))


def _json_default(value: object) -> object:
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, Path):
        return str(value)
    return str(value)


if __name__ == "__main__":
    raise SystemExit(main())
