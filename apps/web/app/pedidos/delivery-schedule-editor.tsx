"use client";

import type { OrderItemDraft } from "@/app/pedidos/order-items-editor";
import { decimal } from "@/app/pedidos/order-items-editor";
import type { DeliveryLocation, SalesItem } from "@/lib/orders";

export type DeliveryDraft = {
  key: number;
  date: string;
  locationKey: string;
  allocations: Record<string, string>;
};

type Props = {
  locations: DeliveryLocation[];
  items: SalesItem[];
  rows: OrderItemDraft[];
  deliveries: DeliveryDraft[];
  onChange: (deliveries: DeliveryDraft[]) => void;
  orderDate: string;
};

export function DeliveryScheduleEditor({ locations, items, rows, deliveries, onChange, orderDate }: Props) {
  function change(key: number, field: "date" | "locationKey", value: string) {
    onChange(deliveries.map((delivery) => delivery.key === key ? { ...delivery, [field]: value } : delivery));
  }

  function changeAllocation(deliveryKey: number, rowKey: number, value: string) {
    onChange(deliveries.map((delivery) => delivery.key === deliveryKey
      ? { ...delivery, allocations: { ...delivery.allocations, [rowKey]: value } }
      : delivery
    ));
  }

  function add() {
    onChange([...deliveries, {
      key: Math.max(...deliveries.map((delivery) => delivery.key), 0) + 1,
      date: orderDate,
      locationKey: locations[0]?.key ?? "",
      allocations: Object.fromEntries(rows.map((row) => [row.key, ""]))
    }]);
  }

  function remove(key: number) {
    onChange(deliveries.filter((delivery) => delivery.key !== key));
  }

  return (
    <fieldset className="delivery-schedule-editor">
      <legend>2. Local e entrega</legend>
      <p className="section-intro">A programação orienta a operação futura. Ela não reserva nem baixa estoque.</p>
      {!locations.length ? (
        <div className="notice-panel warning">
          <strong>Cliente sem local de entrega ativo</strong>
          <span>Cadastre uma propriedade, estabelecimento ou endereço de entrega antes de enviar o pedido.</span>
        </div>
      ) : null}
      <div className="delivery-schedule-list">
        {deliveries.map((delivery, deliveryIndex) => {
          const totalLiters = deliveryVolumeLiters(delivery, rows, items);
          return (
            <article className="delivery-schedule-card" key={delivery.key}>
            <div className="delivery-schedule-heading">
              <div>
                <strong>Entrega {deliveryIndex + 1}</strong>
                <span>Distribua abaixo as quantidades desta entrega.</span>
                <small>{totalLiters === null ? "Volume programado indisponível" : `Volume programado: ${number(totalLiters)} L`}</small>
              </div>
              {deliveries.length > 1 ? <button type="button" className="secondary-button" onClick={() => remove(delivery.key)}>Remover entrega</button> : null}
            </div>
            <div className="delivery-schedule-fields">
              <label>
                <span>Local de entrega</span>
                <select value={delivery.locationKey} onChange={(event) => change(delivery.key, "locationKey", event.target.value)} required>
                  <option value="" disabled>Selecione o local</option>
                  {locations.map((location) => (
                    <option key={location.key} value={location.key}>
                      {locationType(location.type)} - {location.name} - {location.city ?? "Município não informado"}{location.state ? `/${location.state}` : ""}
                    </option>
                  ))}
                </select>
                {delivery.locationKey ? <small>{locationDetail(locations.find((location) => location.key === delivery.locationKey) ?? null)}</small> : null}
              </label>
              <label>
                <span>Previsão de entrega</span>
                <input type="date" min={orderDate} value={delivery.date} onChange={(event) => change(delivery.key, "date", event.target.value)} required />
              </label>
            </div>
            <div className="delivery-allocation-list">
              {rows.map((row, itemIndex) => {
                const item = items.find((candidate) => candidate.id === Number(row.presentationId)) ?? null;
                const ordered = decimal(row.quantity);
                const allocated = decimal(delivery.allocations[row.key] ?? "");
                return (
                  <label key={row.key}>
                    <span className="delivery-allocation-copy">
                      <strong>{item ? `${item.productName} - ${item.packaging}` : `Item ${itemIndex + 1}`}</strong>
                      <small>
                        Pedido: {number(ordered)} un.
                        {item?.volumeLiters === null || item?.volumeLiters === undefined
                          ? " · Litros não configurados"
                          : ` · ${number(ordered * item.volumeLiters)} L`}
                      </small>
                    </span>
                    <input
                      inputMode="decimal"
                      min="0"
                      value={delivery.allocations[row.key] ?? ""}
                      onChange={(event) => changeAllocation(delivery.key, row.key, event.target.value)}
                      aria-label={`Quantidade do item ${itemIndex + 1} na entrega ${deliveryIndex + 1}`}
                      placeholder="0"
                    />
                    <small className="delivery-allocation-result">
                      Nesta entrega: {number(allocated)} un.
                      {item?.volumeLiters === null || item?.volumeLiters === undefined
                        ? " · Litros não configurados"
                        : ` · ${number(allocated * item.volumeLiters)} L`}
                    </small>
                  </label>
                );
              })}
            </div>
          </article>
          );
        })}
      </div>
      <div className="delivery-schedule-footer">
        <button type="button" className="secondary-button" onClick={add} disabled={!locations.length}>Adicionar outra entrega</button>
        <div className="delivery-coverage">
          {rows.map((row, index) => {
            const planned = deliveries.reduce((sum, delivery) => sum + decimal(delivery.allocations[row.key] ?? ""), 0);
            const ordered = decimal(row.quantity);
            const difference = ordered - planned;
            const item = items.find((candidate) => candidate.id === Number(row.presentationId)) ?? null;
            return (
              <span className={Math.abs(difference) < 0.000001 && ordered > 0 ? "is-complete" : "is-pending"} key={row.key}>
                <strong>{item?.productName ?? `Item ${index + 1}`}</strong>
                <small>{number(planned)} de {number(ordered)} un.</small>
                <small>
                  {item?.volumeLiters === null || item?.volumeLiters === undefined
                    ? "Litros não configurados"
                    : `${number(planned * item.volumeLiters)} de ${number(ordered * item.volumeLiters)} L`}
                </small>
              </span>
            );
          })}
        </div>
      </div>
    </fieldset>
  );
}

