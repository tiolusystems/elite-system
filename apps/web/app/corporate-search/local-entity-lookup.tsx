"use client";

import { useId, useMemo, useRef, useState } from "react";

import styles from "./search-controls.module.css";

export type LocalLookupOption = {
  id: number;
  label: string;
  detail?: string | null;
  disabled?: boolean;
};

type LocalEntityLookupProps = {
  name?: string;
  label: string;
  placeholder: string;
  options: LocalLookupOption[];
  value?: number | null;
  defaultValue?: number | null;
  onValueChange?: (value: number | null) => void;
  required?: boolean;
  disabled?: boolean;
  helpText?: string;
  className?: string;
  emptyText?: string;
};

const MAX_VISIBLE_OPTIONS = 50;

export function LocalEntityLookup({
  name,
  label,
  placeholder,
  options,
  value,
  defaultValue = null,
  onValueChange,
  required = false,
  disabled = false,
  helpText,
  className = "",
  emptyText = "Nenhum registro encontrado"
}: LocalEntityLookupProps) {
  const generatedId = useId().replaceAll(":", "");
  const inputId = `${name ?? "lookup"}-${generatedId}`;
  const listboxId = `${inputId}-resultados`;
  const inputRef = useRef<HTMLInputElement>(null);
  const controlled = value !== undefined;
  const [internalValue, setInternalValue] = useState<number | null>(defaultValue);
  const selectedId = controlled ? value ?? null : internalValue;
  const [query, setQuery] = useState(() => options.find((option) => option.id === selectedId)?.label ?? "");
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);

  const selectedOption = selectedId === null
    ? null
    : options.find((candidate) => candidate.id === selectedId) ?? null;

  const filteredOptions = useMemo(() => {
    if (selectedId !== null) return options;
    const normalizedQuery = normalize(query);
    if (!normalizedQuery) return options;
    return options.filter((option) => normalize(`${option.label} ${option.detail ?? ""}`).includes(normalizedQuery));
  }, [options, query, selectedId]);
  const visibleOptions = filteredOptions.slice(0, MAX_VISIBLE_OPTIONS);

  function setSelection(next: number | null) {
    if (!controlled) setInternalValue(next);
    onValueChange?.(next);
  }

  function firstEnabledIndex(start: number, step: 1 | -1) {
    let index = start;
    while (index >= 0 && index < visibleOptions.length) {
      if (!visibleOptions[index]?.disabled) return index;
      index += step;
    }
    return -1;
  }

  function choose(option: LocalLookupOption) {
    if (option.disabled) return;
    setSelection(option.id);
    setQuery(option.label);
    setOpen(false);
    setActiveIndex(-1);
    inputRef.current?.setCustomValidity("");
  }

  function clear() {
    setSelection(null);
    setQuery("");
    setOpen(true);
    setActiveIndex(firstEnabledIndex(0, 1));
    inputRef.current?.setCustomValidity(required ? "Selecione uma opção válida." : "");
    inputRef.current?.focus();
  }

  return (
    <div
      className={`${styles.lookup} ${className}`.trim()}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
    >
      <label className={styles.label} htmlFor={inputId}>{label}</label>
      {name ? <input type="hidden" name={name} value={selectedId ?? ""} /> : null}
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
          value={selectedId !== null ? selectedOption?.label ?? "" : query}
          placeholder={placeholder}
          onFocus={() => {
            setOpen(true);
            setActiveIndex(firstEnabledIndex(0, 1));
          }}
          onChange={(event) => {
            setQuery(event.target.value);
            setSelection(null);
            setOpen(true);
            setActiveIndex(0);
            event.currentTarget.setCustomValidity(
              event.target.value.trim()
                ? "Escolha um registro da lista."
                : required
                  ? "Selecione um registro."
                  : ""
            );
          }}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              setOpen(true);
              const next = firstEnabledIndex(activeIndex < 0 ? 0 : activeIndex + 1, 1);
              if (next >= 0) setActiveIndex(next);
            }
            if (event.key === "ArrowUp") {
              event.preventDefault();
              const next = firstEnabledIndex(activeIndex < 0 ? visibleOptions.length - 1 : activeIndex - 1, -1);
              if (next >= 0) setActiveIndex(next);
            }
            if (event.key === "Enter" && open && activeIndex >= 0 && visibleOptions[activeIndex]) {
              event.preventDefault();
              choose(visibleOptions[activeIndex]);
            }
            if (event.key === "Escape") setOpen(false);
          }}
        />
        <button
          className={styles.iconButton}
          type="button"
          onClick={() => setOpen((current) => !current)}
          aria-label={`Consultar ${label.toLocaleLowerCase("pt-BR")}`}
          disabled={disabled}
        >
          ⌕
        </button>
        {query || selectedId ? (
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
      {open ? (
        <div className={styles.lookupPanel} id={listboxId} role="listbox" aria-label={`Resultados de ${label.toLocaleLowerCase("pt-BR")}`}>
          <div className={styles.lookupStatus} role="status" aria-live="polite">
            {filteredOptions.length === 0
              ? emptyText
              : filteredOptions.length > MAX_VISIBLE_OPTIONS
                ? `${MAX_VISIBLE_OPTIONS} de ${filteredOptions.length} registro(s). Digite para refinar.`
                : `${filteredOptions.length} registro(s) disponível(is)`}
          </div>
          {visibleOptions.map((option, index) => (
            <button
              id={`${listboxId}-${index}`}
              className={styles.lookupOption}
              key={option.id}
              type="button"
              role="option"
              aria-selected={selectedId === option.id}
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
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-BR")
    .trim();
}