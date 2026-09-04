import {
  clearSecurityPermissionOverrideAction,
  assignSecurityAccessProfileAction,
  inviteSecurityAuthUserAction,
  linkSecurityUserCommercialPersonAction,
  reviewSecurityEmailChangeAction,
  removeSecurityAccessProfileAction,
  setSecurityPermissionOverrideAction,
  upsertSecurityUserProfileAction,
} from "@/app/seguranca/actions";
import { getSecurityDashboard, type EffectivePermission, type SecurityProfile } from "@/lib/security";
import { internalValueLabel } from "@/lib/labels-ptbr";

type SearchParams = Record<string, string | string[] | undefined>;

export const dynamic = "force-dynamic";

const ROLES = ["admin", "comercial", "producao", "estoque", "expedicao", "auditoria"];

export default async function SegurancaPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const selectedUserId = singleValue(params.user_id);
  const requestedPersonId = positiveInteger(singleValue(params.pessoa_id));
  const result = singleValue(params.result);
  const dashboard = await getSecurityDashboard(selectedUserId);
  const formMessage = messageForResult(result);
  const selectedProfile = dashboard.selectedProfile;
  const selectedEmailChangeRequest = dashboard.emailChangeRequests[0] ?? null;
  const linkedPerson = selectedProfile
    ? dashboard.commercialPeople.find((person) => person.userProfileId === selectedProfile.id) ?? null
    : null;
  const availablePeople = dashboard.commercialPeople.filter(
    (person) => person.status === "active" && (person.userProfileId === null || person.userProfileId === selectedProfile?.id)
  );
  const effectivePermissionCount = dashboard.permissions.filter((permission) => permission.effectiveAllowed).length;

  return (
    <main className="app-shell">
      <section className="workspace">
        <div className="toolbar">
          <div>
            <h1>Seguranca e alcadas</h1>
            <p className="muted">
              Contas, confirmação de e-mail, perfis, alçadas e auditoria de acesso.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de seguranca">
            <a className="secondary-button" href="/login">
              Login
            </a>
            <a className="secondary-button" href="#novo-acesso">
              Novo acesso
            </a>
            <a className="primary-button" href="#perfis">
              Contas
            </a>
          </div>
        </div>

        <section className="summary-grid" aria-label="Resumo de seguranca">
          <div className="summary-card">
            <span>Perfis</span>
            <strong>{valueOrDash(dashboard.metrics.totalProfiles)}</strong>
          </div>
          <div className="summary-card">
            <span>E-mails confirmados</span>
            <strong>{valueOrDash(dashboard.metrics.confirmedEmails)}</strong>
          </div>
          <div className="summary-card">
            <span>Confirmações pendentes</span>
            <strong>{valueOrDash(dashboard.metrics.pendingEmails)}</strong>
          </div>
          <div className="summary-card">
            <span>E-mails fictícios</span>
            <strong>{valueOrDash(dashboard.metrics.placeholderEmails)}</strong>
          </div>
        </section>

        {dashboard.error ? (
          <section className="notice-panel" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" id="novo-acesso" aria-labelledby="novo-acesso-title">
            <div className="panel-header">
              <h2 id="novo-acesso-title">Convidar novo usuário</h2>
              <span className="pill">confirmação por e-mail</span>
            </div>
            <form action={inviteSecurityAuthUserAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Email
                  <input name="email" type="email" placeholder="usuario@empresa.com" required />
                </label>
                <label className="wide-field">
                  Nome
                  <input name="display_name" placeholder="Nome exibido no sistema" required />
                </label>
                <label>
                  Papel
                  <select name="role" defaultValue="auditoria">
                    {ROLES.map((role) => (
                      <option value={role} key={role}>
                        {securityRoleLabel(role)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="wide-field">
                  Perfil de acesso inicial
                  <select name="access_profile_id" required defaultValue={dashboard.accessProfiles[0]?.id ?? ""}>
                    <option value="">Selecione um perfil versionado</option>
                    {dashboard.accessProfiles.map((accessProfile) => (
                      <option value={accessProfile.id} key={accessProfile.id}>
                        {accessProfile.name} · {accessProfile.permissionCount} capacidades
                      </option>
                    ))}
                  </select>
                </label>
                <label className="wide-field">
                  Pessoa existente (opcional)
                  <select name="pessoa_id" defaultValue={requestedPersonId ?? ""}>
                    <option value="">Criar identidade humana automaticamente</option>
                    {availablePeople.map((person) => (
                      <option value={person.id} key={person.id}>{person.name}</option>
                    ))}
                  </select>
                  <span className="field-help">Sem seleção, o sistema cria uma pessoa interna sem papel comercial.</span>
                </label>
              </div>
              <div className="form-footer">
                <span>A conta fica pendente até o destinatário confirmar o e-mail e criar sua senha.</span>
                <button className="primary-button" type="submit">
                  Enviar convite
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="selecao-title">
            <div className="panel-header">
              <div>
                <h2 id="selecao-title">Acesso da conta selecionada</h2>
                <p className="muted">O bloqueio impede o uso do sistema sem excluir a pessoa, as alçadas ou o histórico.</p>
              </div>
              <span className="pill">{dashboard.selectedProfile ? securityRoleLabel(dashboard.selectedProfile.role) : "Nenhum"}</span>
            </div>
            {dashboard.selectedProfile ? (
              <dl className="status-list">
                <div className="status-row">
                  <dt>Nome</dt>
                  <dd>{dashboard.selectedProfile.displayName}</dd>
                </div>
                <div className="status-row">
                  <dt>E-mail</dt>
                  <dd>{dashboard.selectedProfile.email ?? "não cadastrado"}</dd>
                </div>
                <div className="status-row">
                  <dt>Confirmação</dt>
                  <dd>
                    <span className={`status-chip ${emailStatusTone(dashboard.selectedProfile.emailStatus)}`}>
                      {emailStatusLabel(dashboard.selectedProfile.emailStatus)}
                    </span>
                  </dd>
                </div>
                <div className="status-row">
                  <dt>Acesso ao sistema</dt>
                  <dd>
                    <span className={`status-chip ${dashboard.selectedProfile.status}`}>
                      {internalValueLabel(dashboard.selectedProfile.status)}
                    </span>
                  </dd>
                </div>
                <div className="status-row">
                  <dt>Overrides</dt>
                  <dd>{dashboard.selectedProfile.overridesCount}</dd>
                </div>
                <div className="status-row">
                  <dt>Tipo</dt>
                  <dd>{dashboard.selectedProfile.isSystemActor ? "ator de sistema" : "usuario operacional"}</dd>
                </div>
              </dl>
            ) : (
              <div className="empty-state">
                <strong>Nenhum perfil carregado</strong>
                <span>Configure Supabase ou crie um perfil vinculado ao Auth.</span>
              </div>
            )}
            {dashboard.selectedProfile && !dashboard.selectedProfile.isSystemActor ? (
              <form action={upsertSecurityUserProfileAction}>
                <input name="user_id" type="hidden" value={dashboard.selectedProfile.id} />
                <input name="display_name" type="hidden" value={dashboard.selectedProfile.displayName} />
                <input name="role" type="hidden" value={dashboard.selectedProfile.role} />
                <input
                  name="status"
                  type="hidden"
                  value={dashboard.selectedProfile.status === "active" ? "inactive" : "active"}
                />
                <p className="field-note">Alterar alçadas não bloqueia a conta. Esta ação pertence somente à conta selecionada e nunca exclui o usuário.</p>
                <div className="form-footer">
                  <span>A mudanÃ§a preserva o perfil, as alÃ§adas e o histÃ³rico de auditoria.</span>
                  <button className="secondary-button" type="submit">
                    {dashboard.selectedProfile.status === "active" ? "Inativar usuÃ¡rio" : "Reativar usuÃ¡rio"}
                  </button>
                </div>
              </form>
            ) : null}
          </section>
        </section>

        <details className="panel form-panel" id="vinculo-pessoa">
          <summary>Reparo avançado de vínculo Pessoa - Conta</summary>
          <div className="panel-header">
            <div>
              <h2 id="vinculo-pessoa-title">Identidade operacional</h2>
              <p className="muted">Associe a conta à pessoa usada em carteira de clientes, pedidos e auditoria.</p>
            </div>
            <span className="pill">{linkedPerson ? "vínculo ativo" : "sem vínculo"}</span>
          </div>

          {!selectedProfile || selectedProfile.isSystemActor ? (
            <div className="empty-state">
              <strong>Selecione uma conta operacional</strong>
              <span>Atores de sistema não participam dos vínculos comerciais.</span>
            </div>
          ) : linkedPerson ? (
            <dl className="status-list">
              <div className="status-row">
                <dt>Conta</dt>
                <dd>{selectedProfile.displayName}</dd>
              </div>
              <div className="status-row">
                <dt>Pessoa vinculada</dt>
                <dd>{linkedPerson.name}</dd>
              </div>
              <div className="status-row">
                <dt>Situação</dt>
                <dd>{internalValueLabel(linkedPerson.status)}</dd>
              </div>
            </dl>
          ) : (
            <form action={linkSecurityUserCommercialPersonAction}>
              <input name="user_id" type="hidden" value={selectedProfile.id} />
              <div className="form-grid">
                <label className="wide-field">
                  Pessoa comercial
                  <select name="pessoa_id" defaultValue={requestedPersonId ?? ""} required>
                    <option value="">Selecione uma pessoa sem conta</option>
                    {availablePeople.map((person) => (
                      <option value={person.id} key={person.id}>
                        {person.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="wide-field">
                  Justificativa
                  <input
                    name="motivo"
                    minLength={10}
                    placeholder="Explique por que esta conta representa a pessoa"
                    required
                  />
                </label>
              </div>
              <div className="form-footer">
                <span>O vínculo é individual, auditado e não concede alçadas automaticamente.</span>
                <button className="primary-button" type="submit" disabled={!dashboard.identityLinkAvailable}>
                  Vincular identidade
                </button>
              </div>
              {!dashboard.identityLinkAvailable ? (
                <p className="field-help">Sua conta não possui alçada para criar este vínculo.</p>
              ) : null}
            </form>
          )}
        </details>

        <section className="panel form-panel" id="troca-email" aria-labelledby="troca-email-title">
          <div className="panel-header">
            <h2 id="troca-email-title">Troca de e-mail do usuário</h2>
            <span className="pill">
              {selectedEmailChangeRequest ? emailChangeStatusLabel(selectedEmailChangeRequest.status) : "sem solicitação"}
            </span>
          </div>

          {!selectedProfile || selectedProfile.isSystemActor ? (
            <div className="empty-state">
              <strong>Selecione um usuário operacional</strong>
              <span>Atores de sistema não possuem e-mail de acesso.</span>
            </div>
          ) : null}

          {selectedProfile && !selectedProfile.isSystemActor && !selectedEmailChangeRequest ? (
            <div className="empty-state">
              <strong>Nenhuma solicitação pendente</strong>
              <span>O usuário deve solicitar a troca. Ele não consegue alterar o endereço diretamente.</span>
            </div>
          ) : null}

          {selectedProfile && selectedEmailChangeRequest ? (
            <dl className="status-list">
              <div className="status-row">
                <dt>Usuário</dt>
                <dd>{selectedProfile.displayName}</dd>
              </div>
              <div className="status-row">
                <dt>Motivo</dt>
                <dd>{emailChangeReasonLabel(selectedEmailChangeRequest.requestReasonCode)}</dd>
              </div>
              {selectedEmailChangeRequest.requestReasonDetail ? (
                <div className="status-row">
                  <dt>Detalhes</dt>
                  <dd>{selectedEmailChangeRequest.requestReasonDetail}</dd>
                </div>
              ) : null}
              {selectedEmailChangeRequest.newEmail ? (
                <div className="status-row">
                  <dt>Novo e-mail definido</dt>
                  <dd>{selectedEmailChangeRequest.newEmail}</dd>
                </div>
              ) : null}
            </dl>
          ) : null}

          {selectedProfile && selectedEmailChangeRequest?.status === "pending_admin" ? (
            <div className="two-column">
              <form action={reviewSecurityEmailChangeAction}>
                <input name="request_id" type="hidden" value={selectedEmailChangeRequest.requestId} />
                <input name="user_id" type="hidden" value={selectedProfile.id} />
                <input name="decision" type="hidden" value="approve" />
                <div className="form-grid single-field-grid">
                  <label>
                    Novo e-mail
                    <input name="new_email" type="email" autoComplete="off" required />
                  </label>
                  <label>
                    Motivo da aprovação
                    <input name="review_reason" placeholder="Conferência realizada pelo administrador" required />
                  </label>
                </div>
                <div className="form-footer">
                  <span>O endereço será travado para confirmação pelo titular.</span>
                  <button className="primary-button" type="submit">
                    Aprovar endereço
                  </button>
                </div>
              </form>

              <form action={reviewSecurityEmailChangeAction}>
                <input name="request_id" type="hidden" value={selectedEmailChangeRequest.requestId} />
                <input name="user_id" type="hidden" value={selectedProfile.id} />
                <input name="decision" type="hidden" value="reject" />
                <div className="form-grid single-field-grid">
                  <label>
                    Motivo da rejeição
                    <input name="review_reason" placeholder="Explique por que a solicitação foi rejeitada" required />
                  </label>
                </div>
                <div className="form-footer">
                  <span>Nenhum dado do Auth será alterado.</span>
                  <button className="secondary-button" type="submit">
                    Rejeitar solicitação
                  </button>
                </div>
              </form>
            </div>
          ) : null}

          {selectedEmailChangeRequest?.status === "approved" ? (
            <div className="empty-state">
              <strong>Endereço aprovado pelo administrador</strong>
              <span>O usuário deve entrar no sistema e enviar a confirmação para esse endereço.</span>
            </div>
          ) : null}

          {selectedEmailChangeRequest?.status === "confirmation_pending" ? (
            <div className="empty-state">
              <strong>Aguardando confirmação do titular</strong>
              <span>O e-mail atual permanece válido até o novo endereço ser confirmado.</span>
            </div>
          ) : null}
        </section>

        <section className="panel" id="perfis" aria-labelledby="perfis-title">
          <div className="panel-header">
            <h2 id="perfis-title">Perfis</h2>
            <span className="pill">{dashboard.source}</span>
          </div>
          <div className="table-scroll">
            <table className="data-table security-profile-table">
              <thead>
                <tr>
                  <th>Usuário</th>
                  <th>E-mail</th>
                  <th>Confirmação</th>
                  <th>Função organizacional</th>
                  <th>Status</th>
                  <th>Overrides</th>
                  <th>Selecionar</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.profiles.length === 0 ? (
                  <tr>
                    <td colSpan={7}>Nenhum perfil encontrado.</td>
                  </tr>
                ) : (
                  dashboard.profiles.map((profile) => (
                    <ProfileRow key={profile.id} profile={profile} selected={profile.id === dashboard.selectedProfile?.id} />
                  ))
                )}
              </tbody>
            </table>
          </div>
        </section>

        <details className="panel" id="alcadas">
          <summary>Exceções avançadas</summary>
          <div className="panel-header">
            <div>
              <h2 id="alcadas-title">Resumo das capacidades efetivas</h2>
              <p className="muted">{dashboard.selectedProfile ? `${effectivePermissionCount} capacidades efetivas pelos perfis de acesso e exceções individuais.` : "Selecione uma conta para consultar capacidades efetivas."}</p>
            </div>
            <form className="security-user-picker" action="/seguranca" method="get">
              <select name="user_id" defaultValue={selectedProfile?.id ?? ""}>
                {dashboard.profiles.map((profile) => (
                  <option value={profile.id} key={profile.id}>
                    {profile.displayName} - {securityRoleLabel(profile.role)}
                  </option>
                ))}
              </select>
              <button className="secondary-button" type="submit">
                Ver
              </button>
            </form>
          </div>
          <div className="table-scroll">
            <table className="data-table security-permission-table">
              <thead>
                <tr>
                  <th>Modulo</th>
                  <th>Acao</th>
                  <th>Base legada</th>
                  <th>Exceção individual</th>
                  <th>Acesso atual</th>
                  <th>Alterar acesso</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.permissions.length === 0 || !selectedProfile ? (
                  <tr>
                    <td colSpan={6}>Selecione um perfil operacional para ver alcadas.</td>
                  </tr>
                ) : (
                  dashboard.permissions.map((permission) => (
                    <PermissionRow
                      key={permission.actionKey}
                      permission={permission}
                      selectedProfile={selectedProfile}
                    />
                  ))
                )}
              </tbody>
            </table>
          </div>
        </details>

        <section className="panel" id="perfis-acesso" aria-labelledby="perfis-acesso-title">
          <div className="panel-header">
            <div>
              <h2 id="perfis-acesso-title">Perfis de acesso combinados</h2>
              <p className="muted">Cada perfil e versionado e concede somente capacidades atomicas cadastradas. A combinacao nao altera a funcao comercial.</p>
            </div>
            <span className="pill">{dashboard.selectedAccessProfiles.length} atribuido(s)</span>
          </div>
          {!selectedProfile || selectedProfile.isSystemActor ? (
            <div className="empty-state"><strong>Selecione uma conta operacional</strong><span>Atores de sistema nao recebem perfil humano.</span></div>
          ) : (
            <>
              <div className="table-scroll">
                <table className="data-table">
                  <thead><tr><th>Perfil</th><th>Versao</th><th>Concedido em</th><th>Motivo</th><th>Acao</th></tr></thead>
                  <tbody>
                    {dashboard.selectedAccessProfiles.length === 0 ? (
                      <tr><td colSpan={5}>Nenhum perfil de acesso atribuido.</td></tr>
                    ) : dashboard.selectedAccessProfiles.map((assigned) => (
                      <tr key={assigned.profileId}>
                        <td><strong>{assigned.profileName}</strong><span className="table-subtext">{assigned.profileKey}</span></td>
                        <td>v{assigned.profileVersion}</td><td>{assigned.assignedAt}</td><td>{assigned.reason}</td>
                        <td><form action={removeSecurityAccessProfileAction}><input type="hidden" name="user_id" value={selectedProfile.id} /><input type="hidden" name="profile_id" value={assigned.profileId} /><input type="hidden" name="reason" value="Remocao administrativa solicitada" /><button className="secondary-button" type="submit">Remover</button></form></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <form action={assignSecurityAccessProfileAction} className="form-footer">
                <input type="hidden" name="user_id" value={selectedProfile.id} />
                <select name="profile_id" defaultValue="" required>
                  <option value="">Adicionar perfil de acesso</option>
                  {dashboard.accessProfiles.filter((profile) => !dashboard.selectedAccessProfiles.some((assigned) => assigned.profileId === profile.id)).map((profile) => (
                    <option value={profile.id} key={profile.id}>{profile.name} · {profile.permissionCount} capacidades</option>
                  ))}
                </select>
                <input name="reason" placeholder="Motivo da atribuição (mínimo 10 caracteres)" minLength={10} required />
                <button className="primary-button" type="submit">Atribuir perfil</button>
              </form>
            </>
          )}
        </section>
      </section>
    </main>
  );
}

function ProfileRow({ profile, selected }: { profile: SecurityProfile; selected: boolean }) {
  return (
    <tr>
      <td>
        <strong>{profile.displayName}</strong>
        {profile.systemActorKey ? <span className="table-subtext">{profile.systemActorKey}</span> : null}
      </td>
      <td>{profile.email ?? "-"}</td>
      <td>
        <span className={`status-chip ${emailStatusTone(profile.emailStatus)}`}>
          {emailStatusLabel(profile.emailStatus)}
        </span>
      </td>
      <td>{securityRoleLabel(profile.role)}</td>
      <td>
        <span className={`status-chip ${profile.status}`}>{internalValueLabel(profile.status)}</span>
      </td>
      <td>{profile.overridesCount}</td>
      <td>
        <a className={selected ? "primary-button" : "secondary-button"} href={`/seguranca?user_id=${profile.id}#alcadas`}>
          {selected ? "Selecionado" : "Selecionar"}
        </a>
      </td>
    </tr>
  );
}

function PermissionRow({
  permission,
  selectedProfile
}: {
  permission: EffectivePermission;
  selectedProfile: SecurityProfile;
}) {
  const disabled = selectedProfile.isSystemActor;

  return (
    <tr>
      <td>{securityModuleLabel(permission.module)}</td>
      <td>
        <strong>{permission.description}</strong>
        <span className="table-subtext">Permissão operacional governada</span>
      </td>
      <td>{permission.defaultAllowed ? "Permitido" : "Negado"}</td>
      <td>
  {permission.overrideAllowed === null
    ? "Sem exceção"
    : permission.overrideAllowed
      ? "Permitido para este usuário"
      : "Negado para este usuário"}
</td>
      <td>
        <span className={`status-chip ${permission.effectiveAllowed ? "ativo" : "alta"}`}>
          {permission.effectiveAllowed ? "Permitido" : "Negado"}
        </span>
      </td>
      <td>
        <div className="permission-actions">
          <form action={setSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <input name="allowed" type="hidden" value="true" />
            <button className="secondary-button" type="submit" disabled={disabled}>
              Permitir para este usuário
            </button>
          </form>
          <form action={setSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <input name="allowed" type="hidden" value="false" />
            <button className="secondary-button" type="submit" disabled={disabled}>
              Negar para este usuário
            </button>
          </form>
          <form action={clearSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <button className="secondary-button" type="submit" disabled={disabled || permission.overrideAllowed === null}>
              Voltar a base legada
            </button>
          </form>
        </div>
      </td>
    </tr>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function singleValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function positiveInteger(value: string | null): number | null {
  if (!value || !/^[1-9]\d*$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function messageForResult(result: string | null): { kind: "ok" | "warning"; title: string; detail: string } | null {
  switch (result) {
    case "profile_saved":
      return { kind: "ok", title: "Perfil salvo", detail: "O perfil operacional foi gravado com auditoria." };
    case "person_linked":
      return { kind: "ok", title: "Identidade vinculada", detail: "A conta agora representa a pessoa comercial selecionada." };
    case "missing_person_link_required":
      return { kind: "warning", title: "Dados incompletos", detail: "Selecione a pessoa e informe uma justificativa com pelo menos 10 caracteres." };
    case "person_link_conflict":
      return { kind: "warning", title: "Vínculo existente", detail: "A conta ou a pessoa já está vinculada a outra identidade operacional." };
    case "person_inactive":
      return { kind: "warning", title: "Pessoa inativa", detail: "Somente uma pessoa comercial ativa pode receber uma conta." };
    case "person_not_found":
      return { kind: "warning", title: "Pessoa não localizada", detail: "A pessoa selecionada não está mais disponível." };
    case "auth_invitation_sent":
      return { kind: "ok", title: "Convite enviado", detail: "A conta permanecerá pendente até o e-mail ser confirmado e a senha ser criada." };
    case "permission_saved":
      return { kind: "ok", title: "Alçada atualizada", detail: "A exceção individual de permissão foi registrada." };
    case "permission_cleared":
      return { kind: "ok", title: "Decisão individual removida", detail: "O usuário voltou ao padrão da ação." };
    case "not_configured":
      return { kind: "warning", title: "Supabase nao configurado", detail: "Configure o ambiente antes de gravar." };
    case "service_role_missing":
      return { kind: "warning", title: "Configuração segura ausente", detail: "O administrador precisa concluir a configuração protegida do servidor." };
    case "auth_user_create_failed":
      return { kind: "warning", title: "Convite não criado", detail: "O serviço de identidade recusou a criação da conta." };
    case "auth_user_exists":
      return { kind: "warning", title: "E-mail já cadastrado", detail: "Este endereço já pertence a uma conta do sistema. Consulte o status na lista abaixo." };
    case "permission_denied":
      return { kind: "warning", title: "Permissao negada", detail: "Seu perfil nao tem alcada para esta operacao." };
    case "auth_user_missing":
      return { kind: "warning", title: "Conta de acesso ausente", detail: "Crie a conta de acesso antes do perfil operacional." };
    case "system_actor_blocked":
      return { kind: "warning", title: "Ator protegido", detail: "Atores de sistema nao usam fluxo operacional." };
    case "permission_action_not_found":
      return { kind: "warning", title: "Permissão inválida", detail: "A permissão informada não existe no catálogo." };
    case "target_profile_not_found":
      return { kind: "warning", title: "Perfil nao encontrado", detail: "Selecione um perfil existente." };
    case "invalid_uuid":
      return { kind: "warning", title: "Identificador inválido", detail: "Informe um identificador válido da conta de acesso." };
    case "invalid_email":
      return { kind: "warning", title: "Email invalido", detail: "Informe um email valido para login." };
    case "fictitious_email":
      return { kind: "warning", title: "E-mail fictício bloqueado", detail: "Informe um endereço real que possa receber a confirmação." };
    case "email_change_approved":
      return { kind: "ok", title: "Novo e-mail aprovado", detail: "O usuário agora pode enviar a confirmação para o endereço definido." };
    case "email_change_rejected":
      return { kind: "ok", title: "Solicitação rejeitada", detail: "Nenhum e-mail do Auth foi alterado." };
    case "email_review_reason_required":
      return { kind: "warning", title: "Motivo obrigatório", detail: "Registre o motivo da decisão administrativa." };
    case "invalid_email_review":
      return { kind: "warning", title: "Decisão inválida", detail: "Use aprovar ou rejeitar." };
    case "admin_role_required":
      return { kind: "warning", title: "Administrador obrigatório", detail: "Somente perfil admin pode decidir a troca de e-mail." };
    case "email_change_request_not_found":
      return { kind: "warning", title: "Solicitação não encontrada", detail: "Atualize a tela e selecione uma solicitação existente." };
    case "email_change_request_not_pending":
      return { kind: "warning", title: "Solicitação já analisada", detail: "Esta solicitação não aceita uma segunda decisão." };
    case "email_unchanged":
      return { kind: "warning", title: "E-mail não alterado", detail: "O endereço informado já é o e-mail atual do usuário." };
    case "invalid_role":
      return { kind: "warning", title: "Papel invalido", detail: "Escolha um papel permitido." };
    case "invalid_status":
      return { kind: "warning", title: "Situação inválida", detail: "Escolha Ativo ou Inativo." };
    case "missing_profile_required":
    case "missing_auth_user_required":
    case "missing_permission_required":
      return { kind: "warning", title: "Campos obrigatorios", detail: "Preencha os campos exigidos." };
    case "security_error":
      return { kind: "warning", title: "Falha de seguranca", detail: "A operacao nao foi concluida." };
    default:
      return null;
  }
}

function emailChangeStatusLabel(status: string): string {
  const labels: Record<string, string> = {
    approved: "aprovada",
    confirmation_pending: "aguardando confirmação",
    pending_admin: "aguardando administrador"
  };
  return labels[status] ?? "Situação não reconhecida";
}

function emailChangeReasonLabel(reason: string): string {
  const labels: Record<string, string> = {
    lost_access: "Sem acesso ao e-mail atual",
    other: "Outro",
    professional_change: "Alteração de e-mail profissional",
    registration_correction: "Correção de cadastro"
  };
  return labels[reason] ?? "Motivo não reconhecido";
}

function securityModuleLabel(moduleKey: string): string {
  const labels: Record<string, string> = {
    cadastros: "Cadastros",
    core: "Núcleo",
    estoque: "Estoque",
    expedicao: "Expedição",
    faturamento: "Faturamento",
    financeiro: "Financeiro",
    importacao: "Importação",
    metas: "Metas",
    pedidos: "Pedidos",
    pcp: "Produção",
    relatorios: "Relatórios",
    security: "Segurança",
    seguranca: "Segurança",
  };
  return labels[moduleKey] ?? "Módulo não reconhecido";
}

function securityRoleLabel(role: string): string {
  const labels: Record<string, string> = {
    admin: "Administrador",
    auditoria: "Auditoria",
    comercial: "Comercial",
    estoque: "Estoque",
    expedicao: "Expedição",
    producao: "Produção"
  };
  return labels[role] ?? "Função não reconhecida";
}

function emailStatusLabel(status: SecurityProfile["emailStatus"]): string {
  const labels: Record<SecurityProfile["emailStatus"], string> = {
    confirmed: "confirmado",
    missing: "ausente",
    not_applicable: "não aplicável",
    pending_activation: "e-mail confirmado; falta criar senha",
    pending_confirmation: "aguardando confirmação",
    placeholder: "e-mail fictício"
  };
  return labels[status];
}

function emailStatusTone(status: SecurityProfile["emailStatus"]): string {
  if (status === "confirmed") return "active";
  if (status === "pending_activation" || status === "pending_confirmation") return "pending";
  if (status === "not_applicable") return "blocked";
  return "rejected";
}
