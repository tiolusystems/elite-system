import Link from "next/link";
import type { ReactNode } from "react";

import styles from "./search-controls.module.css";

export function FilterToolbar({ children, action, className = "" }: { children: ReactNode; action?: string; className?: string }) {
  return <form className={`${styles.toolbar} ${className}`.trim()} action={action} method="get" role="search">{children}</form>;
}

export const SearchToolbar = FilterToolbar;

export function SearchField({ name, label, defaultValue, placeholder, wide = false }: { name: string; label: string; defaultValue?: string; placeholder: string; wide?: boolean }) {
  return <label className={wide ? styles.wide : undefined}><span>{label}</span><input type="search" name={name} defaultValue={defaultValue} placeholder={placeholder} /></label>;
}

export function FilterActions({ clearHref, submitLabel = "Pesquisar" }: { clearHref: string; submitLabel?: string }) {
  return <div className={styles.actions}><button className="secondary-button" type="submit">{submitLabel}</button><Link href={clearHref}>Limpar filtros</Link></div>;
}

export function AdvancedFilterPanel({ children, open = false, activeCount = 0 }: { children: ReactNode; open?: boolean; activeCount?: number }) {
  return <details className={styles.advancedPanel} open={open}>
    <summary className={styles.advancedSummary}>
      <span>Mais filtros</span>
      {activeCount > 0 ? <small>{activeCount} ativo(s)</small> : <small>Opcional</small>}
    </summary>
    <div className={styles.advancedGrid}>{children}</div>
  </details>;
}

export function ActiveFilterChips({ filters, clearHref }: { filters: Array<{ label: string; value: string; href: string }>; clearHref: string }) {
  if (!filters.length) return null;
  return <div className={styles.chips} aria-label="Filtros ativos"><span>Filtros ativos:</span>{filters.map((filter) => <Link key={`${filter.label}-${filter.value}`} href={filter.href} aria-label={`Remover filtro ${filter.label}: ${filter.value}`}><strong>{filter.label}:</strong> {filter.value} ×</Link>)}<Link className={styles.clearAll} href={clearHref}>Limpar todos</Link></div>;
}

export function PaginatedResultList({ page, total, pageSize, previousHref, nextHref }: { page: number; total: number; pageSize: number; previousHref?: string | null; nextHref?: string | null }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return <nav className={styles.pagination} aria-label="Paginação dos resultados"><span>Página {page} de {pages} · {total} registro(s)</span><div>{previousHref ? <Link className="secondary-button" href={previousHref}>Anterior</Link> : <span />}{nextHref ? <Link className="secondary-button" href={nextHref}>Próxima</Link> : <span />}</div></nav>;
}
