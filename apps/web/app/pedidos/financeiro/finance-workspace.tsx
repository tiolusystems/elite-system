import Link from "next/link";

import type { FinanceAccess } from "@/lib/finance";

type Props = {
  access: FinanceAccess;
  current: "overview" | "assignment" | "receipts" | "commissions" | "report";
  eyebrow: string;
  title: string;
  description: string;
  children: React.ReactNode;
  actions?: React.ReactNode;
};

export function FinanceWorkspace({ access, current, eyebrow, title, description, children, actions }: Props) {
  const items = [
    { key: "overview", href: "/pedidos/financeiro", label: "Visão financeira", visible: access.dashboardView || access.receiptsView || access.receiptsRegister || access.commissionsView || access.commissionsPay || access.commissionsAdjust },
    { key: "assignment", href: "/pedidos/financeiro/comissionamento", label: "Comissionamento", visible: access.commissionAssign },
    { key: "receipts", href: "/pedidos/financeiro/recebimentos", label: "Recebimentos", visible: access.receiptsView || access.receiptsRegister },
    { key: "commissions", href: "/pedidos/financeiro/comissoes", label: "Comissões", visible: access.commissionsView || access.commissionsPay || access.commissionsAdjust },
    { key: "report", href: "/pedidos/financeiro/comissoes/relatorio", label: "Relatório", visible: access.commissionsView },
  ].filter((item) => item.visible);

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace finance-workspace">
        <nav className="segmented-control finance-navigation" aria-label="Áreas do Financeiro">
          {items.map((item) => (
            <Link href={item.href} aria-current={current === item.key ? "page" : undefined} key={item.key}>
              {item.label}
            </Link>
          ))}
        </nav>
        <header className="dashboard-header finance-page-header">
          <div>
            <span className="eyebrow">{eyebrow}</span>
            <h1>{title}</h1>
            <p className="muted">{description}</p>
          </div>
          {actions ? <div className="finance-page-actions">{actions}</div> : null}
        </header>
        {children}
      </section>
    </main>
  );
}

export function FinancePermissionState({ detail }: { detail: string }) {
  return (
    <section className="permission-state panel" role="status">
      <span className="eyebrow">Somente consulta autorizada</span>
      <h2>Operação protegida por alçada individual</h2>
      <p>{detail}</p>
    </section>
  );
}
