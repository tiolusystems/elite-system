"use client";

import { cloneElement, useActionState, useEffect, useRef, useState, type FormEvent, type ReactElement, type ReactNode, type RefObject } from "react";
import { useRouter } from "next/navigation";

import {
  calculatePricingScenarioAction, createPricingPolicyAction, createPricingScenarioAction,
  reviewPricingCalculationAction, reviewPricingPolicyAction,
} from "./actions";
import { PricingIdempotencyKeyInput } from "./pricing-idempotency-key-input";
import { PRICING_COMPONENTS, percentageWarning, validateCalculation, validatePolicy, validateReview, validateScenario, type PricingFieldErrors, type PricingValidation } from "./pricing-form-validation";
import { readFormControlValue, writeFormControlValue } from "./pricing-form-dom";
import { INITIAL_PRICING_ACTION_STATE, normalizePricingActionState, type PricingActionState } from "./pricing-action-state";
import styles from "./pricing.module.css";

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

export function PricingPolicyForm({ policies }: { policies: SelectOption[] }) {
  const [method, setMethod] = useState("margem_liquida");
  const [policyId, setPolicyId] = useState("");
  const form = usePricingForm(createPricingPolicyAction, validatePolicy, () => { setMethod("margem_liquida"); setPolicyId(""); });
  const marginApplies = method === "margem_liquida";
  const isNewPolicy = policyId === "";

  return <form {...form.props} className={styles.pricingForm}>
    <PricingIdempotencyKeyInput value={form.requestKey} />
    <Field label="Politica" name="politica_id" error={form.error("politica_id")} wide help="Deixe como nova politica para o sistema emitir o proximo codigo.">
      <select name="politica_id" value={policyId} onChange={(event) => { setPolicyId(event.target.value); form.clear("politica_id"); }}>
        <option value="">Nova politica</option>{policies.map((policy) => <option key={policy.id} value={policy.id}>{policy.label}</option>)}
      </select>
    </Field>
    {isNewPolicy ? <Field label="Nome" name="nome" error={form.error("nome")} wide><input name="nome" placeholder="Politica comercial padrao" required /></Field> : <div className={styles.pricingPolicyIdentity}><strong>Nova versao da politica selecionada</strong><span>Codigo e nome sao definidos pelo sistema.</span></div>}
    <Field label="Metodo" name="metodo" error={form.error("metodo")}>
      <select name="metodo" value={method} onChange={(event) => { const next = event.target.value; setMethod(next); form.clear("metodo"); if (next === "margem_liquida") form.clearValue("markup"); else form.clearValue("lucro_minimo"); }}>
        <option value="margem_liquida">Margem liquida</option><option value="markup">Markup</option>
      </select>
    </Field>
    {marginApplies ? <Field label="Lucro minimo (%)" name="lucro_minimo" error={form.error("lucro_minimo")} help={percentageWarning(form.value("lucro_minimo")) ?? "Informe o percentual desejado. Ex.: 20 ou 20%."}>
      <input name="lucro_minimo" inputMode="decimal" placeholder="20" required />
    </Field> : <Field label="Markup (%)" name="markup" error={form.error("markup")} help={percentageWarning(form.value("markup")) ?? "Informe o percentual desejado. Ex.: 25 ou 25%."}>
      <input name="markup" inputMode="decimal" placeholder="25" required />
    </Field>}
    <Field label="Juros ao mes (%)" name="juros_mensais" error={form.error("juros_mensais")} help={percentageWarning(form.value("juros_mensais")) ?? "Aceita virgula ou ponto decimal. Ex.: 1,9 representa 1,9%."}>
      <input name="juros_mensais" inputMode="decimal" placeholder="1,9" required />
    </Field>
    <Field label="Motivo" name="motivo" error={form.error("motivo")} wide><input name="motivo" minLength={10} required placeholder="Explique a finalidade desta versao" /></Field>
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Submit pending={form.pending} ready={form.ready} idle="Criar versao" pendingLabel="Criando..." />
  </form>;
}

