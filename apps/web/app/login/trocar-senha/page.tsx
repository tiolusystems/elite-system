import Link from "next/link";

import { changeOwnPasswordAction, logoutAction } from "@/app/login/actions";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ChangeTemporaryPasswordPage({
  searchParams
}: {
  searchParams?: Promise<SearchParams>;
}) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const result = singleValue(params.result);
  const next = singleValue(params.next) ?? "/";
  const requestedMode = passwordChangeMode(singleValue(params.mode));
  const mode = auth.requiresAccountActivation
    ? "invitation"
    : auth.requiresPasswordChange
      ? "temporary"
      : requestedMode;
  const copy = pageCopy(mode);
  const message = messageForResult(result);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>{copy.brandLabel}</span>
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
            <span className="eyebrow">segurança</span>
            <h1>{copy.title}</h1>
            <p className="muted">{copy.description}</p>
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
              <h2 id="change-password-title">{copy.formTitle}</h2>
              <span className="pill">{auth.isAuthenticated ? "sessão validada" : "link inválido"}</span>
            </div>
            <form action={changeOwnPasswordAction}>
              <input type="hidden" name="next" value={next} />
              <input type="hidden" name="mode" value={mode} />
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
                  {copy.buttonLabel}
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
                <strong>Não foi possível validar sua sessão</strong>
                <span>Solicite um novo link de recuperação ou volte ao login.</span>
                <Link href="/login/recuperar-senha">Recuperar acesso</Link>
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
    password_changed_audit_failed: {
      kind: "warning",
      title: "Senha alterada, auditoria pendente",
      detail: "Não repita a alteração. Avise o administrador para conferir o registro de segurança."
    },
    login_failed: {
      kind: "warning",
      title: "Troca nao concluida",
      detail: "Nao foi possivel trocar a senha."
    }
  };
  return messages[result] ?? messages.login_failed;
}

type PasswordChangeMode = "authenticated" | "invitation" | "recovery" | "temporary";

function passwordChangeMode(value: string | undefined): PasswordChangeMode {
  if (value === "invitation" || value === "recovery" || value === "temporary") {
    return value;
  }
  return "authenticated";
}

function pageCopy(mode: PasswordChangeMode) {
  if (mode === "invitation") {
    return {
      brandLabel: "Ativação da conta",
      title: "Confirme seu acesso",
      description: "Seu e-mail foi confirmado. Crie a senha que usará para entrar no Elite System.",
      formTitle: "Criar senha",
      buttonLabel: "Ativar conta"
    };
  }
  if (mode === "recovery") {
    return {
      brandLabel: "Recuperação de senha",
      title: "Criar nova senha",
      description: "O link de recuperação foi validado. Defina a senha que usará nos próximos acessos.",
      formTitle: "Nova senha",
      buttonLabel: "Redefinir senha"
    };
  }
  if (mode === "temporary") {
    return {
      brandLabel: "Primeiro acesso",
      title: "Trocar senha temporária",
      description: "Defina uma senha própria antes de acessar os módulos operacionais.",
      formTitle: "Senha definitiva",
      buttonLabel: "Trocar senha"
    };
  }
  return {
    brandLabel: "Minha senha",
    title: "Alterar minha senha",
    description: "Defina uma nova senha para esta conta.",
    formTitle: "Nova senha",
    buttonLabel: "Alterar senha"
  };
}
