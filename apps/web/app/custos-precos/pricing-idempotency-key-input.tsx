"use client";

import { useState } from "react";

export function PricingIdempotencyKeyInput() {
  const [key] = useState(() => crypto.randomUUID());

  return <input type="hidden" name="idempotency_key" value={key} />;
}
