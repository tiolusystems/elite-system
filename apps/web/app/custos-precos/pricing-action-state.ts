import type { PricingFieldErrors } from "./pricing-form-validation";

export type PricingActionState = {
  status: "idle" | "success" | "error";
  message: string;
  fieldErrors: PricingFieldErrors;
  values: Record<string, string>;
  resultId: string;
  occurrenceId: string | null;
};

export const INITIAL_PRICING_ACTION_STATE: PricingActionState = {
  status: "idle",
  message: "",
  fieldErrors: {},
  values: {},
  resultId: "",
  occurrenceId: null,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function normalizePricingActionState(value: unknown): PricingActionState {
  const candidate = isRecord(value) ? value : {};
  const rawFieldErrors = isRecord(candidate.fieldErrors) ? candidate.fieldErrors : {};
  const rawValues = isRecord(candidate.values) ? candidate.values : {};

  return {
    status: candidate.status === "success" || candidate.status === "error" ? candidate.status : "idle",
    message: typeof candidate.message === "string" ? candidate.message : "",
    fieldErrors: Object.fromEntries(Object.entries(rawFieldErrors).filter(([, error]) => typeof error === "string")) as PricingFieldErrors,
    values: Object.fromEntries(Object.entries(rawValues).map(([name, entry]) => [name, String(entry)])),
    resultId: typeof candidate.resultId === "string" ? candidate.resultId : "",
    occurrenceId: typeof candidate.occurrenceId === "string" ? candidate.occurrenceId : null,
  };
}
