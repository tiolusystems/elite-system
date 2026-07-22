"use client";

export function OrderContractPrintButton() {
  return (
    <button className="primary-button print-hidden" type="button" onClick={() => window.print()}>
      Imprimir ou salvar em PDF
    </button>
  );
}
