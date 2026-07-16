import Link from "next/link";

import {
  dispatchApprovedOwnEmailChangeAction,
  loginAction,
  logoutAction,
  requestOwnEmailChangeReviewAction,
  switchUserAction
} from "@/app/login/actions";
import { AuthPublicShell } from "@/app/login/auth-public-shell";
import { PasswordInput } from "@/app/login/password-input";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";
import { getOwnEmailChangeRequest } from "@/lib/security";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function LoginPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const result = singleValue(params.result);
  const next = singleValue(params.next) ?? "/";
  const message = messageForResult(result);
  const emailChange = auth.isAuthenticated
    ? await getOwnEmailChangeRequest()
    : { request: null, error: null };
  const emailRequest = emailChange.request;
  const hasPlaceholderEmail = auth.email?.toLowerCase().endsWith("@elite.local") === true;

  return (
    <AuthPublicShell runtime={runtime} section="Acesso seguro">
      <section className="auth-public-intro">
        <span className="eyebrow">acesso controlado</span>
        <h1>{auth.isAuthenticated ? "Sua sessão está ativa" : "Entrar no Elite System"}</h1>
        <p>
          {auth.isAuthenticated
            ? "Confirme a conta conectada ou escolha como deseja continuar."
            : "Acesse o ambiente de trabalho com sua conta individual."}
        </p>
      </section>

      {message ? <AuthNotice message={message} /> : null}
      {auth.error ? (
        <AuthNotice
          message={{
            kind: "warning",
            title: "Serviço de acesso indisponível",
            detail: "Não foi possível consultar sua sessão agora. Tente novamente em alguns instantes."
          }}
        />
      ) : null}

      {auth.isAuthenticated ? (
        <section className="auth-card" aria-labelledby="session-title">
          <div className="auth-card-heading">
            <div>
              <span className="auth-card-kicker">conta conectada</span>
              <h2 id="session-title">{auth.profile?.displayName ?? "Usuário Elite"}</h2>
            </div>
            <span className="pill">sessão validada</span>
          </div>
          <dl className="auth-session-list">
            <div><dt>E-mail</dt><dd>{auth.email ?? "Não informado"}</dd></div>
            <div><dt>Perfil</dt><dd>{auth.profile?.role ?? "Perfil não carregado"}</dd></div>
            <div><dt>Ambiente</dt><dd>{runtime.databaseLabel}</dd></div>
          </dl>
          <div className="auth-actions auth-actions-primary">
            <Link className="primary-button" href={next}>Continuar no sistema</Link>
            <form action={switchUserAction}><button className="secondary-button" type="submit">Trocar usuário</button></form>
            <form action={logoutAction}><button className="secondary-button" type="submit">Sair</button></form>
          </div>
          <div className="auth-account-links">
            <Link href="/login/trocar-senha?mode=authenticated">Alterar minha senha</Link>
            <a href="#meu-email">Solicitar troca de e-mail</a>
          </div>
        </section>
      ) : (
        <section className="auth-card auth-login-card" aria-labelledby="login-title">
          <div className="auth-card-heading">
            <div>
              <span className="auth-card-kicker">identificação</span>
              <h2 id="login-title">Entrar</h2>
            </div>
            <span className="pill">{auth.isConfigured ? "protegido" : "indisponível"}</span>
          </div>
          <form action={loginAction}>
            <input type="hidden" name="next" value={next} />
            <div className="auth-form-fields">
              <label>
                E-mail
                <input name="email" type="email" autoComplete="email" placeholder="usuario@empresa.com" required />
              </label>
              <PasswordInput name="password" label="Senha" autoComplete="current-password" />
            </div>
            <div className="auth-form-footer">
              <Link href="/login/recuperar-senha">Esqueci minha senha</Link>
              <button className="primary-button" type="submit">Entrar</button>
            </div>
          </form>
        </section>
      )}

      {auth.isAuthenticated ? (
        <details className="auth-card auth-account-details" id="meu-email">
          <summary>Solicitação de troca de e-mail</summary>
          {hasPlaceholderEmail ? <p>E-mail técnico precisa ser substituído.</p> : null}
          {emailChange.error ? <p>O fluxo de e-mail está temporariamente indisponível.</p> : null}
          <dl className="auth-session-list">
            <div><dt>E-mail atual</dt><dd>{auth.email ?? "-"}</dd></div>
            <div><dt>Situação</dt><dd>{emailRequest?.status ?? "sem solicitação"}</dd></div>
          </dl>
          {!emailRequest || ["completed", "rejected"].includes(emailRequest.status) ? (
            <form action={requestOwnEmailChangeReviewAction}>
              <div className="auth-form-fields">
                <label>Motivo
                  <select name="reason_code" defaultValue="lost_access" required>
                    <option value="lost_access">Sem acesso ao e-mail atual</option>
                    <option value="registration_correction">Correção de cadastro</option>
                    <option value="professional_change">Alteração de e-mail profissional</option>
                    <option value="other">Outro</option>
                  </select>
                </label>
                <label>Detalhes<input name="reason_detail" /></label>
              </div>
              <button className="primary-button" type="submit">Solicitar ao administrador</button>
            </form>
          ) : null}
          {emailRequest?.status === "approved" ? (
            <form action={dispatchApprovedOwnEmailChangeAction}>
              <button className="primary-button" type="submit">Enviar confirmação aprovada</button>
            </form>
          ) : null}
        </details>
      ) : null}
    </AuthPublicShell>
  );
}

function AuthNotice({ message }: { message: AuthMessage }) {
  return <section className={`auth-notice ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></section>;
}

type AuthMessage = { kind: "ok" | "warning"; title: string; detail: string };

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function messageForResult(result: string | undefined): AuthMessage | null {
  if (!result) return null;
  const messages: Record<string, AuthMessage> = {
    logged_out: { kind: "ok", title: "Sessão encerrada", detail: "Você saiu com segurança deste navegador." },
    switch_user: { kind: "ok", title: "Troca de usuário", detail: "A sessão anterior foi encerrada. Entre com a outra conta." },
    password_changed: { kind: "ok", title: "Senha alterada", detail: "Sua nova senha já está válida." },
    password_recovered: { kind: "ok", title: "Senha redefinida", detail: "Entre com seu e-mail e a nova senha." },
    account_activated: { kind: "ok", title: "Conta ativada", detail: "Entre para acessar o sistema." },
    missing_credentials: { kind: "warning", title: "Preencha os campos", detail: "Informe seu e-mail e sua senha." },
    invalid_credentials: { kind: "warning", title: "Não foi possível entrar", detail: "Confira o e-mail e a senha informados." },
    auth_required: { kind: "warning", title: "Sessão necessária", detail: "Entre para acessar essa área." },
    profile_required: { kind: "warning", title: "Perfil não liberado", detail: "Peça ao administrador para verificar seu cadastro." },
    email_not_confirmed: { kind: "warning", title: "E-mail ainda não confirmado", detail: "Confirme seu e-mail antes de entrar." },
    rate_limited: { kind: "warning", title: "Muitas tentativas", detail: "Aguarde alguns minutos e tente novamente." },
    not_configured: { kind: "warning", title: "Acesso ainda não configurado", detail: "O ambiente não está pronto para autenticação." },
    login_failed: { kind: "warning", title: "Serviço de acesso indisponível", detail: "Não foi possível entrar agora. Tente novamente em alguns instantes." }
  };
  return messages[result] ?? messages.login_failed;
}
