"use client";

import { cloneElement, useActionState, useEffect, useRef, useState, type FormEvent, type ReactElement, type ReactNode, type RefObject } from "react";
import { useRouter } from "next/navigation";

import {
  calculatePricingScenarioAction, createPricingPolicyAction, createPricingScenarioAction, INITIAL_PRICING_ACTION_STATE,
  reviewPricingCalculationAction, reviewPricingPolicyAction, type PricingActionState,
} from "./actions";
import { PricingIdempotencyKeyInput } from "./pricing-idempotency-key-input";
import { PRICING_COMPONENTS, percentageWarning, validateCalculation, validatePolicy, validateReview, validateScenario, type PricingFieldErrors, type PricingValidation } from "./pricing-form-validation";

type PricingAction = (previous: PricingActionState, formData: FormData) => Promise<PricingActionState>;
type Validator = (formData: FormData) => PricingValidation<unknown>;
type SelectOption = { id: number; label: string };
type ClientValidationState = { resultId: string; fieldErrors: PricingFieldErrors; message: string };
type DismissedServerErrorState = { resultId: string; fields: Record<string, true> };

const COST_LABELS: Record<string, string> = {
  materia_prima: "Materia-prima", embalagem: "Embalagem", custo_pontuacao_vendedor: "Pontuacao do vendedor",
  custo_pontuacao_revenda: "Pontuacao da revenda", premiacao_revenda: "Premiacao da revenda", premio_producao: "Premio de producao",
  frete: "Frete", comissao: "Comissao", risco: "Risco", marketing: "Marketing", tributacao: "Tributacao",
};

export function PricingPolicyForm() {
  const [method, setMethod] = useState("margem_liquida");
  const form = usePricingForm(createPricingPolicyAction, validatePolicy, () => setMethod("margem_liquida"));
  const marginApplies = method === "margem_liquida";

  return <form {...form.props} className="pricing-form">
    <PricingIdempotencyKeyInput value={form.requestKey} />
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Field label="Codigo" name="codigo" error={form.error("codigo")}><input name="codigo" placeholder="POL-MARGEM-01" required /></Field>
    <Field label="Nome" name="nome" error={form.error("nome")} wide><input name="nome" placeholder="Politica comercial padrao" required /></Field>
    <Field label="Metodo" name="metodo" error={form.error("metodo")}>
      <select name="metodo" value={method} onChange={(event) => { const next = event.target.value; setMethod(next); form.clear("metodo"); if (next === "margem_liquida") form.clearValue("markup"); else form.clearValue("lucro_minimo"); }}>
        <option value="margem_liquida">Margem liquida</option><option value="markup">Markup</option>
      </select>
    </Field>
    <Field label="Lucro minimo (%)" name="lucro_minimo" error={form.error("lucro_minimo")} help={marginApplies ? percentageWarning(form.value("lucro_minimo")) ?? "Informe o percentual desejado. Ex.: 20 representa 20%." : "Nao se aplica ao metodo Markup."} notApplicable={!marginApplies}>
      <input name="lucro_minimo" inputMode="decimal" placeholder="20" disabled={!marginApplies} required={marginApplies} />
    </Field>
    <Field label="Markup (%)" name="markup" error={form.error("markup")} help={!marginApplies ? percentageWarning(form.value("markup")) ?? "Informe o percentual desejado. Ex.: 25 representa 25%." : "Nao se aplica ao metodo Margem liquida."} notApplicable={marginApplies}>
      <input name="markup" inputMode="decimal" placeholder="25" disabled={marginApplies} required={!marginApplies} />
    </Field>
    <Field label="Juros ao mes (%)" name="juros_mensais" error={form.error("juros_mensais")} help={percentageWarning(form.value("juros_mensais")) ?? "Aceita virgula ou ponto decimal. Ex.: 1,9 representa 1,9%."}>
      <input name="juros_mensais" inputMode="decimal" placeholder="1,9" required />
    </Field>
    <Field label="Motivo" name="motivo" error={form.error("motivo")} wide><input name="motivo" minLength={10} required placeholder="Explique a finalidade desta versao" /></Field>
    <Submit pending={form.pending} idle="Criar versao" pendingLabel="Criando..." />
  </form>;
}

