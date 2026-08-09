"use client";

export function PrintButton() {
  return (
    <button className="primary-button print-hidden" type="button" onClick={() => window.print()}>
      Imprimir
    </button>
  );
}
