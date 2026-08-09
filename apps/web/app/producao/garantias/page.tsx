import Link from "next/link";

import { GuaranteeWorkbench } from "@/app/producao/garantias/guarantee-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionGuaranteesPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getPcpDashboard();
  const today = new Date().toISOString().slice(0, 10);

  return (
    <ProductionShell
      active="garantias"
      title="Garantias e conformidade"
      description="Valores declarados do produto e resultados de laboratório preservados por vigência e lote."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/cadastros/tecnicos">Unidades e nutrientes</Link>
          <Link className="primary-button" href="/producao/formulas">Ver fórmulas</Link>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />
      <GuaranteeWorkbench dashboard={dashboard} today={today} />
    </ProductionShell>
  );
}
