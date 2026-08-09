"use client";

import type { CorporateLookupEntity } from "@/lib/corporate-lookups";

import { SmartLookup } from "./smart-lookup";

export type EntityLookupProps = {
  entity: CorporateLookupEntity;
  name: string;
  label: string;
  placeholder: string;
  defaultValue?: number | null;
  defaultLabel?: string;
  labelName?: string;
  contextId?: number | null;
  required?: boolean;
  disabled?: boolean;
  helpText?: string;
};

export function EntityCombobox({
  entity,
  name,
  label,
  placeholder,
  defaultValue = null,
  defaultLabel = "",
  labelName,
  contextId = null,
  required = false,
  disabled = false,
  helpText
}: EntityLookupProps) {
  return (
    <SmartLookup
      mode="selection"
      source={{ kind: "remote", entity, contextId }}
      name={name}
      label={label}
      placeholder={placeholder}
      defaultValue={defaultValue}
      defaultLabel={defaultLabel}
      labelName={labelName}
      required={required}
      disabled={disabled}
      helpText={helpText}
    />
  );
}

export function EntityLookup(props: EntityLookupProps) {
  return <EntityCombobox {...props} />;
}