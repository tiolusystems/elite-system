"use client";

import { FormEvent, SyntheticEvent, useMemo, useRef, useState } from "react";

import type {
  HistoricalWorkbookAnalysis,
  WorkbookMappingStatus,
  WorkbookReference,
  WorkbookSheetAnalysis,
  WorkbookSourceClassificationName,
  WorkbookTableAnalysis
} from "@/lib/historical-workbook";

import { analyzeHistoricalWorkbookAction } from "./actions";
import { WorkbookHomologationWorkspace } from "./workbook-homologation";

const READ_ONLY_NOTICE = "Esta etapa apenas analisa o arquivo. Nenhum dado será gravado no banco.";
const STATUS_LABELS: Record<WorkbookMappingStatus, string> = {
  defined: "Destino definido",
  transform: "Requer transformação",
  pending: "Pendente de decisão",
  rejected: "Rejeitado",
  out_of_scope: "Fora da carga operacional"
};

const SOURCE_CLASSIFICATION_LABELS: Record<WorkbookSourceClassificationName, string> = {
  source_master: "Fonte cadastral",
  source_transaction: "Fonte transacional",
  source_formula: "Formula / composicao",
  reconciliation_report: "Relatorio de reconciliacao",
  derived_calculation: "Calculo derivado",
  duplicate_source: "Fonte duplicada",
  dashboard_or_summary: "Painel / resumo",
  deferred: "Adiado",
  out_of_scope: "Fora do escopo"
};

type Filters = { sheet: string; domain: string; status: string; text: string };

const EMPTY_FILTERS: Filters = { sheet: "", domain: "", status: "", text: "" };

export function WorkbookAnalysisWorkspace() {
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [analysis, setAnalysis] = useState<HistoricalWorkbookAnalysis | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [filters, setFilters] = useState<Filters>(EMPTY_FILTERS);

  const filteredSheets = useMemo(
    () => analysis ? filterSheets(analysis.sheets, filters) : [],
    [analysis, filters]
  );
  const domains = useMemo(
    () => analysis ? Object.keys(analysis.summary.domainCounts).sort((left, right) => left.localeCompare(right, "pt-BR")) : [],
    [analysis]
  );

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file || pending) return;
    setPending(true);
    setError(null);
    setAnalysis(null);
    setFilters(EMPTY_FILTERS);
    try {
      const formData = new FormData();
      formData.set("workbook", file);
      formData.set("modifiedAt", new Date(file.lastModified).toISOString());
      const result = await analyzeHistoricalWorkbookAction(formData);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      setAnalysis(result.analysis);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Não foi possível concluir a análise local.");
    } finally {
      setPending(false);
    }
  }

  return (
    <section className="workspace workbook-workspace">
      <div className="dashboard-header workbook-heading">
        <div>
          <span className="eyebrow">I1 · análise integral</span>
          <h1>Conferência do Excel histórico</h1>
          <p className="muted">Inventário estrutural do Tio Lu System antes de qualquer carga de dados.</p>
        </div>
        {analysis ? (
          <button className="secondary-button" type="button" onClick={() => downloadCsvReport(analysis)}>
            Baixar relatório CSV
          </button>
        ) : null}
      </div>

      <section className="workbook-readonly-notice" role="note" aria-label="Garantia de somente leitura">
        <strong>{READ_ONLY_NOTICE}</strong>
        <span>O arquivo é processado neste computador e o temporário é eliminado ao final.</span>
      </section>

      <form className="workbook-picker" onSubmit={submit}>
        <div className="workbook-picker-main">
          <label htmlFor="historical-workbook">Workbook .xlsx</label>
          <input
            ref={inputRef}
            id="historical-workbook"
            name="workbook"
            type="file"
            accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            onChange={(event) => {
              const nextFile = event.currentTarget.files?.[0] ?? null;
              setFile(nextFile);
              setAnalysis(null);
              setError(null);
            }}
          />
          <span>{file ? `${file.name} · ${formatBytes(file.size)} · ${formatDate(file.lastModified)}` : "Nenhum arquivo selecionado"}</span>
        </div>
        <button className="primary-button" type="submit" disabled={!file || pending}>
          {pending ? "Analisando workbook..." : "Analisar arquivo"}
        </button>
      </form>

      {pending ? (
        <section className="workbook-processing" role="status" aria-live="polite">
          <span className="workbook-spinner" aria-hidden="true" />
          <div>
            <strong>Leitura estrutural em andamento</strong>
            <span>Abas, tabelas, colunas, fórmulas e alertas estão sendo contados.</span>
          </div>
        </section>
      ) : null}

      {error ? <section className="notice-panel warning" role="alert"><strong>Análise não concluída</strong><span>{error}</span></section> : null}

      {analysis ? (
        <>
          <FileIdentity analysis={analysis} />
          <AnalysisSummary analysis={analysis} />
          <WorkbookHomologationWorkspace key={analysis.file.sha256} analysis={analysis} />
          <AnalysisFilters
            analysis={analysis}
            domains={domains}
            filters={filters}
            onChange={setFilters}
          />
          <section className="workbook-results" aria-labelledby="workbook-results-title">
            <div className="section-heading">
              <div>
                <span className="eyebrow">inventário detalhado</span>
                <h2 id="workbook-results-title">Abas e tabelas analisadas</h2>
              </div>
              <p>{filteredSheets.length} de {analysis.sheets.length} abas visíveis com os filtros atuais.</p>
            </div>
            <div className="workbook-sheet-list">
              {filteredSheets.map((sheet) => <SheetResult key={`${sheet.order}-${sheet.name}`} sheet={sheet} />)}
              {filteredSheets.length === 0 ? (
                <div className="empty-state"><strong>Nenhuma referência encontrada</strong><span>Altere os filtros para ampliar a consulta.</span></div>
              ) : null}
            </div>
          </section>
        </>
      ) : null}
    </section>
  );
}

