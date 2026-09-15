"use client";

import { useEffect, useState } from "react";

export type OperationalFeedbackKind = "ok" | "warning" | "error";

type OperationalFeedbackProps = {
  kind: OperationalFeedbackKind;
  title: string;
  detail: string;
};

export function OperationalFeedback({ kind, title, detail }: OperationalFeedbackProps) {
  const [visible, setVisible] = useState(true);
  const isSuccess = kind === "ok";

  useEffect(() => {
    if (!isSuccess) return;
    const timeout = window.setTimeout(() => setVisible(false), 5000);
    return () => window.clearTimeout(timeout);
  }, [isSuccess]);

  if (!visible) return null;

  return (
    <section
      className={`operational-feedback ${kind}`}
      role={isSuccess ? "status" : "alert"}
      aria-live={isSuccess ? "polite" : "assertive"}
      aria-atomic="true"
    >
      <div>
        <strong>{title}</strong>
        <span>{detail}</span>
      </div>
      <button className="operational-feedback-close" type="button" onClick={() => setVisible(false)} aria-label="Fechar mensagem">
        <span aria-hidden="true">x</span>
      </button>
    </section>
  );
}
