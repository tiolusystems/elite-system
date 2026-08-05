"use client";

export function PrintButton() {
  return (
    <button className="primary-button no-print" type="button" onClick={() => window.print()}>
      Imprimir
    </button>
  );
}
