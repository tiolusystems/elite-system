"use client";

import { useMemo, useState } from "react";

import type { SalesItem } from "@/lib/orders";

type Row = { key: number; productId: string; quantity: string; unitPrice: string };

export function OrderItemsEditor({ items }: { items: SalesItem[] }) {
  const [rows, setRows] = useState<Row[]>([{ key: 1, productId: "", quantity: "", unitPrice: "" }]);
  const payload = useMemo(() => JSON.stringify(rows.map((row) => ({
    produto_embalagem_id: Number(row.productId),
    quantidade: decimal(row.quantity),
    valor_unitario: decimal(row.unitPrice)
  }))), [rows]);
  const total = rows.reduce((sum, row) => sum + decimal(row.quantity) * decimal(row.unitPrice), 0);

  function change(key: number, field: keyof Omit<Row, "key">, value: string) {
    setRows((current) => current.map((row) => row.key === key ? { ...row, [field]: value } : row));
  }

  return (
    <fieldset className="order-items-editor">
      <legend>Itens do pedido</legend>
      <input type="hidden" name="itens_json" value={payload} />
      <div className="order-item-head"><span>Produto e apresentação</span><span>Quantidade</span><span>Valor unitário</span><span aria-hidden="true" /></div>
      {rows.map((row) => (
        <div className="order-item-row" key={row.key}>
          <label><span>Produto e apresentação</span><select value={row.productId} onChange={(event) => change(row.key, "productId", event.target.value)} required><option value="" disabled>Selecione</option>{items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
          <label><span>Quantidade</span><input value={row.quantity} onChange={(event) => change(row.key, "quantity", event.target.value)} inputMode="decimal" required /></label>
          <label><span>Valor unitário</span><input value={row.unitPrice} onChange={(event) => change(row.key, "unitPrice", event.target.value)} inputMode="decimal" required /></label>
          <button type="button" className="icon-button" title="Remover item" aria-label="Remover item" disabled={rows.length === 1} onClick={() => setRows((current) => current.filter((item) => item.key !== row.key))}>X</button>
        </div>
      ))}
      <div className="order-items-footer"><button type="button" className="secondary-button" onClick={() => setRows((current) => [...current, { key: Math.max(...current.map((row) => row.key)) + 1, productId: "", quantity: "", unitPrice: "" }])}>Adicionar item</button><div><span>Total do pedido</span><strong>{new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(total)}</strong></div></div>
    </fieldset>
  );
}

function decimal(value: string) {
  const trimmed = value.trim();
  const normalized = trimmed.includes(",") ? trimmed.replace(/\./g, "").replace(",", ".") : trimmed;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : 0;
}
