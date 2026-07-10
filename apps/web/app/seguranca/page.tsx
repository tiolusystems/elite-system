import Link from "next/link";

import {
  clearSecurityPermissionOverrideAction,
  createSecurityAuthUserWithTemporaryPasswordAction,
  setSecurityPermissionOverrideAction,
  upsertSecurityUserProfileAction
} from "@/app/seguranca/actions";
import { getRuntimeStatus } from "@/lib/runtime";
import { getSecurityDashboard, type EffectivePermission, type SecurityProfile } from "@/lib/security";

type SearchParams = Record<string, string | string[] | undefined>;

export const dynamic = "force-dynamic";

const ROLES = ["admin", "comercial", "producao", "estoque", "expedicao", "auditoria"];

export default async function SegurancaPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const selectedUserId = singleValue(params.user_id);
  const result = singleValue(params.result);
  const runtime = getRuntimeStatus();
  const dashboard = await getSecurityDashboard(selectedUserId);
  const formMessage = messageForResult(result);
  const selectedProfile = dashboard.selectedProfile;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Seguranca</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp">PCP</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca" aria-current="page">
            Seguranca
          </a>
          <a href="/login">Login</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace">
        <div className="toolbar">
          <div>
            <h1>Seguranca e alcadas</h1>
            <p className="muted">
              Perfis vinculados ao Supabase Auth, checks por usuario e auditoria das mudancas de permissao.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de seguranca">
            <a className="secondary-button" href="/login">
              Login
            </a>
            <a className="secondary-button" href="#novo-acesso">
              Novo acesso
            </a>
            <a className="primary-button" href="#perfil">
              Perfil
            </a>
          </div>
        </div>

        <section className="summary-grid" aria-label="Resumo de seguranca">
          <div className="summary-card">
            <span>Perfis</span>
            <strong>{valueOrDash(dashboard.metrics.totalProfiles)}</strong>
          </div>
          <div className="summary-card">
            <span>Ativos</span>
            <strong>{valueOrDash(dashboard.metrics.activeProfiles)}</strong>
          </div>
          <div className="summary-card">
            <span>Atores de sistema</span>
            <strong>{valueOrDash(dashboard.metrics.systemActors)}</strong>
          </div>
          <div className="summary-card">
            <span>Overrides</span>
            <strong>{valueOrDash(dashboard.metrics.overrides)}</strong>
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
              <h2 id="novo-acesso-title">Novo acesso por email</h2>
              <span className="pill">{runtime.supabaseConfigured ? "Auth + auditoria" : "aguardando Supabase"}</span>
            </div>
            <form action={createSecurityAuthUserWithTemporaryPasswordAction}>
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
                  <select name="role" defaultValue="comercial">
                    {ROLES.map((role) => (
                      <option value={role} key={role}>
                        {role}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Status
                  <select name="status" defaultValue="active">
                    <option value="active">active</option>
                    <option value="inactive">inactive</option>
                  </select>
                </label>
              </div>
              <div className="form-footer">
                <span>Senha temporaria enviada pelo canal configurado. Credenciais nao entram no log.</span>
                <button className="primary-button" type="submit">
                  Criar e enviar
                </button>
              </div>
            </form>
          </section>

          <section className="panel form-panel" id="perfil" aria-labelledby="perfil-title">
            <div className="panel-header">
              <h2 id="perfil-title">Perfil operacional</h2>
              <span className="pill">{runtime.supabaseConfigured ? "RPC auditada" : "aguardando Supabase"}</span>
            </div>
            <form action={upsertSecurityUserProfileAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Auth user id
                  <input name="user_id" placeholder="UUID do usuario no Supabase Auth" required />
                </label>
                <label className="wide-field">
                  Nome
                  <input name="display_name" placeholder="Nome exibido no sistema" required />
                </label>
                <label>
                  Papel
                  <select name="role" defaultValue="comercial">
                    {ROLES.map((role) => (
                      <option value={role} key={role}>
                        {role}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Status
                  <select name="status" defaultValue="active">
                    <option value="active">active</option>
                    <option value="inactive">inactive</option>
                  </select>
                </label>
              </div>
              <div className="form-footer">
                <span>O usuario precisa existir no Supabase Auth antes do perfil operacional.</span>
                <button className="primary-button" type="submit">
                  Salvar perfil
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="selecao-title">
            <div className="panel-header">
              <h2 id="selecao-title">Usuario selecionado</h2>
              <span className="pill">{dashboard.selectedProfile ? dashboard.selectedProfile.role : "vazio"}</span>
            </div>
            {dashboard.selectedProfile ? (
              <dl className="status-list">
                <div className="status-row">
                  <dt>Nome</dt>
                  <dd>{dashboard.selectedProfile.displayName}</dd>
                </div>
                <div className="status-row">
                  <dt>Status</dt>
                  <dd>
                    <span className={`status-chip ${dashboard.selectedProfile.status}`}>
                      {dashboard.selectedProfile.status}
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
          </section>
        </section>

        <section className="panel" aria-labelledby="perfis-title">
          <div className="panel-header">
            <h2 id="perfis-title">Perfis</h2>
            <span className="pill">{dashboard.source}</span>
          </div>
          <div className="table-scroll">
            <table className="data-table security-profile-table">
              <thead>
                <tr>
                  <th>Usuario</th>
                  <th>Papel</th>
                  <th>Status</th>
                  <th>Overrides</th>
                  <th>Atualizado</th>
                  <th>Selecionar</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.profiles.length === 0 ? (
                  <tr>
                    <td colSpan={6}>Nenhum perfil encontrado.</td>
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

        <section className="panel" id="alcadas" aria-labelledby="alcadas-title">
          <div className="panel-header">
            <h2 id="alcadas-title">Alcadas efetivas</h2>
            <form className="security-user-picker" action="/seguranca" method="get">
              <select name="user_id" defaultValue={selectedProfile?.id ?? ""}>
                {dashboard.profiles.map((profile) => (
                  <option value={profile.id} key={profile.id}>
                    {profile.displayName} - {profile.role}
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
                  <th>Default</th>
                  <th>Override</th>
                  <th>Efetivo</th>
                  <th>Controle</th>
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
        <span className="table-subtext">{profile.id}</span>
        {profile.systemActorKey ? <span className="table-subtext">{profile.systemActorKey}</span> : null}
      </td>
      <td>{profile.role}</td>
      <td>
        <span className={`status-chip ${profile.status}`}>{profile.status}</span>
      </td>
      <td>{profile.overridesCount}</td>
      <td>{formatDate(profile.updatedAt)}</td>
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
      <td>{permission.module}</td>
      <td>
        <strong>{permission.actionKey}</strong>
        <span className="table-subtext">{permission.description}</span>
      </td>
      <td>{labelForBoolean(permission.defaultAllowed)}</td>
      <td>{permission.overrideAllowed === null ? "default" : labelForBoolean(permission.overrideAllowed)}</td>
      <td>
        <span className={`status-chip ${permission.effectiveAllowed ? "ativo" : "alta"}`}>
          {permission.effectiveAllowed ? "permitido" : "bloqueado"}
        </span>
      </td>
      <td>
        <div className="permission-actions">
          <form action={setSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <input name="allowed" type="hidden" value="true" />
            <button className="secondary-button" type="submit" disabled={disabled}>
              Permitir
            </button>
          </form>
          <form action={setSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <input name="allowed" type="hidden" value="false" />
            <button className="secondary-button" type="submit" disabled={disabled}>
              Bloquear
            </button>
          </form>
          <form action={clearSecurityPermissionOverrideAction}>
            <input name="user_id" type="hidden" value={selectedProfile.id} />
            <input name="action_key" type="hidden" value={permission.actionKey} />
            <button className="secondary-button" type="submit" disabled={disabled || permission.overrideAllowed === null}>
              Default
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

function labelForBoolean(value: boolean): string {
  return value ? "permitido" : "bloqueado";
}

function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(date);
}

function singleValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function messageForResult(result: string | null): { kind: "ok" | "warning"; title: string; detail: string } | null {
  switch (result) {
    case "profile_saved":
      return { kind: "ok", title: "Perfil salvo", detail: "O perfil operacional foi gravado com auditoria." };
    case "auth_user_created":
      return { kind: "ok", title: "Acesso criado", detail: "O usuario Auth foi criado e a senha temporaria foi enviada pelo canal configurado." };
    case "permission_saved":
      return { kind: "ok", title: "Alcada atualizada", detail: "O override de permissao foi registrado." };
    case "permission_cleared":
      return { kind: "ok", title: "Override removido", detail: "O usuario voltou ao default da action key." };
    case "not_configured":
      return { kind: "warning", title: "Supabase nao configurado", detail: "Configure o ambiente antes de gravar." };
    case "service_role_missing":
      return { kind: "warning", title: "Service role ausente", detail: "Configure SUPABASE_SERVICE_ROLE_KEY somente no servidor." };
    case "temp_password_mailer_missing":
      return { kind: "warning", title: "Envio nao configurado", detail: "Configure ELITE_TEMP_PASSWORD_EMAIL_WEBHOOK_URL antes de criar senha temporaria." };
    case "temp_password_email_failed":
      return { kind: "warning", title: "Envio falhou", detail: "A senha temporaria nao foi entregue pelo canal configurado." };
    case "auth_user_create_failed":
      return { kind: "warning", title: "Auth nao criado", detail: "O Supabase Auth recusou a criacao do usuario." };
    case "permission_denied":
      return { kind: "warning", title: "Permissao negada", detail: "Seu perfil nao tem alcada para esta operacao." };
    case "auth_user_missing":
      return { kind: "warning", title: "Auth ausente", detail: "Crie o usuario no Supabase Auth antes do perfil." };
    case "system_actor_blocked":
      return { kind: "warning", title: "Ator protegido", detail: "Atores de sistema nao usam fluxo operacional." };
    case "permission_action_not_found":
      return { kind: "warning", title: "Action key invalida", detail: "A permissao informada nao existe no catalogo." };
    case "target_profile_not_found":
      return { kind: "warning", title: "Perfil nao encontrado", detail: "Selecione um perfil existente." };
    case "invalid_uuid":
      return { kind: "warning", title: "UUID invalido", detail: "Informe um identificador valido do Supabase Auth." };
    case "invalid_email":
      return { kind: "warning", title: "Email invalido", detail: "Informe um email valido para login." };
    case "invalid_role":
      return { kind: "warning", title: "Papel invalido", detail: "Escolha um papel permitido." };
    case "invalid_status":
      return { kind: "warning", title: "Status invalido", detail: "Escolha active ou inactive." };
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
