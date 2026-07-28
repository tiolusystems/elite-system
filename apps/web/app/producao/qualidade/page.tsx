import Link from "next/link";

import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { QualityWorkbench } from "@/app/producao/qualidade/quality-workbench";
import { getOpControlledProcedures } from "@/lib/controlled-procedures";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionQualityPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const [dashboard, procedures] = await Promise.all([
    getPcpDashboard(),
    getOpControlledProcedures()
  ]);
  const proceduresByOp = new Map<number, typeof procedures>();
  for (const procedure of procedures) {
    proceduresByOp.set(procedure.opId, [...(proceduresByOp.get(procedure.opId) ?? []), procedure]);
  }
  const orders = dashboard.recentOps.map((op) => ({
    ...op,
    procedures: proceduresByOp.get(op.id) ?? []
  }));
  const type = singleProductionParam(params.tipo);
  const inProcess = orders.filter(
    (op) => op.status === "in_process" && (!type || op.tipoOp === type)
  );
  const completed = orders.filter((op) => op.status === "completed").slice(0, 12);

  return (
    <ProductionShell
      active="qualidade"
      title="CQ e finalização"
      description="Registro de processo, participantes, resultado do controle de qualidade e lotes gerados."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/ordens">Ordens</Link>
          <a className="primary-button" href="#cq-pendente">OP aguardando CQ</a>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      <section className="technical-kpis quality-kpis" aria-label="Resumo do controle de qualidade">
        <article><span>Em processo</span><strong>{inProcess.length}</strong><small>Aguardando dados e finalização.</small></article>
        <article><span>Finalizadas recentes</span><strong>{completed.length}</strong><small>Com fato produtivo preservado.</small></article>
        <article><span>Lotes bloqueados</span><strong>{dashboard.metrics.lotesBloqueados ?? "-"}</strong><small>Dependem de decisão posterior.</small></article>
        <article><span>Garantias vigentes</span><strong>{dashboard.metrics.garantiasVigentes ?? "-"}</strong><small>Produto e lotes de MP.</small></article>
      </section>
      <QualityWorkbench inProcess={inProcess} completed={completed} lookups={dashboard.lookups} />
    </ProductionShell>
  );
}
