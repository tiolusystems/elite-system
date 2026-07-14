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
      title="Formulas"
      description="Receitas imutaveis por versao, com componentes operacionais separados da documentacao MAPA."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/cadastros/produtos">Produtos PA/PI</Link>
          <a className="primary-button" href="#nova-formula">Nova versao</a>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      <FormulaWorkbench dashboard={dashboard} />
    </ProductionShell>
  );
}
