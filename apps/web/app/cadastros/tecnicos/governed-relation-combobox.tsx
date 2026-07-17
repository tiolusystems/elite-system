"use client";

import { useId, useMemo, useRef, useState } from "react";

import styles from "./governed-relation-combobox.module.css";

export type GovernedRelationOption = {
  id: number;
  label: string;
  detail?: string | null;
};

type GovernedRelationComboboxProps = {
  name: string;
  label: string;
  options: GovernedRelationOption[];
  defaultValue?: number | null;
  emptyLabel: string;
  placeholder: string;
};

export function GovernedRelationCombobox({
  name,
  label,
  options,
  defaultValue = null,
  emptyLabel,
  placeholder
}: GovernedRelationComboboxProps) {
  const generatedId = useId().replaceAll(":", "");
  const inputId = `${name}-${generatedId}`;
  const listboxId = `${inputId}-opcoes`;
  const initialOption = options.find((option) => option.id === defaultValue) ?? null;
  const inputRef = useRef<HTMLInputElement>(null);
  const [selectedId, setSelectedId] = useState<number | null>(initialOption?.id ?? null);
  const [query, setQuery] = useState(initialOption?.label ?? "");
  const [open, setOpen] = useState(false);

  const filteredOptions = useMemo(() => {
    const normalizedQuery = normalize(query);
    if (!normalizedQuery || options.some((option) => option.id === selectedId && option.label === query)) {
      return options;
    }
    return options.filter((option) => normalize(`${option.label} ${option.detail ?? ""}`).includes(normalizedQuery));
  }, [options, query, selectedId]);

  function choose(option: GovernedRelationOption | null) {
    setSelectedId(option?.id ?? null);
    setQuery(option?.label ?? "");
    setOpen(false);
    inputRef.current?.setCustomValidity("");
  }

  return (
    <div
      className={styles.field}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
    >
      <label className={styles.label} htmlFor={inputId}>{label}</label>
      <input type="hidden" name={name} value={selectedId ?? ""} />
      <div className={styles.control}>
        <input
          ref={inputRef}
          id={inputId}
          type="search"
          role="combobox"
          aria-autocomplete="list"
          aria-controls={listboxId}
          aria-expanded={open}
          autoComplete="off"
          value={query}
          placeholder={placeholder}
          onChange={(event) => {
            setQuery(event.target.value);
            setSelectedId(null);
            setOpen(true);
            event.currentTarget.setCustomValidity(
              event.target.value.trim() ? "Selecione uma opção válida na lista." : ""
            );
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={(event) => {
            if (event.key === "Escape") setOpen(false);
          }}
        />
        {query || selectedId !== null ? (
          <button className={styles.clearButton} type="button" onClick={() => choose(null)} aria-label={`Limpar ${label.toLocaleLowerCase("pt-BR")}`}>
            &times;
          </button>
        ) : null}
      </div>
      {open ? (
        <div className={styles.options} id={listboxId} role="listbox" aria-label={`Opções de ${label.toLocaleLowerCase("pt-BR")}`}>
          <button className={styles.option} type="button" role="option" aria-selected={selectedId === null && query === ""} onClick={() => choose(null)}>
            <strong>{emptyLabel}</strong>
            <small>Manter como pendência para revisão</small>
          </button>
          {filteredOptions.map((option) => (
            <button
              className={styles.option}
              key={option.id}
              type="button"
              role="option"
              aria-selected={option.id === selectedId}
              onClick={() => choose(option)}
            >
              <strong>{option.label}</strong>
              {option.detail ? <small>{option.detail}</small> : null}
            </button>
          ))}
          {filteredOptions.length === 0 ? <span className={styles.empty}>Nenhuma opção encontrada.</span> : null}
        </div>
      ) : null}
    </div>
  );
}

function normalize(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLocaleLowerCase("pt-BR");
}
