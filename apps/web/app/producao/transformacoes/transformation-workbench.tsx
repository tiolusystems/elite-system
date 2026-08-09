import { randomUUID } from "node:crypto";

import Link from "next/link";

import { LocalEntityLookup } from "@/app/corporate-search/local-entity-lookup";
import { createPcpOpAction } from "@/app/pcp/actions";
import { PlanningOrderCard } from "@/app/producao/ordens/orders-workbench";
import type {
  PcpAvailableLot,
  PcpDashboard,
  PcpFormulaVersion,
  PcpOrderCapabilities,
  PcpRecentOp
} from "@/lib/pcp";

export function TransformationWorkbench({
  dashboard,
  transformations,
  sourceLot,
  capabilities
}: {
  dashboard: PcpDashboard;
  transformations: PcpRecentOp[];
  sourceLot: PcpAvailableLot | null;
  capabilities: PcpOrderCapabilities;
}) {
  const opRequestKey = randomUUID();
  const formulas = transformationFormulas(dashboard.formulaVersions, sourceLot);

  return (
    <>
      {sourceLot ? (
        <section className={`notice-panel ${sourceLot.status === "bloqueado" ? "warning" : "ok"}`}>
          <strong>Lote de origem selecionado: {sourceLot.codigoLote}</strong>
          <span>
            {sourceLot.tipo} - {sourceLot.targetLabel} - disponivel {formatNumber(sourceLot.saldoDisponivel)}.
            {sourceLot.status === "bloqueado" ? " Libere o lote PA/PI antes de tentar reserva-lo." : ""}
          </span>
        </section>
      ) : null}

      <section className="two-column production-primary-grid">
        {capabilities.canCreate ? (
        <section className="panel form-panel lookup-surface" id="nova-transformacao" aria-labelledby="new-transformation-title">
          <div className="panel-header">
            <div>
              <span className="eyebrow">OP de reprocessamento</span>
              <h2 id="new-transformation-title">Planejar transformacao</h2>
            </div>
            <span className="pill">movimentos auditados</span>
          </div>
          <form action={createPcpOpAction}>
            <input type="hidden" name="idempotency_key" value={opRequestKey} />
            <input type="hidden" name="tipo_op" value="reprocessamento" />
            <input type="hidden" name="return_to" value="transformacoes" />
            <div className="form-grid">
              <LocalEntityLookup
                className="wide-field"
                name="formula_versao_id"
                label="Fórmula de produção"
                placeholder="Abra a lista ou pesquise a fórmula"
                options={formulas.map((formula) => ({
                  id: formula.id,
                  label: `${formula.productLabel} / v${formula.version}`,
                  detail: componentSummary(formula)
                }))}
                required
              />
              <label>
                Volume planejado (L)
                <input name="quantidade_planejada" inputMode="decimal" placeholder="Ex.: 1.000" required />
              </label>
              <label className="full-field">
                Justificativa operacional
                <input
                  name="observacao"
                  placeholder="Reprocessamento, PA para PI, PI para PA ou reenvasamento"
                  required
                />
              </label>
            </div>
            <div className="form-footer">
              <span>O volume multiplica a formula por litro. O destino e informado no CQ e na finalizacao.</span>
              <button className="primary-button" type="submit" disabled={formulas.length === 0}>
                Abrir transformacao
              </button>
            </div>
            {formulas.length === 0 ? (
              <p className="field-note warning-text">Nenhuma formula de producao compativel com o lote selecionado.</p>
            ) : null}
          </form>
        </section>
        ) : (
          <section className="notice-panel warning" aria-label="Transformação em modo de consulta">
            <strong>Criação de transformação não autorizada</strong>
            <span>Você pode consultar as ordens existentes, mas não possui alçada para abrir uma nova.</span>
          </section>
        )}

        <section className="panel transformation-flow-panel" aria-labelledby="transformation-flow-title">
          <div className="panel-header">
            <h2 id="transformation-flow-title">Fluxo governado</h2>
            <span className="pill">sem ajuste de saldo</span>
          </div>
          <ol className="transformation-steps">
            <li><span>01</span><div><strong>Formula</strong><small>Entradas MP, PA ou PI versionadas.</small></div></li>
            <li><span>02</span><div><strong>Reserva</strong><small>Lote de origem fica comprometido.</small></div></li>
            <li><span>03</span><div><strong>Producao e CQ</strong><small>Processo e participantes registrados.</small></div></li>
            <li><span>04</span><div><strong>Novo lote</strong><small>Consumo e entrada correlacionados pela OP.</small></div></li>
          </ol>
          <Link className="secondary-button" href="/producao/formulas">Revisar formulas</Link>
        </section>
      </section>

      <section className="panel" id="transformacoes" aria-labelledby="transformations-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Fila operacional</span>
            <h2 id="transformations-title">Transformacoes e reprocessamentos</h2>
          </div>
          <span className="pill">{transformations.length} resultado(s)</span>
        </div>
        {transformations.length > 0 ? (
          <div className="pcp-op-list">
            {transformations.map((op) => (
              <PlanningOrderCard
                key={op.id}
                op={op}
                availableLots={dashboard.availableLots}
                capabilities={capabilities}
                returnTo="transformacoes"
              />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Nenhuma transformacao encontrada</strong>
            <span>Revise o filtro ou abra uma OP de reprocessamento.</span>
          </div>
        )}
      </section>
    </>
  );
}

type TransformationFormula = {
  id: number;
  productLabel: string;
  version: number;
  components: PcpFormulaVersion["components"];
};

function transformationFormulas(
  formulas: PcpFormulaVersion[],
  sourceLot: PcpAvailableLot | null
): TransformationFormula[] {
  return formulas
    .filter((formula) => formula.tipoReceita === "producao" && formula.components.length > 0)
    .filter((formula) => !sourceLot || formula.components.some(
      (component) => component.tipoComponente === sourceLot.tipo && component.targetId === sourceLot.targetId
    ))
    .map((formula) => ({
      id: formula.id,
      productLabel: formula.produtoLabel,
      version: formula.versao,
      components: formula.components
    }));
}

function componentSummary(formula: TransformationFormula): string {
  return Array.from(new Set(formula.components.map((component) => component.tipoComponente))).join(" + ");
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}
