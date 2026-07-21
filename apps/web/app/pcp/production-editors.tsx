"use client";

import { useState } from "react";

import type { PcpLookupOption } from "@/lib/pcp";
import { productionOptionLabel, unitOptionLabel } from "@/lib/production-labels";

type FormulaTargets = {
  materiasPrimas: PcpLookupOption[];
  produtos: PcpLookupOption[];
  produtoEmbalagens: PcpLookupOption[];
  unidades: PcpLookupOption[];
};

export function FormulaComponentRows({ targets, perLiterOnly = false }: { targets: FormulaTargets; perLiterOnly?: boolean }) {
  const availableUnits = perLiterOnly
    ? targets.unidades.filter((option) =>
        ["kg_l_produzido", "l_l_produzido", "un_l_produzido"].includes(option.label)
      )
    : targets.unidades;
  return (
    <div className="pcp-component-editor" aria-label="Componentes da formula">
      {Array.from({ length: 6 }, (_, index) => (
        <FormulaComponentRow key={index + 1} index={index + 1} targets={{ ...targets, unidades: availableUnits }} />
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
          <option value="">Não utilizar esta linha</option>
          <option value="MP">Matéria-prima</option>
          <option value="PA">Produto acabado</option>
          <option value="PI">Produto intermediário</option>
        </select>
      </label>
      <label className="wide-field">
        Item
        <select key={`${index}-${type}`} name={`component_${index}_target_id`} defaultValue="" disabled={!type}>
          <option value="">Selecione</option>
          {options.map((option) => (
            <option key={`${type}-${option.id}`} value={option.id}>
              {productionOptionLabel(option)}
            </option>
          ))}
        </select>
      </label>
      <label>
        Quantidade por 1 L
        <input name={`component_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label>
        Unidade
        <select name={`component_${index}_unidade_id`} defaultValue="" disabled={!type} required={Boolean(type)}>
          <option value="">Selecione</option>
          {targets.unidades.map((option) => (
            <option key={option.id} value={option.id}>{unitOptionLabel(option)}</option>
          ))}
        </select>
      </label>
      <label className="wide-field">
        Observação
        <input name={`component_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}

export function OutputRows({ targets }: { targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens"> }) {
  return (
    <div className="pcp-output-editor" aria-label="Produtos gerados">
      <OutputRow index={1} targets={targets} />
    </div>
  );
}

function OutputRow({ index, targets }: { index: number; targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens"> }) {
  return (
    <div className="pcp-output-row">
      <span className="pcp-row-index">{index}</span>
      <input type="hidden" name={`output_${index}_tipo`} value="PI" />
      <label>
        Saída
        <input value="Produto intermediário (PI)" readOnly />
      </label>
      <label className="wide-field">
        Produto gerado
        <select name={`output_${index}_target_id`} defaultValue="" required>
          <option value="">Selecione</option>
          {targets.produtos.map((option) => (
            <option key={`PI-${option.id}`} value={option.id}>
              {productionOptionLabel(option)}
            </option>
          ))}
        </select>
      </label>
      <label>
        Quantidade
        <input name={`output_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label className="wide-field">
        Observação
        <input name={`output_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}
