import {
  getReportsDashboard,
  type ReprocessamentoRow,
  type ValidityLotRow
} from "@/lib/reports";
import { getRuntimeStatus } from "@/lib/runtime";

export default async function RelatoriosPage() {
  const runtime = getRuntimeStatus();
  const dashboard = await getReportsDashboard();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Relatorios</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/">Inicio</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp">PCP</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios" aria-current="page">
            Relatorios
          </a>
          <a href="/login">Login</a>
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
            <span className="eyebrow">analise operacional</span>
            <h1>Relatorios e vencimentos</h1>
            <p className="muted">
              Primeira tela analitica para catalogo de relatorios, lotes vencidos, lotes a vencer e candidatos a
              reprocessamento de PA, PI e MP.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de relatorio">
            <a className="secondary-button" href="#catalogo">
              Catalogo
            </a>
            <a className="primary-button" href="#reprocessamento">
              Reprocessamento
            </a>
          </div>
        </div>

        <section className="kpi-grid" aria-label="Resumo dos relatorios">
          <article className="kpi-card accent-blue">
            <span>Relatorios catalogados</span>
            <strong>{valueOrDash(dashboard.metrics.catalogados)}</strong>
            <p>{valueOrDash(dashboard.metrics.ativos)} ativo(s) para uso inicial.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Vencidos com saldo</span>
            <strong>{valueOrDash(dashboard.metrics.vencidosComSaldo)}</strong>
            <p>Lotes que devem ser tratados antes de nova expedicao ou producao.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Vencem em 30 dias</span>
            <strong>{valueOrDash(dashboard.metrics.vencendo30Dias)}</strong>
            <p>Saldo disponivel que pode exigir decisao comercial, CQ ou PCP.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Candidatos a reprocessar</span>
            <strong>{valueOrDash(dashboard.metrics.candidatosReprocessamento)}</strong>
            <p>{valueOrDash(dashboard.metrics.candidatosAlta)} com prioridade alta.</p>
          </article>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {dashboard.source !== "supabase" ? (
          <section className="notice-panel" role="status">
            <strong>Relatorios aguardando banco</strong>
            <span>Configure Supabase para carregar catalogo, vencimentos e candidatos a reprocessamento.</span>
          </section>
        ) : null}

        <section className="dashboard-grid">
          <section className="panel" id="catalogo" aria-labelledby="catalogo-title">
            <div className="panel-header">
              <h2 id="catalogo-title">Catalogo de relatorios</h2>
              <span className="pill">{dashboard.catalog.length} item(ns)</span>
            </div>
            {dashboard.catalog.length > 0 ? (
              <div className="report-list">
                {dashboard.catalog.map((item) => (
                  <article className="report-row" key={item.codigo}>
                    <div>
                      <strong>{item.nome}</strong>
                      <span>{item.codigo}</span>
                    </div>
                    <p>{item.descricao}</p>
                    <div className="tag-row">
                      <span className="tag">{item.modulo}</span>
                      <span className={`status-chip ${item.status}`}>{item.status}</span>
                      <span className="tag">{item.fontePrincipal}</span>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <EmptyState title="Catalogo nao carregado" detail="O catalogo aparecera quando a migration 0010 estiver aplicada." />
            )}
          </section>

          <section className="panel" id="reprocessamento" aria-labelledby="reprocessamento-title">
            <div className="panel-header">
              <h2 id="reprocessamento-title">Fila de reprocessamento</h2>
              <span className="pill">{dashboard.reprocessamentoRows.length} lote(s)</span>
            </div>
            {dashboard.reprocessamentoRows.length > 0 ? (
              <div className="queue-list">
                {dashboard.reprocessamentoRows.slice(0, 10).map((row) => (
                  <ReprocessamentoItem key={`${row.tipoLote}-${row.loteId}`} row={row} />
                ))}
              </div>
            ) : (
              <EmptyState
                title="Sem candidatos carregados"
                detail="Lotes vencidos, a vencer ou bloqueados com saldo disponivel aparecerao aqui."
              />
            )}
          </section>
        </section>

        <section className="panel" aria-labelledby="vencimentos-title">
          <div className="panel-header">
            <h2 id="vencimentos-title">Lotes por vencimento</h2>
            <span className="pill">{dashboard.validityRows.length} linha(s)</span>
          </div>
          {dashboard.validityRows.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Tipo</th>
                    <th>Lote</th>
                    <th>Cadastro</th>
                    <th>Status</th>
                    <th>Validade</th>
                    <th>Dias</th>
                    <th>Saldo</th>
                    <th>Reserva</th>
                    <th>Disponivel</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.validityRows.slice(0, 80).map((row) => (
                    <ValidityRow key={`${row.tipoLote}-${row.loteId}`} row={row} />
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <EmptyState
              title="Sem lotes carregados"
              detail="Quando houver PA, PI ou MP com validade, este relatorio mostrara saldo, reserva e prazo."
            />
          )}
        </section>
      </section>
    </main>
  );
}

function ReprocessamentoItem({ row }: { row: ReprocessamentoRow }) {
  return (
    <article className="queue-row">
      <span className={`queue-status ${priorityClass(row.prioridadeReprocessamento)}`}></span>
      <div>
        <strong>
          {row.tipoLote} {row.codigoLote}
        </strong>
        <p>
          {row.nomeCadastro} - {numberOrDash(row.saldoDisponivel)} disponivel - {statusLabel(row.statusVencimento)}
        </p>
        <div className="tag-row">
          <span className={`status-chip ${row.prioridadeReprocessamento}`}>{row.prioridadeReprocessamento}</span>
          <span className="tag">{row.status}</span>
          <span className="tag">{dateOrDash(row.dataValidade)}</span>
        </div>
      </div>
    </article>
  );
}

function ValidityRow({ row }: { row: ValidityLotRow }) {
  return (
    <tr>
      <td>
        <span className="tag">{row.tipoLote}</span>
      </td>
      <td>
        <strong>{row.codigoLote}</strong>
        <span className="table-subtext">{row.embalagem ?? row.origemRef ?? "sem complemento"}</span>
      </td>
      <td>
        <strong>{row.codigoCadastro}</strong>
        <span className="table-subtext">{row.nomeCadastro}</span>
      </td>
      <td>
        <span className={`status-chip ${row.statusVencimento}`}>{statusLabel(row.statusVencimento)}</span>
      </td>
      <td>{dateOrDash(row.dataValidade)}</td>
      <td>{row.diasParaVencer === null ? "sem prazo" : row.diasParaVencer}</td>
      <td>{numberOrDash(row.saldoFisico)}</td>
      <td>{numberOrDash(row.quantidadeReservada)}</td>
      <td>{numberOrDash(row.saldoDisponivel)}</td>
    </tr>
  );
}

function EmptyState({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="empty-state">
      <strong>{title}</strong>
      <span>{detail}</span>
    </div>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function numberOrDash(value: number): string {
  return new Intl.NumberFormat("pt-BR", {
    maximumFractionDigits: 3
  }).format(value);
}

function dateOrDash(value: string | null): string {
  if (!value) {
    return "sem validade";
  }
  const [year, month, day] = value.slice(0, 10).split("-");
  if (!year || !month || !day) {
    return value;
  }
  return `${day}/${month}/${year}`;
}

function statusLabel(value: string): string {
  const labels: Record<string, string> = {
    sem_validade: "sem validade",
    vencido_com_saldo: "vencido com saldo",
    vencido_sem_saldo: "vencido sem saldo",
    vence_30_dias: "vence em 30 dias",
    vence_60_dias: "vence em 60 dias",
    vigente: "vigente"
  };
  return labels[value] ?? value;
}

function priorityClass(value: string): string {
  if (value === "alta") {
    return "danger";
  }
  if (value === "media") {
    return "warning";
  }
  return "ok";
}
