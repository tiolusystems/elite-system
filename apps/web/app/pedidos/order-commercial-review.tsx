"use client";

import type { OrderItemDraft } from "@/app/pedidos/order-items-editor";

export type CommercialReviewPreview = {
  previewHash: string;
  complete: boolean;
  pmpDays: number;
  items: CommercialReviewItem[];
  totals: {
    reference: number;
    practiced: number | null;
    grossDiscount: number | null;
    grossOverprice: number | null;
    netResult: number | null;
    netPercentage: number | null;
  };
};

type CommercialReviewItem = {
  index: number;
  productName: string;
  presentationCode: string;
  packagingName: string;
  pricingUnit: string;
  factor: number;
  commercialQuantity: number;
  referenceUnitPrice: number;
  practicedUnitPrice: number | null;
  differenceUnitPrice: number | null;
  differencePercentage: number | null;
  referenceValue: number;
  practicedValue: number | null;
  financialImpact: number | null;
  classification: string | null;
};

type Props = {
  rows: OrderItemDraft[];
  preview: CommercialReviewPreview | null;
  stale: boolean;
  loading: boolean;
  error: string | null;
  canPreview: boolean;
  justification: string;
  discountsConfirmed: boolean;
  onPriceChange: (key: number, value: string) => void;
  onJustificationChange: (value: string) => void;
  onDiscountsConfirmedChange: (value: boolean) => void;
  onCalculate: () => void;
};

export function OrderCommercialReview({
  rows,
  preview,
  stale,
  loading,
  error,
  canPreview,
  justification,
  discountsConfirmed,
  onPriceChange,
  onJustificationChange,
  onDiscountsConfirmedChange,
  onCalculate
}: Props) {
  const hasDiscount = preview?.items.some((item) => item.classification === "BELOW_REFERENCE") ?? false;

  return (
    <fieldset className="order-commercial-review">
      <legend>5. Revisão comercial</legend>
      <p className="section-intro">O banco resolve a referência, a unidade comercial e todos os valores da comparação. Alterações exigem novo cálculo.</p>

      {!canPreview ? (
        <div className="notice-panel warning">
          <strong>Revisão comercial indisponível para esta conta</strong>
          <span>Solicite à Segurança a alçada individual para previsualizar condições comerciais.</span>
        </div>
      ) : null}

      {preview ? (
        <div className="commercial-review-items">
          {preview.items.map((item) => {
            const row = rows[item.index - 1];
            return (
              <article key={`${item.index}-${item.presentationCode}`} className={classificationClass(item.classification)}>
                <header>
                  <div>
                    <strong>{item.productName}</strong>
                    <span>{item.presentationCode} · {item.packagingName}</span>
                  </div>
                  <span className="commercial-classification">{classificationLabel(item.classification)}</span>
                </header>
                <dl>
                  <div><dt>Quantidade</dt><dd>{number(item.commercialQuantity)} {item.pricingUnit}</dd></div>
                  <div><dt>Fator comercial</dt><dd>{number(item.factor)} {item.pricingUnit} por apresentação</dd></div>
                  <div><dt>Referência</dt><dd>{moneyFromCents(item.referenceUnitPrice)} por {item.pricingUnit}</dd></div>
                  <div><dt>Valor de referência</dt><dd>{moneyFromCents(item.referenceValue)}</dd></div>
                </dl>
                <label>
                  <span>Preço praticado por {item.pricingUnit}</span>
                  <input
                    inputMode="decimal"
                    placeholder="0,00"
                    value={row?.practicedPrice ?? ""}
                    onChange={(event) => row && onPriceChange(row.key, event.target.value)}
                    aria-label={`Preço praticado do item ${item.index} por ${item.pricingUnit}`}
                  />
                </label>
                {item.practicedUnitPrice !== null ? (
                  <div className="commercial-item-result">
                    <span>Praticado: <strong>{moneyFromCents(item.practicedUnitPrice)} por {item.pricingUnit}</strong></span>
                    <span>Diferença: <strong>{signedMoneyFromCents(item.differenceUnitPrice)}</strong></span>
                    <span>Percentual: <strong>{signedPercentage(item.differencePercentage)}</strong></span>
                    <span>Impacto financeiro: <strong>{signedMoneyFromCents(item.financialImpact)}</strong></span>
                  </div>
                ) : <small>Informe o preço praticado e calcule novamente.</small>}
              </article>
            );
          })}
        </div>
      ) : (
        <div className="empty-state compact">
          <strong>Referências ainda não calculadas</strong>
          <span>Complete itens, entregas e condição financeira para consultar as referências aplicáveis.</span>
        </div>
      )}

      {preview?.complete ? (
        <section className="commercial-order-summary" aria-label="Resultado comercial do pedido">
          <div><span>Total de referência</span><strong>{moneyFromCents(preview.totals.reference)}</strong></div>
          <div><span>Total praticado</span><strong>{moneyFromCents(preview.totals.practiced)}</strong></div>
          <div><span>Descontos brutos</span><strong>{moneyFromCents(preview.totals.grossDiscount)}</strong></div>
          <div><span>Acima da referência</span><strong>{moneyFromCents(preview.totals.grossOverprice)}</strong></div>
          <div><span>Resultado líquido</span><strong>{signedMoneyFromCents(preview.totals.netResult)}</strong></div>
          <div><span>Percentual líquido ponderado</span><strong>{signedPercentage(preview.totals.netPercentage)}</strong></div>
        </section>
      ) : null}

      {hasDiscount ? (
        <section className="commercial-discount-warning" role="alert">
          <strong>Este pedido contém item abaixo da referência</strong>
          <span>A solicitação de desconto permanece obrigatória mesmo quando o resultado líquido total é positivo.</span>
          <label>
            <span>Justificativa comercial do pedido</span>
            <textarea name="justificativa_comercial" rows={3} minLength={10} value={justification} onChange={(event) => onJustificationChange(event.target.value)} />
          </label>
          <label className="order-confirmation">
            <input name="confirmacao_descontos" type="checkbox" checked={discountsConfirmed} onChange={(event) => onDiscountsConfirmedChange(event.target.checked)} />
            <span>Confirmo que estou solicitando os descontos apresentados.</span>
          </label>
        </section>
      ) : null}

      {stale ? <p className="commercial-preview-stale">A proposta mudou. Calcule novamente antes de confirmar.</p> : null}
      {error ? <p className="field-error" role="alert">{error}</p> : null}
      <div className="commercial-review-actions">
        <span>{preview ? `PMP calculado: ${number(preview.pmpDays)} dias` : "O cálculo não grava rascunho nem cria pedido."}</span>
        <button type="button" className="secondary-button" onClick={onCalculate} disabled={!canPreview || loading}>
          {loading ? "Calculando..." : preview ? "Recalcular condições" : "Calcular referências"}
        </button>
      </div>
    </fieldset>
  );
}

