type FormControlLike = { value: string };
type FormLike = { elements: { namedItem(name: string): unknown } };

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
