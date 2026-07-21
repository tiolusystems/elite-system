import Link from "next/link";

import {
  getLotValidity,
  StockWorkbench,
  type LotValidity
} from "@/app/producao/estoque/stock-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionStockPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getPcpDashboard();
  const query = singleProductionParam(params.q)?.trim().toLocaleLowerCase("pt-BR") ?? "";
  const family = singleProductionParam(params.familia) ?? "all";
  const status = singleProductionParam(params.status) ?? "com_saldo";
  const validity = singleProductionParam(params.validade) ?? "all";
  const today = new Date().toISOString().slice(0, 10);
  const lots = dashboard.availableLots.filter((lot) => {
    const lotValidity = getLotValidity(lot, today);
    const queryMatches = !query
      || `${lot.codigoLote} ${lot.targetLabel} ${lot.origemRef ?? ""}`.toLocaleLowerCase("pt-BR").includes(query);
    const familyMatches = family === "all" || lot.tipo === family;
    const statusMatches = status === "all"
      || (status === "com_saldo" && lot.saldoFisico > 0)
      || lot.status === status;
    const validityMatches = validity === "all" || lotValidity === validity;
    return queryMatches && familyMatches && statusMatches && validityMatches;
  });

  return (
    <ProductionShell
      active="estoque"
      title="Lotes e estoque"
      description="Consulta operacional dos saldos fisico, reservado e disponivel por lote de MP, PA e PI."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/ordens">Ordens</Link>
          <Link className="primary-button" href="/producao/transformacoes">Transformacoes</Link>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      <form className="catalog-filter inventory-filter" method="get">
        <label>
          Buscar lote
          <input name="q" defaultValue={singleProductionParam(params.q) ?? ""} placeholder="Codigo, item ou origem" />
        </label>
        <label>
          Familia
          <select name="familia" defaultValue={family}>
            <option value="all">MP, PA e PI</option>
            <option value="MP">Materia-prima</option>
            <option value="PA">Produto acabado</option>
            <option value="PI">Produto intermediario</option>
          </select>
        </label>
        <label>
          Status
          <select name="status" defaultValue={status}>
            <option value="com_saldo">Com saldo</option>
            <option value="all">Todos</option>
            <option value="disponivel">Disponivel</option>
            <option value="bloqueado">Bloqueado</option>
            <option value="esgotado">Esgotado</option>
            <option value="cancelado">Cancelado</option>
          </select>
        </label>
        <label>
          Validade
          <select name="validade" defaultValue={validity}>
            <option value="all">Todas</option>
            {validityOption("vencido", "Vencidos")}
            {validityOption("vence_30_dias", "Vencem em 30 dias")}
            {validityOption("vigente", "Vigentes")}
            {validityOption("sem_validade", "Sem validade")}
          </select>
        </label>
        <button className="secondary-button" type="submit">Filtrar</button>
        <Link href="/producao/estoque">Limpar</Link>
      </form>

      <div className="section-heading inventory-results-heading">
        <div>
          <span className="eyebrow">Livro de estoque derivado</span>
          <h2>{lots.length} lote(s) encontrado(s)</h2>
        </div>
        <span className="pill">sem edicao direta de saldo</span>
      </div>
      <StockWorkbench lots={lots} today={today} />
    </ProductionShell>
  );
}

function validityOption(value: LotValidity, label: string) {
  return <option value={value}>{label}</option>;
}
