from __future__ import annotations

from dataclasses import dataclass


VALID_ROLES = {"admin", "comercial", "producao", "estoque", "expedicao", "auditoria"}
ACTIVE_STATUS = "active"


@dataclass(frozen=True)
class User:
    id: int
    username: str
    display_name: str
    role: str
    status: str
    must_change_password: bool


@dataclass(frozen=True)
class AuthResult:
    ok: bool
    user: User | None = None
    reason: str | None = None
