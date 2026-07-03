from __future__ import annotations

from html import escape
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

from elite_system.db import connect, init_db
from elite_system.services.security import (
    authenticate_user,
    can_perform_action,
    create_session,
    create_user,
    has_users,
    list_permission_matrix,
    list_users,
    revoke_session,
    set_user_permission,
    user_from_session,
)


SESSION_COOKIE = "elite_session"
TEST_PATH_MARKERS = ("test", "teste", "tmp", "temp", "descart", "etapa2", "scratch")


def classify_database_condition(db_path: str | Path) -> dict[str, object]:
    path = Path(db_path)
    resolved = _safe_resolve(path)
    temp_root = _safe_resolve(Path(tempfile.gettempdir()))
    path_text = str(resolved if resolved else path).casefold()
    parts = {part.casefold() for part in path.parts}
    in_temp = False
    if resolved and temp_root:
        in_temp = resolved == temp_root or temp_root in resolved.parents

    if in_temp or any(marker in path_text for marker in TEST_PATH_MARKERS):
        return {
            "mode": "descartavel",
            "is_test": True,
            "label": "BANCO DE TESTE/DESCARTAVEL",
            "detail": "As acoes desta tela usam banco descartavel e nao alteram o banco oficial.",
            "database": path.name or "banco",
        }
    if "data" in parts and path.name.casefold() == "elite.sqlite":
        return {
            "mode": "local",
            "is_test": True,
            "label": "BANCO LOCAL/DESENVOLVIMENTO",
            "detail": "As acoes desta tela usam SQLite local, nao o ambiente cloud operacional.",
            "database": path.name,
        }
    return {
        "mode": "operacional",
        "is_test": False,
        "label": "BANCO OPERACIONAL",
        "detail": "Ambiente sem marcador local ou descartavel detectado.",
        "database": path.name or "banco",
    }


def _safe_resolve(path: Path) -> Path | None:
    try:
        return path.resolve()
    except OSError:
        return None


def run_admin_server(db_path: str | Path, host: str = "127.0.0.1", port: int = 8765) -> None:
    init_db(db_path)
    handler = _handler_factory(Path(db_path))
    server = ThreadingHTTPServer((host, port), handler)
    print(f"Elite System admin: http://{host}:{port}")
    server.serve_forever()


def _handler_factory(db_path: Path) -> type[BaseHTTPRequestHandler]:
    class AdminHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            app = _AdminApp(self, db_path)
            app.handle_get()

        def do_POST(self) -> None:
            app = _AdminApp(self, db_path)
            app.handle_post()

        def log_message(self, format: str, *args: object) -> None:
            return

    return AdminHandler


