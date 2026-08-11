import {
  closePessoaCommercialRelationshipAction,
  createPessoaCommissionPolicyDraftAction,
  linkPessoaCommercialRelationshipAction,
  publishPessoaCommissionPolicyAction,
  removePessoaCommissionPolicyRateAction,
  setPessoaCommissionPolicyRateAction
} from "@/app/cadastros/actions";
import { cadastroStatusLabel } from "@/lib/master-data-governance";
import type {
  MasterDataPerson,
  MasterDataPersonCommissionWorkspace,
  MasterDataPersonRole
} from "@/lib/master-data";

export function PersonCommercialStructureAndCommission({
  person,
  people,
  rolesByPerson,
  personRoles,
  workspace
}: {
  person: MasterDataPerson;
  people: MasterDataPerson[];
  rolesByPerson: Map<number, MasterDataPersonRole[]>;
  personRoles: MasterDataPersonRole[];
  workspace: MasterDataPersonCommissionWorkspace | null;
}) {
  const peopleById = new Map(people.map((item) => [item.id, item]));
  const roleValues = personRoles.map((role) => role.papel);
  const outgoing = (workspace?.relationships ?? []).filter((relation) => relation.originPersonId === person.id);
  const incoming = (workspace?.relationships ?? []).filter((relation) => relation.targetPersonId === person.id);
  const sellerCandidates = people.filter((candidate) =>
    candidate.id !== person.id
    && candidate.status === "active"
    && (rolesByPerson.get(candidate.id) ?? []).some((role) => role.papel === "vendedor")
  );
  const managerCandidates = people.filter((candidate) =>
    candidate.id !== person.id
    && candidate.status === "active"
    && (rolesByPerson.get(candidate.id) ?? []).some((role) => role.papel === "gerente")
  );

  return (
    <>
      <section className="panel related-records-panel" aria-labelledby="estrutura-comercial-title">
        <div className="panel-header">
          <div>
            <span className="section-kicker">Hierarquia temporal</span>
            <h2 id="estrutura-comercial-title">Estrutura comercial</h2>
          </div>
          <span className="pill">Vínculos opcionais</span>
        </div>

        {workspace?.error ? <div className="notice-panel warning">{workspace.error}</div> : null}

        {outgoing.length ? (
          <div className="related-record-list">
            {outgoing.map((relation) => (
              <article key={relation.id}>
                <div>
                  <strong>{relationshipTypeLabel(relation.type)}</strong>
                  <span>{peopleById.get(relation.targetPersonId)?.nome ?? "Pessoa não localizada"}</span>
                </div>
                <div>
                  <span>{formatValidity(relation.startDate, relation.endDate)}</span>
                  <span className={`status-chip status-${relation.status}`}>{relationshipStatusLabel(relation.status)}</span>
                  {relation.status === "active" && workspace?.canManageRelationships ? (
                    <details className="inline-relation-action">
                      <summary>Encerrar vínculo</summary>
                      <form action={closePessoaCommercialRelationshipAction}>
                        <input name="pessoa_id" type="hidden" value={person.id} />
                        <input name="relacionamento_id" type="hidden" value={relation.id} />
                        <label>Data final<input name="vigencia_fim" type="date" required /></label>
                        <label>Justificativa<input name="motivo" minLength={10} required /></label>
                        <button className="secondary-button" type="submit">Confirmar encerramento</button>
                      </form>
                    </details>
                  ) : null}
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Nenhum vínculo acima</strong>
            <span>Esta pessoa pode operar sem vendedor ou gerente responsável.</span>
          </div>
        )}

        {incoming.length ? (
          <div className="related-record-list">
            {incoming.map((relation) => (
              <article key={`incoming-${relation.id}`}>
                <div>
                  <strong>{peopleById.get(relation.originPersonId)?.nome ?? "Pessoa não localizada"}</strong>
                  <span>{relationshipTypeLabel(relation.type)}</span>
                </div>
                <div>
                  <span>{formatValidity(relation.startDate, relation.endDate)}</span>
                  <span className={`status-chip status-${relation.status}`}>{relationshipStatusLabel(relation.status)}</span>
                </div>
              </article>
            ))}
          </div>
        ) : null}

        {workspace?.canManageRelationships && roleValues.includes("agente") ? (
          <RelationshipForm
            currentPersonId={person.id}
            candidates={sellerCandidates}
            type="agente_vendedor"
            label="Vincular vendedor"
          />
        ) : null}

        {workspace?.canManageRelationships && roleValues.includes("vendedor") ? (
          <RelationshipForm
            currentPersonId={person.id}
            candidates={managerCandidates}
            type="vendedor_gerente"
            label="Vincular gerente"
          />
        ) : null}
      </section>

      <CommissionPolicySection
        personId={person.id}
        roles={roleValues}
        workspace={workspace}
      />
    </>
  );
}

function RelationshipForm({
  currentPersonId,
  candidates,
  type,
  label
}: {
  currentPersonId: number;
  candidates: MasterDataPerson[];
  type: "agente_vendedor" | "vendedor_gerente";
  label: string;
}) {
  return (
    <form className="area-link-form" action={linkPessoaCommercialRelationshipAction}>
      <input name="pessoa_id" type="hidden" value={currentPersonId} />
      <input name="tipo_relacionamento" type="hidden" value={type} />
      <label>
        {label}
        <select name="pessoa_destino_id" required>
          <option value="">Selecione</option>
          {candidates.map((candidate) => <option key={candidate.id} value={candidate.id}>{candidate.nome}</option>)}
        </select>
      </label>
      <label>Início da vigência<input name="vigencia_inicio" type="date" required /></label>
      <label>Fim da vigência<input name="vigencia_fim" type="date" /></label>
      <label className="wide-field">Justificativa<input name="motivo" minLength={10} required /></label>
      <button className="primary-button" disabled={candidates.length === 0} type="submit">{label}</button>
    </form>
  );
}

function CommissionPolicySection({
  personId,
  roles,
  workspace
}: {
  personId: number;
  roles: string[];
  workspace: MasterDataPersonCommissionWorkspace | null;
}) {
  const policies = workspace?.policies ?? [];
  const draft = policies.find((policy) => policy.status === "draft") ?? null;
  const groupNames = new Map((workspace?.productGroups ?? []).map((group) => [group.id, `${group.code} · ${group.name}`]));
  const roleOptions: Array<[string, string]> = [
    ...(roles.includes("vendedor") ? [["vendedor", "Vendedor"] as [string, string]] : []),
    ...(roles.includes("agente") ? [["agente", "Agente"] as [string, string]] : []),
    ...(roles.includes("gerente") ? [["gerente", "Gerente"] as [string, string]] : []),
    ...(roles.includes("tecnico_campo") ? [["tecnico_campo", "Técnico de campo"] as [string, string]] : []),
    ["outro", "Outro"]
  ];

  return (
    <section className="panel related-records-panel" aria-labelledby="politica-comissao-title">
      <div className="panel-header">
        <div>
          <span className="section-kicker">Regra versionada</span>
          <h2 id="politica-comissao-title">Política de comissão</h2>
        </div>
        <span className="pill">{workspace?.canManagePolicy ? "Configuração autorizada" : "Consulta"}</span>
      </div>

      {!workspace?.canViewPolicy && !workspace?.canManagePolicy ? (
        <div className="empty-state">
          <strong>Sem alçada financeira</strong>
          <span>A política de comissão não está disponível para esta conta.</span>
        </div>
      ) : policies.length ? (
        <div className="related-record-list">
          {policies.map((policy) => (
            <article key={policy.id}>
              <div>
                <strong>Versão {policy.version} · {policy.commissionable ? "Comissionável" : "Não comissionável"}</strong>
                <span>{formatValidity(policy.startDate, policy.endDate)} · {commissionPolicyStatusLabel(policy.status)}</span>
                {policy.rates.length ? (
                  <small>
                    {policy.rates.map((rate) =>
                      `${groupNames.get(rate.productGroupId) ?? `Grupo ${rate.productGroupId}`}: ${rate.percentage.toLocaleString("pt-BR")}% (${commissionRoleLabel(rate.role)})`
                    ).join(" · ")}
                  </small>
                ) : <small>Sem percentuais cadastrados.</small>}
              </div>
            </article>
          ))}
        </div>
      ) : (
        <div className="empty-state">
          <strong>Nenhuma política cadastrada</strong>
          <span>Sem política publicada, o sistema não inventa percentuais automáticos.</span>
        </div>
      )}

      {workspace?.canManagePolicy && !draft ? (
        <form className="area-link-form" action={createPessoaCommissionPolicyDraftAction}>
          <input name="pessoa_id" type="hidden" value={personId} />
          <label className="check-line">
            <input name="comissionavel" type="checkbox" value="sim" defaultChecked />
            Pessoa comissionável
          </label>
          <label>Início da vigência<input name="vigencia_inicio" type="date" required /></label>
          <label>Fim da vigência<input name="vigencia_fim" type="date" /></label>
          <label className="wide-field">Motivo da nova versão<input name="motivo" minLength={10} required /></label>
          <button className="primary-button" type="submit">Criar nova versão</button>
        </form>
      ) : null}

      {workspace?.canManagePolicy && draft ? (
        <>
          {draft.commissionable ? (
            <form className="area-link-form" action={setPessoaCommissionPolicyRateAction}>
              <input name="pessoa_id" type="hidden" value={personId} />
              <input name="politica_id" type="hidden" value={draft.id} />
              <label>
                Grupo de produto
                <select name="grupo_produto_id" required>
                  <option value="">Selecione</option>
                  {(workspace.productGroups ?? []).map((group) =>
                    <option key={group.id} value={group.id}>{group.code} · {group.name}</option>
                  )}
                </select>
              </label>
              <label>
                Papel
                <select name="papel_comissao" required>
                  {roleOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </label>
              <label>Percentual<input name="percentual" type="number" min="0.0001" max="100" step="0.0001" required /></label>
              <button className="primary-button" type="submit">Salvar percentual</button>
            </form>
          ) : null}

          {draft.rates.map((rate) => (
            <details className="inline-relation-action" key={`rate-${rate.id}`}>
              <summary>
                Remover {groupNames.get(rate.productGroupId) ?? `grupo ${rate.productGroupId}`} · {rate.percentage.toLocaleString("pt-BR")}%
              </summary>
              <form action={removePessoaCommissionPolicyRateAction}>
                <input name="pessoa_id" type="hidden" value={personId} />
                <input name="taxa_id" type="hidden" value={rate.id} />
                <label>Justificativa<input name="motivo" minLength={10} required /></label>
                <button className="secondary-button" type="submit">Remover do rascunho</button>
              </form>
            </details>
          ))}

          <form className="area-link-form" action={publishPessoaCommissionPolicyAction}>
            <input name="pessoa_id" type="hidden" value={personId} />
            <input name="politica_id" type="hidden" value={draft.id} />
            <label className="check-line">
              <input name="confirmar_publicacao" type="checkbox" value="sim" required />
              Revisei a vigência e todos os percentuais desta versão
            </label>
            <label className="wide-field">Motivo da publicação<input name="motivo" minLength={10} required /></label>
            <button className="primary-button" type="submit">Publicar política</button>
          </form>
        </>
      ) : null}
    </section>
  );
}

function relationshipTypeLabel(value: string) {
  if (value === "agente_vendedor") return "Agente → Vendedor";
  if (value === "vendedor_gerente") return "Vendedor → Gerente";
  return value;
}

function relationshipStatusLabel(value: string) {
  if (value === "active") return "Ativo";
  if (value === "closed") return "Encerrado";
  if (value === "cancelled") return "Cancelado";
  return cadastroStatusLabel(value);
}

function commissionPolicyStatusLabel(value: string) {
  const labels: Record<string, string> = {
    draft: "Rascunho",
    published: "Publicada",
    closed: "Encerrada",
    cancelled: "Cancelada"
  };
  return labels[value] ?? value;
}

function commissionRoleLabel(value: string) {
  const labels: Record<string, string> = {
    vendedor: "Vendedor",
    agente: "Agente",
    gerente: "Gerente",
    tecnico_campo: "Técnico de campo",
    outro: "Outro"
  };
  return labels[value] ?? value;
}

function formatValidity(start: string | null, end: string | null) {
  if (!start && !end) return "Vigência não informada";
  if (start && !end) return `Desde ${formatDate(start)}`;
  if (!start && end) return `Até ${formatDate(end)}`;
  return `${formatDate(start!)} a ${formatDate(end!)}`;
}

function formatDate(value: string) {
  const [year, month, day] = value.slice(0, 10).split("-");
  return `${day}/${month}/${year}`;
}
