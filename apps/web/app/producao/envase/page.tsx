import { PackagingWorkbench } from "@/app/producao/envase/packaging-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPackagingOrdersData } from "@/lib/packaging-orders";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PackagingOrdersPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const data = await getPackagingOrdersData();
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
      <PackagingWorkbench data={data} />
    </ProductionShell>
  );
}
