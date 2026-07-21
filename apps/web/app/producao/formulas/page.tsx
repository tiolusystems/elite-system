import Link from "next/link";

import { FormulaWorkbench } from "@/app/producao/formulas/formula-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionFormulasPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getPcpDashboard();

  return (
    <ProductionShell
      active="formulas"
      title="Fórmulas"
      description="Receitas imutáveis por versão, com produção operacional separada da documentação MAPA."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/cadastros/produtos">Produtos PA/PI</Link>
          <a className="primary-button" href="#nova-formula">Nova versão</a>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      <FormulaWorkbench dashboard={dashboard} />
    </ProductionShell>
  );
}
