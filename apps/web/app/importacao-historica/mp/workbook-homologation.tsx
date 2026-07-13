"use client";

import { ChangeEvent, useEffect, useMemo, useState } from "react";

import {
  EXPECTED_HISTORICAL_WORKBOOK_TABLES,
  WORKBOOK_HOMOLOGATION_DECISION_LABELS,
  WORKBOOK_HOMOLOGATION_DECISIONS,
  buildWorkbookHomologationArtifact,
  createWorkbookHomologationRows,
  isWorkbookHomologationDecision,
  isWorkbookHomologationReady,
  summarizeWorkbookHomologation,
  validateWorkbookHomologationArtifact,
  workbookHomologationCsv,
  type WorkbookHomologationArtifact,
  type WorkbookHomologationDecision,
  type WorkbookHomologationRow,
  type WorkbookHomologationStatus
} from "@/lib/historical-workbook-homologation";
import type {
  HistoricalWorkbookAnalysis,
  WorkbookSourceClassificationName
} from "@/lib/historical-workbook";

type Review = Pick<WorkbookHomologationRow, "decision" | "observation" | "updatedAt">;
type ReviewState = Record<string, Review>;
type DecisionFilter =
  | ""
  | WorkbookHomologationDecision
  | "sem_decisao"
  | "aprovadas_i2"
  | "excluidas"
  | "pendentes";

type Filters = {
  text: string;
  domain: string;
  classification: string;
  decision: DecisionFilter;
};

type LocalDraft = {
  workbookSha256: string;
  reviews: ReviewState;
  previousArtifact: WorkbookHomologationArtifact | null;
};

const EMPTY_FILTERS: Filters = { text: "", domain: "", classification: "", decision: "" };

const CLASSIFICATION_LABELS: Record<WorkbookSourceClassificationName, string> = {
  source_master: "Fonte cadastral",
  source_transaction: "Fonte transacional",
  source_formula: "Formula / composicao",
  reconciliation_report: "Relatorio de reconciliacao",
  derived_calculation: "Calculo derivado",
  duplicate_source: "Fonte duplicada",
  dashboard_or_summary: "Painel / resumo",
  deferred: "Adiado tecnicamente",
  out_of_scope: "Fora do escopo tecnico"
};

const DUPLICATE_RISK_LABELS = {
  low: "Baixo",
  medium: "Medio",
  high: "Alto",
  unknown: "Nao classificado"
} as const;