function FileIdentity({ analysis }: { analysis: HistoricalWorkbookAnalysis }) {
  return (
    <section className="workbook-file-identity" aria-label="Identidade do arquivo analisado">
      <div><span>Arquivo</span><strong>{analysis.file.name}</strong></div>
      <div><span>Tamanho</span><strong>{formatBytes(analysis.file.sizeBytes)}</strong></div>
      <div><span>Modificado em</span><strong>{formatIsoDate(analysis.file.modifiedAt)}</strong></div>
      <div className="workbook-hash"><span>SHA256</span><code>{analysis.file.sha256}</code></div>
    </section>
  );
}

function AnalysisSummary({ analysis }: { analysis: HistoricalWorkbookAnalysis }) {
  const { summary } = analysis;
  const metrics: Array<{ label: string; value: number; tone: string }> = [
    { label: "Abas", value: summary.sheetCount, tone: "neutral" },
    { label: "Tabelas", value: summary.tableCount, tone: "neutral" },
    { label: "Linhas em tabelas", value: summary.tableRowCount, tone: "neutral" },
    { label: "Referências classificadas", value: summary.referenceCount, tone: "neutral" },
    { label: "Tabelas classificadas", value: summary.classifiedTableCount, tone: "defined" },
    { label: "Drift estrutural", value: summary.schemaDriftTableCount, tone: summary.schemaDriftTableCount ? "rejected" : "defined" },
    { label: "Destino definido", value: summary.statusCounts.defined, tone: "defined" },
    { label: "Transformação", value: summary.statusCounts.transform, tone: "transform" },
    { label: "Pendentes", value: summary.statusCounts.pending, tone: "pending" },
    { label: "Rejeitados", value: summary.statusCounts.rejected, tone: "rejected" },
    { label: "Fora da carga", value: summary.statusCounts.out_of_scope, tone: "out_of_scope" }
  ];
  return (
    <>
      <section className={`workbook-profile ${summary.profileMatchesReference ? "matched" : "different"}`} role="status">
        <strong>{summary.profileMatchesReference ? "Workbook de referência confirmado" : "Estrutura diferente do inventário aprovado"}</strong>
        <span>{summary.sheetCount} abas · {summary.tableCount} tabelas · {formatNumber(summary.referenceCount)} referências</span>
      </section>
      <section className="workbook-metrics" aria-label="Resumo da análise">
        {metrics.map((metric) => (
          <article className={`workbook-metric ${metric.tone}`} key={metric.label}>
            <span>{metric.label}</span>
            <strong>{formatNumber(metric.value)}</strong>
          </article>
        ))}
      </section>
    </>
  );
}

