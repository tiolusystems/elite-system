type FormControlLike = { value: string };
type FormLike = { elements: { namedItem(name: string): unknown } };
type FeedbackLike = {
  getBoundingClientRect(): { top: number; bottom: number };
  focus(options?: FocusOptions): void;
  scrollIntoView(options?: ScrollIntoViewOptions): void;
};

function isFormControl(value: unknown): value is FormControlLike {
  return typeof value === "object" && value !== null && "value" in value && typeof value.value === "string";
}

export function readFormControlValue(form: FormLike | null | undefined, name: string): string {
  const control = form?.elements.namedItem(name);
  return isFormControl(control) ? control.value : "";
}

export function writeFormControlValue(form: FormLike | null | undefined, name: string, value: string) {
  const control = form?.elements.namedItem(name);
  if (isFormControl(control)) control.value = value;
}

export function revealPricingFeedback(feedback: FeedbackLike | null | undefined, viewportHeight: number): boolean {
  if (!feedback) return false;
  const bounds = feedback.getBoundingClientRect();
  if (bounds.top >= 0 && bounds.bottom <= viewportHeight) return false;
  feedback.focus({ preventScroll: true });
  feedback.scrollIntoView({ behavior: "smooth", block: "nearest" });
  return true;
}
