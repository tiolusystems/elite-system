"use client";

export type PaymentInstallmentDraft = {
  key: number;
  paymentMethod: "boleto" | "pix" | "ted" | "cessao_credito";
  amount: string;
  dueDate: string;
};

type Props = {
  installments: PaymentInstallmentDraft[];
  orderDate: string;
  onChange: (installments: PaymentInstallmentDraft[]) => void;
};

export function OrderPaymentTermsEditor({ installments, orderDate, onChange }: Props) {
  function change(key: number, field: keyof Omit<PaymentInstallmentDraft, "key">, value: string) {
    onChange(installments.map((installment) => installment.key === key
      ? { ...installment, [field]: value }
      : installment
    ));
  }

  function add() {
    onChange([...installments, {
      key: Math.max(...installments.map((installment) => installment.key), 0) + 1,
      paymentMethod: "boleto",
      amount: "",
      dueDate: orderDate
    }]);
  }

  function remove(key: number) {
    onChange(installments.filter((installment) => installment.key !== key));
  }

  return (
    <fieldset className="order-payment-editor">
      <legend>Condição financeira</legend>
      <p className="section-intro">Informe os valores absolutos e os vencimentos. O prazo médio é calculado pelo banco a partir da data do pedido.</p>
      <div className="order-payment-list">
        {installments.map((installment, index) => (
          <article key={installment.key}>
            <strong>Parcela {index + 1}</strong>
            <label>
              <span>Forma de pagamento</span>
              <select value={installment.paymentMethod} onChange={(event) => change(installment.key, "paymentMethod", event.target.value)}>
                <option value="boleto">Boleto</option>
                <option value="pix">PIX</option>
                <option value="ted">TED</option>
                <option value="cessao_credito">Cessão de crédito</option>
              </select>
            </label>
            <label>
              <span>Valor da parcela</span>
              <input inputMode="decimal" placeholder="0,00" value={installment.amount} onChange={(event) => change(installment.key, "amount", event.target.value)} />
            </label>
            <label>
              <span>Vencimento</span>
              <input type="date" min={orderDate} value={installment.dueDate} onChange={(event) => change(installment.key, "dueDate", event.target.value)} />
            </label>
            <button type="button" className="icon-button" title="Remover parcela" aria-label={`Remover parcela ${index + 1}`} disabled={installments.length === 1} onClick={() => remove(installment.key)}>X</button>
          </article>
        ))}
      </div>
      <button type="button" className="secondary-button" onClick={add}>Adicionar parcela</button>
    </fieldset>
  );
}
