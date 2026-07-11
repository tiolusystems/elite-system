import Link from "next/link";

import {
  setSystemModuleRolloutAction,
  setSystemRuntimeEnvironmentAction
} from "@/app/modulos/actions";
import {
  getModuleRuntimeDashboard,
  type ModuleAccessMode,
  type ModuleLifecycle,
  type SystemEnvironment
} from "@/lib/modules";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export const dynamic = "force-dynamic";

const ENVIRONMENTS: SystemEnvironment[] = ["unconfigured", "development", "test", "staging", "production"];
const ROLLOUT_ENVIRONMENTS: SystemEnvironment[] = ["development", "test", "staging", "production"];
const LIFECYCLES: ModuleLifecycle[] = [
  "construction",
  "technical_validation",
  "business_validation",
  "pilot",
  "operational",
  "suspended"
];
const ACCESS_MODES: ModuleAccessMode[] = ["disabled", "read_only", "read_write"];

export default async function ModulosPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const result = singleValue(params.result);
  const changedModule = singleValue(params.module);
  const viewedEnvironment = parseEnvironment(singleValue(params.environment));
  const runtime = getRuntimeStatus();
  const dashboard = await getModuleRuntimeDashboard(viewedEnvironment);
  const message = messageForResult(result, changedModule);
  const defaultTargetEnvironment = dashboard.environment === "unconfigured" ? "test" : dashboard.environment;
  const environmentMismatch =
    runtime.databaseMode !== "not_configured" &&
    dashboard.activeEnvironment !== "unconfigured" &&
    runtime.databaseMode !== dashboard.activeEnvironment;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Implantacao modular</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos" aria-current="page">Modulos</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/producao">Producao</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
        </nav>
      </header>

      <aside className={`db-banner ${dashboard.activeEnvironment === "production" ? "operational" : ""}`}>
        <strong>DB ativo: {environmentLabel(dashboard.activeEnvironment)}</strong>
        <span>Estado autoritativo do PostgreSQL. Frontend declarado: {runtime.databaseMode}.</span>
        <span className="pill">{dashboard.source}</span>
      </aside>

      <section className="workspace module-runtime-workspace">
        <div className="toolbar">
          <div>
            <span className="eyebrow">liberacao progressiva</span>
            <h1>Prontidao dos modulos</h1>
            <p className="muted">
              Maturidade, acesso efetivo e dependencias controlados pelo banco antes de qualquer operacao.
            </p>
          </div>
          <div className="toolbar-actions">
            <a className="secondary-button" href="#ambiente">Ambiente</a>
            <a className="primary-button" href="#catalogo">Rollout</a>
          </div>
        </div>

        <section className="summary-grid" aria-label="Resumo da implantacao">
          <div className="summary-card">
            <span>Catalogados</span>
            <strong>{dashboard.metrics.total}</strong>
          </div>
          <div className="summary-card">
            <span>Disponiveis</span>
            <strong>{dashboard.metrics.available}</strong>
          </div>
          <div className="summary-card">
            <span>Com escrita</span>
            <strong>{dashboard.metrics.readWrite}</strong>
          </div>
          <div className="summary-card">
            <span>Bloqueados</span>
            <strong>{dashboard.metrics.blocked}</strong>
          </div>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Contrato de runtime indisponivel</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {environmentMismatch ? (
          <section className="notice-panel warning" role="alert">
            <strong>Ambientes divergentes</strong>
            <span>
              `ELITE_DATABASE_MODE` informa {runtime.databaseMode}, mas o banco declara {dashboard.activeEnvironment}. Corrija antes de homologar.
            </span>
          </section>
        ) : null}

        {message ? (
          <section className={`notice-panel ${message.kind}`} role="status">
            <strong>{message.title}</strong>
            <span>{message.detail}</span>
          </section>
        ) : null}

        <section className="panel form-panel" id="ambiente" aria-labelledby="ambiente-title">
          <div className="panel-header">
            <h2 id="ambiente-title">Ambiente autoritativo do banco</h2>
            <span className="pill">{environmentLabel(dashboard.activeEnvironment)}</span>
          </div>
          <form action={setSystemRuntimeEnvironmentAction} className="module-environment-form">
            <label>
              Novo ambiente
              <select name="environment" defaultValue={dashboard.activeEnvironment} disabled={!dashboard.canManage}>
                {ENVIRONMENTS.map((environment) => (
                  <option value={environment} key={environment}>{environmentLabel(environment)}</option>
                ))}
              </select>
            </label>
            <label>
              Motivo
              <select name="reason_code" defaultValue="initial_configuration" disabled={!dashboard.canManage}>
                <option value="initial_configuration">Configuracao inicial</option>
                <option value="deployment_promotion">Promocao de deploy</option>
                <option value="test_reset">Reinicio de teste</option>
                <option value="rollback">Rollback</option>
                <option value="incident">Incidente</option>
                <option value="other">Outro</option>
              </select>
            </label>
            <label className="wide-field">
              Justificativa
              <input name="reason_detail" placeholder="Registro objetivo da mudanca" disabled={!dashboard.canManage} />
            </label>
            <button className="primary-button" type="submit" disabled={!dashboard.canManage || !runtime.supabaseConfigured}>
              Alterar ambiente
            </button>
          </form>
          <div className="form-footer">
            <span>
              {dashboard.canManage
                ? "A mudanca gera evento append-only e action log."
                : "Seu perfil pode consultar, mas nao possui system.admin para alterar."}
            </span>
          </div>
        </section>

        <section className="panel" id="catalogo" aria-labelledby="catalogo-title">
          <div className="panel-header">
            <h2 id="catalogo-title">Catalogo e dependencias</h2>
            <form method="get" className="module-environment-view">
              <label>
                Visualizar
                <select name="environment" defaultValue={dashboard.environment}>
                  {ENVIRONMENTS.map((environment) => (
                    <option value={environment} key={environment}>{environmentLabel(environment)}</option>
                  ))}
                </select>
              </label>
              <button className="secondary-button" type="submit">Abrir</button>
            </form>
          </div>
          {dashboard.environment !== dashboard.activeEnvironment ? (
            <div className="module-view-banner">
              Preparando {environmentLabel(dashboard.environment)}; o banco continua operando em {environmentLabel(dashboard.activeEnvironment)}.
            </div>
          ) : null}
          <div className="table-scroll">
            <table className="data-table module-runtime-table">
              <thead>
                <tr>
                  <th>Modulo</th>
                  <th>Estado atual</th>
                  <th>Dependencias</th>
                  <th>Promocao auditada</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.modules.map((module) => (
                  <tr key={module.moduleKey}>
                    <td>
                      <strong>{module.displayName}</strong>
                      <span className="table-subtext">{module.moduleKey} · dono: {module.ownerDomain}</span>
                      <span className="table-subtext">{module.description}</span>
                    </td>
                    <td>
                      <span className={`status-chip ${module.available ? "active" : "blocked"}`}>
                        {accessLabel(module.effectiveAccess)}
                      </span>
                      <span className="table-subtext">{lifecycleLabel(module.lifecycle)}</span>
                      <span className="table-subtext">{reasonLabel(module.reason)}</span>
                    </td>
                    <td>
                      {module.blockers.length === 0 ? (
                        <span className="status-chip active">Atendidas</span>
                      ) : (
                        <ul className="module-blocker-list">
                          {module.blockers.map((blocker) => (
                            <li key={`${module.moduleKey}:${blocker.moduleKey}`}>
                              {blocker.moduleKey}: {reasonLabel(blocker.reason)} ({accessLabel(blocker.requiredAccess)})
                            </li>
                          ))}
                        </ul>
                      )}
                    </td>
                    <td>
                      <form action={setSystemModuleRolloutAction} className="module-rollout-form">
                        <input type="hidden" name="module_key" value={module.moduleKey} />
                        <select name="environment" defaultValue={defaultTargetEnvironment} aria-label={`Ambiente de ${module.displayName}`} disabled={!dashboard.canManage || module.isCore}>
                          {ROLLOUT_ENVIRONMENTS.map((environment) => (
                            <option value={environment} key={environment}>{environmentLabel(environment)}</option>
                          ))}
                        </select>
                        <select name="lifecycle" defaultValue={module.lifecycle ?? "technical_validation"} aria-label={`Maturidade de ${module.displayName}`} disabled={!dashboard.canManage || module.isCore}>
                          {LIFECYCLES.map((lifecycle) => (
                            <option value={lifecycle} key={lifecycle}>{lifecycleLabel(lifecycle)}</option>
                          ))}
                        </select>
                        <select name="access_mode" defaultValue={module.configuredAccess} aria-label={`Acesso de ${module.displayName}`} disabled={!dashboard.canManage || module.isCore}>
                          {ACCESS_MODES.map((access) => (
                            <option value={access} key={access}>{accessLabel(access)}</option>
                          ))}
                        </select>
                        <select name="reason_code" defaultValue="technical_validation" aria-label={`Motivo de ${module.displayName}`} disabled={!dashboard.canManage || module.isCore}>
                          <option value="technical_validation">Validacao tecnica</option>
                          <option value="business_validation">Validacao de negocio</option>
                          <option value="pilot_start">Inicio de piloto</option>
                          <option value="production_release">Liberacao de producao</option>
                          <option value="dependency_change">Dependencia</option>
                          <option value="rollback">Rollback</option>
                          <option value="incident">Incidente</option>
                          <option value="other">Outro</option>
                        </select>
                        <input name="reason_detail" placeholder="Justificativa" aria-label={`Justificativa de ${module.displayName}`} disabled={!dashboard.canManage || module.isCore} />
                        <button className="secondary-button" type="submit" disabled={!dashboard.canManage || module.isCore || !runtime.supabaseConfigured}>
                          Registrar
                        </button>
                      </form>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </main>
  );
}