function AnalysisFilters({
  analysis,
  domains,
  filters,
  onChange
}: {
  analysis: HistoricalWorkbookAnalysis;
  domains: string[];
  filters: Filters;
  onChange: (filters: Filters) => void;
}) {
  return (
    <section className="workbook-filters" aria-label="Filtros da análise">
      <label>Texto<input value={filters.text} onChange={(event) => onChange({ ...filters, text: event.target.value })} placeholder="Aba, tabela, coluna ou destino" /></label>
      <label>Aba<select value={filters.sheet} onChange={(event) => onChange({ ...filters, sheet: event.target.value })}><option value="">Todas</option>{analysis.sheets.map((sheet) => <option value={sheet.name} key={`${sheet.order}-${sheet.name}`}>{sheet.order}. {sheet.name}</option>)}</select></label>
      <label>Domínio<select value={filters.domain} onChange={(event) => onChange({ ...filters, domain: event.target.value })}><option value="">Todos</option>{domains.map((domain) => <option value={domain} key={domain}>{domainLabel(domain)}</option>)}</select></label>
      <label>Status<select value={filters.status} onChange={(event) => onChange({ ...filters, status: event.target.value })}><option value="">Todos</option>{Object.entries(STATUS_LABELS).map(([status, label]) => <option value={status} key={status}>{label}</option>)}</select></label>
      <button className="secondary-button" type="button" onClick={() => onChange(EMPTY_FILTERS)}>Limpar filtros</button>
    </section>
  );
}

function SheetResult({ sheet }: { sheet: WorkbookSheetAnalysis }) {
  const [open, setOpen] = useState(false);
  const referenceCount = sheet.tables.reduce((total, table) => total + table.mappings.length, 0) + sheet.outsideColumns.length;
  return (
    <details className="workbook-sheet" onToggle={(event) => setOpen(detailsOpen(event))}>
      <summary>
        <span className="workbook-sheet-order">{sheet.order}</span>
        <span><strong>{sheet.name}</strong><small>{sheet.tables.length} tabela(s) · {referenceCount} referência(s) · intervalo {sheet.dimension}</small></span>
        <span className="workbook-sheet-state">{sheet.state === "visible" ? "visível" : sheet.state}</span>
      </summary>
      {open ? <div className="workbook-sheet-body">
        <div className="workbook-sheet-stats">
          <span>{formatNumber(sheet.nonemptyRows)} linhas usadas</span>
          <span>{formatNumber(sheet.nonemptyCells)} células preenchidas</span>
          <span>{formatNumber(sheet.formulaCells)} fórmulas</span>
          <span>{formatNumber(sheet.errorCells)} erros Excel</span>
        </div>
        {sheet.warnings.map((warning) => <p className="workbook-warning" key={warning}>{warning}</p>)}
        {sheet.tables.map((table) => <TableResult key={`${sheet.order}-${table.name}-${table.ref}`} table={table} />)}
        {sheet.outsideColumns.length > 0 ? (
          <TableResult
            table={{
              name: "Conteúdo fora de tabelas estruturadas",
              ref: sheet.dimension,
              rowCount: sheet.nonemptyRows,
              populatedRowCount: sheet.nonemptyRows,
              columnCount: sheet.outsideColumns.length,
              formulaCellCount: sheet.formulaCells,
              calculatedValueCount: sheet.formulaCells,
              headers: sheet.outsideColumns.map((item) => item.excelColumn),
              warnings: ["Estas colunas serão preservadas somente na camada bruta auditável."],
              mappings: sheet.outsideColumns
            }}
          />
        ) : null}
      </div> : null}
    </details>
  );
}

function TableResult({ table }: { table: WorkbookTableAnalysis }) {
  const [open, setOpen] = useState(false);
  const classification = table.sourceClassification?.classification;
  const classificationLabel = classification ? SOURCE_CLASSIFICATION_LABELS[classification] : "Metadado de planilha";
  return (
    <details className="workbook-table" onToggle={(event) => setOpen(detailsOpen(event))}>
      <summary>
        <span><strong>{table.name}</strong><small>{classificationLabel} · {table.ref} · {formatNumber(table.rowCount)} linhas · {table.columnCount} colunas</small></span>
        <span>{formatNumber(table.populatedRowCount)} linhas preenchidas</span>
      </summary>
      {open ? <div className="workbook-table-body">
        {table.warnings.map((warning) => <p className="workbook-warning" key={warning}>{warning}</p>)}
        <div className="workbook-headers" aria-label="Cabeçalhos da tabela">
          {table.headers.map((header, index) => <span key={`${index}-${header}`}>{header}</span>)}
        </div>
        <div className="table-scroll">
          <table className="data-table workbook-mapping-table">
            <thead><tr><th>Coluna Excel</th><th>Domínio</th><th>Status</th><th>Destino previsto</th><th>Regra e alerta</th></tr></thead>
            <tbody>{table.mappings.map((mapping, index) => <MappingRow key={`${mapping.sourceKind}-${mapping.excelColumn}-${index}`} mapping={mapping} />)}</tbody>
          </table>
        </div>
      </div> : null}
    </details>
  );
}

