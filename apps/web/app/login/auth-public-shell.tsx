import Link from "next/link";
import type { ReactNode } from "react";

import { DeveloperSignature } from "@/app/developer-signature";
import { getBuildInfo } from "@/lib/build-info";
import type { RuntimeStatus } from "@/lib/runtime";

type AuthPublicShellProps = {
  children: ReactNode;
  runtime: RuntimeStatus;
  section: string;
};

export function AuthPublicShell({ children, runtime, section }: AuthPublicShellProps) {
  const build = getBuildInfo();

  return (
    <main className="auth-public-shell">
      <header className="auth-public-header">
        <Link className="auth-public-brand" href="/login" aria-label="Elite System - acesso">
          <strong>Elite System</strong>
          <span>{section}</span>
        </Link>
        <div className="auth-public-environment" aria-label="Ambiente atual">
          <span>{runtime.databaseLabel}</span>
          <strong>{environmentName(runtime.databaseMode)}</strong>
        </div>
      </header>

      <section className="auth-public-main">{children}</section>

      <footer className="auth-public-footer">
        <div>
          <strong>Elite Agrociências</strong>
          <DeveloperSignature />
        </div>
        <div className="auth-public-release" aria-label="Versão do sistema">
          <span>Versão {build.version}</span>
          <span>{build.release}</span>
          <span>© {new Date().getFullYear()}</span>
        </div>
      </footer>
    </main>
  );
}

function environmentName(mode: RuntimeStatus["databaseMode"]): string {
  const labels: Record<RuntimeStatus["databaseMode"], string> = {
    local: "Local",
    test: "Teste",
    staging: "Homologação",
    production: "Produção",
    not_configured: "Não configurado"
  };
  return labels[mode];
}
