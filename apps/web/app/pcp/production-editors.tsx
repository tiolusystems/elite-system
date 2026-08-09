"use client";

import { useState } from "react";

import { LocalEntityLookup } from "@/app/corporate-search/local-entity-lookup";
import type { PcpFormulaComponent, PcpLookupOption } from "@/lib/pcp";
import { productionOptionLabel, unitOptionLabel } from "@/lib/production-labels";

type FormulaTargets = {
  materiasPrimas: PcpLookupOption[];
  produtos: PcpLookupOption[];
  produtoEmbalagens: PcpLookupOption[];
  unidades: PcpLookupOption[];
};

export function FormulaComponentRows({
  targets,
  perLiterOnly = false,
  initialComponents = []
}: {
  targets: FormulaTargets;
  perLiterOnly?: boolean;
  initialComponents?: PcpFormulaComponent[];
}) {
  const availableUnits = perLiterOnly
    ? targets.unidades.filter((option) =>
        ["kg_l_produzido", "l_l_produzido", "un_l_produzido"].includes(option.label)
      )
    : targets.unidades;
  const [rowCount, setRowCount] = useState(() => Math.min(6, Math.max(1, initialComponents.length)));

  return (
    <div className="pcp-component-editor" aria-label="Componentes da fórmula">
      <div className="pcp-component-rows">
        {Array.from({ length: rowCount }, (_, index) => (
          <FormulaComponentRow
            initialComponent={initialComponents[index]}
            key={index + 1}
            index={index + 1}
            targets={{ ...targets, unidades: availableUnits }}
          />
        ))}
      </div>
      <div className="formula-component-actions">
        <button
          className="secondary-button"
          type="button"
          disabled={rowCount >= 6}
          onClick={() => setRowCount((current) => Math.min(6, current + 1))}
        >
          Adicionar componente
        </button>
        {rowCount > 1 ? (
          <button
            className="text-button"
            type="button"
            onClick={() => setRowCount((current) => Math.max(1, current - 1))}
          >
            Remover último
          </button>
        ) : null}
        <span>{rowCount === 1 ? "1 componente exibido" : `${rowCount} componentes exibidos`} · máximo 6</span>
      </div>
    </div>
  );
}

function FormulaComponentRow({ index, targets, initialComponent }: { index: number; targets: FormulaTargets; initialComponent?: PcpFormulaComponent }) {
  const [type, setType] = useState(initialComponent?.tipoComponente ?? "");
  const [targetId, setTargetId] = useState<number | null>(initialComponent?.targetId ?? null);
  const options =
    type === "MP" ? targets.materiasPrimas : type === "PA" ? targets.produtoEmbalagens : type === "PI" ? targets.produtos : [];
  const initialUnitId = initialComponent?.unidade
    ? targets.unidades.find((option) => option.label === initialComponent.unidade)?.id
    : undefined;

  return (
    <div className="pcp-component-row">
      <span className="pcp-row-index">{index}</span>
      <label>
        Tipo
        <select name={`component_${index}_tipo`} value={type} onChange={(event) => { setType(event.target.value); setTargetId(null); }}>
          <option value="">Não usar</option>
          <option value="MP">Matéria-prima</option>
          <option value="PA">Produto acabado</option>
          <option value="PI">Produto intermediário</option>
        </select>
      </label>
      <LocalEntityLookup
        key={`${index}-${type}`}
        className="wide-field"
        name={`component_${index}_target_id`}
        label="Item"
        placeholder={type ? "Abra a lista ou pesquise o item" : "Selecione o tipo primeiro"}
        options={options.map((option) => ({ id: option.id, label: productionOptionLabel(option) }))}
        value={targetId}
        onValueChange={setTargetId}
        disabled={!type}
      />
      <label>
        Quantidade por 1 L
        <input name={`component_${index}_quantidade`} inputMode="decimal" defaultValue={initialComponent?.quantidade} />
      </label>
      <label>
        Unidade
        <select name={`component_${index}_unidade_id`} defaultValue={initialUnitId ?? ""} disabled={!type} required={Boolean(type)}>
          <option value="">Selecione</option>
          {targets.unidades.map((option) => (
            <option key={option.id} value={option.id}>{unitOptionLabel(option)}</option>
          ))}
        </select>
      </label>
      <label className="wide-field">
        Observação
        <input name={`component_${index}_observacao`} placeholder="Opcional" defaultValue={initialComponent?.observacao ?? ""} />
      </label>
    </div>
  );
}

export function OutputRows({
  targets,
  fixedProduct,
  defaultQuantity
}: {
  targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens">;
  fixedProduct?: { id: number; label: string };
  defaultQuantity?: number | null;
}) {
  return (
    <div className="pcp-output-editor" aria-label="Produtos gerados">
      <OutputRow index={1} targets={targets} fixedProduct={fixedProduct} defaultQuantity={defaultQuantity} />
    </div>
  );
}

function OutputRow({ index, targets, fixedProduct, defaultQuantity }: {
  index: number;
  targets: Pick<FormulaTargets, "produtos" | "produtoEmbalagens">;
  fixedProduct?: { id: number; label: string };
  defaultQuantity?: number | null;
}) {
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
        {fixedProduct ? (
          <><input value={fixedProduct.label} readOnly /><input type="hidden" name={`output_${index}_target_id`} value={fixedProduct.id} /></>
        ) : (
          <select name={`output_${index}_target_id`} defaultValue="" required>
            <option value="">Selecione</option>
            {targets.produtos.map((option) => (
              <option key={`PI-${option.id}`} value={option.id}>{productionOptionLabel(option)}</option>
            ))}
          </select>
        )}
      </label>
      <label>
        Quantidade do lote PI
        <input value="Igual ao volume real do CQ" readOnly />
        <input type="hidden" name={`output_${index}_quantidade`} value={defaultQuantity ?? 1} />
      </label>
      <label className="wide-field">
        Observação
        <input name={`output_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}
