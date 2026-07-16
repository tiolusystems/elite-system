"use client";

import { useId, useState } from "react";

type PasswordInputProps = {
  autoComplete: "current-password" | "new-password";
  label: string;
  minLength?: number;
  name: string;
};

export function PasswordInput({ autoComplete, label, minLength, name }: PasswordInputProps) {
  const id = useId();
  const [visible, setVisible] = useState(false);

  return (
    <label htmlFor={id}>
      {label}
      <span className="auth-password-control">
        <input
          id={id}
          name={name}
          type={visible ? "text" : "password"}
          autoComplete={autoComplete}
          minLength={minLength}
          required
        />
        <button
          className="auth-password-toggle"
          type="button"
          aria-controls={id}
          aria-pressed={visible}
          onClick={() => setVisible((current) => !current)}
        >
          {visible ? "Ocultar" : "Mostrar"}
        </button>
      </span>
    </label>
  );
}
