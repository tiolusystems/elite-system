"use client";

import { useState } from "react";

import type { PcpLookupOption } from "@/lib/pcp";

type FormulaTargets = {
  materiasPrimas: PcpLookupOption[];
  produtos: PcpLookupOption[];
  produtoEmbalagens: PcpLookupOption[];
  unidades: PcpLookupOption[];
};

export function FormulaComponentRows({ targets }: { targets: FormulaTargets }) {
  return (
    <div className="pcp-component-editor" aria-label="Componentes da formula">
      {Array.from({ length: 6 }, (_, index) => (
        <FormulaComponentRow key={index + 1} index={index + 1} targets={targets} />
      ))}
    </div>
  );
}

function FormulaComponentRow({ index, targets }: { index: number; targets: FormulaTargets }) {
  const [type, setType] = useState("");
  const options =
    type === "MP" ? targets.materiasPrimas : type === "PA" ? targets.produtoEmbalagens : type === "PI" ? targets.produtos : [];

  return (
    <div className="pcp-component-row">
      <span className="pcp-row-index">{index}</span>
      <label>
        Tipo
        <select name={`component_${index}_tipo`} value={type} onChange={(event) => setType(event.target.value)}>
          <option value="">ignorar</option>
          <option value="MP">MP</option>
          <option value="PA">PA</option>
          <option value="PI">PI</option>
        </select>
      </label>
      <label className="wide-field">
        Item
        <select key={`${index}-${type}`} name={`component_${index}_target_id`} defaultValue="" disabled={!type}>
          <option value="">Selecione</option>
          {options.map((option) => (
            <option key={`${type}-${option.id}`} value={option.id}>
              {option.label}{option.detail ? ` - ${option.detail}` : ""}
            </option>
          ))}
        </select>
      </label>
      <label>
        Quantidade
        <input name={`component_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label>
        Unidade
        <select name={`component_${index}_unidade`} defaultValue="" disabled={!type}>
          <option value="">Selecione</option>
          {targets.unidades.map((option) => (
            <option key={option.id} value={option.label}>{option.label} - {option.detail}</option>
          ))}
        </select>
      </label>
      <label className="wide-field">
        Observacao
        <input name={`component_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}

export function OutputRows({ targets }: { targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens"> }) {
  return (
    <div className="pcp-output-editor" aria-label="Produtos gerados">
      {Array.from({ length: 3 }, (_, index) => (
        <OutputRow key={index + 1} index={index + 1} targets={targets} />
      ))}
    </div>
  );
}

function OutputRow({ index, targets }: { index: number; targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens"> }) {
  const [type, setType] = useState("");
  const options = type === "PA" ? targets.produtoEmbalagens : type === "PI" ? targets.produtos : [];

  return (
    <div className="pcp-output-row">
      <span className="pcp-row-index">{index}</span>
      <label>
        Saida
        <select name={`output_${index}_tipo`} value={type} onChange={(event) => setType(event.target.value)}>
          <option value="">ignorar</option>
          <option value="PA">PA</option>
          <option value="PI">PI</option>
        </select>
      </label>
      <label className="wide-field">
        Produto gerado
        <select key={`${index}-${type}`} name={`output_${index}_target_id`} defaultValue="" disabled={!type}>
          <option value="">Selecione</option>
          {options.map((option) => (
            <option key={`${type}-${option.id}`} value={option.id}>
              {option.label}{option.detail ? ` - ${option.detail}` : ""}
            </option>
          ))}
        </select>
      </label>
      <label>
        Quantidade
        <input name={`output_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label className="wide-field">
        Observacao
        <input name={`output_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}
