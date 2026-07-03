from __future__ import annotations

import argparse
import json
from pathlib import Path

from .audit import run_audit
from .db import init_db
from .migration import import_workbook


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="elite", description="Elite System")
    sub = parser.add_subparsers(dest="command", required=True)

    init_parser = sub.add_parser("init", help="Inicializa o banco local")
    init_parser.add_argument("--db", required=True, type=Path)

    import_parser = sub.add_parser("import-excel", help="Importa uma workbook Excel para o banco auditavel")
    import_parser.add_argument("--db", required=True, type=Path)
    import_parser.add_argument("--workbook", required=True, type=Path)

    audit_parser = sub.add_parser("audit", help="Roda auditoria da ultima importacao")
    audit_parser.add_argument("--db", required=True, type=Path)
    audit_parser.add_argument("--batch-id", type=int)

    args = parser.parse_args(argv)
    if args.command == "init":
        init_db(args.db)
        _print({"status": "ok", "db": str(args.db.resolve())})
        return 0
    if args.command == "import-excel":
        _print(import_workbook(args.workbook, args.db))
        return 0
    if args.command == "audit":
        _print(run_audit(args.db, args.batch_id))
        return 0
    parser.error("Comando invalido")
    return 2


def _print(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    raise SystemExit(main())
