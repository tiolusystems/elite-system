"use client";

import {
  SmartLookup,
  type SmartLookupOption
} from "./smart-lookup";

export type LocalLookupOption = SmartLookupOption;

type LocalEntityLookupProps = {
  name?: string;
  label: string;
  placeholder: string;
  options: LocalLookupOption[];
  value?: number | null;
  defaultValue?: number | null;
  onValueChange?: (value: number | null) => void;
  required?: boolean;
  disabled?: boolean;
  helpText?: string;
  className?: string;
  emptyText?: string;
};

export function LocalEntityLookup({
  name,
  label,
  placeholder,
  options,
  value,
  defaultValue = null,
  onValueChange,
  required = false,
  disabled = false,
  helpText,
  className = "",
  emptyText = "Nenhum registro encontrado"
}: LocalEntityLookupProps) {
  return (
    <SmartLookup
      mode="selection"
      source={{ kind: "local", options }}
      name={name}
      label={label}
      placeholder={placeholder}
      value={value}
      defaultValue={defaultValue}
      onValueChange={onValueChange}
      required={required}
      disabled={disabled}
      helpText={helpText}
      className={className}
      emptyText={emptyText}
    />
  );
}