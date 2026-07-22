import Link from "next/link";

import {
  getReportsDashboard,
  type ReprocessamentoRow,
  type ValidityLotRow
} from "@/lib/reports";

export const dynamic = "force-dynamic";

type ReportsPageProps = {
  searchParams: Promise<{ familia?: string; data?: string }>;
};

const LOT_FAMILY_OPTIONS = ["TODOS", "PI", "PA", "MP"] as const;
type LotFamilyFilter = (typeof LOT_FAMILY_OPTIONS)[number];

export default async function RelatoriosPage({ searchParams }: ReportsPageProps) {
  const params = await searchParams;
  const dataCorte = /^\d{4}-\d{2}-\d{2}$/.test(params.data ?? "") ? params.data! : new Date().toISOString().slice(0, 10);
  const dashboard = await getReportsDashboard(dataCorte);
  const requestedFamily = params.familia?.toUpperCase();
  const family: LotFamilyFilter = LOT_FAMILY_OPTIONS.includes(requestedFamily as LotFamilyFilter)
    ? (requestedFamily as LotFamilyFilter)
    : "TODOS";
  const validityRows = filterByFamily(dashboard.validityRows, family);
  const reprocessamentoRows = filterByFamily(dashboard.reprocessamentoRows, family);
  const vencidosComSaldo = validityRows.filter((row) => row.statusVencimento === "vencido_com_saldo").length;
  const vencendo30Dias = validityRows.filter((row) => row.statusVencimento === "vence_30_dias").length;
  const candidatosAlta = reprocessamentoRows.filter((row) => row.prioridadeReprocessamento === "alta").length;

  return (
    <main className="app-shell">
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
            <strong>{dashboard.source === "supabase" ? vencidosComSaldo : "sem conexao"}</strong>
            <p>Lotes que devem ser tratados antes de nova expedicao ou producao.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Vencem em 30 dias</span>
            <strong>{dashboard.source === "supabase" ? vencendo30Dias : "sem conexao"}</strong>
            <p>Saldo disponivel que pode exigir decisao comercial, CQ ou producao.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Candidatos a reprocessar</span>
            <strong>{dashboard.source === "supabase" ? reprocessamentoRows.length : "sem conexao"}</strong>
            <p>{dashboard.source === "supabase" ? candidatosAlta : "sem conexao"} com prioridade alta.</p>
          </article>
        </section>

        <nav className="segmented-control" aria-label="Filtrar relatórios por família de estoque">
          {LOT_FAMILY_OPTIONS.map((option) => (
            <Link
              key={option}
              href={option === "TODOS" ? "/relatorios" : `/relatorios?familia=${option}`}
              aria-current={family === option ? "page" : undefined}
            >
              {option === "TODOS" ? "Todos" : option}
            </Link>
          ))}
        </nav>

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

        <section className="panel" aria-labelledby="posicao-pa-title">
          <div className="panel-header">
            <div><h2 id="posicao-pa-title">Posição de estoque PA</h2><p className="muted">Saldo físico, empenhado em romaneio e disponível no fim da data.</p></div>
            <form method="get"><label>Data de corte <input type="date" name="data" defaultValue={dataCorte} /></label><button className="secondary-button" type="submit">Consultar</button></form>
          </div>
          {dashboard.paStockPositionRows.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Lote</th><th>Físico</th><th>Empenhado</th><th>Disponível</th><th>Litros físicos</th><th>Volumes físicos</th><th>Litros empenhados</th><th>Volumes empenhados</th></tr></thead><tbody>
            {dashboard.paStockPositionRows.map((row) => <tr key={row.lotePaId}><td>{row.codigoLote}</td><td>{numberOrDash(row.saldoFisico)}</td><td>{numberOrDash(row.saldoEmpenhado)}</td><td>{numberOrDash(row.saldoDisponivel)}</td><td>{numberOrDash(row.litrosFisicos)}</td><td>{row.volumesFisicos === null ? "Pendente" : numberOrDash(row.volumesFisicos)}</td><td>{numberOrDash(row.litrosEmpenhados)}</td><td>{row.volumesEmpenhados === null ? "Pendente" : numberOrDash(row.volumesEmpenhados)}</td></tr>)}
          </tbody></table></div> : <EmptyState title="Sem posição PA" detail="Lotes e empenhos aparecerão após a movimentação de teste." />}
        </section>

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
              <span className="pill">{reprocessamentoRows.length} lote(s) de {familyLabel(family)}</span>
            </div>
            {reprocessamentoRows.length > 0 ? (
              <div className="queue-list">
                {reprocessamentoRows.slice(0, 10).map((row) => (
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
            <span className="pill">{validityRows.length} linha(s) de {familyLabel(family)}</span>
          </div>
          {validityRows.length > 0 ? (
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
                  {validityRows.slice(0, 80).map((row) => (
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

function filterByFamily<T extends ValidityLotRow>(rows: T[], family: LotFamilyFilter): T[] {
  return family === "TODOS" ? rows : rows.filter((row) => row.tipoLote.toUpperCase() === family);
}

function familyLabel(family: LotFamilyFilter): string {
  return family === "TODOS" ? "todas as famílias" : family;
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
