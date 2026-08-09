"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";

import type {
  CorporateLookupEntity,
  CorporateLookupPage
} from "@/lib/corporate-lookups";

import styles from "./search-controls.module.css";

export type SmartLookupOption = {
  id: number;
  label: string;
  detail?: string | null;
  status?: string | null;
  disabled?: boolean;
};

export type SmartLookupSource =
  | {
      kind: "local";
      options: SmartLookupOption[];
      maxVisible?: number;
    }
  | {
      kind: "remote";
      entity: CorporateLookupEntity;
      contextId?: number | null;
    };

type SmartLookupBaseProps = {
  label: string;
  placeholder: string;
  source: SmartLookupSource;
  disabled?: boolean;
  helpText?: string;
  className?: string;
  emptyText?: string;
};

type SmartSelectionLookupProps = SmartLookupBaseProps & {
  mode?: "selection";
  name?: string;
  value?: number | null;
  defaultValue?: number | null;
  defaultLabel?: string;
  labelName?: string;
  onValueChange?: (value: number | null) => void;
  required?: boolean;
};

type SmartSearchLookupProps = SmartLookupBaseProps & {
  mode: "search";
  name: string;
  defaultQuery?: string;
  onQueryChange?: (value: string) => void;
  onOptionSelect?: (option: SmartLookupOption) => void;
  required?: boolean;
  minQueryLength?: number;
  submitOnSelect?: boolean;
};

export type SmartLookupProps = SmartSelectionLookupProps | SmartSearchLookupProps;

export type SmartSearchFieldProps = {
  name: string;
  label: string;
  placeholder: string;
  source: SmartLookupSource;
  defaultValue?: string;
  onQueryChange?: (value: string) => void;
  onOptionSelect?: (option: SmartLookupOption) => void;
  required?: boolean;
  disabled?: boolean;
  helpText?: string;
  className?: string;
  emptyText?: string;
  minQueryLength?: number;
  submitOnSelect?: boolean;
};

const DEFAULT_LOCAL_LIMIT = 50;

export function SmartSearchField({
  name,
  label,
  placeholder,
  source,
  defaultValue = "",
  onQueryChange,
  onOptionSelect,
  required = false,
  disabled = false,
  helpText,
  className = "",
  emptyText,
  minQueryLength = 0,
  submitOnSelect = false
}: SmartSearchFieldProps) {
  return (
    <SmartLookup
      mode="search"
      name={name}
      label={label}
      placeholder={placeholder}
      source={source}
      defaultQuery={defaultValue}
      onQueryChange={onQueryChange}
      onOptionSelect={onOptionSelect}
      required={required}
      disabled={disabled}
      helpText={helpText}
      className={className}
      emptyText={emptyText}
      minQueryLength={minQueryLength}
      submitOnSelect={submitOnSelect}
    />
  );
}

