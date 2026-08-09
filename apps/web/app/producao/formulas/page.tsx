import Link from "next/link";

import { FormulaWorkbench } from "@/app/producao/formulas/formula-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionFormulasPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getPcpDashboard();
  const startCreating = singleProductionParam(params.nova) === "1";
  const result = singleProductionParam(params.result);
  const initialStatus = result === "formula_created" ? "all" : "active";

  return (
    <ProductionShell
      active="formulas"
      title="Fórmulas"
      description="Receitas imutáveis por versão, com produção operacional separada da documentação MAPA."
      source={dashboard.source}
      error={dashboard.error ? "Não foi possível carregar as fórmulas neste ambiente. Atualize a página ou procure o suporte." : null}
      actions={(
        <>
          <Link className="secondary-button" href="/cadastros/produtos">Produtos PA/PI</Link>
          <Link className="primary-button" href="/producao/formulas?nova=1#nova-formula">Nova fórmula</Link>
        </>
      )}
    >
      <ProductionFeedback result={result} />
      <FormulaWorkbench key={startCreating ? "creating" : `catalog-${initialStatus}`} dashboard={dashboard} startCreating={startCreating} initialStatus={initialStatus} />
    </ProductionShell>
  );
}