class _AdminApp:
    def __init__(self, handler: BaseHTTPRequestHandler, db_path: Path) -> None:
        self.handler = handler
        self.db_path = db_path
        self.parsed = urlparse(handler.path)

    def handle_get(self) -> None:
        if self.parsed.path == "/":
            self._redirect("/permissions")
            return
        if self.parsed.path == "/login":
            self._render_login()
            return
        if self.parsed.path == "/bootstrap":
            self._render_bootstrap()
            return
        if self.parsed.path == "/permissions":
            self._render_permissions()
            return
        self._not_found()

    def handle_post(self) -> None:
        form = self._read_form()
        if self.parsed.path == "/login":
            self._post_login(form)
            return
        if self.parsed.path == "/logout":
            self._post_logout()
            return
        if self.parsed.path == "/bootstrap":
            self._post_bootstrap(form)
            return
        if self.parsed.path == "/permissions":
            self._post_permissions(form)
            return
        self._not_found()

    def _render_login(self, message: str | None = None) -> None:
        with connect(self.db_path) as conn:
            empty = not has_users(conn)
        bootstrap = (
            '<p class="notice">Nenhum usuário cadastrado. '
            '<a href="/bootstrap">Criar primeiro administrador</a>.</p>'
            if empty
            else ""
        )
        body = f"""
        <main class="login-shell">
          <section class="login-panel">
            <h1>Elite System</h1>
            <p class="muted">Acesso administrativo</p>
            {self._db_banner()}
            {self._notice(message)}
            {bootstrap}
            <form method="post" action="/login" class="stack">
              <label>Usuário<input name="username" autocomplete="username" required></label>
              <label>Senha<input name="password" type="password" autocomplete="current-password" required></label>
              <button type="submit">Entrar</button>
            </form>
          </section>
        </main>
        """
        self._send_html("Login", body)

    def _render_bootstrap(self, message: str | None = None) -> None:
        with connect(self.db_path) as conn:
            if has_users(conn):
                self._redirect("/login")
                return
        body = f"""
        <main class="login-shell">
          <section class="login-panel">
            <h1>Primeiro administrador</h1>
            <p class="muted">Cria o primeiro usuário local para acessar a tela de alçadas.</p>
            {self._db_banner()}
            {self._notice(message)}
            <form method="post" action="/bootstrap" class="stack">
              <label>Usuário<input name="username" value="admin" autocomplete="username" required></label>
              <label>Nome<input name="display_name" value="Administrador" required></label>
              <label>Senha<input name="password" type="password" autocomplete="new-password" minlength="8" required></label>
              <button type="submit">Criar administrador</button>
            </form>
          </section>
        </main>
        """
        self._send_html("Primeiro administrador", body)

    def _render_permissions(self, message: str | None = None) -> None:
        with connect(self.db_path) as conn:
            user = self._current_user(conn)
            if user is None:
                self._redirect("/login")
                return
            decision = can_perform_action(conn, user_id=user.id, action_key="security.manage_permissions")
            if not decision.allowed:
                self._send_html("Acesso negado", self._forbidden_body(user.display_name))
                return
            users = list_users(conn)
            if not users:
                self._redirect("/bootstrap")
                return
            selected_id = self._selected_user_id(users)
            permissions = list_permission_matrix(conn, user_id=selected_id)
            selected = next(item for item in users if int(item["id"]) == selected_id)

        user_options = "".join(
            f'<option value="{int(item["id"])}" {"selected" if int(item["id"]) == selected_id else ""}>'
            f'{escape(str(item["display_name"]))} ({escape(str(item["username"]))})</option>'
            for item in users
        )
        rows = "\n".join(self._permission_row(item) for item in permissions)
        body = f"""
        <header class="topbar">
          <div>
            <strong>Elite System</strong>
            <span>Alçadas</span>
          </div>
          <form method="post" action="/logout"><button class="ghost" type="submit">Sair</button></form>
        </header>
        {self._db_banner()}
        <main class="workspace">
          <section class="toolbar">
            <div>
              <h1>Usuários e alçadas</h1>
              <p class="muted">Todos começam liberados. Desmarque os checks para retirar acesso.</p>
            </div>
            <form method="get" action="/permissions" class="user-select">
              <label>Usuário
                <select name="user_id" onchange="this.form.submit()">{user_options}</select>
              </label>
            </form>
          </section>
          {self._notice(message)}
          <section class="summary">
            <div><span>Usuário</span><strong>{escape(str(selected["display_name"]))}</strong></div>
            <div><span>Perfil</span><strong>{escape(str(selected["role"]))}</strong></div>
            <div><span>Status</span><strong>{escape(str(selected["status"]))}</strong></div>
            {self._db_summary_card()}
          </section>
          <form method="post" action="/permissions" class="permission-form">
            <input type="hidden" name="user_id" value="{selected_id}">
            <table>
              <thead>
                <tr><th>Permitir</th><th>Módulo</th><th>Ação</th><th>Origem</th></tr>
              </thead>
              <tbody>{rows}</tbody>
            </table>
            <div class="actions"><button type="submit">Salvar checks</button></div>
          </form>
        </main>
        """
        self._send_html("Alçadas", body)

    def _post_login(self, form: dict[str, list[str]]) -> None:
        username = self._form_value(form, "username")
        password = self._form_value(form, "password")
        with connect(self.db_path) as conn:
            result = authenticate_user(conn, username=username, password=password)
            if not result.ok or result.user is None:
                conn.commit()
                self._render_login("Usuário ou senha inválidos.")
                return
            token = create_session(conn, user_id=result.user.id)
            conn.commit()
        self._redirect("/permissions", cookie_value=token)

    def _post_logout(self) -> None:
        token = self._session_token()
        with connect(self.db_path) as conn:
            user = self._current_user(conn)
            revoke_session(conn, token=token, actor_user_id=user.id if user else None)
            conn.commit()
        self._redirect("/login", clear_cookie=True)

    def _post_bootstrap(self, form: dict[str, list[str]]) -> None:
        username = self._form_value(form, "username")
        password = self._form_value(form, "password")
        display_name = self._form_value(form, "display_name")
        with connect(self.db_path) as conn:
            if has_users(conn):
                self._redirect("/login")
                return
            try:
                user = create_user(
                    conn,
                    username=username,
                    password=password,
                    display_name=display_name,
                    role="admin",
                )
                token = create_session(conn, user_id=user.id)
                conn.commit()
            except ValueError as exc:
                conn.rollback()
                self._render_bootstrap(str(exc))
                return
        self._redirect("/permissions", cookie_value=token)

    def _post_permissions(self, form: dict[str, list[str]]) -> None:
        selected_id = int(self._form_value(form, "user_id"))
        allowed_actions = set(form.get("allow", []))
        with connect(self.db_path) as conn:
            actor = self._current_user(conn)
            if actor is None:
                self._redirect("/login")
                return
            decision = can_perform_action(conn, user_id=actor.id, action_key="security.manage_permissions")
            if not decision.allowed:
                self._send_html("Acesso negado", self._forbidden_body(actor.display_name))
                return
            permissions = list_permission_matrix(conn, user_id=selected_id)
            for permission in permissions:
                action_key = str(permission["action_key"])
                set_user_permission(
                    conn,
                    actor_user_id=actor.id,
                    user_id=selected_id,
                    action_key=action_key,
                    allowed=action_key in allowed_actions,
                )
            conn.commit()
        query = urlencode({"user_id": selected_id, "saved": "1"})
        self._redirect(f"/permissions?{query}")

    def _current_user(self, conn) -> object | None:
        return user_from_session(conn, self._session_token())

    def _selected_user_id(self, users: list[dict[str, object]]) -> int:
        query = parse_qs(self.parsed.query)
        raw = query.get("user_id", [None])[0]
        ids = {int(item["id"]) for item in users}
        if raw and raw.isdigit() and int(raw) in ids:
            return int(raw)
        return int(users[0]["id"])

    def _permission_row(self, item: dict[str, object]) -> str:
        allowed = bool(item.get("allowed_for_user", item.get("default_allowed", True)))
        checked = "checked" if allowed else ""
        action_key = escape(str(item["action_key"]))
        module = escape(str(item["module"]))
        description = escape(str(item["description"]))
        source = escape(str(item.get("decision_source", "default")))
        return f"""
        <tr>
          <td><input type="checkbox" name="allow" value="{action_key}" {checked}></td>
          <td>{module}</td>
          <td><strong>{action_key}</strong><span>{description}</span></td>
          <td><span class="badge">{source}</span></td>
        </tr>
        """

    def _forbidden_body(self, display_name: str) -> str:
        return f"""
        <header class="topbar"><strong>Elite System</strong></header>
        {self._db_banner()}
        <main class="workspace">
          <h1>Acesso negado</h1>
          <p class="muted">{escape(display_name)} não possui permissão para administrar alçadas.</p>
        </main>
        """

    def _read_form(self) -> dict[str, list[str]]:
        length = int(self.handler.headers.get("Content-Length", "0"))
        raw = self.handler.rfile.read(length).decode("utf-8")
        return parse_qs(raw)

    def _form_value(self, form: dict[str, list[str]], name: str) -> str:
        return form.get(name, [""])[0].strip()

    def _session_token(self) -> str | None:
        header = self.handler.headers.get("Cookie")
        if not header:
            return None
        jar = cookies.SimpleCookie()
        jar.load(header)
        morsel = jar.get(SESSION_COOKIE)
        return None if morsel is None else morsel.value

    def _notice(self, message: str | None) -> str:
        if message:
            return f'<p class="notice">{escape(message)}</p>'
        query = parse_qs(self.parsed.query)
        if query.get("saved") == ["1"]:
            return '<p class="notice">Alçadas salvas.</p>'
        return ""

    def _db_banner(self) -> str:
        condition = classify_database_condition(self.db_path)
        css_class = "warning" if bool(condition["is_test"]) else "normal"
        return f"""
        <aside class="db-banner {css_class}">
          <strong>{escape(str(condition["label"]))}</strong>
          <span>{escape(str(condition["detail"]))}</span>
          <span class="db-pill">{escape(str(condition["database"]))}</span>
        </aside>
        """

    def _db_summary_card(self) -> str:
        condition = classify_database_condition(self.db_path)
        mode = str(condition["mode"]).replace("_", " ")
        return (
            '<div class="db-summary-card">'
            "<span>Banco</span>"
            f'<strong>{escape(str(condition["label"]))}</strong>'
            f"<small>{escape(mode)}</small>"
            "</div>"
        )

    def _send_html(self, title: str, body: str, status: int = 200) -> None:
        html = f"""<!doctype html>
        <html lang="pt-BR">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>{escape(title)} - Elite System</title>
          <style>{_CSS}</style>
        </head>
        <body>{body}</body>
        </html>
        """
        data = html.encode("utf-8")
        self.handler.send_response(status)
        self.handler.send_header("Content-Type", "text/html; charset=utf-8")
        self.handler.send_header("Content-Length", str(len(data)))
        self.handler.end_headers()
        self.handler.wfile.write(data)

    def _redirect(self, location: str, cookie_value: str | None = None, clear_cookie: bool = False) -> None:
        self.handler.send_response(303)
        self.handler.send_header("Location", location)
        if cookie_value:
            self.handler.send_header("Set-Cookie", f"{SESSION_COOKIE}={cookie_value}; HttpOnly; SameSite=Lax; Path=/")
        if clear_cookie:
            self.handler.send_header("Set-Cookie", f"{SESSION_COOKIE}=; Max-Age=0; HttpOnly; SameSite=Lax; Path=/")
        self.handler.end_headers()

    def _not_found(self) -> None:
        self._send_html("Não encontrado", "<main class=\"workspace\"><h1>Não encontrado</h1></main>", status=404)


