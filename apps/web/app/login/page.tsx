import Link from "next/link";

import {
  dispatchApprovedOwnEmailChangeAction,
  loginAction,
  logoutAction,
  requestOwnEmailChangeReviewAction
} from "@/app/login/actions";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";
import { getOwnEmailChangeRequest } from "@/lib/security";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function LoginPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const emailChange = auth.isAuthenticated
    ? await getOwnEmailChangeRequest()
    : { request: null, error: null };
  const emailRequest = emailChange.request;
  const result = singleValue(params.result);
  const next = singleValue(params.next) ?? "/";
  const message = messageForResult(result);
  const hasPlaceholderEmail = auth.email?.toLowerCase().endsWith("@elite.local") === true;

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
          <a href="/producao">Producao</a>
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
            <span className="eyebrow">acesso seguro</span>
            <h1>Entrar no Elite System</h1>
            <p className="muted">
              Use o e-mail cadastrado e sua senha. Cada navegador mantém sua própria sessão.
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

        {hasPlaceholderEmail ? (
          <section className="notice-panel warning" role="status">
            <strong>E-mail técnico precisa ser substituído</strong>
            <span>Solicite a troca abaixo. O administrador definirá o novo endereço no cadastro do usuário.</span>
          </section>
        ) : null}

        {emailChange.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Fluxo de e-mail indisponível</strong>
            <span>{emailChange.error}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" aria-labelledby="login-title">
            <div className="panel-header">
              <h2 id="login-title">Entrar</h2>
              <span className="pill">{auth.isConfigured ? "acesso protegido" : "indisponível"}</span>
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
                <Link href="/login/recuperar-senha">Esqueci minha senha</Link>
                <div className="form-footer-actions">
                  <button className="primary-button" type="submit">
                    Entrar
                  </button>
                </div>
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
              <div className="form-footer">
                <span>Conta conectada somente neste navegador.</span>
                <div className="form-footer-actions">
                  <Link className="secondary-button" href="/login/trocar-senha?mode=authenticated">
                    Alterar senha
                  </Link>
                  <a className="secondary-button" href="#meu-email">
                    Solicitar troca de e-mail
                  </a>
                  <form action={logoutAction}>
                    <button className="secondary-button" type="submit">
                      Sair
                    </button>
                  </form>
                </div>
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma sessão ativa neste navegador</strong>
                <span>Uma sessão aberta no navegador do Codex não é compartilhada com o navegador externo.</span>
              </div>
            )}
          </section>
        </section>

        {auth.isAuthenticated ? (
          <section className="panel form-panel" id="meu-email" aria-labelledby="my-email-title">
            <div className="panel-header">
              <h2 id="my-email-title">Solicitação de troca de e-mail</h2>
              <span className="pill">{emailRequest ? emailChangeStatusLabel(emailRequest.status) : "sem solicitação"}</span>
            </div>
            <dl className="status-list">
              <div className="status-row">
                <dt>E-mail atual</dt>
                <dd>{auth.email ?? "-"}</dd>
              </div>
              {emailRequest?.newEmail ? (
                <div className="status-row">
                  <dt>E-mail aprovado</dt>
                  <dd>{emailRequest.newEmail}</dd>
                </div>
              ) : null}
            </dl>

            {!emailRequest || emailRequest.status === "completed" || emailRequest.status === "rejected" ? (
              <form action={requestOwnEmailChangeReviewAction}>
                <div className="form-grid">
                  <label>
                    Motivo
                    <select name="reason_code" defaultValue="lost_access" required>
                      <option value="lost_access">Sem acesso ao e-mail atual</option>
                      <option value="registration_correction">Correção de cadastro</option>
                      <option value="professional_change">Alteração de e-mail profissional</option>
                      <option value="other">Outro</option>
                    </select>
                  </label>
                  <label className="wide-field">
                    Detalhes
                    <input name="reason_detail" placeholder="Obrigatório quando o motivo for outro" />
                  </label>
                </div>
                <div className="form-footer">
                  <span>Você não informa o novo endereço. O administrador fará isso no cadastro do usuário.</span>
                  <button className="primary-button" type="submit">
                    Solicitar ao administrador
                  </button>
                </div>
              </form>
            ) : null}

            {emailRequest?.status === "pending_admin" ? (
              <div className="empty-state">
                <strong>Aguardando administrador</strong>
                <span>A solicitação não altera o acesso até ser analisada no módulo Segurança.</span>
              </div>
            ) : null}

            {emailRequest?.status === "approved" ? (
              <form action={dispatchApprovedOwnEmailChangeAction}>
                <div className="form-footer">
                  <span>O administrador aprovou o endereço acima. Envie a confirmação para comprovar que ele existe.</span>
                  <button className="primary-button" type="submit">
                    Enviar confirmação aprovada
                  </button>
                </div>
              </form>
            ) : null}

            {emailRequest?.status === "confirmation_pending" ? (
              <div className="form-footer">
                <span>Aguardando confirmação no novo endereço. O e-mail atual permanece válido até a conclusão.</span>
                <div className="form-footer-actions">
                  {runtime.databaseMode === "local" ? (
                    <a className="secondary-button" href="http://127.0.0.1:54324" target="_blank" rel="noreferrer">
                      Abrir e-mail local
                    </a>
                  ) : null}
                  <form action={dispatchApprovedOwnEmailChangeAction}>
                    <button className="secondary-button" type="submit">
                      Reenviar confirmação
                    </button>
                  </form>
                </div>
              </div>
            ) : null}
          </section>
        ) : null}
      </section>
    </main>
  );
}

