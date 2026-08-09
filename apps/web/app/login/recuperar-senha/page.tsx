import Link from "next/link";

import { requestPasswordRecoveryAction } from "@/app/login/actions";
import { AuthPublicShell } from "@/app/login/auth-public-shell";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PasswordRecoveryPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const result = singleValue(params.result);
  const runtime = getRuntimeStatus();
  const message = messageForResult(result);

  return (
    <AuthPublicShell runtime={runtime} section="Recuperação de acesso">
      <section className="auth-public-intro">
        <span className="eyebrow">senha esquecida</span>
        <h1>Recuperar acesso</h1>
        <p>Solicite um link seguro para definir uma nova senha.</p>
      </section>

      {message ? <section className={`auth-notice ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></section> : null}

      <section className="auth-card auth-login-card" aria-labelledby="recovery-title">
        <div className="auth-card-heading">
          <div><span className="auth-card-kicker">recuperação</span><h2 id="recovery-title">Enviar link por e-mail</h2></div>
          <span className="pill">tempo limitado</span>
        </div>
        <form action={requestPasswordRecoveryAction}>
          <div className="auth-form-fields">
            <label>E-mail cadastrado<input name="email" type="email" autoComplete="email" required /></label>
          </div>
          <p className="auth-privacy-note">A resposta não revela se existe ou não uma conta para o e-mail informado.</p>
          <div className="auth-form-footer">
            <Link href="/login">Voltar ao login</Link>
            <button className="primary-button" type="submit">Enviar link</button>
          </div>
        </form>
      </section>
    </AuthPublicShell>
  );
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) return null;
  const messages = {
    recovery_sent: { kind: "ok", title: "Solicitação recebida", detail: "Se existe uma conta ativa para este e-mail, o link foi enviado." },
    invalid_email: { kind: "warning", title: "E-mail inválido", detail: "Confira o endereço informado." },
    recovery_expired: { kind: "warning", title: "Link inválido ou vencido", detail: "Solicite um novo link de recuperação." },
    rate_limited: { kind: "warning", title: "Aguarde antes de tentar novamente", detail: "O limite temporário de envios foi atingido." },
    not_configured: { kind: "warning", title: "Recuperação indisponível", detail: "O ambiente ainda não está configurado para autenticação." },
    recovery_failed: { kind: "warning", title: "Não foi possível enviar o link", detail: "Tente novamente em alguns instantes." }
  } satisfies Record<string, { kind: "ok" | "warning"; title: string; detail: string }>;
  return messages[result as keyof typeof messages] ?? messages.recovery_failed;
}
