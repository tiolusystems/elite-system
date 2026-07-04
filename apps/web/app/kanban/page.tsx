import { getKanbanDashboard, type KanbanOrder } from "@/lib/kanban";
import { getRuntimeStatus } from "@/lib/runtime";

export default async function KanbanPage() {
  const runtime = getRuntimeStatus();
  const dashboard = await getKanbanDashboard();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Kanban comercial</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/">Inicio</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban" aria-current="page">
            Kanban
          </a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp">PCP</a>
          <a href="/relatorios">Relatorios</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace kanban-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">pedido por propriedade</span>
            <h1>Kanban de pedidos</h1>
            <p className="muted">
              Visualizacao por status para vendedor, gerente vinculado e area comercial, preservando cliente e
              propriedade do pedido.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes do Kanban">
            <a className="secondary-button" href="/pedidos#novo-pedido">
              Novo pedido
            </a>
            <a className="primary-button" href="/pedidos">
              Operar pedidos
            </a>
          </div>
        </div>

        <section className="kpi-grid" aria-label="Resumo Kanban">
          <article className="kpi-card accent-blue">
            <span>Total no quadro</span>
            <strong>{valueOrDash(dashboard.metrics.total)}</strong>
            <p>Pedidos carregados na visao atual.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Rascunhos</span>
            <strong>{valueOrDash(dashboard.metrics.rascunho)}</strong>
            <p>Ainda sem obrigacao de seguir fluxo.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Abertos</span>
            <strong>{valueOrDash(dashboard.metrics.aberto)}</strong>
            <p>{moneyOrDash(dashboard.metrics.valorAberto)} em aberto.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Bloqueados</span>
            <strong>{valueOrDash(dashboard.metrics.bloqueado)}</strong>
            <p>Requerem decisao de credito, cadastro ou regra operacional.</p>
          </article>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        <section className="kanban-board" aria-label="Quadro Kanban de pedidos">
          {dashboard.columns.map((column) => (
            <section className="kanban-column" key={column.key} aria-labelledby={`kanban-${column.key}`}>
              <div className="kanban-column-header">
                <div>
                  <h2 id={`kanban-${column.key}`}>{column.title}</h2>
                  <p>{column.detail}</p>
                </div>
                <span className="status-chip">{column.orders.length}</span>
              </div>
              <div className="kanban-card-list">
                {column.orders.length > 0 ? (
                  column.orders.map((order) => <KanbanCard key={order.pedidoId} order={order} />)
                ) : (
                  <div className="empty-state compact-empty">
                    <strong>Sem pedidos</strong>
                    <span>Nenhum card nesta coluna.</span>
                  </div>
                )}
              </div>
            </section>
          ))}
        </section>
      </section>
    </main>
  );
}

function KanbanCard({ order }: { order: KanbanOrder }) {
  return (
    <article className={`kanban-card kanban-${order.colunaKanban}`}>
      <div className="kanban-card-title">
        <strong>{order.codigoPedido}</strong>
        <span>{moneyOrDash(order.valorTotal)}</span>
      </div>
      <p>{order.clienteNome}</p>
      <div className="tag-row">
        <span className="tag">{order.tipoPedido}</span>
        <span className="tag">{order.dataPedido}</span>
        <span className="tag">seq: {order.sequenciaPropriedade ?? "-"}</span>
      </div>
      <dl className="kanban-mini-list">
        <div>
          <dt>Propriedade</dt>
          <dd>
            {order.propriedadeNome ?? "sem propriedade"}
            {order.propriedadeUf ? ` / ${order.propriedadeUf}` : ""}
          </dd>
        </div>
        <div>
          <dt>Vendedor</dt>
          <dd>{order.vendedorGeradorNome ?? "sem vendedor"}</dd>
        </div>
        <div>
          <dt>Gerente</dt>
          <dd>{order.gerenteVinculadoNome ?? order.gerenteAreaNome ?? "sem gerente"}</dd>
        </div>
        <div>
          <dt>Area</dt>
          <dd>{order.areaNome ?? "sem area"}</dd>
        </div>
      </dl>
    </article>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function moneyOrDash(value: number | null): string {
  if (value === null) {
    return "sem conexao";
  }
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL"
  }).format(value);
}
