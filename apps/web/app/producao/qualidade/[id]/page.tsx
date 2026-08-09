import Link from "next/link";
import { notFound } from "next/navigation";

import { ProductionShell } from "@/app/producao/production-shell";
import { QualityOrderDetail } from "@/app/producao/qualidade/quality-workbench";
import { getOpControlledProcedures } from "@/lib/controlled-procedures";
import { getPcpDashboard, getPcpOrderPrintData, getPcpQualityCapabilities } from "@/lib/pcp";

export default async function QualityOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const opId = Number(id);
  if (!Number.isInteger(opId) || opId <= 0) notFound();

  const [op, dashboard, procedures, capabilities] = await Promise.all([
    getPcpOrderPrintData(opId),
    getPcpDashboard(),
    getOpControlledProcedures(opId),
    getPcpQualityCapabilities()
  ]);
  if (!op) notFound();
  op.procedures = procedures;

  return (
    <ProductionShell
      active="qualidade"
      title={`CQ da ${op.codigoOp}`}
      description="Registre processo, participantes e resultado apenas para a ordem selecionada."
      source={dashboard.source}
      error={dashboard.error}
      actions={<Link className="secondary-button" href="/producao/qualidade">Voltar para a fila</Link>}
    >
      <QualityOrderDetail op={op} lookups={dashboard.lookups} capabilities={capabilities} />
    </ProductionShell>
  );
}
