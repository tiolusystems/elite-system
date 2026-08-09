import Link from "next/link";

import { SmartSearchField } from "@/app/corporate-search/smart-lookup";
import {
  DataTable,
  type DataTableColumn,
  FilterActions,
  FilterToolbar,
  OperationalPageShell,
  PaginationBar,
  PrimarySecondaryCell,
  StatusBadge
} from "@/app/operational-table/operational-table";
import { OrderCreationWorkbench } from "@/app/producao/ordens/orders-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard, getPcpOrderCapabilities, getPcpOrderQueue } from "@/lib/pcp";
import { orderStatusLabel, orderTypeLabel } from "@/lib/production-labels";

type SearchParams = Record<string, string | string[] | undefined>;
type OrderRow = Awaited<ReturnType<typeof getPcpOrderQueue>>["items"][number];

const orderColumns: Array<DataTableColumn<OrderRow>> = [
  {
    key: "order",
    label: "OP e fórmula",
    width: "19%",
    render: (op) => <PrimarySecondaryCell primary={op.codigoOp} secondary={formulaSummary(op.formulaLabel, op.produtoLabel)} />
  },
  {
    key: "product",
    label: "Produto",
    width: "21%",
    render: (op) => {
      const product = splitPrimarySecondary(op.produtoLabel);
      return <PrimarySecondaryCell primary={product.primary} secondary={product.secondary} />;
    }
  },
  { key: "purpose", label: "Finalidade", width: "14%", render: (op) => orderTypeLabel(op.tipoOp) },
  {
    key: "quantity",
    label: "Volume planejado",
    width: "12%",
    align: "end",
    render: (op) => op.quantidadePlanejada === null ? "Não informado" : `${formatNumber(op.quantidadePlanejada)} L`
  },
  { key: "status", label: "Situação", width: "12%", render: (op) => <StatusBadge status={op.status}>{orderStatusLabel(op.status)}</StatusBadge> },
  { key: "date", label: "Aberta em", width: "11%", render: (op) => shortDate(op.createdAt) },
  { key: "action", label: "Ação", width: "11%", render: (op) => <Link className="secondary-button compact-button" href={`/producao/ordens/${op.id}`}>Abrir OP</Link> }
];

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
        <OperationalPageShell
          counters={<nav className="order-status-navigation" aria-label="Situação das ordens">
            <OrderStatusLink label="Abertas" value="open" count={(queue.statusCounts.draft ?? 0) + (queue.statusCounts.planned ?? 0) + (queue.statusCounts.in_process ?? 0)} active={status === "open"} />
            {(["draft", "planned", "in_process", "completed", "cancelled"] as const).map((value) => <OrderStatusLink key={value} label={orderStatusLabel(value)} value={value} count={queue.statusCounts[value] ?? 0} active={status === value} />)}
          </nav>}
          filters={<FilterToolbar>
            <SmartSearchField
              name="q"
              label="Buscar OP"
              defaultValue={query}
              placeholder="Código da OP, fórmula ou produto"
              source={{ kind: "remote", entity: "ops-producao" }}
            />
            <label>Situação<select name="status" defaultValue={status}><option value="open">Abertas</option><option value="all">Todas</option><option value="draft">Rascunho</option><option value="planned">Planejada</option><option value="in_process">Em processo</option><option value="completed">Finalizada</option><option value="cancelled">Cancelada</option></select></label>
            <label>Finalidade<select name="tipo" defaultValue={type}><option value="all">Todas</option><option value="estoque">Produção para estoque</option><option value="experimental">Experimental</option><option value="desenvolvimento">Desenvolvimento</option><option value="reprocessamento">Reprocessamento</option></select></label>
            <FilterActions clearHref="/producao/ordens#ops" />
          </FilterToolbar>}
        >
          <section className="panel" id="ops" aria-labelledby="orders-title">
            <div className="panel-header"><div><span className="eyebrow">Consulta operacional</span><h2 id="orders-title">Fila de ordens</h2></div><span className="pill">{queue.total} resultado(s)</span></div>
            {queue.items.length > 0 ? (
              <DataTable caption="Ordens de produção encontradas" columns={orderColumns} rows={queue.items} rowKey={(op) => op.id} />
            ) : <div className="empty-state"><strong>Nenhuma OP encontrada</strong><span>Revise os filtros ou abra uma nova ordem.</span></div>}
            <PaginationBar
              page={Math.min(page, pageCount)}
              pageCount={pageCount}
              total={queue.total}
              previousHref={page > 1 ? pageHref(page - 1, query, status, type) : null}
              nextHref={page < pageCount ? pageHref(page + 1, query, status, type) : null}
            />
          </section>
        </OperationalPageShell>
      ) : null}
    </ProductionShell>
  );
}

function OrderStatusLink({ label, value, count, active }: { label: string; value: string; count: number; active: boolean }) {
  return <Link className={`order-status-link ${active ? "is-active" : ""}`} href={`/producao/ordens?status=${encodeURIComponent(value)}#ops`} aria-current={active ? "page" : undefined}><span>{label}</span><strong>{count}</strong></Link>;
}

function pageHref(page: number, query: string, status: string, type: string) {
  const params = new URLSearchParams({ pagina: String(page), status, tipo: type });
  if (query) params.set("q", query);
  return `/producao/ordens?${params.toString()}#ops`;
}

function formatNumber(value: number): string { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value); }
function shortDate(value: string): string { return new Intl.DateTimeFormat("pt-BR").format(new Date(value)); }
function formulaSummary(formula: string, product: string): string { return formula.startsWith(`${product} / `) ? formula.slice(product.length + 3) : formula; }
function splitPrimarySecondary(value: string): { primary: string; secondary?: string } {
  const separator = value.indexOf(" - ");
  return separator < 0 ? { primary: value } : { primary: value.slice(0, separator), secondary: value.slice(separator + 3) };
}
