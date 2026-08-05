import Link from "next/link";

import { OrderCreationWorkbench } from "@/app/producao/ordens/orders-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard, getPcpOrderCapabilities, getPcpOrderQueue } from "@/lib/pcp";
import { orderStatusLabel, orderTypeLabel } from "@/lib/production-labels";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionOrdersPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const capabilities = await getPcpOrderCapabilities();
  const startCreating = capabilities.canCreate && singleProductionParam(params.nova) === "1";
  const query = singleProductionParam(params.q)?.trim() ?? "";
  const status = singleProductionParam(params.status) ?? "open";
  const type = singleProductionParam(params.tipo) ?? "all";
  const page = Math.max(1, Number(singleProductionParam(params.pagina) ?? "1") || 1);
  const dashboard = startCreating ? await getPcpDashboard() : null;
  const queue = startCreating ? null : await getPcpOrderQueue({ query, status, type, page });
  const hasOperationalCapability = Object.values(capabilities).some(Boolean);
  const source = dashboard?.source ?? queue?.source ?? "error";
  const error = dashboard?.error ?? queue?.error ?? null;
  const pageCount = queue ? Math.max(1, Math.ceil(queue.total / queue.pageSize)) : 1;

  return (
    <ProductionShell
      active="ordens"
      title="Ordens e reservas"
      description="Consulte as OPs e abra uma ordem específica para conferir componentes, reservas e mudanças de estado."
      source={source}
      error={error ? "Não foi possível carregar as ordens neste ambiente. Atualize a página ou procure o suporte." : null}
      actions={<><Link className="secondary-button" href="/producao/formulas">Fórmulas</Link>{capabilities.canCreate ? <Link className="primary-button" href={startCreating ? "/producao/ordens" : "/producao/ordens?nova=1"}>{startCreating ? "Voltar às ordens" : "Abrir OP"}</Link> : null}</>}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      {!hasOperationalCapability ? (
        <div className="notice-panel warning order-readonly-notice" role="status">
          <strong>Consulta disponível em modo somente leitura</strong>
          <span>Você não possui alçada para abrir, reservar, iniciar ou cancelar ordens. As ações não são exibidas.</span>
        </div>
      ) : null}
      {startCreating && dashboard ? <OrderCreationWorkbench dashboard={dashboard} /> : null}
      {!startCreating && queue ? (
        <>
          <nav className="order-status-navigation" aria-label="Situação das ordens">
            <OrderStatusLink label="Abertas" value="open" count={(queue.statusCounts.draft ?? 0) + (queue.statusCounts.planned ?? 0) + (queue.statusCounts.in_process ?? 0)} active={status === "open"} />
            {(["draft", "planned", "in_process", "completed", "cancelled"] as const).map((value) => <OrderStatusLink key={value} label={orderStatusLabel(value)} value={value} count={queue.statusCounts[value] ?? 0} active={status === value} />)}
          </nav>
          <section className="panel" id="ops" aria-labelledby="orders-title">
            <div className="panel-header"><div><span className="eyebrow">Consulta operacional</span><h2 id="orders-title">Fila de ordens</h2></div><span className="pill">{queue.total} resultado(s)</span></div>
            <form className="catalog-filter production-order-filter" method="get">
              <label>Buscar OP<input name="q" type="search" defaultValue={query} placeholder="Código, fórmula ou produto" /></label>
              <label>Situação<select name="status" defaultValue={status}><option value="open">Abertas</option><option value="all">Todas</option><option value="draft">Rascunho</option><option value="planned">Planejada</option><option value="in_process">Em processo</option><option value="completed">Finalizada</option><option value="cancelled">Cancelada</option></select></label>
              <label>Finalidade<select name="tipo" defaultValue={type}><option value="all">Todas</option><option value="estoque">Produção para estoque</option><option value="experimental">Experimental</option><option value="desenvolvimento">Desenvolvimento</option><option value="reprocessamento">Reprocessamento</option></select></label>
              <button className="secondary-button" type="submit">Filtrar</button>
            </form>
            {queue.items.length > 0 ? (
              <div className="record-table-wrap"><table className="record-table"><thead><tr><th>OP</th><th>Produto</th><th>Finalidade</th><th>Planejado</th><th>Situação</th><th>Aberta em</th><th><span className="sr-only">Ação</span></th></tr></thead><tbody>
                {queue.items.map((op) => <tr key={op.id}><td><strong>{op.codigoOp}</strong><small>{op.formulaLabel}</small></td><td>{op.produtoLabel}</td><td>{orderTypeLabel(op.tipoOp)}</td><td>{op.quantidadePlanejada === null ? "Não informado" : formatNumber(op.quantidadePlanejada)}</td><td><span className={`status-chip ${op.status}`}>{orderStatusLabel(op.status)}</span></td><td>{shortDate(op.createdAt)}</td><td><Link className="secondary-button compact" href={`/producao/ordens/${op.id}`}>Abrir OP</Link></td></tr>)}
              </tbody></table></div>
            ) : <div className="empty-state"><strong>Nenhuma OP encontrada</strong><span>Revise os filtros ou abra uma nova ordem.</span></div>}
            <nav className="pagination" aria-label="Paginação"><PageLink disabled={page <= 1} page={page - 1} query={query} status={status} type={type}>Anterior</PageLink><span>Página {Math.min(page, pageCount)} de {pageCount}</span><PageLink disabled={page >= pageCount} page={page + 1} query={query} status={status} type={type}>Próxima</PageLink></nav>
          </section>
        </>
      ) : null}
    </ProductionShell>
  );
}

function OrderStatusLink({ label, value, count, active }: { label: string; value: string; count: number; active: boolean }) {
  return <Link className={`order-status-link ${active ? "is-active" : ""}`} href={`/producao/ordens?status=${encodeURIComponent(value)}#ops`} aria-current={active ? "page" : undefined}><span>{label}</span><strong>{count}</strong></Link>;
}

function PageLink({ disabled, page, query, status, type, children }: { disabled: boolean; page: number; query: string; status: string; type: string; children: string }) {
  if (disabled) return <span className="secondary-button compact disabled" aria-disabled="true">{children}</span>;
  const params = new URLSearchParams({ pagina: String(page), status, tipo: type });
  if (query) params.set("q", query);
  return <Link className="secondary-button compact" href={`/producao/ordens?${params.toString()}#ops`}>{children}</Link>;
}

function formatNumber(value: number): string { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value); }
function shortDate(value: string): string { return new Intl.DateTimeFormat("pt-BR").format(new Date(value)); }
