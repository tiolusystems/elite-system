"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import {
  adjustCommissionAction,
  assignOrderCommissionAction,
  INITIAL_FINANCE_ACTION_STATE,
  payCommissionAction,
  registerReceiptAction,
  type FinanceActionState,
} from "@/app/pedidos/financeiro/actions";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import type { CommissionAccount, CommissionOrder, ReceiptOrder } from "@/lib/finance";

export function CommissionAssignmentForm({
  order,
  requestKey,
}: {
  order: CommissionOrder;
  requestKey: string;
}) {
  const router = useRouter();
  const [state, action, pending] = useActionState(assignOrderCommissionAction, INITIAL_FINANCE_ACTION_STATE);
  const [key, setKey] = useState(requestKey);
  const [role, setRole] = useState("vendedor");
  const [percentage, setPercentage] = useState("");
  const [reason, setReason] = useState("");
  const formRef = useFocusFirstError(state);

  useRefreshAfterSuccess(state, router.refresh, () => {
    setKey(crypto.randomUUID());
    setPercentage("");
    setReason("");
  });

  return (
    <form action={action} className="finance-operation-form" ref={formRef}>
      <input type="hidden" name="idempotency_key" value={key} />
      <input type="hidden" name="pedido_id" value={order.id} />
      <ActionFeedback state={state} />
      <div className="form-grid finance-form-grid">
        <div>
          <EntityLookup
            key={key}
            entity="pessoas"
            name="pessoa_id"
            label="Pessoa comissionada"
            placeholder="Abra a lista ou pesquise por nome"
            required
            helpText="A seleção mantém o vínculo pela pessoa cadastrada, não por texto livre."
          />
          <FieldError value={state.fieldErrors.pessoa_id} />
        </div>
        <label>
          Papel na comissão
          <select name="papel_comissao" value={role} onChange={(event) => setRole(event.target.value)} aria-invalid={Boolean(state.fieldErrors.papel_comissao)}>
            <option value="vendedor">Vendedor</option>
            <option value="agente">Agente</option>
            <option value="gerente">Gerente</option>
            <option value="outro">Outro</option>
          </select>
          <FieldError value={state.fieldErrors.papel_comissao} />
        </label>
        <label>
          Percentual
          <input name="percentual_comissao" inputMode="decimal" value={percentage} onChange={(event) => setPercentage(event.target.value)} min="0.0001" max="100" step="0.0001" aria-invalid={Boolean(state.fieldErrors.percentual_comissao)} required />
          <FieldError value={state.fieldErrors.percentual_comissao} />
        </label>
        <label className="wide-field">
          Justificativa
          <input name="justificativa" value={reason} onChange={(event) => setReason(event.target.value)} minLength={10} placeholder="Regra comercial aprovada para este pedido" aria-invalid={Boolean(state.fieldErrors.justificativa)} required />
          <FieldError value={state.fieldErrors.justificativa} />
        </label>
      </div>
      <div className="form-footer">
        <span>Usuários com alçada específica podem definir os comissionados após a liberação e antes do primeiro recebimento.</span>
        <button className="primary-button" disabled={pending}>{pending ? "Registrando..." : "Definir comissionado"}</button>
      </div>
    </form>
  );
}

