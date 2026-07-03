from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
from typing import Any

from elite_system.domain.security import ACTIVE_STATUS, VALID_ROLES, AuthResult, PermissionDecision, User
from elite_system.repositories import security_repository


PASSWORD_ALGORITHM = "pbkdf2_sha256"
PASSWORD_ITERATIONS = 600_000
SESSION_TOKEN_BYTES = 32


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


def create_session(
    conn: sqlite3.Connection,
    *,
    user_id: int,
    hours: int = 12,
    metadata: dict[str, Any] | None = None,
) -> str:
    user = security_repository.get_user_by_id(conn, user_id)
    token = secrets.token_urlsafe(SESSION_TOKEN_BYTES)
    now = datetime.now(timezone.utc)
    expires_at = (now + timedelta(hours=hours)).isoformat(timespec="seconds")
    security_repository.create_session_record(
        conn,
        user_id=user.id,
        token_hash=_token_hash(token),
        expires_at=expires_at,
        metadata_json=_json_dump(metadata),
    )
    log_action(
        conn,
        actor_user_id=user.id,
        action="auth.session_created",
        entity_type="user_sessions",
        entity_id=str(user.id),
        metadata={"hours": hours},
        occurred_at=now.isoformat(timespec="seconds"),
    )
    return token


def user_from_session(conn: sqlite3.Connection, token: str | None) -> User | None:
    if not token:
        return None
    row = security_repository.get_active_session(conn, _token_hash(token), _utc_now())
    if row is None:
        return None
    return User(
        id=int(row["user_id"]),
        username=str(row["username"]),
        display_name=str(row["display_name"]),
        role=str(row["role"]),
        status=str(row["status"]),
        must_change_password=bool(row["must_change_password"]),
    )


def revoke_session(conn: sqlite3.Connection, *, token: str | None, actor_user_id: int | None = None) -> None:
    if not token:
        return
    occurred_at = _utc_now()
    security_repository.revoke_session(conn, _token_hash(token), occurred_at)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="auth.session_revoked",
        entity_type="user_sessions",
        status="success",
        occurred_at=occurred_at,
    )


def list_users(conn: sqlite3.Connection) -> list[dict[str, object]]:
    return [dict(row) for row in security_repository.list_users(conn)]


def has_users(conn: sqlite3.Connection) -> bool:
    return security_repository.count_users(conn) > 0


def can_perform_action(conn: sqlite3.Connection, *, user_id: int, action_key: str) -> PermissionDecision:
    action_key = _normalize_action_key(action_key)
    try:
        user = security_repository.get_user_by_id(conn, user_id)
    except LookupError:
        return PermissionDecision(False, action_key, "user", "user_not_found")

    if user.status != ACTIVE_STATUS:
        return PermissionDecision(False, action_key, "user", "inactive_user")

    user_override = security_repository.get_user_permission_override(conn, user.id, action_key)
    if user_override is not None:
        allowed = bool(user_override["allowed"])
        return PermissionDecision(allowed, action_key, "user_override", "explicit_user_setting")

    role_override = security_repository.get_role_permission_override(conn, user.role, action_key)
    if role_override is not None:
        allowed = bool(role_override["allowed"])
        return PermissionDecision(allowed, action_key, "role_override", "explicit_role_setting")

    action = security_repository.get_permission_action(conn, action_key)
    if action is not None:
        allowed = bool(action["default_allowed"])
        return PermissionDecision(allowed, action_key, "default", "default_action_setting")

    return PermissionDecision(True, action_key, "implicit_default", "full_access_until_restricted")


def set_role_permission(
    conn: sqlite3.Connection,
    *,
    actor_user_id: int | None,
    role: str,
    action_key: str,
    allowed: bool,
) -> None:
    role = _normalize_role(role)
    action_key = _ensure_permission_action(conn, action_key)
    before = _permission_override_payload(security_repository.get_role_permission_override(conn, role, action_key))
    security_repository.upsert_role_permission_override(conn, role, action_key, allowed)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="security.role_permission_updated",
        entity_type="role_permission_overrides",
        entity_id=f"{role}:{action_key}",
        before=before,
        after={"role": role, "action_key": action_key, "allowed": allowed},
    )


def set_user_permission(
    conn: sqlite3.Connection,
    *,
    actor_user_id: int | None,
    user_id: int,
    action_key: str,
    allowed: bool,
) -> None:
    user = security_repository.get_user_by_id(conn, user_id)
    action_key = _ensure_permission_action(conn, action_key)
    before = _permission_override_payload(security_repository.get_user_permission_override(conn, user.id, action_key))
    security_repository.upsert_user_permission_override(conn, user.id, action_key, allowed)
    log_action(
        conn,
        actor_user_id=actor_user_id,
        action="security.user_permission_updated",
        entity_type="user_permission_overrides",
        entity_id=f"{user.id}:{action_key}",
        before=before,
        after={"user_id": user.id, "action_key": action_key, "allowed": allowed},
    )


def list_permission_matrix(conn: sqlite3.Connection, *, user_id: int | None = None) -> list[dict[str, object]]:
    rows = []
    for action in security_repository.list_permission_actions(conn):
        item = dict(action)
        if user_id is not None:
            decision = can_perform_action(conn, user_id=user_id, action_key=str(action["action_key"]))
            item["allowed_for_user"] = decision.allowed
            item["decision_source"] = decision.source
            item["decision_reason"] = decision.reason
        rows.append(item)
    return rows


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


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


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


def _ensure_permission_action(conn: sqlite3.Connection, action_key: str) -> str:
    action_key = _normalize_action_key(action_key)
    if security_repository.get_permission_action(conn, action_key) is None:
        module = action_key.split(".", 1)[0] if "." in action_key else "custom"
        security_repository.upsert_permission_action(
            conn,
            action_key=action_key,
            module=module,
            description=f"Permissao operacional: {action_key}",
            default_allowed=True,
        )
    return action_key


def _normalize_action_key(action_key: str) -> str:
    value = action_key.strip().casefold()
    if not value:
        raise ValueError("action_key is required")
    return value


def _permission_override_payload(row: sqlite3.Row | None) -> dict[str, Any]:
    if row is None:
        return {}
    return {"allowed": bool(row["allowed"])}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
