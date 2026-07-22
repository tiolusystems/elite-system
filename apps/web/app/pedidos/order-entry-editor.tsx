"use client";

import { useMemo, useState } from "react";

import { OrderItemsEditor } from "@/app/pedidos/order-items-editor";
import type { ExchangeSourceItem, SalesItem } from "@/lib/orders";

type Props = { clientName: string; items: SalesItem[]; exchangeItems: ExchangeSourceItem[] };

export function OrderEntryEditor({ clientName, items, exchangeItems }: Props) {
  const [type, setType] = useState("venda");
  const [sourceItemId, setSourceItemId] = useState("");
  const sourceItem = useMemo(() => exchangeItems.find((item) => item.id === Number(sourceItemId)) ?? null, [exchangeItems, sourceItemId]);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <>
      <div className="form-grid orders-form-grid">
        <label>Tipo de pedido<select name="tipo_pedido" value={type} onChange={(event) => setType(event.target.value)}><option value="venda">Venda</option><option value="bonificacao">Bonificação</option><option value="mostruario">Mostruário</option><option value="troca">Troca</option></select></label>
        <label>Data do pedido<input name={type === "troca" ? "data_troca" : "data_pedido"} type="date" defaultValue={today} required /></label>
      </div>

      {type === "venda" ? <OrderItemsEditor items={items} /> : null}

      {["mostruario", "bonificacao"].includes(type) ? <div className="form-grid orders-form-grid">
        <label className="wide-field">Produto e apresentação<select name="produto_embalagem_id" required defaultValue=""><option value="" disabled>Selecione</option>{items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <label>Quantidade<input name="quantidade" inputMode="decimal" required /></label>
        <label className="wide-field">{type === "bonificacao" ? "Justificativa da bonificação" : "Finalidade do mostruário"}<textarea name="observacao" rows={3} minLength={type === "bonificacao" ? 10 : undefined} required placeholder={`Explique a saída para ${clientName}`} /></label>
        <p className="field-note wide-field">{type === "bonificacao" ? "Bonificação não gera comissão e exige liberação de superior." : "Mostruário não gera comissão e seguirá para liberação."}</p>
      </div> : null}

      {type === "troca" ? <div className="form-grid orders-form-grid" id="troca-pedido">
        <input type="hidden" name="pedido_origem_id" value={sourceItem?.orderId ?? ""} />
        <input type="hidden" name="status_troca" value="blocked" />
        <label className="wide-field">Item do pedido original<select name="pedido_item_origem_id" value={sourceItemId} onChange={(event) => setSourceItemId(event.target.value)} required><option value="" disabled>Selecione pedido e item</option>{exchangeItems.map((item) => <option key={item.id} value={item.id}>{item.orderCode} - {item.label} - quantidade original {item.quantity}</option>)}</select></label>
        <label className="wide-field">Produto de reposição<select name="produto_embalagem_id" defaultValue=""><option value="">Manter o produto original</option>{items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <label>Quantidade<input name="quantidade_troca" inputMode="decimal" placeholder={sourceItem ? `Até ${sourceItem.quantity}` : "Selecione a origem"} required /></label>
        <label>Motivo<select name="motivo_troca" defaultValue="qualidade"><option value="qualidade">Qualidade</option><option value="avaria_transporte">Avaria no transporte</option><option value="erro_separacao">Erro de separação</option><option value="erro_comercial">Erro comercial</option><option value="acordo_comercial">Acordo comercial</option><option value="outro">Outro</option></select></label>
        <label className="wide-field">Detalhes<textarea name="observacao_troca" rows={3} placeholder="Obrigatório quando o motivo for Outro" /></label>
        <p className="field-note wide-field">O banco verifica novamente a quantidade já trocada antes de gravar.</p>
      </div> : null}

      {type === "venda" ? <label className="wide-field orders-observation">Observação comercial<textarea name="observacao" rows={3} placeholder="Condição ou informação relevante" /></label> : null}
      <div className="form-footer"><span>{type === "venda" ? "O vendedor não altera limite nem libera o próprio pedido." : "A operação será registrada e ficará sujeita às alçadas existentes."}</span><button className="primary-button" type="submit" disabled={type === "troca" && !sourceItem}>Enviar para liberação</button></div>
    </>
  );
}