function singleValue(value: string | string[] | undefined): string | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function parseEnvironment(value: string | null): SystemEnvironment | null {
  if (value === "unconfigured" || value === "development" || value === "test" || value === "staging" || value === "production") {
    return value;
  }
  return null;
}

function environmentLabel(value: SystemEnvironment): string {
  const labels: Record<SystemEnvironment, string> = {
    unconfigured: "Nao configurado",
    development: "Desenvolvimento",
    test: "Teste",
    staging: "Homologacao",
    production: "Producao"
  };
  return labels[value];
}

function lifecycleLabel(value: ModuleLifecycle | null): string {
  if (!value) return "Sem rollout";
  const labels: Record<ModuleLifecycle, string> = {
    construction: "Em construcao",
    technical_validation: "Validacao tecnica",
    business_validation: "Validacao de negocio",
    pilot: "Piloto",
    operational: "Operacional",
    suspended: "Suspenso"
  };
  return labels[value];
}

function accessLabel(value: ModuleAccessMode): string {
  const labels: Record<ModuleAccessMode, string> = {
    disabled: "Bloqueado",
    read_only: "Somente leitura",
    read_write: "Leitura e escrita"
  };
  return labels[value];
}

function reasonLabel(value: string): string {
  const labels: Record<string, string> = {
    available: "Disponivel",
    module_disabled: "Desabilitado neste ambiente",
    module_suspended: "Suspenso",
    environment_unconfigured: "Ambiente ainda nao configurado",
    rollout_missing: "Rollout ausente",
    access_insufficient: "Acesso insuficiente",
    lifecycle_not_allowed: "Maturidade insuficiente para o ambiente",
    dependency_unavailable: "Dependencia indisponivel",
    database_not_configured: "Supabase nao configurado",
    runtime_contract_unavailable: "Contrato indisponivel"
  };
  return labels[value] ?? value;
}

