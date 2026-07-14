import Link from "next/link";

import { OrdersWorkbench } from "@/app/producao/ordens/orders-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionOrdersPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getPcpDashboard();
  const query = singleProductionParam(params.q)?.trim().toLocaleLowerCase("pt-BR") ?? "";
  const status = singleProductionParam(params.status) ?? "open";
  const type = singleProductionParam(params.tipo) ?? "all";
  const orders = dashboard.recentOps.filter((op) => {
    const statusMatches = status === "all"
      || (status === "open" && ["draft", "planned", "in_process"].includes(op.status))
      || op.status === status;
    const typeMatches = type === "all" || op.tipoOp === type;
    const queryMatches = !query || `${op.codigoOp} ${op.formulaLabel} ${op.produtoLabel}`.toLocaleLowerCase("pt-BR").includes(query);
    return statusMatches && typeMatches && queryMatches;
  });

  return (
    <ProductionShell
      active="ordens"
      title="Ordens e reservas"
      description="Planejamento de OP, componentes previstos e reserva auditada de lotes antes do consumo."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/formulas">Formulas</Link>
          <a className="primary-button" href="#nova-op">Abrir OP</a>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      <form className="catalog-filter production-order-filter" method="get">
        <label>
          Buscar OP
          <input name="q" defaultValue={singleProductionParam(params.q) ?? ""} placeholder="Codigo, formula ou produto" />
        </label>
        <label>
          Status
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
          Tipo
          <select name="tipo" defaultValue={type}>
            <option value="all">Todos</option>
            <option value="estoque">Estoque</option>
            <option value="experimental">Experimental</option>
            <option value="desenvolvimento">Desenvolvimento</option>
            <option value="reprocessamento">Reprocessamento</option>
            <option value="mapa_documental">MAPA documental</option>
          </select>
        </label>
        <button className="secondary-button" type="submit">Filtrar</button>
      </form>

      <OrdersWorkbench dashboard={dashboard} orders={orders} />
    </ProductionShell>
  );
}