export function ReceiptForm({ order, requestKey }: { order: ReceiptOrder; requestKey: string }) {
  const router = useRouter();
  const [state, action, pending] = useActionState(registerReceiptAction, INITIAL_FINANCE_ACTION_STATE);
  const [key, setKey] = useState(requestKey);
  const [value, setValue] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState("transferencia");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const formRef = useFocusFirstError(state);

  useRefreshAfterSuccess(state, router.refresh, () => {
    setKey(crypto.randomUUID());
    setValue("");
    setReference("");
    setNote("");
  });

  const numericValue = Number(value.replace(",", "."));
  const valueError = value && (!Number.isFinite(numericValue) || numericValue <= 0)
    ? "Informe um valor maior que zero."
    : numericValue > order.open
      ? "O valor não pode ultrapassar o saldo aberto."
      : undefined;
  const resultingBalance = Number.isFinite(numericValue) ? Math.max(order.open - numericValue, 0) : order.open;

  return (
    <form action={action} className="finance-operation-form" ref={formRef}>
      <input type="hidden" name="idempotency_key" value={key} />
      <input type="hidden" name="pedido_id" value={order.id} />
      <ActionFeedback state={state} />
      <div className="finance-confirmation-strip" aria-label="Prévia do recebimento">
        <span>Saldo anterior<strong>{money(order.open)}</strong></span>
        <span>Valor informado<strong>{money(Number.isFinite(numericValue) ? numericValue : 0)}</strong></span>
        <span>Saldo resultante<strong>{money(resultingBalance)}</strong></span>
      </div>
      <div className="form-grid finance-form-grid">
        <label>
          Valor recebido
          <input name="valor_recebido" inputMode="decimal" value={value} onChange={(event) => setValue(event.target.value)} min="0.01" max={order.open} step="0.01" aria-invalid={Boolean(state.fieldErrors.valor_recebido || valueError)} required />
          <FieldError value={state.fieldErrors.valor_recebido || valueError} />
        </label>
        <label>
          Data
          <input name="data_recebimento" type="date" value={date} onChange={(event) => setDate(event.target.value)} aria-invalid={Boolean(state.fieldErrors.data_recebimento)} required />
          <FieldError value={state.fieldErrors.data_recebimento} />
        </label>
        <label>
          Forma
          <select name="forma_recebimento" value={method} onChange={(event) => setMethod(event.target.value)}>
            <option value="transferencia">Transferência</option>
            <option value="pix">Pix</option>
            <option value="boleto">Boleto</option>
            <option value="cheque">Cheque</option>
            <option value="dinheiro">Dinheiro</option>
            <option value="outro">Outro</option>
          </select>
        </label>
        <label className="wide-field">
          Referência documental
          <input name="referencia_documental" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="Transação Pix, comprovante, boleto, cheque ou recibo" aria-invalid={Boolean(state.fieldErrors.referencia_documental)} required />
          <FieldError value={state.fieldErrors.referencia_documental} />
        </label>
        <label className="wide-field">
          Observação <span className="optional-label">opcional</span>
          <textarea name="observacao" value={note} onChange={(event) => setNote(event.target.value)} rows={3} placeholder="Informação complementar da conciliação" />
        </label>
      </div>
      <div className="form-footer">
        <span>O recebimento libera proporcionalmente a comissão. A referência fiscal, sozinha, não produz esse efeito.</span>
        <button className="primary-button" disabled={pending || Boolean(valueError) || !value}>{pending ? "Registrando..." : "Registrar recebimento"}</button>
      </div>
    </form>
  );
}

export function CommissionPaymentForm({ account, requestKey }: { account: CommissionAccount; requestKey: string }) {
  const router = useRouter();
  const [state, action, pending] = useActionState(payCommissionAction, INITIAL_FINANCE_ACTION_STATE);
  const [key, setKey] = useState(requestKey);
  const [value, setValue] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState("Pix");
  const [reference, setReference] = useState("");
  const formRef = useFocusFirstError(state);

  useRefreshAfterSuccess(state, router.refresh, () => {
    setKey(crypto.randomUUID());
    setValue("");
    setReference("");
  });

  const numericValue = Number(value.replace(",", "."));
  const valueError = value && (!Number.isFinite(numericValue) || numericValue <= 0)
    ? "Informe um valor maior que zero."
    : numericValue > account.balance
      ? "O pagamento não pode ultrapassar o saldo disponível."
      : undefined;
  return (
    <form action={action} className="finance-operation-form" ref={formRef}>
      <input type="hidden" name="idempotency_key" value={key} />
      <input type="hidden" name="pessoa_id" value={account.personId} />
      <ActionFeedback state={state} />
      <div className="finance-confirmation-strip">
        <span>Saldo anterior<strong>{money(account.balance)}</strong></span>
        <span>Valor pago<strong>{money(Number.isFinite(numericValue) ? numericValue : 0)}</strong></span>
        <span>Saldo resultante<strong>{money(Math.max(account.balance - (Number.isFinite(numericValue) ? numericValue : 0), 0))}</strong></span>
      </div>
      <div className="form-grid finance-form-grid">
        <label>Valor pago<input name="valor_pago" inputMode="decimal" value={value} onChange={(event) => setValue(event.target.value)} min="0.01" max={account.balance} step="0.01" aria-invalid={Boolean(state.fieldErrors.valor_pago || valueError)} required /><FieldError value={state.fieldErrors.valor_pago || valueError} /></label>
        <label>Data<input name="data_pagamento" type="date" value={date} onChange={(event) => setDate(event.target.value)} aria-invalid={Boolean(state.fieldErrors.data_pagamento)} required /><FieldError value={state.fieldErrors.data_pagamento} /></label>
        <label>Forma de pagamento<input name="forma_pagamento" value={method} onChange={(event) => setMethod(event.target.value)} /></label>
        <label className="wide-field">Referência do pagamento<input name="referencia_pagamento" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="Lote de pagamento ou comprovante" /></label>
      </div>
      <div className="form-footer"><span>Nunca é permitido pagar acima do saldo.</span><button className="primary-button" disabled={pending || Boolean(valueError) || !value}>{pending ? "Registrando..." : "Registrar pagamento"}</button></div>
    </form>
  );
}

