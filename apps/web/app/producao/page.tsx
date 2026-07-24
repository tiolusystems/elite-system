import Link from "next/link";
import { redirect } from "next/navigation";

import { ProductionShell } from "@/app/producao/production-shell";
import {
  canCurrentUserViewPcpDashboard,
  getPcpSupervisorDashboard
} from "@/lib/pcp";

export const dynamic = "force-dynamic";

export default async function ProductionOverviewPage() {
  const canViewDashboard = await canCurrentUserViewPcpDashboard();
  if (!canViewDashboard) redirect("/producao/ordens");

  const dashboard = await getPcpSupervisorDashboard();
  const metrics = dashboard.metrics;
  const hasPendingItems = [
    metrics.opsAguardando,
    metrics.opsEmProducao,
    metrics.componentesSemReserva,
    metrics.lotesBloqueados
  ].some((value) => (value ?? 0) > 0);

  return (
    <ProductionShell
      active="overview"
      title="Acompanhamento da produção"
      description="Pendências e exceções que precisam de atenção da supervisão."
      source={dashboard.source}
      error={dashboard.error}
      canViewOverview
      actions={(
        <>
          <Link className="secondary-button" href="/producao/manual">Como operar</Link>
          <Link className="primary-button" href="/producao/ordens">Ver ordens</Link>
        </>
      )}
    >
      <section className="kpi-grid" aria-label="Pendências da produção">
        <article className="kpi-card accent-amber">
          <span>OPs aguardando preparo</span>
          <strong>{valueOrDash(metrics.opsAguardando)}</strong>
          <p>Ordens em rascunho ou planejadas.</p>
        </article>
        <article className="kpi-card accent-blue">
          <span>Produções em andamento</span>
          <strong>{valueOrDash(metrics.opsEmProducao)}</strong>
          <p>Ordens iniciadas aguardando conclusão ou CQ.</p>
        </article>
        <article className="kpi-card accent-amber">
          <span>Componentes sem reserva</span>
          <strong>{valueOrDash(metrics.componentesSemReserva)}</strong>
          <p>Itens planejados que ainda precisam de lote.</p>
        </article>
        <article className="kpi-card accent-red">
          <span>Lotes bloqueados</span>
          <strong>{valueOrDash(metrics.lotesBloqueados)}</strong>
          <p>Dependem de avaliação ou decisão auditada.</p>
        </article>
      </section>

      {dashboard.source === "supabase" && !hasPendingItems ? (
        <section className="notice-panel ok" aria-label="Produção sem pendências críticas">
          <strong>Nenhuma pendência crítica</strong>
          <span>As filas supervisionadas não possuem exceções neste momento.</span>
        </section>
      ) : null}

      <section className="panel" aria-labelledby="production-priorities-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Ações prioritárias</span>
            <h2 id="production-priorities-title">Onde atuar</h2>
          </div>
        </div>
        <div className="operation-card-grid">
          <PriorityLink
            href="/producao/ordens"
            title="Preparar e acompanhar ordens"
            detail="Reservar componentes, iniciar OPs e tratar ordens paradas."
          />
          <PriorityLink
            href="/producao/qualidade"
            title="Concluir CQ"
            detail="Registrar o processo, avaliar resultados e finalizar a produção."
          />
          <PriorityLink
            href="/producao/estoque"
            title="Avaliar lotes bloqueados"
            detail="Consultar o lote e seguir o fluxo auditado de liberação."
          />
        </div>
      </section>
    </ProductionShell>
  );
}

function PriorityLink({
  href,
  title,
  detail
}: {
  href: string;
  title: string;
  detail: string;
}) {
  return (
    <article className="operation-stage-card is-operational">
      <h3>{title}</h3>
      <p>{detail}</p>
      <Link href={href}>Abrir fila</Link>
    </article>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "-" : String(value);
}
