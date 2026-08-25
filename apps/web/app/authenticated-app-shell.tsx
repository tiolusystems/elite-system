"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { useRef, useState } from "react";

import { DeveloperSignature } from "@/app/developer-signature";
import { ManualTrigger } from "@/app/manual-trigger";
import { logoutAction, switchUserAction } from "@/app/login/actions";
import { navigationGroups, navigationItemForPath } from "@/lib/app-navigation";
import type { AuthStatus } from "@/lib/auth";
import type { BuildInfo } from "@/lib/build-info";
import type { FinanceAccess } from "@/lib/finance";
import type { ModuleRuntimeDashboard } from "@/lib/modules";
import type { PriceListAccess } from "@/lib/price-lists";
import type { RuntimeStatus } from "@/lib/runtime";

const PUBLIC_PREFIXES = ["/login", "/auth/confirm", "/health", "/api/health"];

type Props = {
  auth: AuthStatus;
  build: BuildInfo;
  financeAccess: FinanceAccess | null;
  modules: ModuleRuntimeDashboard | null;
  priceListAccess: PriceListAccess | null;
  runtime: RuntimeStatus;
  children: React.ReactNode;
};

export function AuthenticatedAppShell({ auth, build, financeAccess, modules, priceListAccess, runtime, children }: Props) {
  const pathname = usePathname();
  const [navigationOpen, setNavigationOpen] = useState(false);
  const userMenuRef = useRef<HTMLDetailsElement>(null);
  const current = navigationItemForPath(pathname);
  const enabledModules = new Set(
    modules?.modules.filter((module) => module.available || module.isCore).map((module) => module.moduleKey) ?? ["core"]
  );

  if (!auth.isAuthenticated || PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix))) {
    return children;
  }

  const displayName = auth.profile?.displayName || auth.email || "Usuario";
  const role = auth.profile?.role || "perfil ativo";

  return (
    <div className={`authenticated-shell${navigationOpen ? " navigation-open" : ""}`}>
      <header className="authenticated-header">
        <button
          className="navigation-trigger"
          type="button"
          aria-label="Abrir menu principal"
          aria-expanded={navigationOpen}
          onClick={() => setNavigationOpen((open) => !open)}
        >
          <span />
          <span />
          <span />
        </button>
        <Link className="shell-brand" href="/">
          <Image
            src="/brand/elite-agrociencias-logo.png"
            alt="Elite Agrociências"
            width={2126}
            height={898}
            priority
          />
          <span className="mobile-current-module">{current.label}</span>
        </Link>
        <div className="shell-page-context">
          <span>Pagina atual</span>
          <strong>{current.label}</strong>
        </div>
        <span className="shell-environment">{environmentLabel(runtime.databaseMode)}</span>
        <ManualTrigger />
        <details className="shell-user-menu" ref={userMenuRef}>
          <summary aria-label="Abrir menu do usuario">
            <span className="user-avatar" aria-hidden="true">{initials(displayName)}</span>
            <span className="user-summary-copy">
              <strong>{displayName}</strong>
              <span>{role}</span>
            </span>
          </summary>
          <UserMenu displayName={displayName} email={auth.email} role={role} />
        </details>
      </header>

      <aside className="authenticated-navigation" aria-label="Navegacao principal">
        <div className="mobile-navigation-heading">
          <div>
            <strong>Menu principal</strong>
            <span>{current.label}</span>
          </div>
          <button type="button" aria-label="Fechar menu principal" onClick={() => setNavigationOpen(false)}>×</button>
        </div>
        <nav>
          {navigationGroups.map((group) => {
            const items = group.items;
            if (items.length === 0) return null;
            return (
              <section className="navigation-group" key={group.label}>
                <h2>{group.label}</h2>
                {items.map((item) => {
                  if (item.href === "/pedidos/financeiro" && !financeAccess?.any) return null;
                  if (item.href === "/pedidos/listas-precos" && !priceListAccess?.view) return null;
                  const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);
                  const enabled = enabledModules.has(item.moduleKey);
                  return enabled ? (
                    <Link
                      href={item.href}
                      aria-current={active ? "page" : undefined}
                      key={item.href}
                      onClick={() => setNavigationOpen(false)}
                    >
                      <span className="navigation-mark" aria-hidden="true" />
                      {item.label}
                    </Link>
                  ) : (
                    <span className="navigation-disabled" key={item.href} aria-disabled="true" title="Modulo ainda nao liberado neste ambiente">
                      <span className="navigation-mark" aria-hidden="true" />
                      <span>{item.label}</span>
                      <small>Indisponivel</small>
                    </span>
                  );
                })}
              </section>
            );
          })}
        </nav>
        <div className="mobile-user-panel">
          <UserMenu displayName={displayName} email={auth.email} role={role} />
        </div>
        <div className="shell-build-info">
          <span>Versao {build.version}</span>
          <span>{build.release}</span>
        </div>
      </aside>

      <button
        className="navigation-overlay"
        type="button"
        aria-label="Fechar menu principal"
        onClick={() => setNavigationOpen(false)}
      />

      <div className="authenticated-shell-content">
        {children}
        <footer className="authenticated-footer">
          <span>Elite System</span>
          <span>Elite Agrociências</span>
          <span>{environmentLabel(runtime.databaseMode)}</span>
          <span>Versao {build.version}</span>
          <DeveloperSignature />
          <span>© {new Date().getFullYear()}</span>
        </footer>
      </div>
    </div>
  );
}

function UserMenu({ displayName, email, role }: { displayName: string; email: string | null; role: string }) {
  return (
    <div className="user-menu-panel">
      <div className="user-menu-identity">
        <strong>{displayName}</strong>
        <span>{email || "E-mail nao informado"}</span>
        <span>{role}</span>
      </div>
      <Link href="/">Inicio</Link>
      <form action={switchUserAction}><button type="submit">Trocar usuario</button></form>
      <form action={logoutAction}><button type="submit">Sair</button></form>
    </div>
  );
}

function initials(value: string): string {
  return value.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "US";
}

function environmentLabel(mode: RuntimeStatus["databaseMode"]): string {
  const labels: Record<RuntimeStatus["databaseMode"], string> = {
    local: "Local",
    test: "Teste",
    staging: "Homologacao",
    production: "Producao",
    not_configured: "Nao configurado"
  };
  return labels[mode];
}
