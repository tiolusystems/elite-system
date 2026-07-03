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


def touch_last_login(conn: sqlite3.Connection, user_id: int, occurred_at: str) -> None:
    conn.execute(
        """
        UPDATE users
        SET last_login_at = ?, updated_at = ?
        WHERE id = ?
        """,
        (occurred_at, occurred_at, user_id),
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
