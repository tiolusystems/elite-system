"use client";

import { useState } from "react";

export type ClientExportFormat = "xlsx" | "csv";

export function ClientExportMenu({
  label = "Exportar",
  onExport,
}: {
  label?: string;
  onExport: (format: ClientExportFormat) => void | Promise<void>;
}) {
  const [pending, setPending] = useState<ClientExportFormat | null>(null);
  const [error, setError] = useState("");

  async function run(format: ClientExportFormat, details: HTMLDetailsElement | null) {
    setPending(format);
    setError("");
    try {
      await onExport(format);
      details?.removeAttribute("open");
    } catch {
      setError("Não foi possível gerar o arquivo. Tente novamente.");
    } finally {
      setPending(null);
    }
  }

  return (
    <details className="export-menu">
      <summary className="secondary-button export-menu-trigger">
        <span>{label}</span>
        <span aria-hidden="true">▾</span>
      </summary>
      <div className="export-menu-options">
        <button
          className="export-menu-option export-menu-option-primary"
          type="button"
          disabled={pending !== null}
          onClick={(event) => void run("xlsx", event.currentTarget.closest("details"))}
        >
          <span className="export-menu-option-copy">
            <strong>{pending === "xlsx" ? "Gerando Excel..." : "Excel (.xlsx)"}</strong>
            <small>Planilha pronta para abrir e trabalhar no Excel.</small>
          </span>
          <span className="export-menu-badge">Principal</span>
        </button>
        <button
          className="export-menu-option"
          type="button"
          disabled={pending !== null}
          onClick={(event) => void run("csv", event.currentTarget.closest("details"))}
        >
          <span className="export-menu-option-copy">
            <strong>{pending === "csv" ? "Gerando CSV..." : "CSV (.csv)"}</strong>
            <small>Formato simples para integração e tratamento técnico.</small>
          </span>
        </button>
        {error ? <span className="export-menu-error" role="alert">{error}</span> : null}
      </div>
    </details>
  );
}
