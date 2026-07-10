import { randomInt } from "crypto";

type SendTemporaryPasswordEmailInput = {
  displayName: string;
  email: string;
  temporaryPassword: string;
};

type MailResult =
  | { ok: true }
  | { ok: false; code: "temp_password_mailer_missing" | "temp_password_email_failed" };

const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnopqrstuvwxyz";
const DIGITS = "23456789";
const SYMBOLS = "!@#$%&*?";
const ALL = `${UPPER}${LOWER}${DIGITS}${SYMBOLS}`;

export function hasTemporaryPasswordMailerConfig(): boolean {
  return Boolean(process.env.ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL?.trim());
}

export function generateTemporaryPassword(length = 18): string {
  const required = [randomChar(UPPER), randomChar(LOWER), randomChar(DIGITS), randomChar(SYMBOLS)];
  const remaining = Array.from({ length: Math.max(length - required.length, 0) }, () => randomChar(ALL));
  return shuffle([...required, ...remaining]).join("");
}

export async function sendTemporaryPasswordEmail(input: SendTemporaryPasswordEmailInput): Promise<MailResult> {
  const endpoint = process.env.ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL?.trim();
  const token = process.env.ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_TOKEN?.trim();

  if (!endpoint) {
    return { ok: false, code: "temp_password_mailer_missing" };
  }

  const headers: Record<string, string> = {
    "content-type": "application/json"
  };
  if (token) {
    headers.authorization = `Bearer ${token}`;
  }

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify({
        type: "elite_temporary_password",
        email: input.email,
        displayName: input.displayName,
        temporaryPassword: input.temporaryPassword
      })
    });

    if (!response.ok) {
      return { ok: false, code: "temp_password_email_failed" };
    }

    return { ok: true };
  } catch {
    return { ok: false, code: "temp_password_email_failed" };
  }
}

function randomChar(alphabet: string): string {
  return alphabet[randomInt(0, alphabet.length)] ?? alphabet[0];
}

function shuffle(values: string[]): string[] {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const swapIndex = randomInt(0, index + 1);
    [values[index], values[swapIndex]] = [values[swapIndex] ?? "", values[index] ?? ""];
  }
  return values;
}
