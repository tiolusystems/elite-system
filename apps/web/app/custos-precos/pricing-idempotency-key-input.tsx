"use client";

export function PricingIdempotencyKeyInput({ value }: { value: string }) {
  return <input type="hidden" name="idempotency_key" value={value} />;
}