_CSS = """
:root {
  color-scheme: light;
  font-family: Arial, Helvetica, sans-serif;
  background: #f5f7f9;
  color: #1d2730;
}
* { box-sizing: border-box; }
body { margin: 0; background: #f5f7f9; }
button, input, select { font: inherit; }
button {
  border: 0;
  background: #1f6feb;
  color: white;
  padding: 10px 14px;
  border-radius: 6px;
  cursor: pointer;
}
button.ghost { background: #eef2f6; color: #1d2730; }
.login-shell {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 24px;
}
.login-panel {
  width: min(420px, 100%);
  background: white;
  border: 1px solid #dde3ea;
  border-radius: 8px;
  padding: 28px;
  box-shadow: 0 12px 40px rgba(20, 35, 50, 0.08);
}
h1 { margin: 0 0 8px; font-size: 26px; }
.muted { color: #5c6b78; margin-top: 0; }
.stack { display: grid; gap: 14px; }
label { display: grid; gap: 6px; color: #394956; font-weight: 600; }
input, select {
  width: 100%;
  border: 1px solid #cfd8e3;
  border-radius: 6px;
  padding: 10px;
  background: white;
}
.notice {
  background: #eef6ff;
  border: 1px solid #b7d7ff;
  border-radius: 6px;
  padding: 10px 12px;
  color: #164d86;
}
.db-banner {
  width: 100%;
  display: grid;
  grid-template-columns: minmax(180px, auto) 1fr auto;
  align-items: center;
  gap: 10px;
  margin: 12px 0;
  border: 1px solid #c9d7e3;
  border-radius: 8px;
  padding: 10px 12px;
  background: #f7fafc;
  color: #22313d;
}
.topbar + .db-banner {
  margin: 0;
  border-left: 0;
  border-right: 0;
  border-radius: 0;
}
.db-banner.warning {
  background: #fff7e6;
  border-color: #f0c36d;
  color: #573b00;
}
.db-banner.normal {
  background: #ecfdf5;
  border-color: #8fd7b0;
  color: #123d2a;
}
.db-pill {
  border: 1px solid currentColor;
  border-radius: 999px;
  padding: 4px 8px;
  font-size: 12px;
  font-weight: 700;
  white-space: nowrap;
}
.topbar {
  height: 56px;
  background: white;
  border-bottom: 1px solid #dde3ea;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 22px;
}
.topbar div { display: flex; align-items: center; gap: 14px; }
.topbar span { color: #64717d; }
.workspace {
  max-width: 1180px;
  margin: 0 auto;
  padding: 24px;
}
.toolbar {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 18px;
  margin-bottom: 18px;
}
.user-select { min-width: 320px; }
.summary {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 18px;
}
.summary div {
  background: white;
  border: 1px solid #dde3ea;
  border-radius: 8px;
  padding: 14px;
}
.summary span { display: block; color: #657382; font-size: 13px; margin-bottom: 6px; }
.summary small { display: block; margin-top: 4px; color: #657382; }
.permission-form {
  background: white;
  border: 1px solid #dde3ea;
  border-radius: 8px;
  overflow: hidden;
}
table { width: 100%; border-collapse: collapse; }
th, td {
  border-bottom: 1px solid #edf1f5;
  text-align: left;
  padding: 12px;
  vertical-align: middle;
}
th { font-size: 13px; color: #566574; background: #f8fafc; }
td:first-child { width: 82px; text-align: center; }
td input[type="checkbox"] {
  width: 22px;
  height: 22px;
  margin: 0;
}
td strong { display: block; margin-bottom: 4px; }
td span { color: #607080; font-size: 13px; }
.badge {
  display: inline-block;
  background: #eef2f6;
  border-radius: 999px;
  padding: 4px 8px;
  color: #41505f;
}
.actions {
  display: flex;
  justify-content: flex-end;
  padding: 16px;
  background: #fbfcfd;
}
@media (max-width: 760px) {
  .toolbar { display: block; }
  .user-select { min-width: 0; margin-top: 14px; }
  .db-banner { grid-template-columns: 1fr; }
  .db-pill { width: fit-content; }
  .summary { grid-template-columns: 1fr; }
  th:nth-child(2), td:nth-child(2), th:nth-child(4), td:nth-child(4) { display: none; }
  .workspace { padding: 16px; }
}
"""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="elite-admin", description="Elite System admin local")
    parser.add_argument("--db", required=True, type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args(argv)
    run_admin_server(args.db, args.host, args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
