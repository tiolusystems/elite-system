"use client";

import { useState } from "react";

import { createPcpFormulaAction } from "@/app/pcp/actions";
import { FormulaComponentRows } from "@/app/pcp/production-editors";
import type { PcpFormulaVersion, PcpLookups } from "@/lib/pcp";

export function FormulaCreationForm({ lookups, initialFormula }: { lookups: PcpLookups; initialFormula?: PcpFormulaVersion | null }) {
  const initialRecipeType = initialFormula?.tipoReceita === "mapa" ? "mapa" : "producao";
  const [recipeType, setRecipeType] = useState<"producao" | "mapa">(initialRecipeType);
  const [requestKey] = useState(() => crypto.randomUUID());

  return (
    <form action={createPcpFormulaAction}>
      <input type="hidden" name="idempotency_key" value={requestKey} />
      <div className="form-grid">
        <label className="wide-field">
          Produto PA ou PI
          <select name="produto_id" defaultValue={initialFormula?.produtoId ?? ""} required>
            <option value="">Selecione o produto</option>
            {lookups.produtos.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Finalidade da receita
          <select
            name="tipo_receita"
            value={recipeType}
            onChange={(event) => setRecipeType(event.target.value as "producao" | "mapa")}
          >
            <option value="producao">Produção operacional</option>
            <option value="mapa">Documentação MAPA</option>
          </select>
        </label>
        <label className="wide-field">
          Justificativa da versão
          <input name="justificativa" placeholder="Explique a criação ou alteração" required />
        </label>
        <label className="full-field">
          Observação
          <input name="observacao" defaultValue={initialFormula?.observacao ?? ""} placeholder="Informação complementar opcional" />
        </label>
      </div>

      <div className={`workflow-callout ${recipeType === "mapa" ? "neutral" : ""}`}>
        <strong>{recipeType === "producao" ? "Receita que será usada pela fábrica" : "Composição documental para o MAPA"}</strong>
        <span>
          {recipeType === "producao"
            ? "A fórmula produz 1 L. Informe cada componente em kg/L, L/L ou UN/L; a OP calculará os totais pelo volume planejado."
            : "Os componentes são declarações documentais opcionais e nunca movimentam estoque."}
        </span>
      </div>
      <FormulaComponentRows
        initialComponents={initialFormula?.components}
        perLiterOnly={recipeType === "producao"}
        targets={{
          materiasPrimas: lookups.materiasPrimas,
          produtos: lookups.produtos,
          produtoEmbalagens: lookups.produtoEmbalagens,
          unidades: lookups.unidades
        }}
      />

      <div className="form-footer">
        <span>Salvar cria nova versão na base de 1 L. Nenhuma versão anterior é alterada.</span>
        <button className="primary-button" type="submit">Criar versão</button>
      </div>
    </form>
  );
}
