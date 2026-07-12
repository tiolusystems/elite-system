import Link from "next/link";

import { getHistoricalMpDashboard, type HistoricalMpMapping, type HistoricalMpPrice } from "@/lib/historical-mp";
import { getRuntimeStatus } from "@/lib/runtime";

export const dynamic = "force-dynamic";

export default async function HistoricalMpPage() {
  const runtime = getRuntimeStatus();
  const dashboard = await getHistoricalMpDashboard();
  const attention = (dashboard.metrics.pendingItems ?? 0) + (dashboard.metrics.conflictItems ?? 0);
  const historyLoaded = (dashboard.metrics.totalItems ?? 0) > 0;

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
            <span className="eyebrow">preservacao do historico</span>
            <h1>Migracao do historico de materias-primas</h1>
            <p className="muted">
              Aqui voce acompanha o que sera trazido do Tio Lu System e confere os casos que exigem uma decisao.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Atalhos de importacao historica">
            <a className="secondary-button" href="#etapas">Ver etapas</a>
            <a className="primary-button" href="#conferencia">Conferir dados</a>
          </div>
        </div>

        <section className={`notice-panel ${historyLoaded ? "ok" : "warning"}`} role="status">
          <strong>
            {historyLoaded
              ? "Situacao atual: dados do Excel prontos para conferencia"
              : "Situacao atual: estrutura pronta, dados do Excel ainda nao analisados"}
          </strong>
          <span>
            {historyLoaded
              ? "Os registros abaixo ainda nao alteram cadastro ou estoque. Casos duvidosos precisam ser confirmados antes da importacao."
              : "O historico continua preservado. O proximo trabalho da equipe tecnica e executar uma leitura sem alterar o Excel nem o estoque."}
          </span>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>{dashboard.source === "denied" ? "Acesso restrito" : "Conexao pendente"}</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        <section className="migration-progress" id="etapas" aria-labelledby="etapas-title">
          <div className="section-heading">
            <div>
              <span className="eyebrow">onde estamos</span>
              <h2 id="etapas-title">Caminho ate o historico entrar no Elite System</h2>
            </div>
            <p>Nenhuma etapa posterior avanca enquanto a anterior nao estiver conferida.</p>
          </div>
          <ol className="migration-steps">
            <li className="migration-step done">
              <span className="migration-step-number">1</span>
              <div>
                <strong>Estrutura segura criada</strong>
                <p>Banco, rastreabilidade e protecoes contra duplicacao estao prontos.</p>
              </div>
              <span className="migration-step-status">concluido</span>
            </li>
            <li className={`migration-step ${historyLoaded ? "done" : "current"}`}>
              <span className="migration-step-number">2</span>
              <div>
                <strong>Ler o historico do Tio Lu</strong>
                <p>A equipe tecnica executa uma leitura que nao altera o arquivo original.</p>
              </div>
              <span className="migration-step-status">{historyLoaded ? "concluido" : "proximo"}</span>
            </li>
            <li className={`migration-step ${historyLoaded ? "current" : "waiting"}`}>
              <span className="migration-step-number">3</span>
              <div>
                <strong>Conferir nomes e codigos</strong>
                <p>Voce sera acionado somente nos casos duplicados, conflitantes ou desconhecidos.</p>
              </div>
              <span className="migration-step-status">{historyLoaded ? "em conferencia" : "aguardando"}</span>
            </li>
            <li className="migration-step waiting">
              <span className="migration-step-number">4</span>
              <div>
                <strong>Importar e conferir os saldos</strong>
                <p>Lotes, entradas, consumos, precos e saldos entram apenas depois da aprovacao.</p>
              </div>
              <span className="migration-step-status">aguardando</span>
            </li>
          </ol>
        </section>

        <section className="kpi-grid" aria-label="Resumo da importacao historica de MP">
          <article className="kpi-card accent-blue">
            <span>Registros do Excel analisados</span>
            <strong>{valueOrDash(dashboard.metrics.totalItems)}</strong>
            <p>{historyLoaded ? "Materias-primas encontradas para conferencia." : "A leitura do historico ainda nao foi executada."}</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Correspondencias confirmadas</span>
            <strong>{valueOrDash(dashboard.metrics.approvedItems)}</strong>
            <p>{valueOrDash(dashboard.metrics.suggestedItems)} correspondencia(s) sugerida(s) pelo sistema.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Precisam de uma decisao</span>
            <strong>{dashboard.metrics.totalItems === null ? "sem conexao" : attention}</strong>
            <p>Nomes duplicados ou conflitantes nunca sao unidos automaticamente.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Valor historico identificado</span>
            <strong>{moneyOrDash(dashboard.metrics.custoAquisicaoTotal)}</strong>
            <p>{valueOrDash(dashboard.metrics.acquisitionRecords)} entrada(s) de materia-prima analisada(s).</p>
          </article>
        </section>

        <div className="section-heading" id="valores">
          <div>
            <span className="eyebrow">valores preservados</span>
            <h2>Composicao das compras historicas</h2>
          </div>
          <p>Os componentes ficam separados para mostrar exatamente como cada custo foi formado.</p>
        </div>
        <section className="summary-grid" aria-label="Componentes de aquisicao">
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

        <section className="panel" id="conferencia" aria-labelledby="conferencia-title">
          <div className="panel-header">
            <h2 id="conferencia-title">Correspondencia entre o Excel e o cadastro novo</h2>
            <span className="pill">{dashboard.mappings.length} registro(s)</span>
          </div>
          {dashboard.mappings.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table historical-mp-table">
                <thead>
                  <tr>
                    <th>Nome e codigo no Excel</th>
                    <th>Unidade</th>
                    <th>Estado da conferencia</th>
                    <th>Cadastro oficial correspondente</th>
                    <th>Como foi encontrado</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.mappings.map((row) => <MappingRow key={row.stagingItemId} row={row} />)}
                </tbody>
              </table>
            </div>
          ) : (
            <EmptyState
              title="Ainda nao analisamos as materias-primas do Excel"
              detail="O proximo passo da equipe tecnica e executar uma leitura somente leitura. Depois, os nomes e codigos aparecerao aqui para conferencia. Nada sera importado nessa leitura."
            />
          )}
        </section>

        <section className="panel" aria-labelledby="precos-title">
          <div className="panel-header">
            <h2 id="precos-title">Entradas, lotes e custos encontrados no historico</h2>
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
              title="Ainda nao analisamos as entradas de materia-prima"
              detail="Quando a leitura tecnica terminar, esta area mostrara documento, lote, quantidade, valor da mercadoria, frete, DIFAL e custo total."
            />
          )}
        </section>

        <section className="notice-panel" role="note">
          <strong>Proximo passo da equipe tecnica</strong>
          <span>Executar a leitura somente leitura do historico. Voce sera acionado depois apenas para decidir nomes duplicados, codigos conflitantes ou materias-primas desconhecidas.</span>
        </section>
      </section>
    </main>
  );
}

function MappingRow({ row }: { row: HistoricalMpMapping }) {
  return (
    <tr>
      <td><strong>{row.codigoLegado ?? "sem codigo"}</strong><span className="table-subtext">{row.nomeLegado ?? "sem nome"}</span></td>
      <td>{row.unidadeOrigem ?? "-"}</td>
      <td><span className={`status-chip ${row.mappingStatus}`}>{mappingStatusLabel(row.mappingStatus)}</span></td>
      <td>{row.materiaPrimaId ? <><strong>{row.materiaPrimaSku}</strong><span className="table-subtext">{row.materiaPrimaNome}</span></> : "Ainda nao definido"}</td>
      <td>{matchMethodLabel(row.matchMethod)}<span className="table-subtext">{row.confidence === null ? `${row.matchCount} candidato(s)` : `${row.confidence}% de confianca`}</span></td>
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

function matchMethodLabel(method: string): string {
  return ({
    exact_sku: "codigo oficial igual",
    exact_legacy_code: "codigo antigo igual",
    exact_name: "nome igual",
    normalized_name: "nome equivalente",
    manual: "confirmado manualmente",
    none: "sem correspondencia"
  } as Record<string, string>)[method] ?? method;
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
