import { SmartSearchField } from "@/app/corporate-search/smart-lookup";
import { PackagingWorkbench } from "@/app/producao/envase/packaging-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPackagingOrdersData } from "@/lib/packaging-orders";
import Link from "next/link";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PackagingOrdersPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const query = singleProductionParam(params.q)?.trim() ?? "";
  const status = singleProductionParam(params.status) ?? "all";
  const page = Math.max(1, Number(singleProductionParam(params.pagina) ?? 1) || 1);
  const data = await getPackagingOrdersData({ page, pageSize: 20, query, status });
  return (
    <ProductionShell
      active="envase"
      title="OP MAPA e Ordem de Envase"
      description="Emita o documento MAPA e a ordem física; reserve embalagens, consuma PI e gere um lote PA rastreável."
      source={data.source}
      error={data.error}
      actions={<a className="primary-button" href="#emitir">Emitir ordem</a>}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      <form className="catalog-filter" method="get">
        <SmartSearchField
          name="q"
          label="Buscar ordem"
          defaultValue={query}
          placeholder="Código da Ordem de Envase"
          source={{ kind: "remote", entity: "ordens-envase" }}
        />
        <label>Situação<select name="status" defaultValue={status}>
          <option value="all">Todas</option>
          <option value="emitida">Emitida</option>
          <option value="em_separacao">Em separação</option>
          <option value="em_envase">Em envase</option>
          <option value="finalizada">Finalizada</option>
          <option value="cancelada">Cancelada</option>
        </select></label>
        <button className="secondary-button" type="submit">Filtrar</button>
        <Link href="/producao/envase">Limpar</Link>
      </form>
      <PackagingWorkbench data={data} />
      {data.pagination.totalPages > 1 ? <nav className="pagination" aria-label="Páginas das Ordens de Envase">
        {data.pagination.page > 1 ? <Link className="secondary-button" href={pageHref(query, status, data.pagination.page - 1)}>Anterior</Link> : <span />}
        <span>Página {data.pagination.page} de {data.pagination.totalPages}</span>
        {data.pagination.page < data.pagination.totalPages ? <Link className="secondary-button" href={pageHref(query, status, data.pagination.page + 1)}>Próxima</Link> : <span />}
      </nav> : null}
    </ProductionShell>
  );
}

function pageHref(query: string, status: string, page: number): string {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  if (status !== "all") params.set("status", status);
  params.set("pagina", String(page));
  return `/producao/envase?${params.toString()}#ordens-envase`;
}