function MappingRow({ mapping }: { mapping: WorkbookReference }) {
  return (
    <tr>
      <td><strong>{mapping.excelColumn}</strong><span className="table-subtext">{mapping.sourceKind === "worksheet_outside_table" ? "fora de tabela" : `posição ${mapping.columnPosition}`}</span></td>
      <td>{domainLabel(mapping.domain)}</td>
      <td><span className={`mapping-status ${mapping.status}`}>{STATUS_LABELS[mapping.status]}</span></td>
      <td><code>{mapping.target}</code></td>
      <td>{mapping.rule}{mapping.warning ? <span className="table-subtext warning-text">{mapping.warning}</span> : null}</td>
    </tr>
  );
}

function filterSheets(sheets: WorkbookSheetAnalysis[], filters: Filters): WorkbookSheetAnalysis[] {
  const query = filters.text.trim().toLocaleLowerCase("pt-BR");
  return sheets.flatMap((sheet) => {
    if (filters.sheet && sheet.name !== filters.sheet) return [];
    const sheetMatchesText = !query || sheet.name.toLocaleLowerCase("pt-BR").includes(query);
    const tables = sheet.tables.flatMap((table) => {
      const tableMatchesText = sheetMatchesText || table.name.toLocaleLowerCase("pt-BR").includes(query);
      const mappings = table.mappings.filter((mapping) => referenceMatches(mapping, filters, query, tableMatchesText));
      return mappings.length > 0 ? [{ ...table, mappings, headers: mappings.map((mapping) => mapping.excelColumn), columnCount: mappings.length }] : [];
    });
    const outsideColumns = sheet.outsideColumns.filter((mapping) => referenceMatches(mapping, filters, query, sheetMatchesText));
    return tables.length > 0 || outsideColumns.length > 0 ? [{ ...sheet, tables, outsideColumns }] : [];
  });
}

function referenceMatches(mapping: WorkbookReference, filters: Filters, query: string, parentMatchesText: boolean): boolean {
  if (filters.domain && mapping.domain !== filters.domain) return false;
  if (filters.status && mapping.status !== filters.status) return false;
  if (!query || parentMatchesText) return true;
  return [mapping.excelColumn, mapping.target, mapping.rule, mapping.warning ?? ""]
    .some((value) => value.toLocaleLowerCase("pt-BR").includes(query));
}

function downloadCsvReport(analysis: HistoricalWorkbookAnalysis) {
  const headers = ["ordem_aba", "tipo_origem", "aba", "tabela", "intervalo", "source_table_id", "vinculo_fonte", "classificacao_fonte", "posicao", "coluna_excel", "codigo", "status", "dominio", "destino", "regra", "alerta"];
  const rows = analysis.reportRows.map((row) => [row.sheetOrder, row.sourceKind, row.sheet, row.table, row.ref, row.sourceTableId, row.sourceBindingKind, row.sourceClassification ?? "worksheet_metadata", row.columnPosition ?? "", row.excelColumn, row.sourceCode, row.status, row.domain, row.target, row.rule, row.warning ?? ""]);
  const csv = `\uFEFF${[headers, ...rows].map((row) => row.map(csvCell).join(";")).join("\r\n")}`;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `analise-workbook-${analysis.file.sha256.slice(0, 12)}.csv`;
  anchor.click();
  URL.revokeObjectURL(url);
}

function csvCell(value: string | number): string {
  let text = String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function domainLabel(domain: string): string {
  return ({ auditoria: "Auditoria", cadastros: "Cadastros", comercial: "Comercial", estoque: "Estoque", faturamento: "Faturamento", financeiro: "Financeiro", logistica: "Logística", pcp: "PCP / Produção", pedidos: "Pedidos" } as Record<string, string>)[domain] ?? domain;
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

function formatBytes(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value / 1024 / 1024) + " MB";
}

function formatDate(value: number): string {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

function formatIsoDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "não informado" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(date);
}

function detailsOpen(event: SyntheticEvent<HTMLDetailsElement>): boolean {
  return event.currentTarget.open;
}