function emailChangeStatusLabel(status: string): string {
  const labels: Record<string, string> = {
    approved: "aprovada",
    completed: "concluída",
    confirmation_pending: "aguardando confirmação",
    pending_admin: "aguardando administrador",
    rejected: "rejeitada"
  };
  return labels[status] ?? status;
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
    password_changed: {
      kind: "ok",
      title: "Senha alterada",
      detail: "A nova senha já está válida para os próximos acessos."
    },
    password_recovered: {
      kind: "ok",
      title: "Senha redefinida",
      detail: "Entre agora com seu e-mail e a nova senha."
    },
    account_activated: {
      kind: "ok",
      title: "Conta ativada",
      detail: "O e-mail foi confirmado e sua senha foi criada. Entre para acessar o sistema."
    },
    email_confirmation_sent: {
      kind: "ok",
      title: "Confirmação enviada",
      detail: "Abra a mensagem enviada ao endereço aprovado pelo administrador e confirme a alteração."
    },
    email_change_review_requested: {
      kind: "ok",
      title: "Solicitação enviada ao administrador",
      detail: "Nenhum e-mail foi alterado. O administrador analisará a solicitação no cadastro do usuário."
    },
    email_change_request_active: {
      kind: "warning",
      title: "Solicitação já existente",
      detail: "Conclua ou aguarde a análise da solicitação atual antes de criar outra."
    },
    email_change_reason_required: {
      kind: "warning",
      title: "Motivo obrigatório",
      detail: "Selecione o motivo da solicitação."
    },
    email_change_detail_required: {
      kind: "warning",
      title: "Detalhe obrigatório",
      detail: "Descreva o motivo quando escolher a opção outro."
    },
    email_change_not_approved: {
      kind: "warning",
      title: "Troca ainda não aprovada",
      detail: "O envio só é liberado depois que o administrador definir o novo endereço."
    },
    email_confirmed: {
      kind: "ok",
      title: "E-mail confirmado",
      detail: "O novo endereço já é o seu e-mail de acesso."
    },
    email_mismatch: {
      kind: "warning",
      title: "E-mails diferentes",
      detail: "Repita exatamente o novo endereço nos dois campos."
    },
    email_unchanged: {
      kind: "warning",
      title: "E-mail não alterado",
      detail: "O novo endereço é igual ao e-mail atual."
    },
    email_already_used: {
      kind: "warning",
      title: "E-mail já utilizado",
      detail: "Este endereço já pertence a outra conta."
    },
    invalid_email: {
      kind: "warning",
      title: "E-mail inválido",
      detail: "Informe um endereço de e-mail válido."
    },
    fictitious_email: {
      kind: "warning",
      title: "E-mail fictício bloqueado",
      detail: "Informe um endereço real que possa receber a confirmação."
    },
    permission_denied: {
      kind: "warning",
      title: "Alteração não autorizada",
      detail: "Seu perfil não tem alçada para esta etapa do fluxo."
    },
    email_change_expired: {
      kind: "warning",
      title: "Confirmação inválida ou vencida",
      detail: "Solicite novamente a alteração do e-mail."
    },
    invitation_expired: {
      kind: "warning",
      title: "Convite inválido ou vencido",
      detail: "Peça ao administrador um novo convite."
    },
    email_change_audit_failed: {
      kind: "warning",
      title: "Confirmação pendente de auditoria",
      detail: "Não repita a operação. Peça ao administrador para conferir o registro."
    },
    email_change_failed: {
      kind: "warning",
      title: "Alteração não iniciada",
      detail: "Não foi possível enviar a confirmação para o novo e-mail."
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
