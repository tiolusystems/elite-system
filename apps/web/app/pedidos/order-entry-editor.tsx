"use client";

import { useEffect, useMemo, useState } from "react";

import { preverRevisaoComercialAction } from "@/app/pedidos/actions";
import {
  DeliveryLocationSelector,
  DeliveryScheduleEditor,
  deliveriesCoverItems,
  deliveryScheduleIssues,
  type DeliveryDraft
} from "@/app/pedidos/delivery-schedule-editor";
import {
  OrderCommercialReview,
  parseCommercialReviewPreview,
  type CommercialReviewPreview
} from "@/app/pedidos/order-commercial-review";
import { OrderItemsEditor, decimal, orderVolumeLiters, type OrderItemDraft } from "@/app/pedidos/order-items-editor";
import { OrderPaymentTermsEditor, type PaymentInstallmentDraft } from "@/app/pedidos/order-payment-terms-editor";
import type {
  CommercialAreaOption,
  CommercialOriginOption,
  CommercialParticipantOption,
  DeliveryLocation,
  ExchangeSourceItem,
  PortfolioClient,
  SalesItem
} from "@/lib/orders";

type Props = {
  client: PortfolioClient;
  items: SalesItem[];
  exchangeItems: ExchangeSourceItem[];
  locations: DeliveryLocation[];
  commercialOrigins: CommercialOriginOption[];
  commercialAreas: CommercialAreaOption[];
  commercialParticipants: CommercialParticipantOption[];
  canPreviewCommercialReview: boolean;
  canConfirmCommercialReview: boolean;
  result?: string;
};

const INITIAL_ITEM: OrderItemDraft = { key: 1, productId: "", presentationId: "", quantity: "", practicedPrice: "" };