export function parseCommercialReviewPreview(value: Record<string, unknown>): CommercialReviewPreview | null {
  const items = Array.isArray(value.itens) ? value.itens.map(asRecord) : [];
  const totals = asRecord(value.totais);
  const previewHash = typeof value.preview_hash === "string" ? value.preview_hash : "";
  if (!/^[0-9a-f]{64}$/.test(previewHash) || !items.length) return null;
  return {
    previewHash,
    complete: value.complete_for_confirmation === true,
    pmpDays: numeric(value.pmp_dias),
    items: items.map((item) => ({
      index: numeric(item.item_index),
      productName: text(item.produto_nome, "Produto"),
      presentationCode: text(item.apresentacao_codigo, "Apresentação"),
      packagingName: text(item.embalagem_nome, "Embalagem"),
      pricingUnit: text(item.unidade_precificacao_simbolo, text(item.unidade_precificacao_codigo, "un")),
      factor: numeric(item.quantidade_unidade_precificacao_por_apresentacao),
      commercialQuantity: numeric(item.quantidade_unidade_precificacao),
      referenceUnitPrice: numeric(item.preco_referencia_centavos_por_unidade_precificacao),
      practicedUnitPrice: nullableNumeric(item.preco_praticado_centavos_por_unidade_precificacao),
      differenceUnitPrice: nullableNumeric(item.diferenca_centavos_por_unidade_precificacao),
      differencePercentage: nullableNumeric(item.percentual_diferenca),
      referenceValue: numeric(item.valor_referencia_centavos),
      practicedValue: nullableNumeric(item.valor_praticado_centavos),
      financialImpact: nullableNumeric(item.impacto_financeiro_centavos),
      classification: typeof item.classificacao === "string" ? item.classificacao : null
    })),
    totals: {
      reference: numeric(totals.total_referencia_centavos),
      practiced: nullableNumeric(totals.total_praticado_centavos),
      grossDiscount: nullableNumeric(totals.descontos_brutos_centavos),
      grossOverprice: nullableNumeric(totals.overprice_bruto_centavos),
      netResult: nullableNumeric(totals.resultado_liquido_centavos),
      netPercentage: nullableNumeric(totals.percentual_resultado_liquido)
    }
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function numeric(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableNumeric(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function text(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value : fallback;
}

function classificationLabel(value: string | null) {
  return ({
    BELOW_REFERENCE: "Abaixo da referência",
    AT_REFERENCE: "Na referência",
    ABOVE_REFERENCE: "Acima da referência"
  } as Record<string, string>)[value ?? ""] ?? "Aguardando preço";
}

function classificationClass(value: string | null) {
  return ({
    BELOW_REFERENCE: "is-below",
    AT_REFERENCE: "is-at",
    ABOVE_REFERENCE: "is-above"
  } as Record<string, string>)[value ?? ""] ?? "is-pending";
}

function moneyFromCents(value: number | null) {
  if (value === null) return "Pendente";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value / 100);
}

function signedMoneyFromCents(value: number | null) {
  if (value === null) return "Pendente";
  const formatted = moneyFromCents(Math.abs(value));
  return value > 0 ? `+${formatted}` : value < 0 ? `-${formatted}` : formatted;
}

function signedPercentage(value: number | null) {
  if (value === null) return "Pendente";
  const formatted = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Math.abs(value));
  return `${value > 0 ? "+" : value < 0 ? "-" : ""}${formatted}%`;
}

function number(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}
