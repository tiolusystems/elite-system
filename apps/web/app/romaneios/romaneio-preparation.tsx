"use client";

import { useEffect, useMemo, useState } from "react";

import { createRomaneioAction, reserveRomaneioPaLotAction } from "@/app/romaneios/actions";
import type { RomaneioAvailableLot, RomaneioPendingItem, RomaneioRecord } from "@/lib/romaneios";

type OpenItem = {
  id: number;
  produtoEmbalagemId: number;
  itemLabel: string;
  codigoRomaneio: string;
  quantidadeRomaneada: number;
  quantidadeReservada: number;
};

export function RomaneioPreparation({
  pendingItems,
  romaneios
}: {
  pendingItems: RomaneioPendingItem[];
  romaneios: RomaneioRecord[];
}) {
  const [pedidoId, setPedidoId] = useState("");
  const [idempotencyKey] = useState(() => crypto.randomUUID());
  const [selectedItems, setSelectedItems] = useState<number[]>([]);
  const [selectedQuantities, setSelectedQuantities] = useState<Record<number, string>>({});
  const [openItemId, setOpenItemId] = useState("");
  const [selectedLotId, setSelectedLotId] = useState("");
  const [compatibleLots, setCompatibleLots] = useState<RomaneioAvailableLot[]>([]);
  const [lotsLoading, setLotsLoading] = useState(false);
  const [lotsError, setLotsError] = useState("");

  const orders = useMemo(() => {
    const grouped = new Map<number, RomaneioPendingItem[]>();
    for (const item of pendingItems) grouped.set(item.pedidoId, [...(grouped.get(item.pedidoId) ?? []), item]);
    return [...grouped.entries()];
  }, [pendingItems]);
  const orderItems = useMemo(() => orders.find(([id]) => String(id) === pedidoId)?.[1] ?? [], [orders, pedidoId]);
  const loadPreview = useMemo(() => {
    const selected = orderItems.filter((item) => selectedItems.includes(item.pedidoItemId));
    let liters = 0;
    let volumes = 0;
    let netWeight = 0;
    let grossWeight = 0;
    let totalQuantity = 0;
    let hasLiters = selected.length > 0;
    let hasVolumes = selected.length > 0;
    let hasNetWeight = selected.length > 0;
    let hasGrossWeight = selected.length > 0;
    for (const item of selected) {
      const quantity = parseDecimalInput(selectedQuantities[item.pedidoItemId]);
      totalQuantity += quantity;
      if (item.volumeUnitarioL === null) hasLiters = false;
      else liters += quantity * item.volumeUnitarioL;
      if (item.unidadesPorVolume === null) hasVolumes = false;
      else volumes += Math.ceil(quantity / item.unidadesPorVolume);
      if (item.volumeUnitarioL === null || item.densidadeReferenciaKgL === null) hasNetWeight = false;
      else netWeight += quantity * item.volumeUnitarioL * item.densidadeReferenciaKgL;
      if (item.volumeUnitarioL === null || item.densidadeReferenciaKgL === null || item.unidadesPorVolume === null || item.taraVolumeKg === null) hasGrossWeight = false;
      else grossWeight += quantity * item.volumeUnitarioL * item.densidadeReferenciaKgL + Math.ceil(quantity / item.unidadesPorVolume) * item.taraVolumeKg;
    }
    return { totalQuantity, liters: hasLiters ? liters : null, volumes: hasVolumes ? volumes : null, netWeight: hasNetWeight ? netWeight : null, grossWeight: hasGrossWeight ? grossWeight : null };
  }, [orderItems, selectedItems, selectedQuantities]);
  const openItems: OpenItem[] = romaneios
    .filter((romaneio) => ["draft", "separacao"].includes(romaneio.status))
    .flatMap((romaneio) =>
      romaneio.items
        .filter((item) => ["draft", "reservado"].includes(item.status) && item.quantidadeReservada < item.quantidadeRomaneada)
        .map((item) => ({
          id: item.id,
          produtoEmbalagemId: item.produtoEmbalagemId,
          itemLabel: item.itemLabel,
          codigoRomaneio: romaneio.codigoRomaneio,
          quantidadeRomaneada: item.quantidadeRomaneada,
          quantidadeReservada: item.quantidadeReservada
        }))
    );
  const openItem = openItems.find((item) => String(item.id) === openItemId);
  useEffect(() => {
    if (!openItem) return;
    const controller = new AbortController();
    fetch(`/romaneios/api/lotes?produto_embalagem_id=${openItem.produtoEmbalagemId}`, { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error("Não foi possível consultar os lotes deste produto.");
        return response.json() as Promise<{ lots: RomaneioAvailableLot[] }>;
      })
      .then((payload) => setCompatibleLots(payload.lots))
      .catch((error: unknown) => { if ((error as { name?: string }).name !== "AbortError") setLotsError(error instanceof Error ? error.message : "Não foi possível consultar os lotes."); })
      .finally(() => setLotsLoading(false));
    return () => controller.abort();
  }, [openItem]);
  const remaining = openItem ? Math.max(0, openItem.quantidadeRomaneada - openItem.quantidadeReservada) : 0;
  const compatibleBalance = compatibleLots.reduce((sum, lot) => sum + lot.saldoDisponivel, 0);
  const selectedLot = compatibleLots.find((lot) => String(lot.id) === selectedLotId);
  const reservableFromSelectedLot = selectedLot ? Math.min(remaining, selectedLot.saldoDisponivel) : 0;

  return (
    <div className="romaneio-preparation">
      <section className="panel form-panel" id="novo-romaneio" aria-labelledby="novo-romaneio-title">
        <div className="panel-header">
          <div>
            <h2 id="novo-romaneio-title">1. Escolha o pedido</h2>
            <p className="muted">Somente pedidos com saldo a entregar são apresentados.</p>
          </div>
          <span className="pill">consultar não grava</span>
        </div>
        <label className="wide-field">
          Pedido com saldo a entregar
          <select value={pedidoId} onChange={(event) => { setPedidoId(event.target.value); setSelectedItems([]); setSelectedQuantities({}); }}>
            <option value="">Selecione o pedido</option>
            {orders.map(([id, items]) => (
              <option key={id} value={id}>
                {items[0].codigoPedido} - {items[0].clienteNome} - {items.length} produto(s)
              </option>
            ))}
          </select>
        </label>

        {pedidoId ? (
          <form action={createRomaneioAction}>
            <input type="hidden" name="idempotency_key" value={idempotencyKey} />
            <input type="hidden" name="pedido_id" value={pedidoId} />
            <div className="romaneio-order-items">
              {orderItems.map((item) => {
                const available = item.quantidadeDisponivelRomaneio > 0;
                const checked = selectedItems.includes(item.pedidoItemId);
                return (
                  <label className={`romaneio-order-item ${available ? "" : "is-unavailable"}`} key={item.pedidoItemId}>
                    <input
                      type="checkbox"
                      name="pedido_item_id"
                      value={item.pedidoItemId}
                      disabled={!available}
                      checked={checked}
                      onChange={(event) => setSelectedItems((current) => event.target.checked ? [...current, item.pedidoItemId] : current.filter((id) => id !== item.pedidoItemId))}
                    />
                    <span>
                      <strong>{item.itemLabel}</strong>
                      <small>
                        Pedido {formatNumber(item.quantidadePedido)} · entregue {formatNumber(item.quantidadeConfirmada)} · comprometido {formatNumber(item.quantidadeComprometida)} · livre {formatNumber(item.quantidadeDisponivelRomaneio)}
                      </small>
                      {!available ? <small className="field-warning">Todo o saldo já está em outros romaneios. Consulte-os abaixo.</small> : null}
                    </span>
                    <input
                      name={`quantidade_${item.pedidoItemId}`}
                      inputMode="decimal"
                      min="0"
                      max={item.quantidadeDisponivelRomaneio}
                      step="any"
                      placeholder="Quanto entregar"
                      disabled={!checked}
                      required={checked}
                      value={selectedQuantities[item.pedidoItemId] ?? ""}
                      onChange={(event) => setSelectedQuantities((current) => ({ ...current, [item.pedidoItemId]: event.target.value }))}
                    />
                  </label>
                );
              })}
            </div>
            <section className="romaneio-load-preview" aria-label="Prévia consultiva da carga">
              <div><span>Quantidade selecionada</span><strong>{formatNumber(loadPreview.totalQuantity)}</strong></div>
              <div><span>Volume líquido</span><strong>{previewValue(loadPreview.liters, "L")}</strong></div>
              <div><span>Volumes logísticos</span><strong>{previewValue(loadPreview.volumes)}</strong></div>
              <div><span>Peso líquido estimado</span><strong>{previewValue(loadPreview.netWeight, "kg")}</strong></div>
              <div><span>Peso bruto estimado</span><strong>{previewValue(loadPreview.grossWeight, "kg")}</strong></div>
              <p>Esta prévia não grava nem reserva estoque. Pesos são estimados pela densidade de referência; após escolher os lotes, o sistema usa a densidade do CQ.</p>
            </section>
            <div className="form-footer">
              <span>Confira a carga. Somente este botão cria o rascunho.</span>
              <button className="primary-button" type="submit" disabled={selectedItems.length === 0 || loadPreview.totalQuantity <= 0}>Gravar rascunho do romaneio</button>
            </div>
          </form>
        ) : <div className="empty-state compact-empty"><strong>Nenhum pedido selecionado</strong><span>Os produtos serão carregados depois da escolha do pedido.</span></div>}
      </section>

      <section className="panel form-panel" id="reservar-lote" aria-labelledby="reservar-lote-title">
        <div className="panel-header">
          <div><h2 id="reservar-lote-title">2. Escolha o produto e consulte os lotes</h2><p className="muted">O estoque só é consultado para o produto do romaneio escolhido.</p></div>
          <span className="pill">multilote</span>
        </div>
        <label className="wide-field">
          Produto em romaneio aberto
          <select value={openItemId} onChange={(event) => { setOpenItemId(event.target.value); setSelectedLotId(""); setCompatibleLots([]); setLotsError(""); setLotsLoading(Boolean(event.target.value)); }}>
            <option value="">Selecione o produto</option>
            {openItems.map((item) => <option key={item.id} value={item.id}>{item.codigoRomaneio} - {item.itemLabel} - falta reservar {formatNumber(Math.max(0, item.quantidadeRomaneada - item.quantidadeReservada))}</option>)}
          </select>
        </label>
        {openItem ? (
          <form action={reserveRomaneioPaLotAction}>
            <input type="hidden" name="romaneio_item_id" value={openItem.id} />
            {lotsError ? <div className="notice-panel warning" role="alert"><strong>Consulta indisponível</strong><span>{lotsError}</span></div> : null}
            <div className={`notice-panel ${compatibleBalance >= remaining ? "success" : "warning"}`} role="status">
              <strong>{compatibleBalance >= remaining ? "Estoque compatível localizado" : "Saldo insuficiente para completar a reserva"}</strong>
              <span>Necessário: {formatNumber(remaining)}. Disponível nos lotes deste produto: {formatNumber(compatibleBalance)}.</span>
              {compatibleBalance < remaining ? <span>Reserve o disponível em mais de um lote ou escolha outro produto do pedido.</span> : null}
            </div>
            <div className="form-grid romaneio-form-grid">
              <label className="wide-field">Lote compatível
                <select name="lote_pa_id" value={selectedLotId} onChange={(event) => setSelectedLotId(event.target.value)} required disabled={compatibleLots.length === 0}>
                  <option value="">{lotsLoading ? "Consultando lotes..." : compatibleLots.length ? "Selecione o lote" : "Nenhum lote disponível para este produto"}</option>
                  {compatibleLots.map((lot) => <option key={lot.id} value={lot.id}>{lot.codigoLote} - disponível {formatNumber(lot.saldoDisponivel)} - validade {lot.dataValidade ?? "não informada"}</option>)}
                </select>
              </label>
              <label>Quantidade a reservar<input name="quantidade_reservada" inputMode="decimal" min="0" max={reservableFromSelectedLot} step="any" required disabled={!selectedLot} /></label>
            </div>
            <div className="form-footer"><span>{selectedLot ? `Neste lote: ${formatNumber(selectedLot.saldoDisponivel)} disponível.` : "Escolha o lote antes de informar a quantidade."} A reserva reduz o disponível, sem baixar o estoque físico.</span><button className="primary-button" type="submit" disabled={!selectedLot || remaining <= 0}>Reservar lote</button></div>
          </form>
        ) : <div className="empty-state compact-empty"><strong>Estoque ainda não consultado</strong><span>Escolha um produto de um romaneio aberto para ver apenas seus lotes compatíveis.</span></div>}
      </section>
    </div>
  );
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function parseDecimalInput(value: string | undefined) {
  if (!value) return 0;
  const parsed = Number(value.replace(",", "."));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function previewValue(value: number | null, unit = "") {
  return value === null ? "Pendente" : `${formatNumber(value)}${unit ? ` ${unit}` : ""}`;
}
