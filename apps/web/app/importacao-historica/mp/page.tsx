import Link from "next/link";

import { getHistoricalMpDashboard, type HistoricalMpMapping, type HistoricalMpPrice } from "@/lib/historical-mp";
import { getRuntimeStatus } from "@/lib/runtime";

export const dynamic = "force-dynamic";

export default async function HistoricalMpPage() {
  const runtime = getRuntimeStatus();
  const dashboard = await getHistoricalMpDashboard();
  const attention = (dashboard.metrics.pendingItems ?? 0) + (dashboard.metrics.conflictItems ?? 0);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Historico de MP</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos">Modulos</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/importacao-historica/mp" aria-current="page">Historico MP</a>
          <a href="/producao">Producao</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">migracao historica auditavel</span>
            <h1>Reconciliacao de materias-primas</h1>
            <p className="muted">
              Confere identidades, lotes e valores do Tio Lu System antes de qualquer promocao ao estoque operacional.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Atalhos de importacao historica">
            <a className="secondary-button" href="#valores">Valores</a>
            <a className="primary-button" href="#mapeamentos">Mapeamentos</a>
          </div>
        </div>

        <section className="notice-panel ok" role="status">
          <strong>Modo de reconciliacao</strong>
          <span>Nenhum cadastro, lote ou saldo e criado automaticamente nesta tela. Sugestao nao equivale a aprovacao.</span>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>{dashboard.source === "denied" ? "Acesso restrito" : "Conexao pendente"}</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        <section className="kpi-grid" aria-label="Resumo da importacao historica de MP">
          <article className="kpi-card accent-blue">
            <span>Identidades no batch</span>
            <strong>{valueOrDash(dashboard.metrics.totalItems)}</strong>
            <p>Batch {dashboard.metrics.batchId ?? "ainda nao carregado"}.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Mapeamentos aprovados</span>
            <strong>{valueOrDash(dashboard.metrics.approvedItems)}</strong>
            <p>{valueOrDash(dashboard.metrics.suggestedItems)} sugestao(oes) aguardando decisao.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Exigem analise</span>
            <strong>{dashboard.metrics.totalItems === null ? "sem conexao" : attention}</strong>
            <p>Pendencias e conflitos nunca sao unificados silenciosamente.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Custo de aquisicao</span>
            <strong>{moneyOrDash(dashboard.metrics.custoAquisicaoTotal)}</strong>
            <p>{valueOrDash(dashboard.metrics.acquisitionRecords)} entrada(s) com componentes preservados.</p>
          </article>
        </section>

        <section className="summary-grid" id="valores" aria-label="Componentes de aquisicao">
          <article className="summary-card">
            <span>Materia-prima</span>
            <strong>{moneyOrDash(dashboard.metrics.valorMateriaPrima)}</strong>
          </article>
          <article className="summary-card">
            <span>Frete</span>
            <strong>{moneyOrDash(dashboard.metrics.frete)}</strong>
          </article>
          <article className="summary-card">
            <span>DIFAL ICMS</span>
            <strong>{moneyOrDash(dashboard.metrics.difalIcms)}</strong>
          </article>
          <article className="summary-card">
            <span>Outras despesas</span>
            <strong>{moneyOrDash(dashboard.metrics.outrasDespesas)}</strong>
          </article>
        </section>

        <section className="panel" id="mapeamentos" aria-labelledby="mapeamentos-title">
          <div className="panel-header">
            <h2 id="mapeamentos-title">Excel para MP canonica</h2>
            <span className="pill">{dashboard.mappings.length} linha(s)</span>
          </div>
          {dashboard.mappings.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table historical-mp-table">
                <thead>
                  <tr>
                    <th>Linha fonte</th>
                    <th>Identidade legada</th>
                    <th>Unidade</th>
                    <th>Situacao</th>
                    <th>MP canonica</th>
                    <th>Criterio</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.mappings.map((row) => <MappingRow key={row.stagingItemId} row={row} />)}
                </tbody>
              </table>
            </div>
          ) : (
            <EmptyState
              title="Nenhum staging de MP carregado"
              detail="O analisador local e o staging auditado devem rodar antes de qualquer decisao de mapeamento."
            />
          )}
        </section>

        <section className="panel" aria-labelledby="precos-title">
          <div className="panel-header">
            <h2 id="precos-title">Historico de precos e lotes</h2>
            <span className="pill">{dashboard.prices.length} entrada(s)</span>
          </div>
          {dashboard.prices.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table historical-mp-price-table">
                <thead>
                  <tr>
                    <th>Documento</th>
                    <th>MP / lote</th>
                    <th>Quantidade</th>
                    <th>Mercadoria</th>
                    <th>Frete</th>
                    <th>DIFAL</th>
                    <th>Total</th>
                    <th>Custo base</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.prices.map((row) => <PriceRow key={row.acquisitionValueId} row={row} />)}
                </tbody>
              </table>
            </div>
          ) : (
            <EmptyState
              title="Nenhum valor promovido"
              detail="Os componentes aparecerao somente apos mapeamento aprovado e importacao em ensaio descartavel."
            />
          )}
        </section>

        <section className="notice-panel" role="note">
          <strong>Proxima trava</strong>
          <span>Importar lotes e movimentos somente depois de quantidade, valor, saldo e vinculos de producao reconciliarem com o Excel.</span>
        </section>
      </section>
    </main>
  );
}