export function CommissionAdjustmentForm({ account, requestKey }: { account: CommissionAccount; requestKey: string }) {
  const router = useRouter();
  const [state, action, pending] = useActionState(adjustCommissionAction, INITIAL_FINANCE_ACTION_STATE);
  const [key, setKey] = useState(requestKey);
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("correcao_calculo");
  const [detail, setDetail] = useState("");
  const formRef = useFocusFirstError(state);

  useRefreshAfterSuccess(state, router.refresh, () => {
    setKey(crypto.randomUUID());
    setValue("");
    setDetail("");
  });

  return (
    <form action={action} className="finance-operation-form" ref={formRef}>
      <input type="hidden" name="idempotency_key" value={key} />
      <input type="hidden" name="pessoa_id" value={account.personId} />
      <ActionFeedback state={state} />
      <div className="form-grid finance-form-grid">
        <label>Valor do ajuste<input name="valor_ajuste" inputMode="decimal" value={value} onChange={(event) => setValue(event.target.value)} step="0.01" placeholder="Positivo ou negativo" aria-invalid={Boolean(state.fieldErrors.valor_ajuste)} required /><FieldError value={state.fieldErrors.valor_ajuste} /></label>
        <label>Motivo<select name="motivo_codigo" value={reason} onChange={(event) => setReason(event.target.value)}><option value="correcao_calculo">Correção de cálculo</option><option value="estorno_devolucao">Estorno por devolução</option><option value="acordo_comercial">Acordo comercial</option><option value="compensacao_futura">Compensação futura</option><option value="outro">Outro</option></select></label>
        <label className="wide-field">Detalhamento<input name="motivo_detalhe" value={detail} onChange={(event) => setDetail(event.target.value)} minLength={10} placeholder="Explique por que o ajuste excepcional é necessário" aria-invalid={Boolean(state.fieldErrors.motivo_detalhe)} required /><FieldError value={state.fieldErrors.motivo_detalhe} /></label>
      </div>
      <div className="form-footer"><span>O ajuste cria um novo movimento e não altera o histórico anterior.</span><button className="secondary-button" disabled={pending}>{pending ? "Registrando..." : "Registrar ajuste"}</button></div>
    </form>
  );
}

function ActionFeedback({ state }: { state: FinanceActionState }) {
  if (state.status === "idle") return null;
  return <div className={`notice-panel ${state.status === "success" ? "success" : "warning"}`} role={state.status === "error" ? "alert" : "status"}><strong>{state.status === "success" ? "Operação concluída" : "Não foi possível concluir"}</strong><span>{state.message}</span></div>;
}

function FieldError({ value }: { value?: string }) {
  return value ? <small className="field-error">{value}</small> : null;
}

function useRefreshAfterSuccess(state: FinanceActionState, refresh: () => void, reset: () => void) {
  const refreshRef = useRef(refresh);
  const resetRef = useRef(reset);
  useEffect(() => {
    refreshRef.current = refresh;
    resetRef.current = reset;
  }, [refresh, reset]);
  useEffect(() => {
    if (state.status !== "success") return;
    resetRef.current();
    refreshRef.current();
  }, [state.status, state.resultId]);
}

function useFocusFirstError(state: FinanceActionState) {
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state.status !== "error") return;
    formRef.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus();
  }, [state.resultId, state.status]);
  return formRef;
}

function money(value: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}
