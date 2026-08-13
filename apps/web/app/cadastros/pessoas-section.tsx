import Link from "next/link";

import { PersonCommercialStructureAndCommission } from "@/app/cadastros/person-commercial-structure-and-commission";

import {
  closePessoaAreaComercialAction,
  deactivatePessoaComercialAction,
  linkPessoaAreaComercialAction,
  reactivatePessoaComercialAction,
  updatePessoaComercialIdentityAction,
  updatePessoaComercialRoleAction
} from "@/app/cadastros/actions";
import { GovernedPersonCreateForm } from "@/app/cadastros/governed-person-create-form";
import {
  MOTIVO_PAPEL_OPTIONS,
  PAPEL_AREA_OPTIONS,
  PAPEL_COMERCIAL_OPTIONS,
  TIPO_COMERCIAL_OPTIONS,
  cadastroStatusLabel,
  formatLegacyCode,
  papelAreaLabel,
  papelComercialLabel,
  tipoComercialLabel
} from "@/lib/master-data-governance";
import type {
  MasterDataCommercialArea,
  MasterDataPerson,
  MasterDataPersonArea,
  MasterDataPersonCommissionWorkspace,
  MasterDataPersonRole
} from "@/lib/master-data";

type PessoasSectionProps = {
  pessoas: MasterDataPerson[];
  papeis: MasterDataPersonRole[];
  areas: MasterDataCommercialArea[];
  vinculosAreas: MasterDataPersonArea[];
  busca: string;
  filtroPapel: string;
  filtroSituacao: string;
  pessoaSelecionadaId: number | null;
  modoNovo: boolean;
  gravacaoDisponivel: boolean;
  commissionWorkspace: MasterDataPersonCommissionWorkspace | null;
};

