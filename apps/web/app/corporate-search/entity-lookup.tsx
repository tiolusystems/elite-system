"use client";

import { useEffect, useId, useRef, useState } from "react";

import type { CorporateLookupEntity, CorporateLookupOption, CorporateLookupPage } from "@/lib/corporate-lookups";

import styles from "./search-controls.module.css";

type EntityLookupProps = {
  entity: CorporateLookupEntity;
  name: string;
  label: string;
  placeholder: string;
  defaultValue?: number | null;
  defaultLabel?: string;
  labelName?: string;
  contextId?: number | null;
  required?: boolean;
  disabled?: boolean;
  helpText?: string;
};

export function EntityLookup({
  entity,
  name,
  label,
  placeholder,
  defaultValue = null,
  defaultLabel = "",
  labelName,
  contextId = null,
  required = false,
  disabled = false,
  helpText
}: EntityLookupProps) {
  const generatedId = useId().replaceAll(":", "");
  const inputId = `${name}-${generatedId}`;
  const listboxId = `${inputId}-resultados`;
  const inputRef = useRef<HTMLInputElement>(null);
  const requestRef = useRef<AbortController | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(defaultValue);
  const [query, setQuery] = useState(defaultLabel);
  const [page, setPage] = useState(1);
  const [result, setResult] = useState<CorporateLookupPage | null>(null);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeIndex, setActiveIndex] = useState(-1);
  const [retryToken, setRetryToken] = useState(0);

  useEffect(() => {
    if (!open || disabled) return;
    const timer = window.setTimeout(async () => {
      requestRef.current?.abort();
      const controller = new AbortController();
      requestRef.current = controller;
      setLoading(true);
      setError(null);
      const parameters = new URLSearchParams({ q: selectedId ? "" : query, pagina: String(page) });
      if (contextId) parameters.set("contexto", String(contextId));
      try {
        const response = await fetch(`/api/lookups/${entity}?${parameters}`, { signal: controller.signal, cache: "no-store" });
        const payload = await response.json() as CorporateLookupPage | { message?: string };
        if (!response.ok || !("options" in payload)) throw new Error("message" in payload ? payload.message : "Não foi possível consultar.");
        setResult(payload);
        setActiveIndex(payload.options.length ? 0 : -1);
      } catch (cause) {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : "Não foi possível consultar.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }, selectedId ? 0 : 250);
    return () => window.clearTimeout(timer);
  }, [contextId, disabled, entity, open, page, query, retryToken, selectedId]);

  function choose(option: CorporateLookupOption) {
    setSelectedId(option.id);
    setQuery(option.label);
    setOpen(false);
    setError(null);
    inputRef.current?.setCustomValidity("");
  }

  function clear() {
    setSelectedId(null);
    setQuery("");
    setPage(1);
    setOpen(false);
    inputRef.current?.setCustomValidity(required ? "Selecione uma opção válida." : "");
    inputRef.current?.focus();
  }

  const options = result?.options ?? [];
  return (
    <div className={styles.lookup} onBlur={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
    }}>
      <label className={styles.label} htmlFor={inputId}>{label}</label>
      <input type="hidden" name={name} value={selectedId ?? ""} />
      {labelName ? <input type="hidden" name={labelName} value={selectedId ? query : ""} /> : null}
      <div className={styles.lookupControl}>
        <input
          ref={inputRef}
          id={inputId}
          type="search"
          role="combobox"
          aria-autocomplete="list"
          aria-controls={listboxId}
          aria-expanded={open}
          aria-activedescendant={activeIndex >= 0 ? `${listboxId}-${activeIndex}` : undefined}
          autoComplete="off"
          disabled={disabled}
          required={required}
          value={query}
          placeholder={placeholder}
          onFocus={() => setOpen(true)}
          onChange={(event) => {
            setQuery(event.target.value);
            setSelectedId(null);
            setPage(1);
            setOpen(true);
            event.currentTarget.setCustomValidity(event.target.value.trim() ? "Escolha um registro da lista." : required ? "Selecione um registro." : "");
          }}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") { event.preventDefault(); setOpen(true); setActiveIndex((index) => Math.min(index + 1, options.length - 1)); }
            if (event.key === "ArrowUp") { event.preventDefault(); setActiveIndex((index) => Math.max(index - 1, 0)); }
            if (event.key === "Enter" && open && activeIndex >= 0 && options[activeIndex]) { event.preventDefault(); choose(options[activeIndex]); }
            if (event.key === "Escape") setOpen(false);
          }}
        />
        <button className={styles.iconButton} type="button" onClick={() => setOpen((current) => !current)} aria-label={`Consultar ${label.toLocaleLowerCase("pt-BR")}`} disabled={disabled}>⌕</button>
        {query || selectedId ? <button className={styles.iconButton} type="button" onClick={clear} aria-label={`Limpar ${label.toLocaleLowerCase("pt-BR")}`} disabled={disabled}>×</button> : null}
      </div>
      {helpText ? <small className={styles.help}>{helpText}</small> : null}
      {open ? <div className={styles.lookupPanel} id={listboxId} role="listbox" aria-label={`Resultados de ${label.toLocaleLowerCase("pt-BR")}`}>
        <div className={styles.lookupStatus} role="status" aria-live="polite">
          {loading ? "Carregando resultados…" : error ? "Não foi possível consultar." : result?.total ? `${result.total} registro(s) autorizado(s)` : "Nenhum registro encontrado"}
        </div>
        {error ? <div className={styles.lookupMessage}><span>{error}</span><button type="button" onClick={() => setRetryToken((current) => current + 1)}>Tentar novamente</button></div> : null}
        {!loading && !error ? options.map((option, index) => <button
          id={`${listboxId}-${index}`}
          className={styles.lookupOption}
          key={option.id}
          type="button"
          role="option"
          aria-selected={selectedId === option.id}
          data-active={activeIndex === index ? "true" : "false"}
          onMouseDown={(event) => event.preventDefault()}
          onMouseEnter={() => setActiveIndex(index)}
          onClick={() => choose(option)}
        >
          <span><strong>{option.label}</strong>{option.detail ? <small>{option.detail}</small> : null}</span>
          {option.status ? <small>{statusLabel(option.status)}</small> : null}
        </button>) : null}
        {!loading && !error && result ? <div className={styles.lookupPagination}>
          <button type="button" onClick={() => setPage((current) => Math.max(1, current - 1))} disabled={page <= 1}>Anterior</button>
          <span>Página {page} de {Math.max(1, Math.ceil(result.total / result.pageSize))}</span>
          <button type="button" onClick={() => setPage((current) => current + 1)} disabled={!result.hasMore}>Próxima</button>
        </div> : null}
      </div> : null}
    </div>
  );
}

function statusLabel(value: string): string {
  return ({ active: "Ativo", inactive: "Inativo", pending_review: "Em revisão", draft: "Rascunho", open: "Aberto", blocked: "Bloqueado", cancelled: "Cancelado", fulfilled: "Concluído", disponivel: "Disponível", bloqueado: "Bloqueado", esgotado: "Esgotado" } as Record<string, string>)[value] ?? "Situação não reconhecida";
}
