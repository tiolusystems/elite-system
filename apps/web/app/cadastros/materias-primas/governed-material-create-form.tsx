"use client";

import { useActionState } from "react";
import {
  reviewAndCreateGovernedMaterialAction,
  type GovernedMaterialCreateState
} from "@/app/cadastros/tipos-insumo/actions";
import { GovernedRelationCombobox } from "@/app/cadastros/tecnicos/governed-relation-combobox";

type Option = { id: number; label: string; detail?: string | null };
type UnitOption = { id: number; label: string };

const INITIAL_STATE: GovernedMaterialCreateState = { status: "idle", candidates: [] };

export function GovernedMaterialCreateForm({ inputTypes, units }: { inputTypes: Option[]; units: UnitOption[] }) {
  const [state, action, pending] = useActionState(reviewAndCreateGovernedMaterialAction, INITIAL_STATE);
  const value = (key: string, fallback = "") => state.values?.[key] ?? fallback;

  return (
    <form action={action}>
      <div className="form-grid">
        <label>SKU<input name="sku_corrigido" defaultValue={value("sku_corrigido")} placeholder="MP-0001" required /></label>
        <label>Nome<input name="nome" defaultValue={value("nome")} required /></label>
        <label>Código legado<input name="codigo_legado" defaultValue={value("codigo_legado")} /></label>
        <div className="wide-field">
          <GovernedRelationCombobox
            name="tipo_insumo_id" label="Tipo de insumo" emptyLabel="Tipo de insumo não definido"
            placeholder="Buscar tipo de insumo" defaultValue={Number(value("tipo_insumo_id")) || null} options={inputTypes}
          />
        </div>
        <label>Unidade base<select name="unidade_base_estoque_id" defaultValue={value("unidade_base_estoque_id", String(units[0]?.id ?? ""))} required>
          {units.map((unit) => <option key={unit.id} value={unit.id}>{unit.label}</option>)}
        </select></label>
        <label>Densidade<input name="densidade" inputMode="decimal" defaultValue={value("densidade")} /></label>
        <label>Estoque mínimo<input name="estoque_minimo" inputMode="decimal" defaultValue={value("estoque_minimo")} /></label>
        <label>Status<select name="status" defaultValue={value("status", "active")}>
          <option value="active">Ativo</option><option value="pending_review">Em revisão</option><option value="inactive">Inativo</option>
        </select></label>
        <label>NCM<input name="ncm" inputMode="numeric" defaultValue={value("ncm")} /></label>
        <label>IBAMA<input name="ibama" defaultValue={value("ibama")} /></label>
        <label>Código ADS<input name="codigo_ads" defaultValue={value("codigo_ads")} /></label>
      </div>

      {state.candidates.length > 0 ? <section className="notice-panel warning wide-field" aria-live="polite">
        <strong>Possível cadastro duplicado</strong>
        <span>{state.message}</span>
        <ul>{state.candidates.map((item) => <li key={item.materia_prima_id}>
          <strong>{item.sku_corrigido} - {item.nome}</strong><br />
          {item.tipo_insumo_nome ?? "Tipo não definido"} · {item.unidade_nome} · {item.motivos.join(", ")}
        </li>)}</ul>
        <label className="check-line"><input type="checkbox" name="confirmar_possivel_duplicidade" value="sim" required /> Confirmo que é um cadastro distinto</label>
        <label>Justificativa para prosseguir<input name="motivo_duplicidade" required minLength={10} /></label>
      </section> : null}

      {state.message ? <div className={`notice-panel ${state.status === "created" ? "success" : state.status === "error" ? "error" : "warning"}`} aria-live="polite">{state.message}</div> : null}
      <div className="form-footer">
        <span>O sistema verifica SKU e cadastros semelhantes antes de gravar.</span>
        <button className="primary-button" type="submit" disabled={pending}>{pending ? "Verificando..." : state.candidates.length ? "Confirmar cadastro" : "Salvar matéria-prima"}</button>
      </div>
    </form>
  );
}