function MappingRow({ row }: { row: HistoricalMpMapping }) {
  return (
    <tr>
      <td>#{row.sourceRowId}<span className="table-subtext">staging {row.stagingItemId}</span></td>
      <td><strong>{row.codigoLegado ?? "sem codigo"}</strong><span className="table-subtext">{row.nomeLegado ?? "sem nome"}</span></td>
      <td>{row.unidadeOrigem ?? "-"}</td>
      <td><span className={`status-chip ${row.mappingStatus}`}>{mappingStatusLabel(row.mappingStatus)}</span></td>
      <td>{row.materiaPrimaId ? <><strong>{row.materiaPrimaSku}</strong><span className="table-subtext">{row.materiaPrimaNome}</span></> : "Nao definida"}</td>
      <td>{row.matchMethod}<span className="table-subtext">{row.confidence === null ? `${row.matchCount} candidato(s)` : `${row.confidence}% de confianca`}</span></td>
    </tr>
  );
}

function PriceRow({ row }: { row: HistoricalMpPrice }) {
  return (
    <tr>
      <td><strong>{row.documentoRef ?? "sem documento"}</strong><span className="table-subtext">{dateLabel(row.dataDocumento)} / {row.ufEmitente ?? "UF nao informada"}</span></td>
      <td><strong>{row.sku} / {row.materiaPrimaNome}</strong><span className="table-subtext">{row.codigoLoteLegado ?? row.codigoLote}</span></td>
      <td>{quantity(row.quantidadeOrigem)} {row.unidadeOrigem}<span className="table-subtext">{quantity(row.quantidadeBase)} na unidade-base</span></td>
      <td>{money(row.valorMateriaPrima)}</td>
      <td>{money(row.frete)}</td>
      <td>{money(row.difalIcms)}</td>
      <td><strong>{money(row.custoAquisicaoTotal)}</strong></td>
      <td>{money(row.custoUnitarioBase)}</td>
    </tr>
  );
}

function EmptyState({ title, detail }: { title: string; detail: string }) {
  return <div className="empty-state"><strong>{title}</strong><span>{detail}</span></div>;
}

function mappingStatusLabel(status: string): string {
  return ({ approved: "aprovado", suggested: "sugerido", pending: "pendente", conflict: "conflito", rejected: "rejeitado" } as Record<string, string>)[status] ?? status;
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function moneyOrDash(value: number | null): string {
  return value === null ? "sem conexao" : money(value);
}

function money(value: number): string {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

function quantity(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function dateLabel(value: string | null): string {
  return value ? new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)) : "data nao informada";
}
