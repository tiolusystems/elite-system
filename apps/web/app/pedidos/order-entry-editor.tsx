"use client";

import { useEffect, useMemo, useState } from "react";

import { DeliveryScheduleEditor, deliveriesCoverItems, type DeliveryDraft } from "@/app/pedidos/delivery-schedule-editor";
import { OrderItemsEditor, decimal, type OrderItemDraft } from "@/app/pedidos/order-items-editor";
import type { DeliveryLocation, ExchangeSourceItem, PortfolioClient, SalesItem } from "@/lib/orders";

type Props = {
  client: PortfolioClient;
  items: SalesItem[];
  exchangeItems: ExchangeSourceItem[];
  locations: DeliveryLocation[];
  result?: string;
};

const INITIAL_ITEM: OrderItemDraft = { key: 1, productId: "", presentationId: "", quantity: "", unitPrice: "" };

export function OrderEntryEditor({ client, items, exchangeItems, locations, result }: Props) {
  const today = new Date().toISOString().slice(0, 10);
  const draftKey = `elite-order-draft-${client.linkId}`;
  const [type, setType] = useState("venda");
  const [sourceItemId, setSourceItemId] = useState("");
  const [orderDate, setOrderDate] = useState(today);
  const [rows, setRows] = useState<OrderItemDraft[]>([INITIAL_ITEM]);
  const [deliveries, setDeliveries] = useState<DeliveryDraft[]>([{
    key: 1,
    date: today,
    locationKey: locations[0]?.key ?? "",
    allocations: { 1: "" }
  }]);
  const [observation, setObservation] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [restored, setRestored] = useState(false);
  const sourceItem = useMemo(() => exchangeItems.find((item) => item.id === Number(sourceItemId)) ?? null, [exchangeItems, sourceItemId]);

  useEffect(() => {
    const restoreTimer = window.setTimeout(() => {
      if (result === "pedido_pending_approval") {
        sessionStorage.removeItem(draftKey);
        setRestored(true);
        return;
      }
      const saved = sessionStorage.getItem(draftKey);
      if (saved) {
        try {
          const draft = JSON.parse(saved) as {
            type?: string;
            orderDate?: string;
            rows?: OrderItemDraft[];
            deliveries?: DeliveryDraft[];
            observation?: string;
          };
          if (draft.type) setType(draft.type);
          if (draft.orderDate) setOrderDate(draft.orderDate);
          if (Array.isArray(draft.rows) && draft.rows.length) setRows(draft.rows);
          if (Array.isArray(draft.deliveries) && draft.deliveries.length) setDeliveries(draft.deliveries);
          if (typeof draft.observation === "string") setObservation(draft.observation);
        } catch {
          sessionStorage.removeItem(draftKey);
        }
      }
      setRestored(true);
    }, 0);
    return () => window.clearTimeout(restoreTimer);
  }, [draftKey, result]);

  useEffect(() => {
    if (!restored) return;
    sessionStorage.setItem(draftKey, JSON.stringify({ type, orderDate, rows, deliveries, observation }));
  }, [deliveries, draftKey, observation, orderDate, restored, rows, type]);

  const itemsPayload = JSON.stringify(rows.map((row) => ({
    produto_embalagem_id: Number(row.presentationId),
    quantidade: decimal(row.quantity),
    valor_unitario: decimal(row.unitPrice)
  })));
  const deliveriesPayload = JSON.stringify(deliveries.map((delivery) => {
    const location = locations.find((candidate) => candidate.key === delivery.locationKey);
    return {
      data_prevista: delivery.date,
      propriedade_id: location?.propertyId ?? null,
      estabelecimento_id: location?.establishmentId ?? null,
      endereco_id: location?.addressId ?? null,
      itens: rows
        .map((row, index) => ({ item_index: index + 1, quantidade: decimal(delivery.allocations[row.key] ?? "") }))
        .filter((item) => item.quantidade > 0)
    };
  }));
  const total = rows.reduce((sum, row) => sum + decimal(row.quantity) * decimal(row.unitPrice), 0);
  const duplicatedPresentation = rows.some((row, index) =>
    row.presentationId && rows.findIndex((candidate) => candidate.presentationId === row.presentationId) !== index
  );
  const validItems = rows.length > 0 && rows.every((row) =>
    row.productId && row.presentationId && decimal(row.quantity) > 0 && decimal(row.unitPrice) >= 0
  ) && !duplicatedPresentation;
  const scheduleComplete = deliveriesCoverItems(rows, deliveries);
  const saleReady = validItems && scheduleComplete && locations.length > 0 && confirmed;

  return (
    <>
      <div className="form-grid orders-form-grid">
        <label><span>Tipo de pedido</span><select name="tipo_pedido" value={type} onChange={(event) => { setType(event.target.value); setConfirmed(false); }}><option value="venda">Venda</option><option value="bonificacao">Bonificação</option><option value="mostruario">Mostruário</option><option value="troca">Troca</option></select></label>
        <label><span>Data do pedido</span><input name={type === "troca" ? "data_troca" : "data_pedido"} type="date" value={orderDate} onChange={(event) => {
          const nextDate = event.target.value;
          setOrderDate(nextDate);
          setDeliveries((current) => synchronizeDeliveries(current, rows, nextDate));
        }} required /></label>
      </div>

      {type === "venda" ? (
        <>
          <input type="hidden" name="itens_json" value={itemsPayload} />
          <input type="hidden" name="entregas_json" value={deliveriesPayload} />
          <DeliveryScheduleEditor locations={locations} items={items} rows={rows} deliveries={deliveries} onChange={setDeliveries} orderDate={orderDate} />
          <OrderItemsEditor items={items} rows={rows} onChange={(nextRows) => {
            setRows(nextRows);
            setDeliveries((current) => synchronizeDeliveries(current, nextRows, orderDate));
            setConfirmed(false);
          }} />
        </>
      ) : null}

      {["mostruario", "bonificacao"].includes(type) ? <div className="form-grid orders-form-grid">
        <label className="wide-field"><span>Produto e apresentação</span><select name="produto_embalagem_id" required defaultValue=""><option value="" disabled>Selecione</option>{items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <label><span>Quantidade</span><input name="quantidade" inputMode="decimal" required /></label>
        <label className="wide-field"><span>{type === "bonificacao" ? "Justificativa da bonificação" : "Finalidade do mostruário"}</span><textarea name="observacao" rows={3} minLength={type === "bonificacao" ? 10 : undefined} required placeholder={`Explique a saída para ${client.clientName}`} /></label>
        <p className="field-note wide-field">{type === "bonificacao" ? "Bonificação não gera comissão e exige liberação de superior." : "Mostruário não gera comissão e seguirá para liberação."}</p>
      </div> : null}

      {type === "troca" ? <div className="form-grid orders-form-grid" id="troca-pedido">
        <input type="hidden" name="pedido_origem_id" value={sourceItem?.orderId ?? ""} />
        <input type="hidden" name="status_troca" value="blocked" />
        <label className="wide-field"><span>Item do pedido original</span><select name="pedido_item_origem_id" value={sourceItemId} onChange={(event) => setSourceItemId(event.target.value)} required><option value="" disabled>Selecione pedido e item</option>{exchangeItems.map((item) => <option key={item.id} value={item.id}>{item.orderCode} - {item.label} - quantidade original {item.quantity}</option>)}</select></label>
        <label className="wide-field"><span>Produto de reposição</span><select name="produto_embalagem_id" defaultValue=""><option value="">Manter o produto original</option>{items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <label><span>Quantidade</span><input name="quantidade_troca" inputMode="decimal" placeholder={sourceItem ? `Até ${sourceItem.quantity}` : "Selecione a origem"} required /></label>
        <label><span>Motivo</span><select name="motivo_troca" defaultValue="qualidade"><option value="qualidade">Qualidade</option><option value="avaria_transporte">Avaria no transporte</option><option value="erro_separacao">Erro de separação</option><option value="erro_comercial">Erro comercial</option><option value="acordo_comercial">Acordo comercial</option><option value="outro">Outro</option></select></label>
        <label className="wide-field"><span>Detalhes</span><textarea name="observacao_troca" rows={3} placeholder="Obrigatório quando o motivo for Outro" /></label>
        <p className="field-note wide-field">O banco verifica novamente a quantidade já trocada antes de gravar.</p>
      </div> : null}

      {type === "venda" ? (
        <>
          <label className="wide-field orders-observation"><span>Observação comercial</span><textarea name="observacao" rows={3} value={observation} onChange={(event) => setObservation(event.target.value)} placeholder="Condição ou informação relevante" /></label>
          <section className="order-review-summary" aria-labelledby="order-review-title">
            <div className="panel-header"><div><h3 id="order-review-title">4. Revisão</h3><p>Confira antes de enviar para liberação.</p></div><strong>{money(total)}</strong></div>
            <dl>
              <div><dt>Cliente</dt><dd>{client.clientName}</dd></div>
              <div><dt>Documento</dt><dd>{client.document ?? "Não informado"}</dd></div>
              <div><dt>Vendedor responsável</dt><dd>{client.sellerName}</dd></div>
              <div><dt>Limite disponível</dt><dd>{moneyNullable(client.availableLimit)}</dd></div>
              <div><dt>Itens</dt><dd>{rows.length}</dd></div>
              <div><dt>Entregas</dt><dd>{deliveries.length}</dd></div>
            </dl>
            <div className="order-review-deliveries">
              {deliveries.map((delivery, index) => {
                const location = locations.find((candidate) => candidate.key === delivery.locationKey);
                return <span key={delivery.key}><strong>Entrega {index + 1}</strong>{location?.name ?? "Local pendente"} · {dateLabel(delivery.date)}</span>;
              })}
            </div>
            {!scheduleComplete ? <p className="field-error">Distribua integralmente a quantidade de cada item entre as entregas.</p> : null}
            <label className="order-confirmation"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /><span>Conferi cliente, locais, datas, itens, quantidades e valores.</span></label>
          </section>
        </>
      ) : null}

      <div className="form-footer">
        <span>{type === "venda" ? "5. O pedido será criado bloqueado. O vendedor não altera limite nem libera o próprio pedido." : "A operação será registrada e ficará sujeita às alçadas existentes."}</span>
        <button className="primary-button" type="submit" disabled={type === "troca" ? !sourceItem : type === "venda" ? !saleReady : false}>Enviar para liberação</button>
      </div>
    </>
  );
}

function money(value: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

function moneyNullable(value: number | null) {
  return value === null ? "Não informado" : money(value);
}

function dateLabel(value: string) {
  if (!value) return "Data pendente";
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

function synchronizeDeliveries(current: DeliveryDraft[], rows: OrderItemDraft[], orderDate: string) {
  return current.map((delivery) => {
    const allocations = Object.fromEntries(rows.map((row) => [
      row.key,
      current.length === 1 ? row.quantity : (delivery.allocations[row.key] ?? "")
    ]));
    return {
      ...delivery,
      date: delivery.date < orderDate ? orderDate : delivery.date,
      allocations
    };
  });
}
