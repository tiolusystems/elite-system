import { activatePcpFormulaAction, createPcpFormulaAction } from "@/app/pcp/actions";
import { FormulaComponentRows } from "@/app/pcp/production-editors";
import type { PcpDashboard, PcpFormulaVersion } from "@/lib/pcp";

export function FormulaWorkbench({ dashboard, includeActive = true }: { dashboard: PcpDashboard; includeActive?: boolean }) {
  return (
    <>
      <section className="two-column production-primary-grid">
        <section className="panel form-panel" id="nova-formula" aria-labelledby="nova-formula-title">
          <div className="panel-header">
            <h2 id="nova-formula-title">Nova versao de formula</h2>
            <span className="pill">append-only</span>
          </div>
          <form action={createPcpFormulaAction}>
            <div className="form-grid">
              <label className="wide-field">
                Produto PA/PI
                <select name="produto_id" defaultValue="" required>
                  <option value="">Selecione o produto</option>
                  {dashboard.lookups.produtos.map((option) => (
                    <option key={option.id} value={option.id}>{option.label}</option>
                  ))}
                </select>
              </label>
              <label>
                Tipo de receita
                <select name="tipo_receita" defaultValue="producao">
                  <option value="producao">Producao operacional</option>
                  <option value="mapa">MAPA documental</option>
                </select>
              </label>
              <label className="wide-field">
                Justificativa
                <input name="justificativa" placeholder="Motivo da criacao ou alteracao" required />
              </label>
              <label className="full-field">
                Observacao
                <input name="observacao" placeholder="Informacao complementar opcional" />
              </label>
            </div>
            <FormulaComponentRows
              targets={{
                materiasPrimas: dashboard.lookups.materiasPrimas,
                produtos: dashboard.lookups.produtos,
                produtoEmbalagens: dashboard.lookups.produtoEmbalagens
              }}
            />
            <div className="form-footer">
              <span>Formula operacional exige componente. A receita MAPA pode ser apenas documental.</span>
              <button className="primary-button" type="submit">Criar versao</button>
            </div>
          </form>
        </section>

        <section className="panel" id="formulas" aria-labelledby="formulas-title">
          <div className="panel-header">
            <h2 id="formulas-title">Historico de versoes</h2>
            <span className="pill">{dashboard.formulaVersions.length} versao(oes)</span>
          </div>
          {dashboard.formulaVersions.length > 0 ? (
            <div className="module-list">
              {dashboard.formulaVersions.slice(0, 20).map((formula) => (
                <FormulaCard key={formula.id} formula={formula} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma formula cadastrada</strong>
              <span>Cadastre a primeira versao para iniciar o fluxo de producao.</span>
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
                    <span>{formula.tipoReceita} v{formula.versao} / {shortDate(formula.ativadaAt)}</span>
                  </div>
                  <div className="module-card-meta">
                    <span>formula</span>
                    <strong>{formula.formulaVersionId}</strong>
                  </div>
                  <p>{formula.motivoAtivacao}</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma formula ativa</strong>
              <span>Ative uma versao aprovada antes de abrir uma OP operacional.</span>
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
        <span>{formula.tipoReceita} v{formula.versao} / {shortDate(formula.createdAt)}</span>
      </div>
      <div className="module-card-meta">
        <span>{formula.isActive ? "ativa" : "versao"}</span>
        <strong>{formula.id}</strong>
      </div>
      <p>{formula.justificativa}</p>
      <div className="tag-row">
        {formula.components.length > 0 ? (
          formula.components.slice(0, 8).map((component) => (
            <span className="tag" key={component.id}>
              {component.tipoComponente} {formatNumber(component.quantidade)} {component.unidade ?? ""} - {component.targetLabel}
            </span>
          ))
        ) : (
          <span className="tag">sem componentes operacionais</span>
        )}
      </div>
      {!formula.isActive ? (
        <form className="compact-action-form" action={activatePcpFormulaAction}>
          <input type="hidden" name="formula_versao_id" value={formula.id} />
          <input name="motivo" placeholder="Motivo para ativar esta versao" required />
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
