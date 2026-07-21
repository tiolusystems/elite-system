import { activatePcpFormulaAction } from "@/app/pcp/actions";
import { FormulaCreationForm } from "@/app/producao/formulas/formula-creation-form";
import type { PcpDashboard, PcpFormulaVersion } from "@/lib/pcp";
import { componentTypeLabel, unitLabel } from "@/lib/production-labels";

export function FormulaWorkbench({ dashboard, includeActive = true }: { dashboard: PcpDashboard; includeActive?: boolean }) {
  return (
    <>
      <section className="two-column production-primary-grid">
        <section className="panel form-panel" id="nova-formula" aria-labelledby="nova-formula-title">
          <div className="panel-header">
            <h2 id="nova-formula-title">Nova versão de fórmula</h2>
            <span className="pill">Histórico preservado</span>
          </div>
          <FormulaCreationForm lookups={dashboard.lookups} />
        </section>

        <section className="panel" id="formulas" aria-labelledby="formulas-title">
          <div className="panel-header">
            <h2 id="formulas-title">Histórico de versões</h2>
            <span className="pill">{dashboard.formulaVersions.length} versão(ões)</span>
          </div>
          {dashboard.formulaVersions.length > 0 ? (
            <div className="module-list">
              {dashboard.formulaVersions.slice(0, 20).map((formula) => (
                <FormulaCard key={formula.id} formula={formula} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma fórmula cadastrada</strong>
              <span>Cadastre a primeira versão para iniciar o fluxo de produção.</span>
            </div>
          )}
        </section>
      </section>

      {includeActive ? (
        <section className="panel" aria-labelledby="formulas-ativas-title">
          <div className="panel-header">
            <h2 id="formulas-ativas-title">Referencias vigentes</h2>
            <span className="pill">{dashboard.activeFormulas.length} ativa(s)</span>
          </div>
          {dashboard.activeFormulas.length > 0 ? (
            <div className="operation-card-grid">
              {dashboard.activeFormulas.map((formula) => (
                <article className="module-card" key={`${formula.produtoId}-${formula.tipoReceita}`}>
                  <div className="module-card-main">
                    <h3>{formula.produtoLabel}</h3>
                    <span>{recipeTypeLabel(formula.tipoReceita)} v{formula.versao} / {shortDate(formula.ativadaAt)}</span>
                  </div>
                  <div className="module-card-meta">
                    <span>fórmula</span>
                    <strong>{formula.formulaVersionId}</strong>
                  </div>
                  <p>{formula.motivoAtivacao}</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma fórmula ativa</strong>
              <span>Ative uma versão aprovada antes de abrir uma OP operacional.</span>
            </div>
          )}
        </section>
      ) : null}
    </>
  );
}

function FormulaCard({ formula }: { formula: PcpFormulaVersion }) {
  return (
    <article className="module-card">
      <div className="module-card-main">
        <h3>{formula.produtoLabel}</h3>
        <span>{recipeTypeLabel(formula.tipoReceita)} v{formula.versao} / {shortDate(formula.createdAt)}</span>
      </div>
      <div className="module-card-meta">
        <span>{formula.isActive ? "ativa" : "versão"}</span>
        <strong>{formula.id}</strong>
      </div>
      <p>{formula.justificativa}</p>
      <div className="tag-row">
        {formula.components.length > 0 ? (
          formula.components.slice(0, 8).map((component) => (
            <span className="tag" key={component.id}>
              {componentTypeLabel(component.tipoComponente)} {formatNumber(component.quantidade)} {unitLabel(component.unidade)} - {component.targetLabel}
            </span>
          ))
        ) : (
          <span className="tag">Sem componentes operacionais</span>
        )}
      </div>
      {!formula.isActive ? (
        <form className="compact-action-form" action={activatePcpFormulaAction}>
          <input type="hidden" name="formula_versao_id" value={formula.id} />
          <input name="motivo" placeholder="Motivo para ativar esta versão" required />
          <button className="secondary-button" type="submit">Ativar</button>
        </form>
      ) : null}
    </article>
  );
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function shortDate(value: string | null): string {
  if (!value) return "-";
  return new Intl.DateTimeFormat("pt-BR").format(new Date(value));
}

function recipeTypeLabel(value: string): string {
  return value === "mapa" ? "Documentação MAPA" : "Produção operacional";
}
