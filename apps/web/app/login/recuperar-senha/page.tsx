import Link from "next/link";

import { requestPasswordRecoveryAction } from "@/app/login/actions";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PasswordRecoveryPage({
  searchParams
}: {
  searchParams?: Promise<SearchParams>;
}) {
  const params = searchParams ? await searchParams : {};
  const result = singleValue(params.result);
  const runtime = getRuntimeStatus();
  const message = messageForResult(result);
  const recoverySent = result === "recovery_sent";

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Recuperação de acesso</span>
        </div>
        <nav className="topnav" aria-label="Acesso">
          <Link href="/login">Login</Link>
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
            <span className="eyebrow">senha esquecida</span>
            <h1>Recuperar acesso</h1>
            <p className="muted">Receba um link seguro para criar uma nova senha.</p>
          </div>
          <div className="toolbar-actions">
            <Link className="secondary-button" href="/login">
              Voltar ao login
            </Link>
          </div>
        </div>

        {message ? (
          <section className={`notice-panel ${message.kind}`} role="status">
            <strong>{message.title}</strong>
            <span>{message.detail}</span>
            {recoverySent && runtime.databaseMode === "local" ? (
              <a href="http://127.0.0.1:54324" target="_blank" rel="noreferrer">
                Abrir a caixa de e-mail do ambiente local
              </a>
            ) : null}
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" aria-labelledby="recovery-title">
            <div className="panel-header">
              <h2 id="recovery-title">Enviar link de recuperação</h2>
              <span className="pill">válido por tempo limitado</span>
            </div>
            <form action={requestPasswordRecoveryAction}>
              <div className="form-grid single-field-grid">
                <label>
                  E-mail cadastrado
                  <input name="email" type="email" autoComplete="email" required />
                </label>
              </div>
              <div className="form-footer">
                <span>A resposta não revela se existe ou não uma conta para o e-mail informado.</span>
                <div className="form-footer-actions">
                  <button className="primary-button" type="submit">
                    Enviar link
                  </button>
                </div>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="recovery-result-title">
            <div className="panel-header">
              <h2 id="recovery-result-title">Nova senha</h2>
              <span className="pill">12 caracteres</span>
            </div>
            <dl className="status-list">
              <div className="status-row">
                <dt>Senha anterior</dt>
                <dd>Não pode ser exibida ou recuperada</dd>
              </div>
              <div className="status-row">
                <dt>Link recebido</dt>
                <dd>Abre a definição de uma nova senha</dd>
              </div>
              <div className="status-row">
                <dt>Próximo acesso</dt>
                <dd>Funciona em qualquer navegador</dd>
              </div>
            </dl>
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
    recovery_sent: {
      kind: "ok",
      title: "Solicitação recebida",
      detail: "Se existe uma conta ativa para este e-mail, o link para definir a nova senha foi enviado."
    },
    invalid_email: {
      kind: "warning",
      title: "E-mail inválido",
      detail: "Informe um endereço de e-mail válido."
    },
    recovery_expired: {
      kind: "warning",
      title: "Link inválido ou vencido",
      detail: "Solicite um novo link de recuperação."
    },
    rate_limited: {
      kind: "warning",
      title: "Aguarde antes de tentar novamente",
      detail: "O limite temporário de envios foi atingido."
    },
    not_configured: {
      kind: "warning",
      title: "Recuperação indisponível",
      detail: "O ambiente ainda não está configurado para autenticação."
    },
    recovery_failed: {
      kind: "warning",
      title: "Não foi possível enviar o link",
      detail: "Tente novamente. Se o problema continuar, acione o administrador."
    }
  };

  return messages[result] ?? messages.recovery_failed;
}
