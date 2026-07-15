import Link from "next/link";

import { ProductionShell } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

export default async function ProductionOverviewPage() {
  const dashboard = await getPcpDashboard();

  return (
    <ProductionShell
      active="overview"
      title="Central de producao"
      description="Da base tecnica ao lote liberado, com cada etapa separada por responsabilidade operacional."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/cadastros/tecnicos">Base tecnica</Link>
          <Link className="primary-button" href="/producao/formulas">Abrir formulas</Link>
        </>
      )}
    >
      <section className="kpi-grid" aria-label="Resumo da producao">
        <article className="kpi-card accent-blue">
          <span>Formulas versionadas</span>
          <strong>{valueOrDash(dashboard.metrics.formulasVersionadas)}</strong>
          <p>{valueOrDash(dashboard.metrics.formulasAtivas)} referencia(s) vigente(s).</p>
        </article>
        <article className="kpi-card accent-amber">
          <span>OP abertas</span>
          <strong>{valueOrDash(dashboard.metrics.opsAbertas)}</strong>
          <p>Rascunho, planejada ou em processo.</p>
        </article>
        <article className="kpi-card accent-green">
          <span>OP em processo</span>
          <strong>{valueOrDash(dashboard.metrics.opsEmProcesso)}</strong>
          <p>Aguardando CQ ou finalizacao.</p>
        </article>
        <article className="kpi-card accent-red">
          <span>Lotes bloqueados</span>
          <strong>{valueOrDash(dashboard.metrics.lotesBloqueados)}</strong>
          <p>Dependem de decisao auditada.</p>
        </article>
      </section>

      <section className="panel" aria-labelledby="production-flow-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Fluxo operacional</span>
            <h2 id="production-flow-title">Sequencia da producao</h2>
          </div>
          <span className="pill">7 etapas</span>
        </div>
        <div className="operation-card-grid production-stage-grid">
          <StageCard number="01" title="Base tecnica" detail="MP, unidades, embalagens e produtos." href="/cadastros/tecnicos" status="Operacional" />
          <StageCard number="02" title="Formulas" detail="Receitas versionadas de producao e MAPA." href="/producao/formulas" status="Operacional" />
          <StageCard number="03" title="Garantias" detail="Declaracoes de produto e analises por lote de MP." href="/producao/garantias" status="Operacional" />
          <StageCard number="04" title="Ordens e reservas" detail="Abertura de OP e reserva de MP, PA ou PI." href="/producao/ordens" status="Operacional" />
          <StageCard number="05" title="CQ e finalizacao" detail="Dados de processo, aprovacao e produto gerado." href="/producao/qualidade" status="Operacional" />
          <StageCard number="06" title="Lotes e estoque" detail="Saldos fisico, reservado e disponivel por lote." href="/producao/estoque" status="Operacional" />
          <StageCard number="07" title="Transformacoes" detail="PA para PI, PI para PA, reenvasamento e reprocessamento." href="/producao/transformacoes" status="Operacional" />
        </div>
      </section>

      <section className="panel production-next-band">
        <div>
          <span className="eyebrow">Fluxo integrado</span>
          <h2>Do lote de origem ao novo lote</h2>
          <p className="muted">Estoque, reserva, reprocessamento, CQ e saida permanecem ligados pela ordem de producao.</p>
        </div>
        <Link className="secondary-button" href="/producao/estoque">Consultar lotes atuais</Link>
      </section>
    </ProductionShell>
  );
}

function StageCard({ number, title, detail, href, status }: { number: string; title: string; detail: string; href: string; status: string }) {
  const operational = status === "Operacional";
  return (
    <article className={`operation-stage-card ${operational ? "is-operational" : ""}`}>
      <div className="operation-stage-heading">
        <span className="operation-stage-number">{number}</span>
        <span className="status-chip">{status}</span>
      </div>
      <h3>{title}</h3>
      <p>{detail}</p>
      <Link href={href}>Abrir etapa</Link>
    </article>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "-" : String(value);
}
