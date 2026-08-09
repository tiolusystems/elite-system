import Link from "next/link";

import { changeOwnPasswordAction } from "@/app/login/actions";
import { AuthPublicShell } from "@/app/login/auth-public-shell";
import { PasswordInput } from "@/app/login/password-input";
import { getAuthStatus } from "@/lib/auth";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;
type PasswordChangeMode = "authenticated" | "invitation" | "recovery" | "temporary";

export default async function ChangePasswordPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const next = singleValue(params.next) ?? "/";
  const requestedMode = passwordChangeMode(singleValue(params.mode));
  const mode = auth.requiresAccountActivation ? "invitation" : auth.requiresPasswordChange ? "temporary" : requestedMode;
  const copy = pageCopy(mode);
  const message = messageForResult(singleValue(params.result));

  return (
    <AuthPublicShell runtime={runtime} section={copy.brandLabel}>
      <section className="auth-public-intro">
        <span className="eyebrow">segurança da conta</span>
        <h1>{copy.title}</h1>
        <p>{copy.description}</p>
      </section>
      {message ? <section className={`auth-notice ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></section> : null}

      <section className="auth-card auth-login-card" aria-labelledby="change-password-title">
        <div className="auth-card-heading">
          <div><span className="auth-card-kicker">senha</span><h2 id="change-password-title">{copy.formTitle}</h2></div>
          <span className="pill">{auth.isAuthenticated ? "link validado" : "link inválido"}</span>
        </div>
        {auth.isAuthenticated ? (
          <form action={changeOwnPasswordAction}>
            <input type="hidden" name="next" value={next} />
            <input type="hidden" name="mode" value={mode} />
            <div className="auth-form-fields">
              <PasswordInput name="new_password" label="Nova senha" autoComplete="new-password" minLength={12} />
              <PasswordInput name="new_password_confirmation" label="Confirmar senha" autoComplete="new-password" minLength={12} />
            </div>
            <p className="auth-privacy-note">Use no mínimo 12 caracteres.</p>
            <div className="auth-form-footer">
              <Link href="/login">Voltar</Link>
              <button className="primary-button" type="submit">{copy.buttonLabel}</button>
            </div>
          </form>
        ) : (
          <div className="auth-empty-state">
            <strong>Não foi possível validar este acesso</strong>
            <span>O link pode estar inválido ou vencido. Solicite uma nova recuperação.</span>
            <div className="auth-actions">
              <Link className="primary-button" href="/login/recuperar-senha">Solicitar novo link</Link>
              <Link className="secondary-button" href="/login">Voltar ao login</Link>
            </div>
          </div>
        )}
      </section>
    </AuthPublicShell>
  );
}

function singleValue(value: string | string[] | undefined): string | undefined { return Array.isArray(value) ? value[0] : value; }
function passwordChangeMode(value: string | undefined): PasswordChangeMode { return value === "invitation" || value === "recovery" || value === "temporary" ? value : "authenticated"; }
function messageForResult(result: string | undefined) {
  if (!result) return null;
  const messages = {
    missing_credentials: { kind: "warning", title: "Campos obrigatórios", detail: "Informe e confirme a nova senha." },
    password_mismatch: { kind: "warning", title: "Senhas diferentes", detail: "A confirmação precisa ser igual à nova senha." },
    weak_password: { kind: "warning", title: "Senha não aceita", detail: "Use uma senha com no mínimo 12 caracteres." },
    permission_denied: { kind: "warning", title: "Alteração não autorizada", detail: "Seu perfil não permite concluir esta operação." },
    password_changed_audit_failed: { kind: "warning", title: "Alteração requer conferência", detail: "Avise o administrador antes de tentar novamente." },
    login_failed: { kind: "warning", title: "Não foi possível trocar a senha", detail: "Tente novamente em alguns instantes." }
  } as const;
  return messages[result as keyof typeof messages] ?? messages.login_failed;
}
function pageCopy(mode: PasswordChangeMode) {
  if (mode === "invitation") return { brandLabel: "Ativação da conta", title: "Confirme seu acesso", description: "Seu e-mail foi confirmado. Crie sua senha de acesso.", formTitle: "Criar senha", buttonLabel: "Ativar conta" };
  if (mode === "recovery") return { brandLabel: "Recuperação de senha", title: "Criar nova senha", description: "O link foi validado. Defina sua nova senha.", formTitle: "Nova senha", buttonLabel: "Redefinir senha" };
  if (mode === "temporary") return { brandLabel: "Primeiro acesso", title: "Trocar senha temporária", description: "Defina uma senha própria antes de acessar o sistema.", formTitle: "Senha definitiva", buttonLabel: "Trocar senha" };
  return { brandLabel: "Minha senha", title: "Alterar minha senha", description: "Defina uma nova senha para sua conta.", formTitle: "Nova senha", buttonLabel: "Alterar senha" };
}
