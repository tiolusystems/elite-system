"use client";

import { useActionState } from "react";

import {
  reviewAndCreatePessoaComercialAction,
  type GovernedPersonCreateState
} from "@/app/cadastros/actions";
import {
  PAPEL_COMERCIAL_OPTIONS,
  TIPO_COMERCIAL_OPTIONS,
  cadastroStatusLabel,
  duplicateReasonLabel,
  papelComercialLabel,
  tipoComercialLabel
} from "@/lib/master-data-governance";

type SellerOption = { id: number; nome: string };

const INITIAL_STATE: GovernedPersonCreateState = { status: "idle", candidates: [] };

export function GovernedPersonCreateForm({ sellers, enabled }: { sellers: SellerOption[]; enabled: boolean }) {
  const [state, action, pending] = useActionState(reviewAndCreatePessoaComercialAction, INITIAL_STATE);
  const value = (key: string, fallback = "") => state.values?.[key] ?? fallback;
  const selectedRoles = state.roles ?? ["vendedor", "comissionado"];

  return (
    <form action={action}>
      <div className="form-grid client-form-grid">
        <label className="wide-field">Nome<input name="nome" defaultValue={value("nome")} placeholder="Nome completo" required /></label>
        <label>Código legado<input name="codigo_legado" defaultValue={value("codigo_legado")} placeholder="Opcional" /></label>
        <label>
          Tipo comercial
          <select name="tipo_comercial" defaultValue={value("tipo_comercial", "vendedor_direto_elite")} required>
            {TIPO_COMERCIAL_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Vendedor responsável
          <select name="vendedor_responsavel_id" defaultValue={value("vendedor_responsavel_id")}>
            <option value="">Não se aplica</option>
            {sellers.map((seller) => <option key={seller.id} value={seller.id}>{seller.nome}</option>)}
          </select>
          <small>Obrigatório somente para agente vinculado.</small>
        </label>
        <label className="wide-field">Apelidos<input name="apelidos" defaultValue={value("apelidos")} placeholder="Separe por ponto e vírgula" /></label>
        <label className="wide-field">Grafias históricas<input name="grafias_incorretas" defaultValue={value("grafias_incorretas")} placeholder="Grafias usadas em registros antigos" /></label>
      </div>

      <fieldset className="person-role-fieldset">
        <legend>Papéis comerciais</legend>
        <div className="check-grid">
          {PAPEL_COMERCIAL_OPTIONS.map((option) => (
            <label key={option.value}>
              <input defaultChecked={selectedRoles.includes(option.value)} name="papeis" type="checkbox" value={option.value} />
              {option.label}
            </label>
          ))}
        </div>
      </fieldset>

      {state.candidates.length > 0 ? (
        <section className="notice-panel warning person-duplicate-review" aria-live="polite">
          <strong>Possíveis cadastros semelhantes</strong>
          <span>{state.message}</span>
          <div className="person-candidate-list">
            {state.candidates.map((candidate) => (
              <article key={candidate.pessoa_id}>
                <div>
                  <strong>{candidate.nome}</strong>
                  <span>{tipoComercialLabel(candidate.tipo_comercial)} · {cadastroStatusLabel(candidate.status)}</span>
                </div>
                <dl>
                  <div><dt>Papéis</dt><dd>{candidate.papeis.map(papelComercialLabel).join(", ") || "Não informados"}</dd></div>
                  <div><dt>Responsável</dt><dd>{candidate.vendedor_responsavel_nome ?? "Não se aplica"}</dd></div>
                  <div><dt>Áreas</dt><dd>{candidate.areas.join(", ") || "Nenhuma área ativa"}</dd></div>
                  <div><dt>Semelhanças</dt><dd>{candidate.motivos.map(duplicateReasonLabel).join(", ")}</dd></div>
                </dl>
                <input name="candidatos_apresentados" type="hidden" value={candidate.pessoa_id} />
              </article>
            ))}
          </div>
          <label className="check-line">
            <input name="confirmar_possivel_duplicidade" type="checkbox" value="sim" required />
            Confirmo que esta é outra pessoa e revisei os cadastros semelhantes
          </label>
          <label>Justificativa para prosseguir<input name="motivo_duplicidade" minLength={10} required /></label>
        </section>
      ) : null}

      {state.message && state.candidates.length === 0 ? (
        <div className={`notice-panel ${state.status === "created" ? "success" : "error"}`} aria-live="polite">{state.message}</div>
      ) : null}

      <div className="form-footer">
        <span>Homônimos são permitidos após revisão; código legado repetido é sempre bloqueado.</span>
        <button className="primary-button" disabled={!enabled || pending} type="submit">
          {pending ? "Verificando..." : state.candidates.length > 0 ? "Confirmar cadastro" : "Cadastrar pessoa"}
        </button>
      </div>
    </form>
  );
}