export function deliveriesCoverItems(rows: OrderItemDraft[], deliveries: DeliveryDraft[]) {
  if (!rows.length || !deliveries.length) return false;
  if (deliveries.some((delivery) => !delivery.date || !delivery.locationKey)) return false;
  return rows.every((row) => {
    const ordered = decimal(row.quantity);
    const planned = deliveries.reduce((sum, delivery) => sum + decimal(delivery.allocations[row.key] ?? ""), 0);
    return ordered > 0 && Math.abs(ordered - planned) < 0.000001;
  });
}

export function deliveryScheduleIssues(rows: OrderItemDraft[], deliveries: DeliveryDraft[], items: SalesItem[] = []) {
  const issues: string[] = [];
  if (!rows.length) issues.push("Adicione ao menos um item ao pedido.");
  if (!deliveries.length) issues.push("Adicione ao menos uma entrega.");
  deliveries.forEach((delivery, index) => {
    if (!delivery.locationKey) issues.push(`Selecione o local da entrega ${index + 1}.`);
    if (!delivery.date) issues.push(`Informe a previsão da entrega ${index + 1}.`);
  });
  rows.forEach((row, index) => {
    const ordered = decimal(row.quantity);
    const planned = deliveries.reduce((sum, delivery) => sum + decimal(delivery.allocations[row.key] ?? ""), 0);
    if (ordered <= 0) return;
    const difference = ordered - planned;
    if (Math.abs(difference) < 0.000001) return;
    const item = items.find((candidate) => candidate.id === Number(row.presentationId)) ?? null;
    const label = item ? `${item.productName} - ${item.packaging}` : `item ${index + 1}`;
    issues.push(difference > 0
      ? `Distribua mais ${number(difference)} un. de ${label}.`
      : `Reduza ${number(Math.abs(difference))} un. de ${label} nas entregas.`
    );
  });
  return issues;
}

export function deliveryVolumeLiters(delivery: DeliveryDraft, rows: OrderItemDraft[], items: SalesItem[]) {
  let total = 0;
  for (const row of rows) {
    const allocated = decimal(delivery.allocations[row.key] ?? "");
    if (allocated <= 0) continue;
    const item = items.find((candidate) => candidate.id === Number(row.presentationId)) ?? null;
    if (!item || item.volumeLiters === null) return null;
    total += allocated * item.volumeLiters;
  }
  return total;
}

function locationType(value: string) {
  return ({ propriedade: "Propriedade", estabelecimento: "Estabelecimento", cadastro_geral: "Endereço de entrega" } as Record<string, string>)[value] ?? "Local";
}

function locationDetail(location: DeliveryLocation | null) {
  if (!location) return "";
  return [location.address, location.city, location.state].filter(Boolean).join(" - ");
}

function number(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}
