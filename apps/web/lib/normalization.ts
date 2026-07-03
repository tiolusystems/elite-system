export function normalizeKey(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, " ")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, " ")
    .replace(/(\d)\s+([A-Z])/g, "$1$2");
}

export function normalizeUf(value: string): string {
  return value.trim().toUpperCase();
}
