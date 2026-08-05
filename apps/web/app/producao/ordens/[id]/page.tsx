import Link from "next/link";
import { notFound } from "next/navigation";

import { PlanningOrderCard } from "@/app/producao/ordens/orders-workbench";
import { ProductionShell } from "@/app/producao/production-shell";
import { getPcpDashboard, getPcpOrderCapabilities, getPcpOrderPrintData } from "@/lib/pcp";

export default async function ProductionOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const opId = Number(id);
  if (!Number.isInteger(opId) || opId <= 0) notFound();

  const [op, dashboard, capabilities] = await Promise.all([
    getPcpOrderPrintData(opId),
    getPcpDashboard(),
    getPcpOrderCapabilities()
  ]);
  if (!op) notFound();
  const hasOperationalCapability = Object.values(capabilities).some(Boolean);

  return (
    <ProductionShell
      active="ordens"
      title={op.codigoOp}
      description="Confira componentes, reservas e a situação antes de executar uma ação sobre esta ordem."
      source={dashboard.source}
      error={dashboard.error}
      actions={<><Link className="secondary-button" href="/producao/ordens">Voltar para a fila</Link><Link className="secondary-button" href={`/producao/ordens/${op.id}/imprimir`}>Imprimir OP</Link></>}
    >
      {!hasOperationalCapability ? (
        <div className="notice-panel warning order-readonly-notice" role="status">
          <strong>Consulta disponível em modo somente leitura</strong>
          <span>Você pode conferir esta OP, mas não possui alçada para alterar reservas ou sua situação.</span>
        </div>
      ) : null}
      <PlanningOrderCard op={op} availableLots={dashboard.availableLots} capabilities={capabilities} returnTo="ordens" defaultOpen />
    </ProductionShell>
  );
}
