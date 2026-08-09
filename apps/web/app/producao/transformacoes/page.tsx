import Link from "next/link";

import { SmartSearchField } from "@/app/corporate-search/smart-lookup";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { TransformationWorkbench } from "@/app/producao/transformacoes/transformation-workbench";
import { getPcpDashboard, getPcpOrderCapabilities, type PcpComponentType } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionTransformationsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const [dashboard, capabilities] = await Promise.all([
    getPcpDashboard(),
    getPcpOrderCapabilities()
  ]);
  const query = singleProductionParam(params.q)?.trim().toLocaleLowerCase("pt-BR") ?? "";
  const status = singleProductionParam(params.status) ?? "open";
  const sourceType = componentType(singleProductionParam(params.source_type));
  const sourceLotId = integerParam(singleProductionParam(params.source_lot_id));
  const sourceLot = sourceType && sourceLotId
    ? dashboard.availableLots.find((lot) => lot.tipo === sourceType && lot.id === sourceLotId) ?? null
    : null;
  const allTransformations = dashboard.recentOps.filter((op) => op.tipoOp === "reprocessamento");
  const transformations = allTransformations.filter((op) => {
    const statusMatches = status === "all"
      || (status === "open" && ["draft", "planned", "in_process"].includes(op.status))
      || op.status === status;
    const queryMatches = !query
      || `${op.codigoOp} ${op.formulaLabel} ${op.produtoLabel} ${op.observacao ?? ""}`
        .toLocaleLowerCase("pt-BR")
        .includes(query);
    return statusMatches && queryMatches;
  });
  const open = allTransformations.filter((op) => ["draft", "planned"].includes(op.status)).length;
  const inProcess = allTransformations.filter((op) => op.status === "in_process").length;
  const completed = allTransformations.filter((op) => op.status === "completed").length;
  const generatedLots = allTransformations.reduce((sum, op) => sum + op.outputs.length, 0);

  return (
    <ProductionShell
      active="transformacoes"
      title="Transformacoes"
      description="PA para PI, PI para PA, reenvasamento e reprocessamento por ordem de producao."
      source={dashboard.source}
      error={dashboard.error}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/estoque">Lotes e estoque</Link>
          {capabilities.canCreate ? <a className="primary-button" href="#nova-transformacao">Nova transformacao</a> : null}
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      <section className="technical-kpis transformation-kpis" aria-label="Resumo das transformacoes">
        <article><span>Planejadas</span><strong>{open}</strong><small>Aguardando reserva ou inicio.</small></article>
        <article><span>Em processo</span><strong>{inProcess}</strong><small>Aguardando CQ e finalizacao.</small></article>
        <article><span>Finalizadas</span><strong>{completed}</strong><small>Fatos produtivos preservados.</small></article>
        <article><span>Lotes gerados</span><strong>{generatedLots}</strong><small>Saidas PA ou PI rastreaveis.</small></article>
      </section>

      <form className="catalog-filter transformation-filter" method="get">
        <SmartSearchField
          name="q"
          label="Buscar transformação"
          defaultValue={singleProductionParam(params.q) ?? ""}
          placeholder="OP, fórmula, produto ou justificativa"
          source={{ kind: "remote", entity: "ops-producao" }}
        />
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
        {sourceType ? <input type="hidden" name="source_type" value={sourceType} /> : null}
        {sourceLotId ? <input type="hidden" name="source_lot_id" value={sourceLotId} /> : null}
        <button className="secondary-button" type="submit">Filtrar</button>
        <Link href="/producao/transformacoes">Limpar</Link>
      </form>

      <TransformationWorkbench
        capabilities={capabilities}
        dashboard={dashboard}
        transformations={transformations}
        sourceLot={sourceLot}
      />
    </ProductionShell>
  );
}

function componentType(value: string | null): PcpComponentType | null {
  return value === "MP" || value === "PA" || value === "PI" ? value : null;
}

function integerParam(value: string | null): number | null {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}
