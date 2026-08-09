"use client";

import { useState } from "react";

import { LocalEntityLookup } from "@/app/corporate-search/local-entity-lookup";
import { createPcpFormulaAction } from "@/app/pcp/actions";
import { FormulaComponentRows } from "@/app/pcp/production-editors";
import type { PcpFormulaVersion, PcpLookups } from "@/lib/pcp";

export function FormulaCreationForm({
  lookups,
  initialFormula,
  onCancel
}: {
  lookups: PcpLookups;
  initialFormula?: PcpFormulaVersion | null;
  onCancel: () => void;
}) {
  const initialRecipeType = initialFormula?.tipoReceita === "mapa" ? "mapa" : "producao";
  const [recipeType, setRecipeType] = useState<"producao" | "mapa">(initialRecipeType);
  const [requestKey] = useState(() => crypto.randomUUID());

  return (
    <form action={createPcpFormulaAction} className="formula-creation-workflow">
      <input type="hidden" name="idempotency_key" value={requestKey} />
      <section className="formula-form-section" aria-labelledby="formula-identification-title">
        <div className="formula-form-section-heading">
          <span>1</span>
          <div>
            <h3 id="formula-identification-title">Identificação</h3>
            <p>Defina o produto e a finalidade desta versão.</p>
          </div>
        </div>
        <div className="form-grid formula-identification-grid">
          <LocalEntityLookup
            className="wide-field"
            name="produto_id"
            label="Produto PA ou PI"
            placeholder="Abra a lista ou pesquise o produto"
            options={lookups.produtos.map((option) => ({ id: option.id, label: option.label, detail: option.detail }))}
            defaultValue={initialFormula?.produtoId ?? null}
            required
          />
          <label>
            Finalidade
            <select
              name="tipo_receita"
              value={recipeType}
              onChange={(event) => setRecipeType(event.target.value as "producao" | "mapa")}
            >
              <option value="producao">Produção operacional</option>
              <option value="mapa">Documentação MAPA</option>
            </select>
          </label>
        </div>
        <div className={`workflow-callout formula-purpose-callout ${recipeType === "mapa" ? "neutral" : ""}`}>
          <strong>{recipeType === "producao" ? "Receita usada pela fábrica" : "Composição documental para o MAPA"}</strong>
          <span>
            {recipeType === "producao"
              ? "A fórmula representa 1 L produzido. A OP multiplica cada componente pelo volume planejado."
              : "Os componentes são declarações documentais opcionais e nunca movimentam estoque."}
          </span>
        </div>
      </section>

      <section className="formula-form-section" aria-labelledby="formula-components-title">
        <div className="formula-form-section-heading">
          <span>2</span>
          <div>
            <h3 id="formula-components-title">
              {recipeType === "producao" ? "Componentes por 1 L" : "Composição declarada"}
            </h3>
            <p>
              {recipeType === "producao"
                ? "Inclua somente os componentes necessários para produzir um litro."
                : "O preenchimento é opcional e não representa consumo real de lotes."}
            </p>
          </div>
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
      </section>

      <section className="formula-form-section" aria-labelledby="formula-record-title">
        <div className="formula-form-section-heading">
          <span>3</span>
          <div>
            <h3 id="formula-record-title">Registro da versão</h3>
            <p>Explique por que a versão está sendo criada e acrescente observações apenas quando necessário.</p>
          </div>
        </div>
        <div className="form-grid formula-record-grid">
          <label className="wide-field">
            Justificativa da versão
            <input name="justificativa" placeholder="Ex.: ajuste validado na composição operacional" required />
          </label>
          <label className="full-field">
            Observação
            <input name="observacao" defaultValue={initialFormula?.observacao ?? ""} placeholder="Informação complementar opcional" />
          </label>
        </div>
      </section>

      <div className="form-footer">
        <span>Salvar cria uma nova versão. Nenhuma versão anterior é alterada ou apagada.</span>
        <div className="formula-form-footer-actions">
          <button className="secondary-button" type="button" onClick={onCancel}>Cancelar</button>
          <button className="primary-button" type="submit">Criar versão</button>
        </div>
      </div>
    </form>
  );
}
