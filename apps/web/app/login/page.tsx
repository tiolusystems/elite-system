import Link from "next/link";

import { loginAction, logoutAction } from "@/app/login/actions";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function LoginPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
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
          <span>Login</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos">Modulos</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp">PCP</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
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
            <span className="eyebrow">multiusuario</span>
            <h1>Acesso por senha</h1>
            <p className="muted">
              Sessao Supabase Auth para vincular usuario, perfil, alcadas e trilha de auditoria das acoes.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de login">
            <Link className="secondary-button" href="/">
              Painel
            </Link>
          </div>
        </div>

        {message ? (
          <section className={`notice-panel ${message.kind}`} role="status">
            <strong>{message.title}</strong>
            <span>{message.detail}</span>
          </section>
        ) : null}

        {auth.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Sessao parcial</strong>
            <span>{auth.error}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" aria-labelledby="login-title">
            <div className="panel-header">
              <h2 id="login-title">Entrar</h2>
              <span className="pill">{auth.isConfigured ? "Supabase Auth" : "aguardando Supabase"}</span>
            </div>
            <form action={loginAction}>
              <input type="hidden" name="next" value={next} />
              <div className="form-grid single-field-grid">
                <label>
                  E-mail
                  <input name="email" type="email" autoComplete="email" placeholder="usuario@empresa.com" required />
                </label>
                <label>
                  Senha
                  <input name="password" type="password" autoComplete="current-password" required />
                </label>
              </div>
              <div className="form-footer">
                <span>Use o usuario cadastrado no Supabase Auth e vinculado em `user_profiles`.</span>
                <button className="primary-button" type="submit">
                  Entrar
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="sessao-title">
            <div className="panel-header">
              <h2 id="sessao-title">Sessao atual</h2>
              <span className="pill">{auth.source}</span>
            </div>
            <dl className="status-list">
              <div className="status-row">
                <dt>Autenticado</dt>
                <dd>{auth.isAuthenticated ? "sim" : "nao"}</dd>
              </div>
              <div className="status-row">
                <dt>E-mail</dt>
                <dd>{auth.email ?? "-"}</dd>
              </div>
              <div className="status-row">
                <dt>Perfil</dt>
                <dd>{auth.profile ? `${auth.profile.displayName} / ${auth.profile.role}` : "-"}</dd>
              </div>
              <div className="status-row">
                <dt>Status</dt>
                <dd>{auth.profile?.status ?? "-"}</dd>
              </div>
            </dl>
            {auth.isAuthenticated ? (
              <form className="form-footer" action={logoutAction}>
                <span>Encerrar sessao neste navegador.</span>
                <button className="secondary-button" type="submit">
                  Sair
                </button>
              </form>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma sessao ativa</strong>
                <span>As acoes protegidas dependem de usuario autenticado e perfil ativo.</span>
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
    logged_out: {
      kind: "ok",
      title: "Sessao encerrada",
      detail: "O usuario saiu deste navegador."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure as variaveis do Supabase antes de autenticar usuarios."
    },
    missing_credentials: {
      kind: "warning",
      title: "Credenciais obrigatorias",
      detail: "Informe e-mail e senha."
    },
    invalid_credentials: {
      kind: "warning",
      title: "Login negado",
      detail: "E-mail ou senha invalidos."
    },
    auth_required: {
      kind: "warning",
      title: "Sessao obrigatoria",
      detail: "Entre com usuario e senha para acessar as telas operacionais."
    },
    profile_required: {
      kind: "warning",
      title: "Perfil obrigatorio",
      detail: "O usuario precisa estar vinculado a um perfil ativo em user_profiles."
    },
    email_not_confirmed: {
      kind: "warning",
      title: "E-mail nao confirmado",
      detail: "Confirme o e-mail no Supabase Auth antes de entrar."
    },
    rate_limited: {
      kind: "warning",
      title: "Muitas tentativas",
      detail: "Aguarde antes de tentar novamente."
    },
    login_failed: {
      kind: "warning",
      title: "Falha no login",
      detail: "Nao foi possivel autenticar. Verifique Supabase Auth e perfil do usuario."
    }
  };
  return messages[result] ?? messages.login_failed;
}
