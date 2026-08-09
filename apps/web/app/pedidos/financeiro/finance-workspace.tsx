import type { ReactNode } from "react";

import {
  DomainShell,
  PermissionState,
  type DomainNavigationItem,
} from "@/app/workspace-components";
import type { FinanceAccess } from "@/lib/finance";

type FinanceRoute = "overview" | "assignment" | "receipts" | "commissions" | "report";

type Props = {
  access: FinanceAccess;
  current: FinanceRoute;
  eyebrow: string;
  title: string;
  description: string;
  children: ReactNode;
  actions?: ReactNode;
};

export function FinanceWorkspace({ access, current, eyebrow, title, description, children, actions }: Props) {
  const items = [
    {
      key: "overview",
      href: "/pedidos/financeiro",
      label: "Visão financeira",
      visible: access.dashboardView || access.receiptsView || access.receiptsRegister || access.commissionsView || access.commissionsPay || access.commissionsAdjust,
    },
    {
      key: "assignment",
      href: "/pedidos/financeiro/comissionamento",
      label: "Comissionamento",
      visible: access.commissionAssign,
    },
    {
      key: "receipts",
      href: "/pedidos/financeiro/recebimentos",
      label: "Recebimentos",
      visible: access.receiptsView || access.receiptsRegister,
    },
    {
      key: "commissions",
      href: "/pedidos/financeiro/comissoes",
      label: "Comissões",
      visible: access.commissionsView || access.commissionsPay || access.commissionsAdjust,
    },
    {
      key: "report",
      href: "/pedidos/financeiro/comissoes/relatorio",
      label: "Relatório",
      visible: access.commissionsView,
    },
  ]
    .filter((item) => item.visible)
    .map(({ key, href, label }) => ({ key, href, label })) satisfies DomainNavigationItem[];

  return (
    <DomainShell
      items={items}
      active={current}
      navigationLabel="Financeiro"
      navigationAriaLabel="Áreas do Financeiro"
      eyebrow={eyebrow}
      title={title}
      description={description}
      actions={actions}
      className="finance-workspace"
    >
      {children}
    </DomainShell>
  );
}

export function FinancePermissionState({ detail }: { detail: string }) {
  return (
    <PermissionState
      title="Operação protegida por alçada individual"
      description={detail}
    />
  );
}