export function WorkbookHomologationWorkspace({ analysis }: { analysis: HistoricalWorkbookAnalysis }) {
  const technicalRows = useMemo(() => createWorkbookHomologationRows(analysis), [analysis]);
  const [reviews, setReviews] = useState<ReviewState>(() => initialReviews(technicalRows));
  const [previousArtifact, setPreviousArtifact] = useState<WorkbookHomologationArtifact | null>(null);
  const [filters, setFilters] = useState<Filters>(EMPTY_FILTERS);
  const [bulkDecision, setBulkDecision] = useState<WorkbookHomologationDecision | "">("");
  const [localDraftLoaded, setLocalDraftLoaded] = useState(false);
  const [message, setMessage] = useState<{ tone: "success" | "warning"; text: string } | null>(null);

  const rows = useMemo(
    () => technicalRows.map((row) => ({ ...row, ...(reviews[row.sourceTableId] ?? emptyReview()) })),
    [reviews, technicalRows]
  );
  const summary = useMemo(() => summarizeWorkbookHomologation(rows), [rows]);
  const domains = useMemo(
    () => [...new Set(rows.map((row) => row.ownerDomain).filter((value): value is string => Boolean(value)))].sort(),
    [rows]
  );
  const classifications = useMemo(
    () => [...new Set(rows.map((row) => row.technicalClassification).filter((value): value is WorkbookSourceClassificationName => Boolean(value)))].sort(),
    [rows]
  );
  const filteredRows = useMemo(() => filterRows(rows, filters), [filters, rows]);
  const approvedRows = useMemo(() => rows.filter((row) => row.decision === "importar_integralmente"), [rows]);
  const excludedRows = useMemo(() => rows.filter((row) => row.decision === "nao_importar"), [rows]);
  const pendingRows = useMemo(
    () => rows.filter((row) => row.decision === null || row.decision === "adiar" || row.decision === "revisar"),
    [rows]
  );
  const finalReady = isWorkbookHomologationReady(analysis, rows);
  const storageKey = `elite:workbook-homologation:v1:${analysis.file.sha256}`;

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const raw = window.localStorage.getItem(storageKey);
        if (!raw) return;
        const local = JSON.parse(raw) as Partial<LocalDraft>;
        if (local.workbookSha256 !== analysis.file.sha256 || !isRecord(local.reviews)) return;
        setReviews(restoreReviews(technicalRows, local.reviews));
        if (local.previousArtifact) {
          const validation = validateWorkbookHomologationArtifact(local.previousArtifact, analysis, technicalRows);
          if (validation.ok) setPreviousArtifact(validation.artifact);
        }
        setMessage({ tone: "success", text: "Rascunho local restaurado para este workbook." });
      } catch {
        setMessage({ tone: "warning", text: "O rascunho local estava invalido e nao foi aplicado." });
      } finally {
        setLocalDraftLoaded(true);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [analysis, storageKey, technicalRows]);

  useEffect(() => {
    if (!localDraftLoaded) return;
    const local: LocalDraft = {
      workbookSha256: analysis.file.sha256,
      reviews,
      previousArtifact
    };
    try {
      window.localStorage.setItem(storageKey, JSON.stringify(local));
    } catch {
      window.setTimeout(() => setMessage({
        tone: "warning",
        text: "O navegador nao conseguiu salvar o rascunho local. Exporte uma revisao JSON antes de sair."
      }), 0);
    }
  }, [analysis.file.sha256, localDraftLoaded, previousArtifact, reviews, storageKey]);

  function updateDecision(sourceTableId: string, decision: WorkbookHomologationDecision | null) {
    setReviews((current) => ({
      ...current,
      [sourceTableId]: {
        ...(current[sourceTableId] ?? emptyReview()),
        decision,
        updatedAt: new Date().toISOString()
      }
    }));
  }

  function updateObservation(sourceTableId: string, observation: string) {
    setReviews((current) => ({
      ...current,
      [sourceTableId]: {
        ...(current[sourceTableId] ?? emptyReview()),
        observation,
        updatedAt: new Date().toISOString()
      }
    }));
  }

  function applyBulkDecision() {
    if (!bulkDecision || filteredRows.length === 0) return;
    const confirmed = window.confirm(
      `Aplicar "${WORKBOOK_HOMOLOGATION_DECISION_LABELS[bulkDecision]}" explicitamente a ${filteredRows.length} tabela(s) visivel(is)?`
    );
    if (!confirmed) return;
    const visibleIds = new Set(filteredRows.map((row) => row.sourceTableId));
    const updatedAt = new Date().toISOString();
    setReviews((current) => Object.fromEntries(
      technicalRows.map((row) => {
        const review = current[row.sourceTableId] ?? emptyReview();
        return [
          row.sourceTableId,
          visibleIds.has(row.sourceTableId) ? { ...review, decision: bulkDecision, updatedAt } : review
        ];
      })
    ));
    setMessage({
      tone: "success",
      text: `${filteredRows.length} decisao(oes) registradas por acao explicita. Nenhuma classificacao tecnica foi alterada.`
    });
  }

  function exportCsv() {
    downloadBlob(
      workbookHomologationCsv(rows),
      `homologacao-workbook-${analysis.file.sha256.slice(0, 12)}.csv`,
      "text/csv;charset=utf-8"
    );
    setMessage({ tone: "success", text: `Matriz CSV exportada com ${rows.length} tabelas.` });
  }

  function exportJson(status: WorkbookHomologationStatus) {
    try {
      const createdAt = new Date().toISOString();
      const artifact = buildWorkbookHomologationArtifact({
        analysis,
        rows,
        revisionId: createRevisionId(),
        createdAt,
        status,
        previousArtifact
      });
      downloadBlob(
        JSON.stringify(artifact, null, 2),
        `${status === "homologated" ? "homologacao-final" : "revisao-homologacao"}-${analysis.file.sha256.slice(0, 12)}-${createdAt.slice(0, 10)}.json`,
        "application/json;charset=utf-8"
      );
      setPreviousArtifact(artifact);
      setMessage({
        tone: "success",
        text: status === "homologated"
          ? "Homologacao final exportada. Somente as tabelas aprovadas integralmente poderao seguir para I2."
          : "Revisao JSON exportada com historico e vinculo ao workbook."
      });
    } catch (error) {
      setMessage({ tone: "warning", text: error instanceof Error ? error.message : "Nao foi possivel exportar a revisao." });
    }
  }

  async function importJson(event: ChangeEvent<HTMLInputElement>) {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = "";
    if (!file) return;
    try {
      const candidate = JSON.parse(await file.text()) as unknown;
      const validation = validateWorkbookHomologationArtifact(candidate, analysis, technicalRows);
      if (!validation.ok) {
        setMessage({ tone: "warning", text: validation.message });
        return;
      }
      const artifact = validation.artifact;
      setReviews(Object.fromEntries(artifact.entries.map((entry) => [entry.sourceTableId, {
        decision: entry.decision,
        observation: entry.observation,
        updatedAt: entry.updatedAt
      }])));
      setPreviousArtifact(artifact);
      setMessage({ tone: "success", text: `Revisao ${artifact.revisionId} importada e validada pelo SHA256.` });
    } catch {
      setMessage({ tone: "warning", text: "O arquivo selecionado nao e uma revisao JSON valida." });
    }
  }

  return (
    <section className="homologation-workspace" aria-labelledby="homologation-title">
      <div className="section-heading homologation-heading">
        <div>
          <span className="eyebrow">I1.2 · decisão funcional</span>
          <h2 id="homologation-title">Homologação das 269 tabelas</h2>
          <p>A classificação técnica permanece protegida. A decisão de carga pertence a Luciano e nunca é preenchida automaticamente.</p>
        </div>
        <span className={`homologation-gate ${finalReady ? "ready" : "pending"}`}>
          {finalReady ? "Pronta para homologação final" : `${summary.withoutDecision} sem decisão explícita`}
        </span>
      </div>

      <div className="homologation-policy" role="note">
        <strong>I2 permanece bloqueada.</strong>
        <span>Somente <code>importar_integralmente</code> será elegível. Adiar ou revisar bloqueia apenas a própria tabela.</span>
      </div>

      <div className="homologation-summary" aria-label="Resumo por decisão final">
        <SummaryMetric label="Total" value={summary.total} />
        <SummaryMetric label="Sem decisão" value={summary.withoutDecision} tone={summary.withoutDecision ? "warning" : "success"} />
        {WORKBOOK_HOMOLOGATION_DECISIONS.map((decision) => (
          <SummaryMetric
            key={decision}
            label={WORKBOOK_HOMOLOGATION_DECISION_LABELS[decision]}
            value={summary.byDecision[decision]}
            tone={decision === "importar_integralmente" ? "success" : decision === "revisar" ? "warning" : "neutral"}
          />
        ))}
      </div>

      <div className="homologation-actions" aria-label="Exportação e revisão">
        <button className="secondary-button" type="button" onClick={exportCsv}>Exportar matriz CSV</button>
        <button className="secondary-button" type="button" onClick={() => exportJson("draft")}>Exportar revisão JSON</button>
        <label className="secondary-button homologation-import-button">
          Importar revisão JSON
          <input className="homologation-file-input" type="file" accept=".json,application/json" onChange={importJson} />
        </label>
        <button
          className="primary-button"
          type="button"
          disabled={!finalReady}
          onClick={() => exportJson("homologated")}
          title={finalReady ? "Exportar homologação final" : "Registre uma decisão explícita nas 269 tabelas"}
        >
          Exportar homologação final
        </button>
      </div>

      {message ? <div className={`homologation-message ${message.tone}`} role="status">{message.text}</div> : null}

      <section className="homologation-lists" aria-label="Listas de resultado da homologação">
        <DecisionList
          label="Aprovadas para I2"
          rows={approvedRows}
          empty="Nenhuma tabela aprovada integralmente."
          onShow={() => setFilters({ ...EMPTY_FILTERS, decision: "aprovadas_i2" })}
        />
        <DecisionList
          label="Excluídas da carga"
          rows={excludedRows}
          empty="Nenhuma tabela marcada como não importar."
          onShow={() => setFilters({ ...EMPTY_FILTERS, decision: "excluidas" })}
        />
        <DecisionList
          label="Pendentes"
          rows={pendingRows}
          empty="Nenhuma tabela pendente."
          onShow={() => setFilters({ ...EMPTY_FILTERS, decision: "pendentes" })}
        />
      </section>

      <section className="homologation-filters" aria-label="Filtros da matriz de homologação">
        <label>
          Buscar
          <input
            value={filters.text}
            onChange={(event) => setFilters({ ...filters, text: event.target.value })}
            placeholder="Aba, tabela, coluna, destino ou justificativa"
          />
        </label>
        <label>
          Domínio
          <select value={filters.domain} onChange={(event) => setFilters({ ...filters, domain: event.target.value })}>
            <option value="">Todos</option>
            {domains.map((domain) => <option value={domain} key={domain}>{domainLabel(domain)}</option>)}
          </select>
        </label>
        <label>
          Classificação técnica
          <select value={filters.classification} onChange={(event) => setFilters({ ...filters, classification: event.target.value })}>
            <option value="">Todas</option>
            {classifications.map((classification) => (
              <option value={classification} key={classification}>{CLASSIFICATION_LABELS[classification]}</option>
            ))}
          </select>
        </label>
        <label>
          Decisão
          <select value={filters.decision} onChange={(event) => setFilters({ ...filters, decision: event.target.value as DecisionFilter })}>
            <option value="">Todas</option>
            <option value="sem_decisao">Sem decisão</option>
            <option value="aprovadas_i2">Aprovadas para I2</option>
            <option value="excluidas">Excluídas</option>
            <option value="pendentes">Pendentes</option>
            {WORKBOOK_HOMOLOGATION_DECISIONS.map((decision) => (
              <option value={decision} key={decision}>{WORKBOOK_HOMOLOGATION_DECISION_LABELS[decision]}</option>
            ))}
          </select>
        </label>
        <button className="secondary-button" type="button" onClick={() => setFilters(EMPTY_FILTERS)}>Limpar filtros</button>
      </section>

      <section className="homologation-bulk" aria-label="Decisão em lote explícita">
        <div>
          <strong>{filteredRows.length} tabela(s) visível(is)</strong>
          <span>A ação em lote exige confirmação e nunca usa a classificação técnica como decisão.</span>
        </div>
        <select value={bulkDecision} onChange={(event) => setBulkDecision(event.target.value as WorkbookHomologationDecision | "")}>
          <option value="">Escolha uma decisão</option>
          {WORKBOOK_HOMOLOGATION_DECISIONS.map((decision) => (
            <option value={decision} key={decision}>{WORKBOOK_HOMOLOGATION_DECISION_LABELS[decision]}</option>
          ))}
        </select>
        <button className="secondary-button" type="button" disabled={!bulkDecision || filteredRows.length === 0} onClick={applyBulkDecision}>
          Aplicar aos resultados visíveis
        </button>
      </section>

      <div className="homologation-table-scroll">
        <table className="data-table homologation-table">
          <thead>
            <tr>
              <th>Fonte no workbook</th>
              <th>Principais colunas</th>
              <th>Classificação e destino técnicos</th>
              <th>Indícios e riscos</th>
              <th>Justificativa técnica</th>
              <th>Decisão final de Luciano</th>
            </tr>
          </thead>
          <tbody>
            {filteredRows.map((row) => (
              <tr key={row.sourceTableId} className={row.decision ? `decision-${row.decision}` : "decision-missing"}>
                <td className="homologation-source-cell">
                  <strong>{row.sheetOrder}. {row.sheetName}</strong>
                  <span>{row.tableName}</span>
                  <code>{row.range}</code>
                  <small>{formatNumber(row.rowCount)} linhas · {row.columnCount} colunas · {formatNumber(row.populatedRowCount)} preenchidas</small>
                  <small>ID: {row.sourceTableId}</small>
                </td>
                <td>
                  <div className="homologation-columns">
                    {row.mainColumns.map((column, index) => <span key={`${row.sourceTableId}-${index}`}>{column}</span>)}
                    {row.columnCount > row.mainColumns.length ? <small>+ {row.columnCount - row.mainColumns.length} coluna(s)</small> : null}
                  </div>
                </td>
                <td className="homologation-technical-cell">
                  <strong>{classificationLabel(row.technicalClassification)}</strong>
                  <span>{domainLabel(row.ownerDomain ?? "sem_dominio")}</span>
                  <code>{row.targetEntity ?? "Destino técnico não definido"}</code>
                  {row.technicalReviewRequired ? <small className="warning-text">Revisão técnica exigida</small> : null}
                </td>
                <td>
                  <div className="homologation-signals">
                    <span>Fórmulas: <strong>{row.formulaCellCount > 0 ? `Sim (${formatNumber(row.formulaCellCount)})` : "Não"}</strong></span>
                    <span>Relatório: <strong>{yesNo(row.reportIndicator)}</strong></span>
                    <span>Cálculo derivado: <strong>{yesNo(row.derivedCalculationIndicator)}</strong></span>
                    <span>Duplicidade: <strong>{DUPLICATE_RISK_LABELS[row.duplicateRisk]}</strong></span>
                  </div>
                </td>
                <td className="homologation-justification">{row.technicalJustification}</td>
                <td className="homologation-decision-cell">
                  <label>
                    Decisão
                    <select
                      value={row.decision ?? ""}
                      onChange={(event) => updateDecision(
                        row.sourceTableId,
                        event.target.value ? event.target.value as WorkbookHomologationDecision : null
                      )}
                    >
                      <option value="">Sem decisão</option>
                      {WORKBOOK_HOMOLOGATION_DECISIONS.map((decision) => (
                        <option value={decision} key={decision}>{WORKBOOK_HOMOLOGATION_DECISION_LABELS[decision]}</option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Observação de Luciano
                    <textarea
                      rows={2}
                      maxLength={1000}
                      value={row.observation}
                      onChange={(event) => updateObservation(row.sourceTableId, event.target.value)}
                      placeholder="Opcional; não substitui a decisão"
                    />
                  </label>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filteredRows.length === 0 ? <div className="empty-state"><strong>Nenhuma tabela encontrada</strong><span>Altere os filtros da homologação.</span></div> : null}
      </div>

      <footer className="homologation-footer">
        <span>{rows.length} de {EXPECTED_HISTORICAL_WORKBOOK_TABLES} tabelas apresentadas.</span>
        <span>Rascunho salvo somente neste navegador · nenhum dado enviado ao PostgreSQL.</span>
      </footer>
    </section>
  );
}

function SummaryMetric({ label, value, tone = "neutral" }: { label: string; value: number; tone?: "neutral" | "success" | "warning" }) {
  return <div className={`homologation-summary-item ${tone}`}><span>{label}</span><strong>{formatNumber(value)}</strong></div>;
}

function DecisionList({
  label,
  rows,
  empty,
  onShow
}: {
  label: string;
  rows: WorkbookHomologationRow[];
  empty: string;
  onShow: () => void;
}) {
  return (
    <details>
      <summary><strong>{label}</strong><span>{rows.length}</span></summary>
      <div>
        <button className="text-button" type="button" onClick={onShow}>Mostrar na matriz</button>
        {rows.length ? (
          <ul>{rows.map((row) => <li key={row.sourceTableId}>{row.sheetOrder}. {row.sheetName} · {row.tableName}</li>)}</ul>
        ) : <p>{empty}</p>}
      </div>
    </details>
  );
}

function filterRows(rows: WorkbookHomologationRow[], filters: Filters): WorkbookHomologationRow[] {
  const query = filters.text.trim().toLocaleLowerCase("pt-BR");
  return rows.filter((row) => {
    if (filters.domain && row.ownerDomain !== filters.domain) return false;
    if (filters.classification && row.technicalClassification !== filters.classification) return false;
    if (!decisionMatches(row.decision, filters.decision)) return false;
    if (!query) return true;
    return [
      row.sheetName,
      row.tableName,
      row.range,
      row.ownerDomain ?? "",
      row.targetEntity ?? "",
      row.technicalJustification,
      row.observation,
      ...row.mainColumns
    ].some((value) => value.toLocaleLowerCase("pt-BR").includes(query));
  });
}

function decisionMatches(decision: WorkbookHomologationDecision | null, filter: DecisionFilter): boolean {
  if (!filter) return true;
  if (filter === "sem_decisao") return decision === null;
  if (filter === "aprovadas_i2") return decision === "importar_integralmente";
  if (filter === "excluidas") return decision === "nao_importar";
  if (filter === "pendentes") return decision === null || decision === "adiar" || decision === "revisar";
  return decision === filter;
}

function initialReviews(rows: WorkbookHomologationRow[]): ReviewState {
  return Object.fromEntries(rows.map((row) => [row.sourceTableId, emptyReview()]));
}

function restoreReviews(rows: WorkbookHomologationRow[], candidate: Record<string, unknown>): ReviewState {
  return Object.fromEntries(rows.map((row) => {
    const stored = candidate[row.sourceTableId];
    if (!isRecord(stored)) return [row.sourceTableId, emptyReview()];
    const decision = stored.decision === null || isWorkbookHomologationDecision(stored.decision) ? stored.decision : null;
    return [row.sourceTableId, {
      decision,
      observation: typeof stored.observation === "string" ? stored.observation.slice(0, 1000) : "",
      updatedAt: typeof stored.updatedAt === "string" ? stored.updatedAt : null
    }];
  }));
}

function emptyReview(): Review {
  return { decision: null, observation: "", updatedAt: null };
}

function createRevisionId(): string {
  const suffix = typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return `i1.2-${suffix}`;
}

function downloadBlob(content: string, fileName: string, type: string) {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
}

function classificationLabel(classification: WorkbookSourceClassificationName | null): string {
  return classification ? CLASSIFICATION_LABELS[classification] : "Sem classificação técnica";
}

function domainLabel(domain: string): string {
  return ({
    auditoria: "Auditoria",
    cadastros: "Cadastros",
    comercial: "Comercial",
    estoque: "Estoque",
    faturamento: "Faturamento",
    financeiro: "Financeiro",
    logistica: "Logística",
    pcp: "PCP / Produção",
    pedidos: "Pedidos",
    sem_dominio: "Sem domínio técnico"
  } as Record<string, string>)[domain] ?? domain;
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

function yesNo(value: boolean): string {
  return value ? "Sim" : "Não";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