export function PricingScenarioForm({ policies, presentations }: { policies: SelectOption[]; presentations: SelectOption[] }) {
  const form = usePricingForm(createPricingScenarioAction, validateScenario);
  return <form {...form.props} className={styles.pricingForm}>
    <PricingIdempotencyKeyInput value={form.requestKey} />
    <Field label="Politica aprovada" name="politica_versao_id" error={form.error("politica_versao_id")} wide><select name="politica_versao_id" required defaultValue=""><option value="">Selecione</option>{policies.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></Field>
    <Field label="Produto e apresentacao" name="produto_embalagem_id" error={form.error("produto_embalagem_id")} wide><select name="produto_embalagem_id" required defaultValue=""><option value="">Selecione</option>{presentations.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></Field>
    <Field label="Nome do cenario" name="nome" error={form.error("nome")} wide><input name="nome" required placeholder="Cenario base para homologacao" /></Field>
    <Field label="Motivo" name="motivo" error={form.error("motivo")} wide><input name="motivo" minLength={10} required /></Field>
    <input type="hidden" name="source_kind" value="substituicao_manual" />
    <Field label="Origem" name="source_kind" error={form.error("source_kind")} help="A origem de sistema ainda nao esta disponivel."><input value="Substituicao manual" readOnly /></Field>
    <Field label="Referencia" name="source_reference" error={form.error("source_reference")}><input name="source_reference" required placeholder="SIMULACAO-001" /></Field>
    <Field label="Data da fonte" name="source_effective_date" error={form.error("source_effective_date")}><input name="source_effective_date" type="date" required /></Field>
    <Field label="Justificativa da fonte" name="source_reason" error={form.error("source_reason")} wide><input name="source_reason" minLength={10} required /></Field>
    <div className={styles.pricingComponents}>{PRICING_COMPONENTS.map(([name, unit]) => <Field key={name} label={COST_LABELS[name]} name={name} error={form.error(name)} help={unit === "FRACAO" ? percentageWarning(form.value(name)) ?? "Percentual. Ex.: 2 representa 2%." : "R$/L. Aceita virgula ou ponto decimal."}><input name={name} inputMode="decimal" required /></Field>)}</div>
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Submit pending={form.pending} ready={form.ready} idle="Congelar cenario" pendingLabel="Congelando..." />
  </form>;
}

export function PricingCalculationForm({ scenarioId }: { scenarioId: number }) {
  const form = usePricingForm(calculatePricingScenarioAction, validateCalculation);
  return <form {...form.props} className={styles.pricingInlineForm}>
    <PricingIdempotencyKeyInput value={form.requestKey} /><input type="hidden" name="cenario_id" value={scenarioId} />
    <Field label="Motivo do calculo" name="motivo" error={form.error("motivo")}><input name="motivo" minLength={10} required defaultValue="Calculo governado para revisao" /></Field>
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Submit pending={form.pending} ready={form.ready} idle="Calcular memoria" pendingLabel="Calculando..." secondary />
  </form>;
}

export function PricingReviewForm({ id, kind }: { id: number; kind: "policy" | "calculation" }) {
  const action = kind === "policy" ? reviewPricingPolicyAction : reviewPricingCalculationAction;
  const validator: Validator = (data) => validateReview(data, kind === "policy" ? "versao_id" : "calculo_id");
  const form = usePricingForm(action, validator);
  const idName = kind === "policy" ? "versao_id" : "calculo_id";
  return <form {...form.props} className={styles.pricingInlineForm}>
    <PricingIdempotencyKeyInput value={form.requestKey} /><input type="hidden" name={idName} value={id} />
    <Field label="Decisao" name="decisao" error={form.error("decisao")}><select name="decisao" defaultValue="APPROVED"><option value="APPROVED">Aprovar</option><option value="REJECTED">Rejeitar</option></select></Field>
    <Field label="Justificativa" name="justificativa" error={form.error("justificativa")}><input name="justificativa" minLength={10} required /></Field>
    <FormFeedback state={form.state} localMessage={form.localMessage} feedbackRef={form.feedbackRef} />
    <Submit pending={form.pending} ready={form.ready} idle="Registrar decisao" pendingLabel="Registrando..." />
  </form>;
}

function usePricingForm(action: PricingAction, validator: Validator, onSuccess?: () => void) {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const feedbackRef = useRef<HTMLElement>(null);
  const successRef = useRef(onSuccess);
  const [rawState, formAction, pending] = useActionState(action, INITIAL_PRICING_ACTION_STATE);
  const state = normalizePricingActionState(rawState);
  const [requestKey, setRequestKey] = useState("");
  const [ready, setReady] = useState(false);
  const [clientValidation, setClientValidation] = useState<ClientValidationState>({ resultId: "", fieldErrors: {}, message: "" });
  const [dismissedServerErrorState, setDismissedServerErrorState] = useState<DismissedServerErrorState>({ resultId: "", fields: {} });
  const [, setInputRevision] = useState(0);
  const clientErrors = clientValidation.resultId === state.resultId ? clientValidation.fieldErrors : {};
  const localMessage = clientValidation.resultId === state.resultId ? clientValidation.message : "";
  const dismissedServerErrors = dismissedServerErrorState.resultId === state.resultId ? dismissedServerErrorState.fields : {};
  const serverErrors = Object.fromEntries(Object.entries(state.fieldErrors ?? {}).filter(([name]) => !dismissedServerErrors[name]));
  const errors = { ...serverErrors, ...clientErrors };

  useEffect(() => { successRef.current = onSuccess; }, [onSuccess]);
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      setRequestKey(globalThis.crypto.randomUUID());
      setReady(true);
    });
    return () => window.cancelAnimationFrame(frame);
  }, []);
  useEffect(() => {
    if (state.status !== "error") return;
    restoreValues(formRef.current, state.values);
    const frame = window.requestAnimationFrame(() => revealFeedback(feedbackRef.current));
    return () => window.cancelAnimationFrame(frame);
  }, [state.resultId, state.status, state.values]);
  useEffect(() => {
    if (state.status !== "success") return;
    const frame = window.requestAnimationFrame(() => {
      formRef.current?.reset();
      setRequestKey(globalThis.crypto.randomUUID());
      successRef.current?.();
      router.refresh();
    });
    return () => window.cancelAnimationFrame(frame);
  }, [router, state.resultId, state.status]);

  function submit(event: FormEvent<HTMLFormElement>) {
    const validation = validator(new FormData(event.currentTarget));
    if (!Object.keys(validation.fieldErrors).length) return;
    event.preventDefault();
    setClientValidation({ resultId: state.resultId, fieldErrors: validation.fieldErrors, message: "Revise os campos destacados antes de continuar." });
  }

  return {
    state, requestKey, pending, ready, feedbackRef, localMessage,
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
    value: (name: string) => readFormControlValue(formRef.current, name),
    clear: (name: string) => setDismissedServerErrorState((current) => current.resultId === state.resultId ? { ...current, fields: { ...current.fields, [name]: true } } : { resultId: state.resultId, fields: { [name]: true } }),
    clearValue: (name: string) => writeFormControlValue(formRef.current, name, ""),
  };
}