export function PricingScenarioForm({ policies, presentations }: { policies: SelectOption[]; presentations: SelectOption[] }) {
  const form = usePricingForm(createPricingScenarioAction, validateScenario);
  return <form {...form.props} className="pricing-form">
    <PricingIdempotencyKeyInput value={form.requestKey} />
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Field label="Politica aprovada" name="politica_versao_id" error={form.error("politica_versao_id")} wide><select name="politica_versao_id" required defaultValue=""><option value="">Selecione</option>{policies.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></Field>
    <Field label="Produto e apresentacao" name="produto_embalagem_id" error={form.error("produto_embalagem_id")} wide><select name="produto_embalagem_id" required defaultValue=""><option value="">Selecione</option>{presentations.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></Field>
    <Field label="Nome do cenario" name="nome" error={form.error("nome")} wide><input name="nome" required placeholder="Cenario base para homologacao" /></Field>
    <Field label="Motivo" name="motivo" error={form.error("motivo")} wide><input name="motivo" minLength={10} required /></Field>
    <input type="hidden" name="source_kind" value="substituicao_manual" />
    <Field label="Origem" name="source_kind" error={form.error("source_kind")} help="A origem de sistema ainda nao esta disponivel."><input value="Substituicao manual" readOnly /></Field>
    <Field label="Referencia" name="source_reference" error={form.error("source_reference")}><input name="source_reference" required placeholder="SIMULACAO-001" /></Field>
    <Field label="Data da fonte" name="source_effective_date" error={form.error("source_effective_date")}><input name="source_effective_date" type="date" required /></Field>
    <Field label="Justificativa da fonte" name="source_reason" error={form.error("source_reason")} wide><input name="source_reason" minLength={10} required /></Field>
    <div className="pricing-components">{PRICING_COMPONENTS.map(([name, unit]) => <Field key={name} label={COST_LABELS[name]} name={name} error={form.error(name)} help={unit === "FRACAO" ? percentageWarning(form.value(name)) ?? "Percentual. Ex.: 2 representa 2%." : "R$/L. Aceita virgula ou ponto decimal."}><input name={name} inputMode="decimal" required /></Field>)}</div>
    <Submit pending={form.pending} idle="Congelar cenario" pendingLabel="Congelando..." />
  </form>;
}

export function PricingCalculationForm({ scenarioId }: { scenarioId: number }) {
  const form = usePricingForm(calculatePricingScenarioAction, validateCalculation);
  return <form {...form.props} className="pricing-inline-form">
    <PricingIdempotencyKeyInput value={form.requestKey} /><input type="hidden" name="cenario_id" value={scenarioId} />
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Field label="Motivo do calculo" name="motivo" error={form.error("motivo")}><input name="motivo" minLength={10} required defaultValue="Calculo governado para revisao" /></Field>
    <Submit pending={form.pending} idle="Calcular memoria" pendingLabel="Calculando..." secondary />
  </form>;
}

export function PricingReviewForm({ id, kind }: { id: number; kind: "policy" | "calculation" }) {
  const action = kind === "policy" ? reviewPricingPolicyAction : reviewPricingCalculationAction;
  const validator: Validator = (data) => validateReview(data, kind === "policy" ? "versao_id" : "calculo_id");
  const form = usePricingForm(action, validator);
  const idName = kind === "policy" ? "versao_id" : "calculo_id";
  return <form {...form.props} className="pricing-inline-form">
    <PricingIdempotencyKeyInput value={form.requestKey} /><input type="hidden" name={idName} value={id} />
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Field label="Decisao" name="decisao" error={form.error("decisao")}><select name="decisao" defaultValue="APPROVED"><option value="APPROVED">Aprovar</option><option value="REJECTED">Rejeitar</option></select></Field>
    <Field label="Justificativa" name="justificativa" error={form.error("justificativa")}><input name="justificativa" minLength={10} required /></Field>
    <Submit pending={form.pending} idle="Registrar decisao" pendingLabel="Registrando..." />
  </form>;
}

function usePricingForm(action: PricingAction, validator: Validator, onSuccess?: () => void) {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const feedbackRef = useRef<HTMLElement>(null);
  const successRef = useRef(onSuccess);
  const [state, formAction, pending] = useActionState(action, INITIAL_PRICING_ACTION_STATE);
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());
  const [clientValidation, setClientValidation] = useState<ClientValidationState>({ resultId: "", fieldErrors: {}, message: "" });
  const [dismissedServerErrorState, setDismissedServerErrorState] = useState<DismissedServerErrorState>({ resultId: "", fields: {} });
  const [, setInputRevision] = useState(0);
  const clientErrors = clientValidation.resultId === state.resultId ? clientValidation.fieldErrors : {};
  const localMessage = clientValidation.resultId === state.resultId ? clientValidation.message : "";
  const dismissedServerErrors = dismissedServerErrorState.resultId === state.resultId ? dismissedServerErrorState.fields : {};
  const serverErrors = Object.fromEntries(Object.entries(state.fieldErrors).filter(([name]) => !dismissedServerErrors[name]));
  const errors = { ...serverErrors, ...clientErrors };

  useEffect(() => { successRef.current = onSuccess; }, [onSuccess]);
  useEffect(() => {
    if (state.status !== "error") return;
    restoreValues(formRef.current, state.values);
    requestAnimationFrame(() => focusProblem(formRef.current, feedbackRef.current));
  }, [state.resultId, state.status, state.values]);
  useEffect(() => {
    if (state.status !== "success") return;
    const frame = requestAnimationFrame(() => {
      formRef.current?.reset();
      setRequestKey(crypto.randomUUID());
      successRef.current?.();
      router.refresh();
    });
    return () => cancelAnimationFrame(frame);
  }, [router, state.resultId, state.status]);

  function submit(event: FormEvent<HTMLFormElement>) {
    const validation = validator(new FormData(event.currentTarget));
    if (!Object.keys(validation.fieldErrors).length) return;
    event.preventDefault();
    setClientValidation({ resultId: state.resultId, fieldErrors: validation.fieldErrors, message: "Revise os campos destacados antes de continuar." });
    requestAnimationFrame(() => focusProblem(formRef.current, feedbackRef.current));
  }

  return {
    state, requestKey, pending, feedbackRef, localMessage,
    props: { action: formAction, noValidate: true, onSubmit: submit, ref: formRef, onInput: (event: FormEvent<HTMLFormElement>) => {
      const name = (event.target as HTMLInputElement).name;
      setInputRevision((value) => value + 1);
      if (state.fieldErrors[name]) setDismissedServerErrorState((current) => current.resultId === state.resultId ? { ...current, fields: { ...current.fields, [name]: true } } : { resultId: state.resultId, fields: { [name]: true } });
      if (!clientErrors[name]) return;
      setClientValidation((current) => {
        if (current.resultId !== state.resultId) return current;
        const fieldErrors = { ...current.fieldErrors }; delete fieldErrors[name];
        return { ...current, fieldErrors };
      });
    } },
    error: (name: string) => errors[name],
    value: (name: string) => { const input = formRef.current?.elements.namedItem(name); return input instanceof HTMLInputElement ? input.value : ""; },
    clear: (name: string) => setDismissedServerErrorState((current) => current.resultId === state.resultId ? { ...current, fields: { ...current.fields, [name]: true } } : { resultId: state.resultId, fields: { [name]: true } }),
    clearValue: (name: string) => { const input = formRef.current?.elements.namedItem(name); if (input instanceof HTMLInputElement) input.value = ""; },
  };
}

function focusProblem(form: HTMLFormElement | null, feedback: HTMLElement | null) {
  const target = form?.querySelector<HTMLElement>("[aria-invalid='true']") ?? feedback;
  target?.focus({ preventScroll: true });
  target?.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function restoreValues(form: HTMLFormElement | null, values: Record<string, string>) {
  if (!form) return;
  for (const [name, value] of Object.entries(values)) {
    const input = form.elements.namedItem(name);
    if (input instanceof HTMLInputElement || input instanceof HTMLSelectElement) input.value = value;
  }
}

function FormFeedback({ state, localMessage, feedbackRef }: { state: PricingActionState; localMessage: string; feedbackRef: RefObject<HTMLElement | null> }) {
  const isError = state.status === "error" || Boolean(localMessage);
  if (state.status === "idle" && !localMessage) return null;
  return <section ref={feedbackRef} tabIndex={-1} className={`pricing-feedback ${isError ? "error" : "success"}`} role={isError ? "alert" : "status"} aria-live={isError ? "assertive" : "polite"}>
    <strong>{isError ? "Operacao nao concluida" : "Operacao concluida"}</strong><span>{localMessage || state.message}</span>{state.occurrenceId ? <small>Codigo de ocorrencia: {state.occurrenceId}</small> : null}
  </section>;
}

function Field({ label, name, error, help, wide = false, notApplicable = false, children }: { label: string; name: string; error?: string; help?: string | null; wide?: boolean; notApplicable?: boolean; children: ReactNode }) {
  const helpId = `${name}-help`; const errorId = `${name}-error`;
  const child = children as ReactElement<{ "aria-invalid"?: boolean; "aria-describedby"?: string }>;
  return <label className={`${wide ? "pricing-wide" : ""} ${notApplicable ? "pricing-not-applicable" : ""}`}>{label}
    {cloneElement(child, { "aria-invalid": Boolean(error), "aria-describedby": error ? errorId : help ? helpId : undefined })}
    {help ? <small id={helpId} className="pricing-help">{help}</small> : null}
    {error ? <small id={errorId} className="pricing-field-error">{error}</small> : null}
  </label>;
}

function Submit({ pending, idle, pendingLabel, secondary = false }: { pending: boolean; idle: string; pendingLabel: string; secondary?: boolean }) {
  return <button className={secondary ? "secondary-button" : "primary-button"} disabled={pending} aria-disabled={pending}>{pending ? pendingLabel : idle}</button>;
}
