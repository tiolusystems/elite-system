import Link from "next/link";

import { OrdersWorkbench } from "@/app/producao/ordens/orders-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard, getPcpOrderCapabilities } from "@/lib/pcp";
import { orderStatusLabel } from "@/lib/production-labels";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionOrdersPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const [dashboard, capabilities] = await Promise.all([
    getPcpDashboard(),
    getPcpOrderCapabilities()
  ]);
  const query = singleProductionParam(params.q)?.trim().toLocaleLowerCase("pt-BR") ?? "";
  const status = singleProductionParam(params.status) ?? "open";
  const type = singleProductionParam(params.tipo) ?? "all";
  const startCreating = capabilities.canCreate && singleProductionParam(params.nova) === "1";
  const orders = dashboard.recentOps.filter((op) => {
    const statusMatches = status === "all"
      || (status === "open" && ["draft", "planned", "in_process"].includes(op.status))
      || op.status === status;
    const typeMatches = type === "all" || op.tipoOp === type;
    const queryMatches = !query || `${op.codigoOp} ${op.formulaLabel} ${op.produtoLabel}`.toLocaleLowerCase("pt-BR").includes(query);
    return statusMatches && typeMatches && queryMatches;
  });
  const statusCounts = Object.fromEntries(
    ["draft", "planned", "in_process", "completed", "cancelled"].map((value) => [
      value,
      dashboard.recentOps.filter((op) => op.status === value).length
    ])
  );

  return (
    <ProductionShell
      active="ordens"
      title="Ordens e reservas"
      description="Planejamento de OP, componentes previstos e reserva auditada de lotes antes do consumo."
      source={dashboard.source}
      error={dashboard.error ? "Não foi possível carregar as ordens neste ambiente. Atualize a página ou procure o suporte." : null}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/formulas">Fórmulas</Link>
          {capabilities.canCreate ? (
            <Link className="primary-button" href={startCreating ? "/producao/ordens#ops" : "/producao/ordens?nova=1#nova-op"}>
              {startCreating ? "Voltar às ordens" : "Abrir OP"}
            </Link>
          ) : null}
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      {!startCreating ? (
        <>
          <nav className="order-status-navigation" aria-label="Situação das ordens">
            <OrderStatusLink label="Abertas" value="open" count={statusCounts.draft + statusCounts.planned + statusCounts.in_process} active={status === "open"} />
            {(["draft", "planned", "in_process", "completed", "cancelled"] as const).map((value) => (
              <OrderStatusLink key={value} label={orderStatusLabel(value)} value={value} count={statusCounts[value]} active={status === value} />
            ))}
          </nav>

          <form className="catalog-filter production-order-filter" method="get">
            <label>
              Buscar OP
              <input name="q" type="search" defaultValue={singleProductionParam(params.q) ?? ""} placeholder="Código, fórmula ou produto" />
            </label>
            <label>
              Situação
              <select name="status" defaultValue={status}>
                <option value="open">Abertas</option>
                <option value="all">Todas</option>
                <option value="draft">Rascunho</option>
                <option value="planned">Planejada</option>
                <option value="in_process">Em processo</option>
                <option value="completed">Finalizada</option>
                <option value="cancelled">Cancelada</option>
              </select>
            </label>
            <label>
              Finalidade
              <select name="tipo" defaultValue={type}>
                <option value="all">Todas</option>
                <option value="estoque">Produção para estoque</option>
                <option value="experimental">Experimental</option>
                <option value="desenvolvimento">Desenvolvimento</option>
                <option value="reprocessamento">Reprocessamento</option>
              </select>
            </label>
            <button className="secondary-button" type="submit">Filtrar</button>
          </form>
        </>
      ) : null}

      <OrdersWorkbench
        capabilities={capabilities}
        dashboard={dashboard}
        orders={orders}
        startCreating={startCreating}
      />
    </ProductionShell>
  );
}

function OrderStatusLink({
  label,
  value,
  count,
  active
}: {
  label: string;
  value: string;
  count: number;
  active: boolean;
}) {
  return (
    <Link
      className={`order-status-link ${active ? "is-active" : ""}`}
      href={`/producao/ordens?status=${encodeURIComponent(value)}#ops`}
      aria-current={active ? "page" : undefined}
    >
      <span>{label}</span>
      <strong>{count}</strong>
    </Link>
  );
}
