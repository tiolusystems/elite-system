"use client";

import { useMemo } from "react";

import type { SalesItem } from "@/lib/orders";

export type OrderItemDraft = {
  key: number;
  productId: string;
  presentationId: string;
  quantity: string;
  practicedPrice: string;
};

type Props = {
  items: SalesItem[];
  rows: OrderItemDraft[];
  onChange: (rows: OrderItemDraft[]) => void;
};

export function OrderItemsEditor({ items, rows, onChange }: Props) {
  const products = useMemo(() => {
    const unique = new Map<number, { id: number; code: string; name: string }>();
    items.forEach((item) => unique.set(item.productId, {
      id: item.productId,
      code: item.productCode,
      name: item.productName
    }));
    return [...unique.values()].sort((left, right) => left.name.localeCompare(right.name, "pt-BR"));
  }, [items]);
  const totalVolumeLiters = orderVolumeLiters(rows, items);
  const hasVolumeInput = rows.some((row) => row.presentationId && decimal(row.quantity) > 0);

  function change(key: number, field: keyof Omit<OrderItemDraft, "key">, value: string) {
    onChange(rows.map((row) => {
      if (row.key !== key) return row;
      if (field === "productId") return { ...row, productId: value, presentationId: "" };
      return { ...row, [field]: value };
    }));
  }

  function remove(key: number) {
    onChange(rows.filter((row) => row.key !== key));
  }

  function add() {
    onChange([...rows, {
      key: Math.max(...rows.map((row) => row.key), 0) + 1,
      productId: "",
      presentationId: "",
      quantity: "",
      practicedPrice: ""
    }]);
  }

  return (
    <fieldset className="order-items-editor">
      <legend>3. Itens do pedido</legend>
      <p className="section-intro">Escolha primeiro o produto e depois uma apresentação comercial ativa.</p>
      <div className="order-item-head">
        <span>Produto</span><span>Apresentação</span><span>Quantidade</span><span aria-hidden="true" />
      </div>
      {rows.map((row, index) => {
        const presentations = items.filter((item) => item.productId === Number(row.productId));
        const selected = items.find((item) => item.id === Number(row.presentationId)) ?? null;
        const duplicate = Boolean(row.presentationId && rows.some((candidate) =>
          candidate.key !== row.key && candidate.presentationId === row.presentationId
        ));
        return (
          <article className="order-item-row" key={row.key}>
            <span className="order-item-position">Item {index + 1}</span>
            <label>
              <span>Produto</span>
              <select value={row.productId} onChange={(event) => change(row.key, "productId", event.target.value)} required>
                <option value="" disabled>Selecione o produto</option>
                {products.map((product) => <option key={product.id} value={product.id}>{product.code} - {product.name}</option>)}
              </select>
            </label>
            <label>
              <span>Apresentação/embalagem</span>
              <select
                value={row.presentationId}
                onChange={(event) => change(row.key, "presentationId", event.target.value)}
                required
                disabled={!row.productId}
                aria-invalid={duplicate}
              >
                <option value="" disabled>{row.productId ? "Selecione a apresentação" : "Selecione o produto primeiro"}</option>
                {presentations.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.presentationCode} - {item.packaging}{item.volumeLiters === null ? "" : ` - ${number(item.volumeLiters)} L`}
                  </option>
                ))}
              </select>
              {duplicate ? <small className="field-error">Esta apresentação já está no pedido. Ajuste a quantidade no item existente.</small> : null}
            </label>
            <label>
              <span>Quantidade</span>
              <input value={row.quantity} onChange={(event) => change(row.key, "quantity", event.target.value)} inputMode="decimal" min="0.0001" required />
            </label>
            <div className="order-item-subtotal">
              <span>Apresentação selecionada</span>
              <strong>{selected?.presentationCode ?? "Pendente"}</strong>
              <small>O preço será informado na revisão comercial.</small>
            </div>
            <button type="button" className="icon-button" title="Remover item" aria-label={`Remover item ${index + 1}`} disabled={rows.length === 1} onClick={() => remove(row.key)}>X</button>
          </article>
        );
      })}
      <div className="order-items-footer">
        <button type="button" className="secondary-button" onClick={add}>Adicionar item</button>
        <div>
          <span>Quantidade de itens</span>
          <strong>{rows.length}</strong>
          {hasVolumeInput ? (
            <small>{totalVolumeLiters === null ? "Volume da apresentação pendente no cadastro" : `${number(totalVolumeLiters)} L no pedido`}</small>
          ) : null}
        </div>
      </div>
    </fieldset>
  );
}

export function decimal(value: string) {
  const trimmed = value.trim();
  const normalized = trimmed.includes(",") ? trimmed.replace(/\./g, "").replace(",", ".") : trimmed;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function orderVolumeLiters(rows: OrderItemDraft[], items: SalesItem[]) {
  if (!rows.length) return null;
  let total = 0;
  for (const row of rows) {
    const item = items.find((candidate) => candidate.id === Number(row.presentationId)) ?? null;
    const quantity = decimal(row.quantity);
    if (!item || item.volumeLiters === null || quantity <= 0) return null;
    total += quantity * item.volumeLiters;
  }
  return total;
}

function number(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value);
}