export function SmartLookup(props: SmartLookupProps) {
  const {
    label,
    placeholder,
    source,
    disabled = false,
    helpText,
    className = "",
    emptyText = "Nenhum registro encontrado",
    required = false
  } = props;
  const selectionProps = props.mode === "search" ? null : props;
  const searchProps = props.mode === "search" ? props : null;
  const mode = searchProps ? "search" : "selection";

  const generatedId = useId().replaceAll(":", "");
  const inputName = props.name ?? "lookup";
  const inputId = `${inputName}-${generatedId}`;
  const listboxId = `${inputId}-resultados`;
  const inputRef = useRef<HTMLInputElement>(null);
  const requestRef = useRef<AbortController | null>(null);

  const controlled = selectionProps?.value !== undefined;
  const defaultSelection = selectionProps?.defaultValue ?? null;
  const [internalValue, setInternalValue] = useState<number | null>(defaultSelection);
  const selectedId = selectionProps
    ? controlled
      ? selectionProps.value ?? null
      : internalValue
    : null;

  const initialLocalLabel = source.kind === "local" && selectedId !== null
    ? source.options.find((option) => option.id === selectedId)?.label ?? ""
    : "";
  const initialQuery = searchProps
    ? searchProps.defaultQuery ?? ""
    : selectionProps?.defaultLabel ?? initialLocalLabel;

  const [query, setQuery] = useState(initialQuery);
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);
  const [page, setPage] = useState(1);
  const [remoteResult, setRemoteResult] = useState<CorporateLookupPage | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryToken, setRetryToken] = useState(0);

  const remoteEntity = source.kind === "remote" ? source.entity : null;
  const remoteContextId = source.kind === "remote" ? source.contextId ?? null : null;
  const localLimit = source.kind === "local" ? source.maxVisible ?? DEFAULT_LOCAL_LIMIT : DEFAULT_LOCAL_LIMIT;
  const minQueryLength = searchProps?.minQueryLength ?? 0;

  const selectedLocalOption = source.kind === "local" && selectedId !== null
    ? source.options.find((option) => option.id === selectedId) ?? null
    : null;

  const filteredLocalOptions = useMemo(() => {
    if (source.kind !== "local") return [];
    if (mode === "selection" && selectedId !== null) return source.options;
    const normalizedQuery = normalize(query);
    if (!normalizedQuery) return source.options;
    return source.options.filter((option) =>
      normalize(`${option.label} ${option.detail ?? ""}`).includes(normalizedQuery)
    );
  }, [mode, query, selectedId, source]);

  const localVisibleOptions = filteredLocalOptions.slice(0, localLimit);
  const remoteOptions: SmartLookupOption[] = remoteResult?.options ?? [];
  const options = source.kind === "local" ? localVisibleOptions : remoteOptions;
  const total = source.kind === "local" ? filteredLocalOptions.length : remoteResult?.total ?? 0;

  useEffect(() => {
    if (!remoteEntity || !open || disabled) return;
    if (mode === "search" && query.trim().length < minQueryLength) return;

    const timer = window.setTimeout(async () => {
      requestRef.current?.abort();
      const controller = new AbortController();
      requestRef.current = controller;
      setLoading(true);
      setError(null);

      const parameters = new URLSearchParams({
        q: mode === "selection" && selectedId ? "" : query,
        pagina: String(page)
      });
      if (remoteContextId) parameters.set("contexto", String(remoteContextId));

      try {
        const response = await fetch(`/api/lookups/${remoteEntity}?${parameters}`, {
          signal: controller.signal,
          cache: "no-store"
        });
        const payload = await response.json() as CorporateLookupPage | { message?: string };
        if (!response.ok || !("options" in payload)) {
          throw new Error("message" in payload ? payload.message : "Não foi possível consultar.");
        }
        setRemoteResult(payload);
        setActiveIndex(firstEnabledIndex(payload.options, 0, 1));
      } catch (cause) {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : "Não foi possível consultar.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }, mode === "selection" && selectedId ? 0 : 250);

    return () => {
      window.clearTimeout(timer);
      requestRef.current?.abort();
    };
  }, [disabled, minQueryLength, mode, open, page, query, remoteContextId, remoteEntity, retryToken, selectedId]);

  function setSelection(next: number | null) {
    if (!selectionProps) return;
    if (!controlled) setInternalValue(next);
    selectionProps.onValueChange?.(next);
  }

  function setSearchQuery(next: string) {
    setQuery(next);
    searchProps?.onQueryChange?.(next);
  }

  function choose(option: SmartLookupOption) {
    if (option.disabled) return;
    if (selectionProps) setSelection(option.id);
    setSearchQuery(option.label);
    setPage(1);
    setOpen(false);
    setActiveIndex(-1);
    setError(null);
    inputRef.current?.setCustomValidity("");
    searchProps?.onOptionSelect?.(option);

    if (searchProps?.submitOnSelect) {
      window.requestAnimationFrame(() => inputRef.current?.form?.requestSubmit());
    }
  }

  function clear() {
    if (selectionProps) setSelection(null);
    setSearchQuery("");
    setPage(1);
    setOpen(false);
    setActiveIndex(-1);
    inputRef.current?.setCustomValidity(required ? requiredMessage(mode) : "");
    inputRef.current?.focus();
  }

  function openLookup() {
    if (mode === "search" && query.trim().length < minQueryLength) {
      setOpen(false);
      setActiveIndex(-1);
      return;
    }

    setOpen(true);
    if (source.kind === "local") {
      setActiveIndex(firstEnabledIndex(localVisibleOptions, 0, 1));
    } else {
      setActiveIndex(-1);
    }
  }

  function moveActive(step: 1 | -1) {
    const start = activeIndex < 0
      ? step === 1 ? 0 : options.length - 1
      : activeIndex + step;
    const next = firstEnabledIndex(options, start, step);
    if (next >= 0) setActiveIndex(next);
  }

  const displayedQuery = selectionProps && selectedId !== null && source.kind === "local"
    ? selectedLocalOption?.label ?? query
    : query;
  const hasValue = Boolean(displayedQuery) || (selectionProps ? selectedId !== null : false);

  return (
    <div
      className={`${styles.lookup} ${className}`.trim()}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
    >
      <label className={styles.label} htmlFor={inputId}>{label}</label>

      {selectionProps?.name ? (
        <input type="hidden" name={selectionProps.name} value={selectedId ?? ""} />
      ) : null}
      {selectionProps?.labelName ? (
        <input type="hidden" name={selectionProps.labelName} value={selectedId ? displayedQuery : ""} />
      ) : null}

      <div className={`${styles.lookupControl} ${mode === "selection" ? styles.selectionControl : ""}`.trim()}>
        {mode === "search" ? <span className={styles.searchIcon} aria-hidden="true">⌕</span> : null}
        <input
          ref={inputRef}
          id={inputId}
          name={searchProps?.name}
          type="search"
          role="combobox"
          aria-autocomplete="list"
          aria-controls={listboxId}
          aria-expanded={open}
          aria-activedescendant={open && activeIndex >= 0 ? `${listboxId}-${activeIndex}` : undefined}
          autoComplete="off"
          disabled={disabled}
          required={required}
          value={displayedQuery}
          placeholder={placeholder}
          onFocus={openLookup}
          onClick={openLookup}
          onChange={(event) => {
            const next = event.target.value;
            setSearchQuery(next);
            if (selectionProps) setSelection(null);
            setPage(1);
            setOpen(mode === "selection" || next.trim().length >= minQueryLength);
            if (mode === "search" && next.trim().length < minQueryLength) {
              setRemoteResult(null);
            }
            setActiveIndex(-1);
            event.currentTarget.setCustomValidity(
              selectionProps && next.trim()
                ? "Escolha um registro da lista."
                : required && !next.trim()
                  ? requiredMessage(mode)
                  : ""
            );
          }}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              openLookup();
              moveActive(1);
            }
            if (event.key === "ArrowUp") {
              event.preventDefault();
              openLookup();
              moveActive(-1);
            }
            if (event.key === "Enter" && open && activeIndex >= 0 && options[activeIndex]) {
              event.preventDefault();
              choose(options[activeIndex]);
            }
            if (event.key === "Escape") setOpen(false);
          }}
        />

        {mode === "selection" ? (
          <button
            className={styles.iconButton}
            type="button"
            onClick={() => {
              if (open) {
                setOpen(false);
                setActiveIndex(-1);
                return;
              }
              openLookup();
              window.requestAnimationFrame(() => inputRef.current?.focus());
            }}
            aria-label={`Abrir lista de ${label.toLocaleLowerCase("pt-BR")}`}
            aria-expanded={open}
            aria-controls={listboxId}
            disabled={disabled}
          >
            ▾
          </button>
        ) : null}

        {hasValue ? (
          <button
            className={styles.iconButton}
            type="button"
            onClick={clear}
            aria-label={`Limpar ${label.toLocaleLowerCase("pt-BR")}`}
            disabled={disabled}
          >
            ×
          </button>
        ) : null}
      </div>

      {helpText ? <small className={styles.help}>{helpText}</small> : null}

      {open && (mode === "selection" || query.trim().length >= minQueryLength) ? (
        <div
          className={styles.lookupPanel}
          id={listboxId}
          role="listbox"
          aria-label={`Resultados de ${label.toLocaleLowerCase("pt-BR")}`}
        >
          <div className={styles.lookupStatus} role="status" aria-live="polite">
            {source.kind === "remote" && loading
              ? "Carregando resultados…"
              : error
                ? "Não foi possível consultar."
                : total === 0
                  ? emptyText
                  : source.kind === "local" && total > localLimit
                    ? `${localLimit} de ${total} registro(s). Digite para refinar.`
                    : `${total} registro(s) disponível(is)`}
          </div>

          {error ? (
            <div className={styles.lookupMessage}>
              <span>{error}</span>
              <button type="button" onClick={() => setRetryToken((current) => current + 1)}>
                Tentar novamente
              </button>
            </div>
          ) : null}

          {!loading && !error ? options.map((option, index) => (
            <button
              id={`${listboxId}-${index}`}
              className={styles.lookupOption}
              key={option.id}
              type="button"
              role="option"
              aria-selected={selectionProps ? selectedId === option.id : false}
              aria-disabled={option.disabled || undefined}
              disabled={option.disabled}
              data-active={activeIndex === index ? "true" : "false"}
              onMouseDown={(event) => event.preventDefault()}
              onMouseEnter={() => { if (!option.disabled) setActiveIndex(index); }}
              onClick={() => choose(option)}
            >
              <span>
                <strong>{option.label}</strong>
                {option.detail ? <small>{option.detail}</small> : null}
              </span>
              {option.status ? <small>{statusLabel(option.status)}</small> : null}
            </button>
          )) : null}

          {source.kind === "remote" && !loading && !error && remoteResult && (page > 1 || remoteResult.hasMore) ? (
            <div className={styles.lookupPagination}>
              <button
                type="button"
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                disabled={page <= 1}
              >
                Anterior
              </button>
              <span>Página {page} de {Math.max(1, Math.ceil(remoteResult.total / remoteResult.pageSize))}</span>
              <button
                type="button"
                onClick={() => setPage((current) => current + 1)}
                disabled={!remoteResult.hasMore}
              >
                Próxima
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

function firstEnabledIndex(options: SmartLookupOption[], start: number, step: 1 | -1): number {
  let index = start;
  while (index >= 0 && index < options.length) {
    const option = options[index];
    if (option && !option.disabled) return index;
    index += step;
  }
  return -1;
}

function requiredMessage(mode: "selection" | "search"): string {
  return mode === "selection" ? "Selecione um registro." : "Informe um termo de pesquisa.";
}

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-BR")
    .trim();
}

function statusLabel(value: string): string {
  return ({
    active: "Ativo",
    inactive: "Inativo",
    pending_review: "Em revisão",
    draft: "Rascunho",
    open: "Aberto",
    blocked: "Bloqueado",
    cancelled: "Cancelado",
    fulfilled: "Concluído",
    disponivel: "Disponível",
    bloqueado: "Bloqueado",
    esgotado: "Esgotado",
    planned: "Planejada",
    in_process: "Em processo",
    completed: "Finalizada",
    emitida: "Emitida",
    em_separacao: "Em separação",
    em_envase: "Em envase",
    finalizada: "Finalizada"
  } as Record<string, string>)[value] ?? value;
}