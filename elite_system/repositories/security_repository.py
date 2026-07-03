from __future__ import annotations

import sqlite3
from typing import Any

from elite_system.domain.security import User


def create_user_record(
    conn: sqlite3.Connection,
    *,
    username: str,
    display_name: str,
    password_hash: str,
    role: str,
    status: str,
    must_change_password: bool,
) -> User:
    cur = conn.execute(
        """
        INSERT INTO users(username, display_name, password_hash, role, status, must_change_password)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (username, display_name, password_hash, role, status, int(must_change_password)),
    )
    return get_user_by_id(conn, int(cur.lastrowid))


def get_user_by_id(conn: sqlite3.Connection, user_id: int) -> User:
    row = conn.execute(
        """
        SELECT id, username, display_name, role, status, must_change_password
        FROM users
        WHERE id = ?
        """,
        (user_id,),
    ).fetchone()
    if row is None:
        raise LookupError(f"User {user_id} not found")
    return _user_from_row(row)


def get_user_with_password(conn: sqlite3.Connection, username: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT id, username, display_name, password_hash, role, status, must_change_password
        FROM users
        WHERE username = ?
        """,
        (username,),
    ).fetchone()


def list_users(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    return list(
        conn.execute(
            """
            SELECT id, username, display_name, role, status, must_change_password, last_login_at
            FROM users
            ORDER BY display_name, username
            """
        )
    )


def count_users(conn: sqlite3.Connection) -> int:
    return int(conn.execute("SELECT COUNT(*) FROM users").fetchone()[0])


def touch_last_login(conn: sqlite3.Connection, user_id: int, occurred_at: str) -> None:
    conn.execute(
        """
        UPDATE users
        SET last_login_at = ?, updated_at = ?
        WHERE id = ?
        """,
        (occurred_at, occurred_at, user_id),
    )


def create_session_record(
    conn: sqlite3.Connection,
    *,
    user_id: int,
    token_hash: str,
    expires_at: str,
    metadata_json: str,
) -> int:
    cur = conn.execute(
        """
        INSERT INTO user_sessions(user_id, token_hash, expires_at, metadata_json)
        VALUES (?, ?, ?, ?)
        """,
        (user_id, token_hash, expires_at, metadata_json),
    )
    return int(cur.lastrowid)


def get_active_session(conn: sqlite3.Connection, token_hash: str, now: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT us.id AS session_id, us.user_id, us.expires_at,
               u.username, u.display_name, u.role, u.status, u.must_change_password
        FROM user_sessions us
        JOIN users u ON u.id = us.user_id
        WHERE us.token_hash = ?
          AND us.revoked_at IS NULL
          AND us.expires_at > ?
        """,
        (token_hash, now),
    ).fetchone()


def revoke_session(conn: sqlite3.Connection, token_hash: str, revoked_at: str) -> None:
    conn.execute(
        """
        UPDATE user_sessions
        SET revoked_at = ?
        WHERE token_hash = ? AND revoked_at IS NULL
        """,
        (revoked_at, token_hash),
    )


def get_permission_action(conn: sqlite3.Connection, action_key: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT action_key, module, description, default_allowed, active, sort_order
        FROM permission_actions
        WHERE action_key = ?
        """,
        (action_key,),
    ).fetchone()


def list_permission_actions(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    return list(
        conn.execute(
            """
            SELECT action_key, module, description, default_allowed, active, sort_order
            FROM permission_actions
            WHERE active = 1
            ORDER BY sort_order, module, action_key
            """
        )
    )


def upsert_permission_action(
    conn: sqlite3.Connection,
    *,
    action_key: str,
    module: str,
    description: str,
    default_allowed: bool = True,
    active: bool = True,
    sort_order: int = 0,
) -> None:
    conn.execute(
        """
        INSERT INTO permission_actions(action_key, module, description, default_allowed, active, sort_order)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(action_key) DO UPDATE SET
            module = excluded.module,
            description = excluded.description,
            default_allowed = excluded.default_allowed,
            active = excluded.active,
            sort_order = excluded.sort_order,
            updated_at = CURRENT_TIMESTAMP
        """,
        (action_key, module, description, int(default_allowed), int(active), sort_order),
    )


def get_role_permission_override(conn: sqlite3.Connection, role: str, action_key: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT allowed
        FROM role_permission_overrides
        WHERE role = ? AND action_key = ?
        """,
        (role, action_key),
    ).fetchone()


def get_user_permission_override(conn: sqlite3.Connection, user_id: int, action_key: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT allowed
        FROM user_permission_overrides
        WHERE user_id = ? AND action_key = ?
        """,
        (user_id, action_key),
    ).fetchone()


def upsert_role_permission_override(conn: sqlite3.Connection, role: str, action_key: str, allowed: bool) -> None:
    conn.execute(
        """
        INSERT INTO role_permission_overrides(role, action_key, allowed)
        VALUES (?, ?, ?)
        ON CONFLICT(role, action_key) DO UPDATE SET
            allowed = excluded.allowed,
            updated_at = CURRENT_TIMESTAMP
        """,
        (role, action_key, int(allowed)),
    )


def upsert_user_permission_override(conn: sqlite3.Connection, user_id: int, action_key: str, allowed: bool) -> None:
    conn.execute(
        """
        INSERT INTO user_permission_overrides(user_id, action_key, allowed)
        VALUES (?, ?, ?)
        ON CONFLICT(user_id, action_key) DO UPDATE SET
            allowed = excluded.allowed,
            updated_at = CURRENT_TIMESTAMP
        """,
        (user_id, action_key, int(allowed)),
    )


def latest_action_hash(conn: sqlite3.Connection) -> str | None:
    row = conn.execute("SELECT entry_hash FROM action_logs ORDER BY id DESC LIMIT 1").fetchone()
    return None if row is None else str(row["entry_hash"])


def insert_action_log(conn: sqlite3.Connection, payload: dict[str, Any]) -> int:
    cur = conn.execute(
        """
        INSERT INTO action_logs(
            actor_user_id, occurred_at, action, entity_type, entity_id, status,
            request_id, source_ip, user_agent, before_json, after_json,
            metadata_json, previous_hash, entry_hash
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            payload["actor_user_id"],
            payload["occurred_at"],
            payload["action"],
            payload["entity_type"],
            payload["entity_id"],
            payload["status"],
            payload["request_id"],
            payload["source_ip"],
            payload["user_agent"],
            payload["before_json"],
            payload["after_json"],
            payload["metadata_json"],
            payload["previous_hash"],
            payload["entry_hash"],
        ),
    )
    return int(cur.lastrowid)


def _user_from_row(row: sqlite3.Row) -> User:
    return User(
        id=int(row["id"]),
        username=str(row["username"]),
        display_name=str(row["display_name"]),
        role=str(row["role"]),
        status=str(row["status"]),
        must_change_password=bool(row["must_change_password"]),
    )
