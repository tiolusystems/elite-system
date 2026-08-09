import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";

import styles from "./operational-table.module.css";

export function OperationalPageShell({
  counters,
  filters,
  children
}: {
  counters?: ReactNode;
  filters?: ReactNode;
  children: ReactNode;
}) {
  return <div className={styles.page}>{counters}{filters}{children}</div>;
}

export function FilterToolbar({ children }: { children: ReactNode }) {
  return <form className={styles.filters} method="get">{children}</form>;
}

export function FilterActions({ clearHref, submitLabel = "Filtrar" }: { clearHref: string; submitLabel?: string }) {
  return <div className={styles.filterActions}>
    <Link className="secondary-button" href={clearHref}>Limpar</Link>
    <button className="primary-button" type="submit">{submitLabel}</button>
  </div>;
}

export type DataTableColumn<Row> = {
  key: string;
  label: string;
  width: string;
  align?: "start" | "end";
  render: (row: Row) => ReactNode;
};

export function DataTable<Row>({
  caption,
  columns,
  rows,
  rowKey
}: {
  caption: string;
  columns: Array<DataTableColumn<Row>>;
  rows: Row[];
  rowKey: (row: Row) => string | number;
}) {
  return <div className={styles.tableFrame}>
    <table className={styles.table}>
      <caption className="sr-only">{caption}</caption>
      <colgroup>{columns.map((column) => <col key={column.key} style={{ "--column-width": column.width } as CSSProperties} />)}</colgroup>
      <thead><tr>{columns.map((column) => <th key={column.key} scope="col" data-align={column.align ?? "start"}>{column.label}</th>)}</tr></thead>
      <tbody>{rows.map((row) => <tr key={rowKey(row)}>{columns.map((column) => <td key={column.key} data-label={column.label} data-align={column.align ?? "start"}>{column.render(row)}</td>)}</tr>)}</tbody>
    </table>
  </div>;
}

export function PrimarySecondaryCell({ primary, secondary }: { primary: ReactNode; secondary?: ReactNode }) {
  return <span className={styles.primarySecondary}><strong>{primary}</strong>{secondary ? <small>{secondary}</small> : null}</span>;
}

export function StatusBadge({ status, children }: { status: string; children: ReactNode }) {
  return <span className={styles.status} data-status={status}>{children}</span>;
}

export function PaginationBar({
  page,
  pageCount,
  total,
  previousHref,
  nextHref
}: {
  page: number;
  pageCount: number;
  total: number;
  previousHref: string | null;
  nextHref: string | null;
}) {
  return <nav className={styles.pagination} aria-label="Paginação dos resultados">
    <span>{previousHref ? <Link className="secondary-button compact" href={previousHref}>Anterior</Link> : <span className={styles.disabledAction} aria-disabled="true">Anterior</span>}</span>
    <span className={styles.pageSummary}>Página {page} de {pageCount}<small>{total} resultado(s)</small></span>
    <span>{nextHref ? <Link className="secondary-button compact" href={nextHref}>Próxima</Link> : <span className={styles.disabledAction} aria-disabled="true">Próxima</span>}</span>
  </nav>;
}