function messageForResult(result: string | null, moduleKey: string | null) {
  switch (result) {
    case "environment_changed":
      return { kind: "ok", title: "Ambiente alterado", detail: "O novo ambiente autoritativo foi registrado no ledger." };
    case "rollout_changed":
      return { kind: "ok", title: "Rollout registrado", detail: `O estado de ${moduleKey ?? "modulo"} foi atualizado por novo evento.` };
    case "permission_denied":
      return { kind: "warning", title: "Permissao negada", detail: "Seu perfil nao possui system.admin." };
    case "dependency_unavailable":
      return { kind: "warning", title: "Dependencia pendente", detail: "Ative primeiro as dependencias obrigatorias indicadas na tabela." };
    case "lifecycle_not_allowed":
      return { kind: "warning", title: "Promocao recusada", detail: "A maturidade informada nao permite esse acesso no ambiente escolhido." };
    case "core_protected":
      return { kind: "warning", title: "Nucleo protegido", detail: "O modulo core deve permanecer operacional." };
    case "target_environment_unavailable":
      return { kind: "warning", title: "Ambiente indisponivel", detail: "Core ou seguranca nao estao prontos no ambiente de destino." };
    case "reason_detail_required":
      return { kind: "warning", title: "Justificativa obrigatoria", detail: "Preencha o detalhe quando o motivo for Outro." };
    case "invalid_environment_change":
    case "invalid_rollout_change":
      return { kind: "warning", title: "Parametros invalidos", detail: "Revise ambiente, maturidade, acesso e motivo." };
    case "not_configured":
      return { kind: "warning", title: "Supabase nao configurado", detail: "Configure o backend antes de alterar o rollout." };
    case "module_unavailable":
    case "runtime_change_failed":
      return { kind: "warning", title: "Mudanca nao aplicada", detail: "O banco recusou a transicao e nenhum estado parcial foi gravado." };
    default:
      return null;
  }
}