function revealFeedback(feedback: HTMLElement | null) {
  if (!feedback) return;
  const bounds = feedback.getBoundingClientRect();
  if (bounds.top >= 0 && bounds.bottom <= window.innerHeight) return;
  feedback.focus({ preventScroll: true });
  feedback.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function restoreValues(form: HTMLFormElement | null, values: Record<string, string> | null | undefined) {
  if (!form) return;
  for (const [name, value] of Object.entries(values ?? {})) {
    writeFormControlValue(form, name, value);
  }
}

function FormFeedback({ state, localMessage, feedbackRef }: { state: PricingActionState; localMessage: string; feedbackRef: RefObject<HTMLElement | null> }) {
  const safeState = normalizePricingActionState(state);
  const isError = safeState.status === "error" || Boolean(localMessage);
  if (safeState.status === "idle" && !localMessage) return null;
  return <section ref={feedbackRef} tabIndex={-1} className={`${styles.pricingFeedback} ${isError ? styles.error : styles.success}`} role={isError ? "alert" : "status"} aria-live={isError ? "assertive" : "polite"}>
    <strong>{isError ? "Operacao nao concluida" : "Operacao concluida"}</strong><span>{localMessage || safeState.message}</span>{safeState.occurrenceId ? <small>Codigo de ocorrencia: {safeState.occurrenceId}</small> : null}
  </section>;
}

function Field({ label, name, error, help, wide = false, children }: { label: string; name: string; error?: string; help?: string | null; wide?: boolean; children: ReactNode }) {
  const helpId = `${name}-help`; const errorId = `${name}-error`;
  const child = children as ReactElement<{ "aria-invalid"?: boolean; "aria-describedby"?: string }>;
  return <label className={wide ? styles.pricingWide : undefined}>{label}
    {cloneElement(child, { "aria-invalid": Boolean(error), "aria-describedby": error ? errorId : help ? helpId : undefined })}
    {help ? <small id={helpId} className={styles.pricingHelp}>{help}</small> : null}
    {error ? <small id={errorId} className={styles.pricingFieldError}>{error}</small> : null}
  </label>;
}

function Submit({ pending, ready, idle, pendingLabel, secondary = false }: { pending: boolean; ready: boolean; idle: string; pendingLabel: string; secondary?: boolean }) {
  return <button className={`${secondary ? "secondary-button" : "primary-button"} ${styles.pricingSubmit}`} disabled={pending || !ready} aria-disabled={pending || !ready}>{pending ? pendingLabel : idle}</button>;
}
