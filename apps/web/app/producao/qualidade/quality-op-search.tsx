"use client";

import { useRouter } from "next/navigation";

import { SmartSearchField } from "@/app/corporate-search/smart-lookup";

export function QualityOpSearch({
  defaultValue,
  view
}: {
  defaultValue: string;
  view: "queue" | "history";
}) {
  const router = useRouter();
  const entity = view === "history" ? "ops-cq-historico" : "ops-cq-fila";

  return (
    <SmartSearchField
      name="q"
      label="Buscar"
      defaultValue={defaultValue}
      placeholder="Código da OP ou produto"
      source={{ kind: "remote", entity }}
      onOptionSelect={(option) => router.push(`/producao/qualidade/${option.id}`)}
    />
  );
}