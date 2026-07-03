from __future__ import annotations

import base64
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
import sqlite3
from typing import Any

from elite_system.domain.security import ACTIVE_STATUS, VALID_ROLES, AuthResult, User
from elite_system.repositories import security_repository


PASSWORD_ALGORITHM = "pbkdf2_sha256"
PASSWORD_ITERATIONS = 600_000


def create_user(
    conn: sqlite3.Connection,
    *,
    username: str,
    password: str,
    display_name: str | None = None,
    role: str = "comercial",
    actor_user_id: int | None = None,
    must_change_password: bool = False,
) -> User:
    username = _normalize_username(username)
    role = _normalize_role(role)
    _validate_password(password)
    user = security_repository.create_user_record(
        conn,
        username=username,
        display_name=display_name or username,
        password_hash=hash_password(password),
        role=role,
        status=ACTIVE_STATUS,
        must_change_password=must_change_password,
    )
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="security.user_created",
        entity_type="users",
        entity_id=str(user.id),
        after={"username": user.username, "role": user.role, "status": user.status},
    )
    return user


def authenticate_user(
    conn: sqlite3.Connection,
    *,
    username: str,
    password: str,
    request_id: str | None = None,
    source_ip: str | None = None,
    user_agent: str | None = None,
) -> AuthResult:
    username = _normalize_username(username)
    occurred_at = _utc_now()
    row = security_repository.get_user_with_password(conn, username)
    if row is None:
        log_action(
            conn,
            actor_user_id=None,
            action="auth.login.failed",
            entity_type="users",
            entity_id=None,
            status="denied",
            metadata={"username": username, "reason": "unknown_user"},
            request_id=request_id,
            source_ip=source_ip,
            user_agent=user_agent,
            occurred_at=occurred_at,
        )
        return AuthResult(ok=False, reason="unknown_user")

    user = User(
        id=int(row["id"]),
        username=str(row["username"]),
        display_name=str(row["display_name"]),
        role=str(row["role"]),
        status=str(row["status"]),
        must_change_password=bool(row["must_change_password"]),
    )
    if user.status != ACTIVE_STATUS:
        log_action(
            conn,
            actor_user_id=user.id,
            action="auth.login.failed",
            entity_type="users",
            entity_id=str(user.id),
            status="denied",
            metadata={"username": username, "reason": "inactive_user"},
            request_id=request_id,
            source_ip=source_ip,
            user_agent=user_agent,
            occurred_at=occurred_at,
        )
        return AuthResult(ok=False, reason="inactive_user")

    if not verify_password(password, str(row["password_hash"])):
        log_action(
            conn,
            actor_user_id=user.id,
            action="auth.login.failed",
            entity_type="users",
            entity_id=str(user.id),
            status="denied",
            metadata={"username": username, "reason": "bad_password"},
            request_id=request_id,
            source_ip=source_ip,
            user_agent=user_agent,
            occurred_at=occurred_at,
        )
        return AuthResult(ok=False, reason="bad_password")

    security_repository.touch_last_login(conn, user.id, occurred_at)
    log_action(
        conn,
        actor_user_id=user.id,
        action="auth.login.success",
        entity_type="users",
        entity_id=str(user.id),
        request_id=request_id,
        source_ip=source_ip,
        user_agent=user_agent,
        occurred_at=occurred_at,
    )
    return AuthResult(ok=True, user=user)


def log_action(
    conn: sqlite3.Connection,
    *,
    actor_user_id: int | None,
    action: str,
    entity_type: str | None = None,
    entity_id: str | None = None,
    status: str = "success",
    request_id: str | None = None,
    source_ip: str | None = None,
    user_agent: str | None = None,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
    metadata: dict[str, Any] | None = None,
    occurred_at: str | None = None,
) -> int:
    occurred_at = occurred_at or _utc_now()
    previous_hash = security_repository.latest_action_hash(conn)
    safe_payload = {
        "actor_user_id": actor_user_id,
        "occurred_at": occurred_at,
        "action": action,
        "entity_type": entity_type,
        "entity_id": entity_id,
        "status": status,
        "request_id": request_id,
        "source_ip": source_ip,
        "user_agent": user_agent,
        "before_json": _json_dump(before),
        "after_json": _json_dump(after),
        "metadata_json": _json_dump(metadata),
        "previous_hash": previous_hash,
    }
    safe_payload["entry_hash"] = _entry_hash(safe_payload)
    return security_repository.insert_action_log(conn, safe_payload)


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PASSWORD_ITERATIONS)
    return "$".join(
        [
            PASSWORD_ALGORITHM,
            str(PASSWORD_ITERATIONS),
            _b64encode(salt),
            _b64encode(digest),
        ]
    )


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        algorithm, iterations_text, salt_text, digest_text = stored_hash.split("$", 3)
        if algorithm != PASSWORD_ALGORITHM:
            return False
        iterations = int(iterations_text)
        salt = _b64decode(salt_text)
        expected = _b64decode(digest_text)
    except (ValueError, TypeError):
        return False
    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected)


def _entry_hash(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _json_dump(value: dict[str, Any] | None) -> str:
    return json.dumps(value or {}, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _normalize_username(username: str) -> str:
    value = username.strip().casefold()
    if not value:
        raise ValueError("username is required")
    return value


def _normalize_role(role: str) -> str:
    value = role.strip().casefold()
    if value not in VALID_ROLES:
        raise ValueError(f"invalid role: {role}")
    return value


def _validate_password(password: str) -> None:
    if len(password) < 8:
        raise ValueError("password must have at least 8 characters")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