export function OrderEntryEditor({
  client,
  items,
  exchangeItems,
  locations,
  commercialOrigins,
  commercialAreas,
  commercialParticipants,
  canPreviewCommercialReview,
  canConfirmCommercialReview,
  result
}: Props) {
  const today = new Date().toISOString().slice(0, 10);
  const draftKey = `elite-order-draft-${client.linkId}`;
  const [type, setType] = useState("venda");
  const [sourceItemId, setSourceItemId] = useState("");
  const [orderDate, setOrderDate] = useState(today);
  const [rows, setRows] = useState<OrderItemDraft[]>([INITIAL_ITEM]);
  const [deliveries, setDeliveries] = useState<DeliveryDraft[]>([{ key: 1, date: today, locationKey: "", allocations: { 1: "" } }]);
  const [installments, setInstallments] = useState<PaymentInstallmentDraft[]>([{ key: 1, paymentMethod: "boleto", amount: "", dueDate: today }]);
  const [commercialOriginId, setCommercialOriginId] = useState(String(commercialOrigins[0]?.id ?? ""));
  const [commercialAreaId, setCommercialAreaId] = useState("");
  const [stateCode, setStateCode] = useState(client.state ?? "");
  const [participantRoleIds, setParticipantRoleIds] = useState<string[]>([]);
  const [observation, setObservation] = useState("");
  const [preview, setPreview] = useState<CommercialReviewPreview | null>(null);
  const [previewFingerprint, setPreviewFingerprint] = useState("");
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [commercialJustification, setCommercialJustification] = useState("");
  const [discountsConfirmed, setDiscountsConfirmed] = useState(false);
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
            installments?: PaymentInstallmentDraft[];
            commercialOriginId?: string;
            commercialAreaId?: string;
            stateCode?: string;
            participantRoleIds?: string[];
            observation?: string;
          };
          if (draft.type) setType(draft.type);
          if (draft.orderDate) setOrderDate(draft.orderDate);
          if (Array.isArray(draft.rows) && draft.rows.length) {
            setRows(draft.rows.map((row) => ({
              ...row,
              practicedPrice: typeof row.practicedPrice === "string" ? row.practicedPrice : ""
            })));
          }
          if (Array.isArray(draft.deliveries) && draft.deliveries.length) setDeliveries(draft.deliveries);
          if (Array.isArray(draft.installments) && draft.installments.length) setInstallments(draft.installments);
          if (draft.commercialOriginId) setCommercialOriginId(draft.commercialOriginId);
          if (typeof draft.commercialAreaId === "string") setCommercialAreaId(draft.commercialAreaId);
          if (typeof draft.stateCode === "string") setStateCode(draft.stateCode);
          if (Array.isArray(draft.participantRoleIds)) setParticipantRoleIds(draft.participantRoleIds);
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
    sessionStorage.setItem(draftKey, JSON.stringify({
      type, orderDate, rows, deliveries, installments, commercialOriginId,
      commercialAreaId, stateCode, participantRoleIds, observation
    }));
  }, [commercialAreaId, commercialOriginId, deliveries, draftKey, installments, observation, orderDate, participantRoleIds, restored, rows, stateCode, type]);

  const proposal = useMemo(() => buildProposal({
    clientLinkId: client.linkId,
    orderDate,
    commercialOriginId,
    commercialAreaId,
    stateCode,
    participantRoleIds,
    rows,
    deliveries,
    installments,
    locations,
    observation
  }), [client.linkId, commercialAreaId, commercialOriginId, deliveries, installments, locations, observation, orderDate, participantRoleIds, rows, stateCode]);
  const proposalFingerprint = JSON.stringify(proposal);
  const previewStale = Boolean(preview && previewFingerprint !== proposalFingerprint);
  const reviewHasDiscount = preview?.items.some((item) => item.classification === "BELOW_REFERENCE") ?? false;
  const totalVolumeLiters = orderVolumeLiters(rows, items);
  const duplicatedPresentation = rows.some((row, index) => row.presentationId && rows.findIndex((candidate) => candidate.presentationId === row.presentationId) !== index);
  const itemIssues = orderItemIssues(rows, duplicatedPresentation);
  const validRows = rows.filter(isValidOrderItem);
  const hasValidItem = validRows.length > 0;
  const scheduleComplete = itemIssues.length === 0 && deliveriesCoverItems(rows, deliveries);
  const scheduleIssues = hasValidItem ? deliveryScheduleIssues(validRows, deliveries, items) : [];
  const contextIssues = [
    ...(!commercialOriginId ? ["Selecione a origem comercial."] : []),
    ...(stateCode && !/^[A-Za-z]{2}$/.test(stateCode) ? ["Informe uma UF válida com duas letras."] : [])
  ];
  const paymentIssues = paymentTermIssues(installments, orderDate);
  const reviewIssues = [
    ...(!canPreviewCommercialReview ? ["Sua conta não possui alçada para calcular a revisão comercial."] : []),
    ...(!canConfirmCommercialReview ? ["Sua conta não possui alçada para confirmar condições comerciais."] : []),
    ...(!preview ? ["Calcule as referências e a comparação comercial."] : []),
    ...(previewStale ? ["A proposta mudou depois do último cálculo. Recalcule as condições."] : []),
    ...(preview && !preview.complete ? ["Informe todos os preços praticados e recalcule."] : []),
    ...(reviewHasDiscount && commercialJustification.trim().length < 10 ? ["Justifique a solicitação de desconto com ao menos 10 caracteres."] : []),
    ...(reviewHasDiscount && !discountsConfirmed ? ["Confirme explicitamente a solicitação dos descontos apresentados."] : [])
  ];
  const submissionIssues = [...new Set([
    ...(!orderDate ? ["Informe a data do pedido."] : []),
    ...contextIssues,
    ...itemIssues,
    ...(!locations.length
      ? ["Cadastre um local de entrega ativo para este cliente.", ...scheduleIssues.filter((issue) => !issue.startsWith("Selecione o local da entrega"))]
      : scheduleIssues),
    ...paymentIssues,
    ...reviewIssues
  ])];
  const saleReady = submissionIssues.length === 0;

  async function calculateCommercialReview() {
    setPreviewLoading(true);
    setPreviewError(null);
    try {
      const result = await preverRevisaoComercialAction(proposal);
      if (result.error || !result.data) {
        setPreviewError(result.error ?? "Não foi possível calcular a revisão comercial.");
        return;
      }
      const parsed = parseCommercialReviewPreview(result.data);
      if (!parsed) {
        setPreviewError("A revisão comercial retornou dados incompletos.");
        return;
      }
      setPreview(parsed);
      setPreviewFingerprint(proposalFingerprint);
      if (!parsed.items.some((item) => item.classification === "BELOW_REFERENCE")) {
        setCommercialJustification("");
        setDiscountsConfirmed(false);
      }
    } finally {
      setPreviewLoading(false);
    }
  }

  return (
    <>
      <div className="form-grid orders-form-grid">
        <label><span>Tipo de pedido</span><select name="tipo_pedido" value={type} onChange={(event) => setType(event.target.value)}><option value="venda">Venda</option><option value="bonificacao">Bonificação</option><option value="mostruario">Mostruário</option><option value="troca">Troca</option></select></label>
        <label><span>Data do pedido</span><input name={type === "troca" ? "data_troca" : "data_pedido"} type="date" value={orderDate} onChange={(event) => {
          const nextDate = event.target.value;
          setOrderDate(nextDate);
          setDeliveries((current) => synchronizeDeliveries(current, rows, nextDate));
          setInstallments((current) => current.map((installment) => ({ ...installment, dueDate: installment.dueDate < nextDate ? nextDate : installment.dueDate })));
        }} required /></label>
      </div>

      {type === "venda" ? (
        <>
          <input type="hidden" name="proposta_json" value={proposalFingerprint} />
          <input type="hidden" name="preview_hash" value={preview && !previewStale ? preview.previewHash : ""} />
          <DeliveryLocationSelector locations={locations} value={deliveries[0]?.locationKey ?? ""} onChange={(locationKey) => setDeliveries((current) => synchronizePrimaryLocation(current, rows, orderDate, locationKey))} />
          <OrderItemsEditor items={items} rows={rows} onChange={(nextRows) => {
            setRows(nextRows);
            setDeliveries((current) => synchronizeDeliveries(current, nextRows, orderDate));
            setDiscountsConfirmed(false);
          }} />
          {hasValidItem ? <DeliveryScheduleEditor locations={locations} items={items} rows={validRows} deliveries={deliveries} onChange={setDeliveries} orderDate={orderDate} /> : null}
          {hasValidItem ? (
            <fieldset className="order-commercial-context">
              <legend>Contexto comercial</legend>
              <p className="section-intro">Registre o contexto desta operação. Relacionamentos cadastrais não substituem o fato informado no pedido.</p>
              <div className="form-grid orders-form-grid">
                <label><span>Origem comercial</span><select value={commercialOriginId} onChange={(event) => setCommercialOriginId(event.target.value)} required><option value="" disabled>Selecione</option>{commercialOrigins.map((origin) => <option key={origin.id} value={origin.id}>{origin.name}</option>)}</select></label>
                <label><span>Área comercial</span><select value={commercialAreaId} onChange={(event) => setCommercialAreaId(event.target.value)}><option value="">Sem área específica</option>{commercialAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select></label>
                <label><span>UF da operação</span><input value={stateCode} onChange={(event) => setStateCode(event.target.value.toUpperCase().slice(0, 2))} maxLength={2} placeholder="SP" /></label>
                <div className="wide-field commercial-participant-field">
                  <span>Participantes comerciais</span>
                  <div className="commercial-participant-options">
                    {commercialParticipants.map((participant) => {
                      const roleId = String(participant.roleId);
                      return (
                        <label key={participant.roleId}>
                          <input
                            type="checkbox"
                            checked={participantRoleIds.includes(roleId)}
                            onChange={(event) => setParticipantRoleIds((current) => event.target.checked
                              ? [...current, roleId]
                              : current.filter((currentRoleId) => currentRoleId !== roleId))}
                          />
                          <span>{participant.name} - {participantRoleLabel(participant.role)}</span>
                        </label>
                      );
                    })}
                    {commercialParticipants.length === 0 ? <small>Nenhum participante comercial ativo disponível.</small> : null}
                  </div>
                  <small>Selecione somente quem participa desta operação. A ausência também é válida.</small>
                </div>
              </div>
            </fieldset>
          ) : null}
          {hasValidItem ? <OrderPaymentTermsEditor installments={installments} orderDate={orderDate} onChange={setInstallments} /> : null}
          {hasValidItem ? (
            <OrderCommercialReview
              rows={rows}
              preview={preview}
              stale={previewStale}
              loading={previewLoading}
              error={previewError}
              canPreview={canPreviewCommercialReview}
              justification={commercialJustification}
              discountsConfirmed={discountsConfirmed}
              onPriceChange={(key, value) => {
                setRows((current) => current.map((row) => row.key === key ? { ...row, practicedPrice: value } : row));
                setDiscountsConfirmed(false);
              }}
              onJustificationChange={setCommercialJustification}
              onDiscountsConfirmedChange={setDiscountsConfirmed}
              onCalculate={calculateCommercialReview}
            />
          ) : null}
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

      {type === "venda" && hasValidItem ? (
        <>
          <label className="wide-field orders-observation"><span>Observação comercial</span><textarea rows={3} value={observation} onChange={(event) => setObservation(event.target.value)} placeholder="Condição ou informação relevante" /></label>
          <section className="order-review-summary" aria-labelledby="order-review-title">
            <div className="panel-header"><div><h3 id="order-review-title">5. Revisão do pedido</h3><p>Confira o pedido e a versão comercial antes da confirmação.</p></div><strong>{preview?.complete ? moneyFromCents(preview.totals.practiced) : "Valor pendente"}</strong></div>
            <dl>
              <div><dt>Cliente</dt><dd>{client.clientName}</dd></div>
              <div><dt>Documento</dt><dd>{client.document ?? "Não informado"}</dd></div>
              <div><dt>Vendedor responsável</dt><dd>{client.sellerName}</dd></div>
              <div><dt>Limite disponível</dt><dd>{moneyNullable(client.availableLimit)}</dd></div>
              <div><dt>Itens</dt><dd>{rows.length}</dd></div>
              <div><dt>Entregas</dt><dd>{deliveries.length}</dd></div>
              <div><dt>Volume físico conhecido</dt><dd>{totalVolumeLiters === null ? "Não aplicável ou não configurado" : `${number(totalVolumeLiters)} L`}</dd></div>
              <div><dt>Versão comercial</dt><dd>{preview && !previewStale && preview.complete ? "Pronta para congelamento" : "Pendente de cálculo final"}</dd></div>
            </dl>
            <div className="order-review-deliveries">{deliveries.map((delivery, index) => { const location = locations.find((candidate) => candidate.key === delivery.locationKey); return <span key={delivery.key}><strong>Entrega {index + 1}</strong>{location?.name ?? "Local pendente"} · {dateLabel(delivery.date)}</span>; })}</div>
            {!scheduleComplete ? <p className="field-error">Distribua integralmente a quantidade de cada item entre as entregas.</p> : null}
          </section>
          <section className={`order-submit-readiness ${saleReady ? "is-ready" : "is-blocked"}`} id="order-submit-status" aria-live="polite">
            <strong>{saleReady ? "Condições comerciais prontas para confirmação" : "Antes de confirmar as condições comerciais"}</strong>
            {saleReady ? <span>O pedido e seus fatos comerciais serão criados atomicamente e permanecerão bloqueados para as etapas futuras.</span> : <ul>{submissionIssues.map((issue) => <li key={issue}>{issue}</li>)}</ul>}
          </section>
        </>
      ) : null}

      <div className="form-footer">
        <span>{type === "venda" ? "6. A confirmação congela esta versão comercial. Ela não aprova desconto, não substitui assinatura e não torna o pedido efetivo." : "A operação será registrada e ficará sujeita às alçadas existentes."}</span>
        <button className="primary-button" type="submit" disabled={type === "troca" ? !sourceItem : type === "venda" ? !saleReady : false} aria-describedby={type === "venda" ? "order-submit-status" : undefined} title={type === "venda" && !saleReady ? submissionIssues[0] : undefined}>
          {type === "venda" ? "Confirmar condições comerciais" : "Enviar para liberação"}
        </button>
      </div>
    </>
  );
}

type ProposalInput = {
  clientLinkId: number;
  orderDate: string;
  commercialOriginId: string;
  commercialAreaId: string;
  stateCode: string;
  participantRoleIds: string[];
  rows: OrderItemDraft[];
  deliveries: DeliveryDraft[];
  installments: PaymentInstallmentDraft[];
  locations: DeliveryLocation[];
  observation: string;
};

function buildProposal(input: ProposalInput) {
  return {
    cliente_vendedor_vinculo_id: input.clientLinkId,
    data_pedido: input.orderDate,
    origem_comercial_id: integerOrNull(input.commercialOriginId),
    area_comercial_id: integerOrNull(input.commercialAreaId),
    uf: input.stateCode.trim().toUpperCase() || null,
    pessoa_papel_ids: input.participantRoleIds.map(Number).filter((value) => Number.isInteger(value) && value > 0),
    itens: input.rows.map((row) => ({
      produto_embalagem_id: integerOrNull(row.presentationId),
      quantidade: decimal(row.quantity),
      ...(moneyInputToCents(row.practicedPrice) !== null ? { preco_praticado_centavos_por_unidade_precificacao: moneyInputToCents(row.practicedPrice) } : {})
    })),
    parcelas: input.installments.map((installment, index) => ({
      numero_parcela: index + 1,
      forma_pagamento: installment.paymentMethod,
      valor_centavos: moneyInputToCents(installment.amount),
      data_vencimento: installment.dueDate
    })),
    entregas: input.deliveries.map((delivery) => {
      const location = input.locations.find((candidate) => candidate.key === delivery.locationKey);
      return {
        data_prevista: delivery.date,
        propriedade_id: location?.propertyId ?? null,
        estabelecimento_id: location?.establishmentId ?? null,
        endereco_id: location?.addressId ?? null,
        itens: input.rows.map((row, index) => ({ item_index: index + 1, quantidade: decimal(delivery.allocations[row.key] ?? "") })).filter((item) => item.quantidade > 0)
      };
    }),
    observacao: input.observation.trim() || null
  };
}

function orderItemIssues(rows: OrderItemDraft[], duplicatedPresentation: boolean) {
  const issues: string[] = [];
  if (!rows.length) return ["Adicione ao menos um item ao pedido."];
  rows.forEach((row, index) => {
    const label = `item ${index + 1}`;
    if (!row.productId) issues.push(`Selecione o produto do ${label}.`);
    if (!row.presentationId) issues.push(`Selecione a apresentação do ${label}.`);
    if (decimal(row.quantity) <= 0) issues.push(`Informe uma quantidade maior que zero no ${label}.`);
  });
  if (duplicatedPresentation) issues.push("Remova a apresentação repetida e ajuste a quantidade no item existente.");
  return issues;
}

function paymentTermIssues(installments: PaymentInstallmentDraft[], orderDate: string) {
  if (!installments.length) return ["Adicione ao menos uma parcela."];
  const issues: string[] = [];
  installments.forEach((installment, index) => {
    const cents = moneyInputToCents(installment.amount);
    if (cents === null || cents <= 0) issues.push(`Informe um valor positivo na parcela ${index + 1}.`);
    if (!installment.dueDate) issues.push(`Informe o vencimento da parcela ${index + 1}.`);
    else if (orderDate && installment.dueDate < orderDate) issues.push(`O vencimento da parcela ${index + 1} não pode anteceder o pedido.`);
  });
  return issues;
}

function isValidOrderItem(row: OrderItemDraft) {
  return Boolean(row.productId && row.presentationId && decimal(row.quantity) > 0);
}

function moneyInputToCents(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const normalized = trimmed.includes(",") ? trimmed.replace(/\./g, "").replace(",", ".") : trimmed;
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [whole, fraction = ""] = normalized.split(".");
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(cents) ? cents : null;
}

function integerOrNull(value: string) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function participantRoleLabel(value: string) {
  return ({ vendedor: "Vendedor", agente: "Agente", tecnico_campo: "Técnico de campo", gerente: "Gerente", comissionado: "Comissionado" } as Record<string, string>)[value] ?? "Participante";
}

function synchronizeDeliveries(current: DeliveryDraft[], rows: OrderItemDraft[], orderDate: string) {
  return current.map((delivery) => ({
    ...delivery,
    date: delivery.date < orderDate ? orderDate : delivery.date,
    allocations: Object.fromEntries(rows.map((row) => [row.key, current.length === 1 ? row.quantity : (delivery.allocations[row.key] ?? "")]))
  }));
}

function synchronizePrimaryLocation(current: DeliveryDraft[], rows: OrderItemDraft[], orderDate: string, locationKey: string) {
  if (!current.length) return [{ key: 1, date: orderDate, locationKey, allocations: Object.fromEntries(rows.map((row) => [row.key, row.quantity])) }];
  return current.map((delivery, index) => index === 0 ? { ...delivery, locationKey } : delivery);
}

function dateLabel(value: string) {
  if (!value) return "Data pendente";
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

function moneyFromCents(value: number | null) {
  return value === null ? "Pendente" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value / 100);
}

function moneyNullable(value: number | null) {
  return value === null ? "Não informado" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

function number(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}