export function PessoasSection({
  pessoas,
  papeis,
  areas,
  vinculosAreas,
  busca,
  filtroPapel,
  filtroSituacao,
  pessoaSelecionadaId,
  modoNovo,
  gravacaoDisponivel,
  commissionWorkspace
}: PessoasSectionProps) {
  const consulta = busca.trim().toLocaleLowerCase("pt-BR");
  const papeisPorPessoa = groupRoles(papeis);
  const pessoasFiltradas = pessoas.filter((pessoa) => {
    const papeisPessoa = (papeisPorPessoa.get(pessoa.id) ?? []).map((papel) => papelComercialLabel(papel.papel));
    const matchesQuery = !consulta || [
      pessoa.nome,
      pessoa.codigoLegado,
      tipoComercialLabel(pessoa.tipoComercial),
      ...pessoa.apelidos,
      ...pessoa.grafiasIncorretas,
      ...papeisPessoa
    ]
      .filter(Boolean)
      .some((value) => value!.toLocaleLowerCase("pt-BR").includes(consulta));
    const matchesStatus = !filtroSituacao || pessoa.status === filtroSituacao;
    const matchesRole = !filtroPapel || (papeisPorPessoa.get(pessoa.id) ?? []).some((role) => role.papel === filtroPapel);
    return matchesQuery && matchesStatus && matchesRole;
  });
  const pessoaSelecionada = modoNovo
    ? null
    : pessoas.find((pessoa) => pessoa.id === pessoaSelecionadaId) ?? null;

  return (
    <section className="clients-workbench" aria-label="Gestão de pessoas e vínculos comerciais">
      <div className="clients-list-panel">
        <div className="clients-list-heading">
          <div>
            <span className="section-kicker">Consulta</span>
            <h2>Pessoas</h2>
          </div>
          <span className="count-badge">{pessoasFiltradas.length}</span>
        </div>

        <form className="people-filter-form" action="/cadastros" method="get">
          <input name="grupo" type="hidden" value="pessoas" />
          <label>Buscar<input name="busca" defaultValue={busca} placeholder="Nome, código, apelido ou grafia" /></label>
          <div>
            <label>Situação<select name="situacao" defaultValue={filtroSituacao}><option value="">Todas</option><option value="active">Ativas</option><option value="pending_review">Em revisão</option><option value="inactive">Inativas</option></select></label>
            <label>Papel<select name="papel" defaultValue={filtroPapel}><option value="">Todos</option>{PAPEL_COMERCIAL_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
          </div>
          <div className="people-filter-actions"><button className="secondary-button" type="submit">Filtrar</button><Link className="text-button" href="/cadastros?grupo=pessoas">Limpar</Link></div>
        </form>

        {pessoasFiltradas.length > 0 ? (
          <div className="clients-list" role="list">
            {pessoasFiltradas.map((pessoa) => {
              const pessoaPapeis = papeisPorPessoa.get(pessoa.id) ?? [];
              const selected = pessoaSelecionada?.id === pessoa.id;
              return (
                <Link
                  aria-current={selected ? "page" : undefined}
                  className={`client-list-item${selected ? " selected" : ""}`}
                  href={`/cadastros?grupo=pessoas&pessoa=${pessoa.id}`}
                  key={pessoa.id}
                  role="listitem"
                >
                  <span className="client-list-main">
                    <strong>{pessoa.nome}</strong>
                    <small>{tipoComercialLabel(pessoa.tipoComercial)}</small>
                  </span>
                  <span className={`status-chip status-${pessoa.status}`}>{cadastroStatusLabel(pessoa.status)}</span>
                  <span className="client-list-meta">
                    {pessoaPapeis.length > 0
                      ? pessoaPapeis.map((papel) => papelComercialLabel(papel.papel)).join(" · ")
                      : "Nenhum papel vigente"}
                  </span>
                </Link>
              );
            })}
          </div>
        ) : (
          <div className="shell-state shell-state-empty compact-state">
            <span className="shell-state-label">Sem resultados</span>
            <h3>Nenhuma pessoa encontrada</h3>
            <p>Revise o nome, código, tipo ou papel utilizado na busca.</p>
            <div className="shell-state-actions">
              <Link className="secondary-button" href="/cadastros?grupo=pessoas">Limpar busca</Link>
            </div>
          </div>
        )}
      </div>

      <div className="clients-detail-panel">
        {pessoaSelecionada ? (
          <PersonDetail
            areas={areas}
            gravacaoDisponivel={gravacaoDisponivel}
            papeis={papeisPorPessoa.get(pessoaSelecionada.id) ?? []}
            papeisPorPessoa={papeisPorPessoa}
            pessoa={pessoaSelecionada}
            pessoas={pessoas}
            vinculosAreas={vinculosAreas.filter((vinculo) => vinculo.pessoaId === pessoaSelecionada.id)}
            commissionWorkspace={commissionWorkspace}
          />
        ) : modoNovo ? (
          <PersonCreateForm gravacaoDisponivel={gravacaoDisponivel} />
        ) : (
          <div className="shell-state shell-state-empty client-selection-state">
            <span className="shell-state-label">Visão detalhada</span>
            <h2>Selecione uma pessoa</h2>
            <p>Abra um cadastro para revisar identidade, papéis, responsável e áreas comerciais.</p>
            <div className="shell-state-actions">
              <Link className="primary-button" href="/cadastros?grupo=pessoas&modo=novo#cadastro-pessoa">
                Cadastrar pessoa
              </Link>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}

function PersonCreateForm({ gravacaoDisponivel }: { gravacaoDisponivel: boolean }) {
  return (
    <section className="panel form-panel client-form-panel" id="cadastro-pessoa" aria-labelledby="cadastro-pessoa-title">
      <div className="panel-header">
        <div>
          <span className="section-kicker">Novo cadastro</span>
          <h2 id="cadastro-pessoa-title">Cadastrar pessoa</h2>
        </div>
        <span className="pill">{gravacaoDisponivel ? "Gravação disponível" : "Somente consulta"}</span>
      </div>
      <GovernedPersonCreateForm enabled={gravacaoDisponivel} />
    </section>
  );
}

function PersonDetail({
  pessoa,
  papeis,
  papeisPorPessoa,
  pessoas,
  areas,
  vinculosAreas,
  gravacaoDisponivel,
  commissionWorkspace
}: {
  pessoa: MasterDataPerson;
  papeis: MasterDataPersonRole[];
  papeisPorPessoa: Map<number, MasterDataPersonRole[]>;
  pessoas: MasterDataPerson[];
  areas: MasterDataCommercialArea[];
  vinculosAreas: MasterDataPersonArea[];
  gravacaoDisponivel: boolean;
  commissionWorkspace: MasterDataPersonCommissionWorkspace | null;
}) {
  const areasPorId = new Map(areas.map((item) => [item.id, item]));
  const roleValues = papeis.map((papel) => papel.papel);
  const activeAreas = areas.filter((area) => area.status === "active");

  return (
    <div className="client-detail-stack">
      <section className="client-summary-panel" aria-labelledby="pessoa-selecionada-title">
        <div className="client-summary-heading">
          <div>
            <span className="section-kicker">Pessoa selecionada</span>
            <h2 id="pessoa-selecionada-title">{pessoa.nome}</h2>
            <p>{tipoComercialLabel(pessoa.tipoComercial)}</p>
          </div>
          <span className={`status-chip status-${pessoa.status}`}>{cadastroStatusLabel(pessoa.status)}</span>
        </div>
        <dl className="client-summary-grid">
          <div><dt>Código legado</dt><dd>{formatLegacyCode(pessoa.codigoLegado)}</dd></div>
          <div><dt>Papéis vigentes</dt><dd>{papeis.length}</dd></div>
          <div><dt>Estrutura comercial</dt><dd>{(commissionWorkspace?.relationships ?? []).filter((relation) => relation.originPersonId === pessoa.id && relation.status === "active").length} vínculo(s)</dd></div>
          <div><dt>Áreas comerciais</dt><dd>{vinculosAreas.filter((item) => item.status === "active").length}</dd></div>
        </dl>
        <div className="role-chip-list" aria-label="Papéis comerciais vigentes">
          {papeis.length > 0
            ? papeis.map((papel) => <span className="role-chip" key={papel.papel}>{papelComercialLabel(papel.papel)}</span>)
            : <span className="muted">Nenhum papel vigente</span>}
        </div>
      </section>

      <section className="panel form-panel client-form-panel" aria-labelledby="identidade-pessoa-title">
        <div className="panel-header">
          <div><span className="section-kicker">Identidade auditada</span><h2 id="identidade-pessoa-title">Dados pessoais</h2></div>
          <span className="pill">{gravacaoDisponivel ? "Gravação disponível" : "Somente consulta"}</span>
        </div>
        <form action={updatePessoaComercialIdentityAction}>
          <input name="pessoa_id" type="hidden" value={pessoa.id} />
          <div className="form-grid client-form-grid">
            <label className="wide-field">Nome<input name="nome" defaultValue={pessoa.nome} required /></label>
            <label>Código legado<input name="codigo_legado" defaultValue={pessoa.codigoLegado ?? ""} /></label>
            <label className="wide-field">Apelidos<input name="apelidos" defaultValue={pessoa.apelidos.join("; ")} /></label>
            <label className="wide-field">Grafias históricas<input name="grafias_incorretas" defaultValue={pessoa.grafiasIncorretas.join("; ")} /></label>
            <label className="wide-field">Motivo da alteração<textarea name="motivo" rows={3} required /></label>
          </div>
          <div className="form-footer"><span>Nome e grafias mantêm histórico de autoria.</span><button className="primary-button" disabled={!gravacaoDisponivel} type="submit">Salvar identidade</button></div>
        </form>
      </section>

      <section className="panel form-panel client-form-panel" aria-labelledby="papeis-pessoa-title">
        <div className="panel-header">
          <div><span className="section-kicker">Alçada de negócio</span><h2 id="papeis-pessoa-title">Papéis e responsabilidade</h2></div>
          <span className="pill">Alteração sensível</span>
        </div>
        <form action={updatePessoaComercialRoleAction}>
          <input name="pessoa_id" type="hidden" value={pessoa.id} />
          <div className="form-grid client-form-grid">
            <label>Tipo comercial<select name="tipo_comercial" defaultValue={pessoa.tipoComercial ?? ""} required>{TIPO_COMERCIAL_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
          </div>
          <RoleFields defaultRoles={roleValues} />
          <div className="form-grid client-form-grid role-reason-grid">
            <label>Motivo<select name="motivo_codigo" defaultValue="correcao_cadastro" required>{MOTIVO_PAPEL_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
            <label>Detalhe do motivo<input name="motivo_detalhe" placeholder="Obrigatório quando o motivo for Outro" /></label>
          </div>
          <div className="form-footer"><span>Esta alteração não muda o perfil de login do usuário.</span><button className="primary-button" disabled={!gravacaoDisponivel} type="submit">Salvar papéis</button></div>
        </form>
      </section>

      <PersonCommercialStructureAndCommission
        person={pessoa}
        people={pessoas}
        rolesByPerson={papeisPorPessoa}
        personRoles={papeis}
        workspace={commissionWorkspace}
      />

      <section className="panel related-records-panel" aria-labelledby="acesso-sistema-title">
        <div className="panel-header">
          <div>
            <span className="section-kicker">Identidade e segurança</span>
            <h2 id="acesso-sistema-title">Acesso ao sistema</h2>
          </div>
          <span className={`status-chip ${pessoa.userProfileId ? "status-active" : "status-pending_review"}`}>
            {pessoa.userProfileId ? "Conta vinculada" : "Sem acesso"}
          </span>
        </div>
        <div className="access-link-summary">
          <div>
            <strong>{pessoa.userProfileId ? "Esta pessoa possui uma conta vinculada." : "Esta pessoa ainda não possui conta vinculada."}</strong>
            <span>
              E-mail, convite, perfil de login e alçadas são administrados somente em Segurança.
            </span>
          </div>
          <Link
            className="primary-button"
            href={`/seguranca?pessoa_id=${pessoa.id}${pessoa.userProfileId ? `&user_id=${pessoa.userProfileId}` : ""}#vinculo-pessoa`}
          >
            Gerenciar acesso e alçadas
          </Link>
        </div>
      </section>

      <section className="panel related-records-panel" aria-labelledby="areas-pessoa-title">
        <div className="panel-header"><div><span className="section-kicker">Escopo comercial</span><h2 id="areas-pessoa-title">Áreas de atuação</h2></div><span className="count-badge">{vinculosAreas.length}</span></div>
        {vinculosAreas.length > 0 ? (
          <div className="related-record-list">
            {vinculosAreas.map((vinculo) => (
              <article key={vinculo.id}>
                <div><strong>{areasPorId.get(vinculo.areaId)?.nome ?? "Área não localizada"}</strong><span>{papelAreaLabel(vinculo.papelArea)}</span></div>
                <div>
                  <span>{formatValidity(vinculo.vigenciaInicio, vinculo.vigenciaFim)}</span>
                  <span className={`status-chip status-${vinculo.status}`}>{cadastroStatusLabel(vinculo.status)}</span>
                  {vinculo.status === "active" ? (
                    <details className="inline-relation-action">
                      <summary>Encerrar vínculo</summary>
                      <form action={closePessoaAreaComercialAction}>
                        <input name="pessoa_id" type="hidden" value={pessoa.id} />
                        <input name="vinculo_id" type="hidden" value={vinculo.id} />
                        <label>Data final<input name="vigencia_fim" type="date" required /></label>
                        <label>Justificativa<input name="motivo" minLength={10} required /></label>
                        <button className="secondary-button" disabled={!gravacaoDisponivel} type="submit">Confirmar encerramento</button>
                      </form>
                    </details>
                  ) : null}
                </div>
              </article>
            ))}
          </div>
        ) : <div className="empty-state"><strong>Nenhuma área vinculada</strong><span>Crie o primeiro vínculo usando uma área ativa.</span></div>}
        {pessoa.status === "active" ? (
          <form className="area-link-form" action={linkPessoaAreaComercialAction}>
            <input name="pessoa_id" type="hidden" value={pessoa.id} />
            <label>Área comercial<select name="area_id" required><option value="">Selecione</option>{activeAreas.map((area) => <option key={area.id} value={area.id}>{area.nome}</option>)}</select></label>
            <label>Papel na área<select name="papel_area" defaultValue="vendedor" required>{PAPEL_AREA_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
            <label>Início da vigência<input name="vigencia_inicio" type="date" required /></label>
            <label className="wide-field">Justificativa<input name="motivo" minLength={10} required /></label>
            <button className="primary-button" disabled={!gravacaoDisponivel || activeAreas.length === 0} type="submit">Vincular área</button>
          </form>
        ) : null}
      </section>

      {pessoa.status !== "inactive" ? (
        <details className="danger-zone">
          <summary>Desativar esta pessoa</summary>
          <form action={deactivatePessoaComercialAction}>
            <input name="pessoa_id" type="hidden" value={pessoa.id} />
            <label>Motivo da desativação<textarea name="motivo" required rows={3} /></label>
            <button className="secondary-button danger-button" disabled={!gravacaoDisponivel} type="submit">Desativar pessoa</button>
          </form>
        </details>
      ) : (
        <details className="reactivation-zone">
          <summary>Reativar esta pessoa</summary>
          <form action={reactivatePessoaComercialAction}>
            <input name="pessoa_id" type="hidden" value={pessoa.id} />
            <label>Justificativa da reativação<textarea name="motivo" minLength={10} required rows={3} /></label>
            <p>Os vínculos comerciais encerrados permanecerão encerrados.</p>
            <button className="primary-button" disabled={!gravacaoDisponivel} type="submit">Reativar pessoa</button>
          </form>
        </details>
      )}
    </div>
  );
}

function RoleFields({ defaultRoles }: { defaultRoles: string[] }) {
  return (
    <fieldset className="person-role-fieldset">
      <legend>Papéis comerciais</legend>
      <div className="check-grid">
        {PAPEL_COMERCIAL_OPTIONS.map((option) => (
          <label key={option.value}><input defaultChecked={defaultRoles.includes(option.value)} name="papeis" type="checkbox" value={option.value} />{option.label}</label>
        ))}
      </div>
    </fieldset>
  );
}

function groupRoles(roles: MasterDataPersonRole[]) {
  const grouped = new Map<number, MasterDataPersonRole[]>();
  for (const role of roles) grouped.set(role.pessoaId, [...(grouped.get(role.pessoaId) ?? []), role]);
  return grouped;
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
