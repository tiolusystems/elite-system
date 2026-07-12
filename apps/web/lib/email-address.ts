export const EMAIL_ADDRESS_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const RESERVED_DOMAINS = new Set(["example.com", "example.net", "example.org"]);
const RESERVED_TLD_PATTERN = /(^|\.)(local|invalid|test)$/;

export function isReservedEmailAddress(email: string): boolean {
  const domain = email.split("@")[1]?.toLowerCase() ?? "";
  return RESERVED_TLD_PATTERN.test(domain) || RESERVED_DOMAINS.has(domain);
}
