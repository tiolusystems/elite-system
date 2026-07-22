import Link from "next/link";

import {
  StockWorkbench,
  type LotValidity
} from "@/app/producao/estoque/stock-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getStockWorkspace } from "@/lib/stock";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionStockPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const query = singleProductionParam(params.q)?.trim() ?? "";
  const family = singleProductionParam(params.familia) ?? "all";
  const status = singleProductionParam(params.status) ?? "com_saldo";
  const validity = singleProductionParam(params.validade) ?? "all";
  const page = Math.max(1, Number(singleProductionParam(params.pagina) ?? 1) || 1);
  const today = new Date().toISOString().slice(0, 10);
  const workspace = await getStockWorkspace({ search: query, family, status, validity, page });
  const pageCount = Math.max(1, Math.ceil(workspace.total / workspace.pageSize));

  return (
    <ProductionShell
      active="estoque"
      title="Lotes e estoque"
      description="Consulta operacional dos saldos fisico, reservado e disponivel por lote de MP, PA e PI."
      source={workspace.source}
      error={workspace.error}
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
          Produto ou materia-prima
          <input name="q" defaultValue={singleProductionParam(params.q) ?? ""} placeholder="Nome, SKU ou codigo do produto" required />
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

      {query ? <><div className="section-heading inventory-results-heading">
        <div>
          <span className="eyebrow">Livro de estoque derivado</span>
          <h2>{workspace.total} lote(s) encontrado(s)</h2>
        </div>
        <span className="pill">pagina {workspace.page} de {pageCount}</span>
      </div>
      <StockWorkbench lots={workspace.lots} today={today} />
      {pageCount > 1 ? <nav className="pagination" aria-label="Paginas do estoque">
        {workspace.page > 1 ? <Link className="secondary-button" href={pageHref(params, workspace.page - 1)}>Anterior</Link> : <span />}
        <span>{workspace.page} de {pageCount}</span>
        {workspace.page < pageCount ? <Link className="secondary-button" href={pageHref(params, workspace.page + 1)}>Proxima</Link> : <span />}
      </nav> : null}</> : <section className="empty-state inventory-query-required">
        <strong>Pesquise primeiro o produto</strong>
        <span>Os lotes serao exibidos somente depois de informar um produto, apresentacao, materia-prima ou SKU.</span>
      </section>}
    </ProductionShell>
  );
}

function pageHref(params: SearchParams, page: number) {
  const next = new URLSearchParams();
  for (const [key, raw] of Object.entries(params)) {
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (value && key !== "pagina") next.set(key, value);
  }
  next.set("pagina", String(page));
  return `/producao/estoque?${next.toString()}`;
}

function validityOption(value: LotValidity, label: string) {
  return <option value={value}>{label}</option>;
}
