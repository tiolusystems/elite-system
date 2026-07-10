import Link from "next/link";

import { changeTemporaryPasswordAction, logoutAction } from "@/app/login/actions";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ChangeTemporaryPasswordPage({
  searchParams
}: {
  searchParams?: SearchParams | Promise<SearchParams>;
}) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const result = singleValue(params.result);
  const next = singleValue(params.next) ?? "/";
  const message = messageForResult(result);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Troca de senha</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/login" aria-current="page">
            Login
          </a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace login-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">seguranca</span>
            <h1>Trocar senha temporaria</h1>
            <p className="muted">
              Defina uma senha propria antes de acessar os modulos operacionais.
            </p>
          </div>
        </div>

        {message ? (
          <section className={`notice-panel ${message.kind}`} role="status">
            <strong>{message.title}</strong>
            <span>{message.detail}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" aria-labelledby="change-password-title">
            <div className="panel-header">
              <h2 id="change-password-title">Nova senha</h2>
              <span className="pill">{auth.isAuthenticated ? "sessao ativa" : "sem sessao"}</span>
            </div>
            <form action={changeTemporaryPasswordAction}>
              <input type="hidden" name="next" value={next} />
              <div className="form-grid single-field-grid">
                <label>
                  Nova senha
                  <input name="new_password" type="password" autoComplete="new-password" minLength={12} required />
                </label>
                <label>
                  Confirmar senha
                  <input
                    name="new_password_confirmation"
                    type="password"
                    autoComplete="new-password"
                    minLength={12}
                    required
                  />
                </label>
              </div>
              <div className="form-footer">
                <span>Use no minimo 12 caracteres.</span>
                <button className="primary-button" type="submit" disabled={!auth.isAuthenticated}>
                  Trocar senha
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="session-title">
            <div className="panel-header">
              <h2 id="session-title">Sessao</h2>
              <span className="pill">{auth.source}</span>
            </div>
            <dl className="status-list">
              <div className="status-row">
                <dt>E-mail</dt>
                <dd>{auth.email ?? "-"}</dd>
              </div>
              <div className="status-row">
                <dt>Perfil</dt>
                <dd>{auth.profile ? `${auth.profile.displayName} / ${auth.profile.role}` : "-"}</dd>
              </div>
            </dl>
            {auth.isAuthenticated ? (
              <form className="form-footer" action={logoutAction}>
                <span>Encerrar sessao e voltar ao login.</span>
                <button className="secondary-button" type="submit">
                  Sair
                </button>
              </form>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma sessao ativa</strong>
                <span>Entre com a senha temporaria recebida por email.</span>
              </div>
            )}
          </section>
        </section>
      </section>
    </main>
  );
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    missing_credentials: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Informe e confirme a nova senha."
    },
    password_mismatch: {
      kind: "warning",
      title: "Confirmacao diferente",
      detail: "A confirmacao precisa ser igual a nova senha."
    },
    weak_password: {
      kind: "warning",
      title: "Senha fraca",
      detail: "Use uma senha com no minimo 12 caracteres."
    },
    permission_denied: {
      kind: "warning",
      title: "Auditoria negada",
      detail: "Seu perfil nao tem permissao para registrar a troca de senha."
    },
    login_failed: {
      kind: "warning",
      title: "Troca nao concluida",
      detail: "Nao foi possivel trocar a senha."
    }
  };
  return messages[result] ?? messages.login_failed;
}
