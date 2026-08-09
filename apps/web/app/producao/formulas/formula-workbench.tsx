"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { SmartSearchField } from "@/app/corporate-search/smart-lookup";
import { activatePcpFormulaAction } from "@/app/pcp/actions";
import { FormulaCreationForm } from "@/app/producao/formulas/formula-creation-form";
import type { PcpDashboard, PcpFormulaVersion } from "@/lib/pcp";
import {
  componentTypeLabel,
  formulaBasisLabel,
  formulaPurposeLabel,
  unitLabel
} from "@/lib/production-labels";

type PurposeFilter = "all" | "producao" | "mapa";
type StatusFilter = "active" | "all" | "history";

export function FormulaWorkbench({
  dashboard,
  startCreating = false,
  initialStatus = "active"
}: {
  dashboard: PcpDashboard;
  startCreating?: boolean;
  initialStatus?: StatusFilter;
}) {
  const router = useRouter();
  const [template, setTemplate] = useState<PcpFormulaVersion | null>(null);
  const [isCreating, setIsCreating] = useState(startCreating);
  const [query, setQuery] = useState("");
  const [purpose, setPurpose] = useState<PurposeFilter>("all");
  const [status, setStatus] = useState<StatusFilter>(initialStatus);

  const filteredFormulas = useMemo(() => {
    const normalizedQuery = normalize(query);
    return dashboard.formulaVersions.filter((formula) => {
      if (purpose !== "all" && formula.tipoReceita !== purpose) return false;
      if (status === "active" && !formula.isActive) return false;
      if (status === "history" && formula.isActive) return false;
      if (!normalizedQuery) return true;
      return normalize(`${formula.produtoLabel} ${formula.justificativa} ${formula.observacao ?? ""}`).includes(normalizedQuery);
    });
  }, [dashboard.formulaVersions, purpose, query, status]);

  const activeOperational = dashboard.activeFormulas.filter((formula) => formula.tipoReceita === "producao").length;
  const activeMapa = dashboard.activeFormulas.filter((formula) => formula.tipoReceita === "mapa").length;

  function startBlankFormula() {
    setTemplate(null);
    setIsCreating(true);
    scrollToCreation();
  }

  function startFromTemplate(formula: PcpFormulaVersion) {
    setTemplate(formula);
    setIsCreating(true);
    scrollToCreation();
  }

  function closeCreation() {
    setTemplate(null);
    setIsCreating(false);
    router.replace("/producao/formulas#formulas", { scroll: false });
    document.getElementById("formulas")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  if (isCreating) {
    return (
      <section className="panel formula-create-panel lookup-surface" id="nova-formula" aria-labelledby="nova-formula-title">
        <div className="panel-header formula-create-header">
          <div>
            <span className="formula-section-eyebrow">Nova versão</span>
            <h2 id="nova-formula-title">{template ? `Baseada na versão ${template.versao}` : "Criar fórmula"}</h2>
            <p>
              {template
                ? `Os dados de ${template.produtoLabel} foram copiados para revisão. O histórico permanece intacto.`
                : "Cadastre a composição operacional por litro ou a referência documental MAPA."}
            </p>
          </div>
          <button className="secondary-button" type="button" onClick={closeCreation}>Voltar às fórmulas</button>
        </div>
        <FormulaCreationForm
          key={template?.id ?? "blank"}
          initialFormula={template}
          lookups={dashboard.lookups}
          onCancel={closeCreation}
        />
      </section>
    );
  }

  return (
    <section className="formula-catalog" id="formulas" aria-labelledby="formulas-title">
      <div className="formula-reference-strip" aria-label="Referências vigentes">
        <div>
          <span>Produção operacional</span>
          <strong>{activeOperational}</strong>
          <small>referência(s) vigente(s)</small>
        </div>
        <div>
          <span>Documentação MAPA</span>
          <strong>{activeMapa}</strong>
          <small>referência(s) vigente(s)</small>
        </div>
        <p>
          Uma versão ativa é a referência vigente. Fórmulas históricas sinalizadas precisam ser revisadas antes da OP.
        </p>
      </div>

      <section className="panel formula-list-panel lookup-surface" aria-labelledby="formulas-title">
        <div className="panel-header formula-list-heading">
          <div>
            <h2 id="formulas-title">Fórmulas cadastradas</h2>
            <p>Consulte a versão vigente ou abra o histórico de um produto.</p>
          </div>
          <button className="primary-button" type="button" onClick={startBlankFormula}>Nova fórmula</button>
        </div>

        <div className="formula-filter-bar" aria-label="Filtros de fórmulas">
          <SmartSearchField
            className="formula-search-field"
            name="formula-query"
            label="Buscar"
            defaultValue={query}
            placeholder="Produto, justificativa ou observação"
            source={{
              kind: "local",
              options: dashboard.formulaVersions.map((formula) => ({
                id: formula.id,
                label: formula.produtoLabel,
                detail: `Versão ${formula.versao} · ${formulaPurposeLabel(formula.tipoReceita)} · ${formula.isActive ? "Vigente" : "Histórico"}`
              }))
            }}
            onQueryChange={setQuery}
          />
          <label>
            Finalidade
            <select value={purpose} onChange={(event) => setPurpose(event.target.value as PurposeFilter)}>
              <option value="all">Todas</option>
              <option value="producao">Produção operacional</option>
              <option value="mapa">Documentação MAPA</option>
            </select>
          </label>
          <label>
            Exibir
            <select value={status} onChange={(event) => setStatus(event.target.value as StatusFilter)}>
              <option value="active">Somente vigentes</option>
              <option value="all">Todas as versões</option>
              <option value="history">Somente histórico</option>
            </select>
          </label>
          <span className="formula-result-count">{filteredFormulas.length} resultado(s)</span>
        </div>

        {filteredFormulas.length > 0 ? (
          <div className="formula-version-list">
            {filteredFormulas.map((formula) => (
              <FormulaRecord key={formula.id} formula={formula} onUseAsTemplate={() => startFromTemplate(formula)} />
            ))}
          </div>
        ) : (
          <div className="empty-state formula-empty-state">
            <strong>{dashboard.formulaVersions.length === 0 ? "Nenhuma fórmula cadastrada" : "Nenhuma fórmula encontrada"}</strong>
            <span>
              {dashboard.formulaVersions.length === 0
                ? "Crie a primeira versão para iniciar o fluxo de produção."
                : "Altere a busca ou os filtros para consultar outras versões."}
            </span>
            {dashboard.formulaVersions.length === 0 ? (
              <button className="primary-button" type="button" onClick={startBlankFormula}>Criar primeira fórmula</button>
            ) : null}
          </div>
        )}
      </section>
    </section>
  );
}

function FormulaRecord({
  formula,
  onUseAsTemplate
}: {
  formula: PcpFormulaVersion;
  onUseAsTemplate: () => void;
}) {
  const needsReview = formula.baseCalculo === "legado_nao_comprovado";

  return (
    <details className={`formula-version-record ${formula.isActive ? "is-active" : ""}`}>
      <summary>
        <span className="formula-record-product">
          <strong>{formula.produtoLabel}</strong>
          <small>{formulaPurposeLabel(formula.tipoReceita)}</small>
        </span>
        <span className="formula-record-version">
          <strong>Versão {formula.versao}</strong>
          <small>{shortDate(formula.createdAt)}</small>
        </span>
        <span className={`formula-basis-label ${needsReview ? "needs-review" : ""}`}>
          {formulaBasisLabel(formula.baseCalculo)}
        </span>
        <span className={`formula-status-label ${formula.isActive ? "is-active" : ""}`}>
          {formula.isActive ? "Vigente" : "Histórico"}
        </span>
        <span className="formula-expand-label">Ver detalhes</span>
      </summary>

      <div className="formula-record-detail">
        <div className="formula-version-notes">
          <div>
            <span>Justificativa</span>
            <p>{formula.justificativa}</p>
          </div>
          {formula.observacao ? (
            <div>
              <span>Observação</span>
              <p>{formula.observacao}</p>
            </div>
          ) : null}
        </div>

        <div className="formula-component-summary">
          <div className="formula-component-summary-heading">
            <h3>{formula.tipoReceita === "mapa" ? "Composição declarada" : "Componentes por 1 L"}</h3>
            <span>{formula.components.length} componente(s)</span>
          </div>
          {formula.components.length > 0 ? (
            <div className="formula-component-table" role="table" aria-label={`Componentes da versão ${formula.versao}`}>
              <div className="formula-component-table-head" role="row">
                <span role="columnheader">Tipo</span>
                <span role="columnheader">Item</span>
                <span role="columnheader">Quantidade</span>
                <span role="columnheader">Observação</span>
              </div>
              {formula.components.map((component) => (
                <div className="formula-component-table-row" role="row" key={component.id}>
                  <span role="cell">{componentTypeLabel(component.tipoComponente)}</span>
                  <strong role="cell">{component.targetLabel}</strong>
                  <span role="cell">{formatNumber(component.quantidade)} {unitLabel(component.unidade)}</span>
                  <span role="cell">{component.observacao ?? "Sem observação"}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state compact">
              <strong>Sem composição declarada</strong>
              <span>Esta versão documental não possui componentes informados.</span>
            </div>
          )}
        </div>

        {needsReview ? (
          <div className="notice-panel warning formula-legacy-warning" role="status">
            <strong>Versão histórica sem base por litro comprovada</strong>
            <span>Use esta versão como referência, revise as quantidades e crie uma nova versão antes de abrir uma OP.</span>
          </div>
        ) : null}

        <div className="formula-record-actions">
          <button className="secondary-button" type="button" onClick={onUseAsTemplate}>Criar nova versão a partir desta</button>
          {!formula.isActive && !needsReview ? (
            <details className="formula-activation-disclosure">
              <summary>Ativar esta versão</summary>
              <form className="compact-action-form" action={activatePcpFormulaAction}>
                <input type="hidden" name="formula_versao_id" value={formula.id} />
                <label>
                  Motivo da ativação
                  <input name="motivo" placeholder="Explique por que esta versão passa a valer" required />
                </label>
                <button className="primary-button" type="submit">Confirmar ativação</button>
              </form>
              <p>Esta versão substituirá a referência vigente do mesmo produto e finalidade, sem apagar o histórico.</p>
            </details>
          ) : null}
        </div>
      </div>
    </details>
  );
}

function scrollToCreation() {
  window.requestAnimationFrame(() => {
    document.getElementById("nova-formula")?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
}

function normalize(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function shortDate(value: string | null): string {
  if (!value) return "Data não informada";
  return new Intl.DateTimeFormat("pt-BR").format(new Date(value));
}
