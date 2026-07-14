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
import {
  getSystemModuleDetail,
  moduleMaturityPercent,
  SYSTEM_DEPLOYMENT_GATES,
  SYSTEM_FLOWS,
  SYSTEM_MAP_LANES,
  type SystemDeploymentGateKey
} from "@/lib/system-map";

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

export default async function ModulosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
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
  const deploymentGates = SYSTEM_DEPLOYMENT_GATES.map((gate) => ({
    ...gate,
    state: deploymentGateState(gate.gateKey, dashboard.activeEnvironment, dashboard.modules)
  }));

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
            <h1>Mapa e prontidao dos modulos</h1>
            <p className="muted">
              Veja como o sistema se encaixa e qual maturidade o banco autoriza em cada bloco.
            </p>
          </div>
          <div className="toolbar-actions">
            <a className="secondary-button" href="#implantacao">Implantacao</a>
            <a className="secondary-button" href="#mapa">Mapa</a>
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

        <section className="deployment-roadmap" id="implantacao" aria-labelledby="implantacao-title">
          <div className="architecture-heading">
            <div>
              <span className="eyebrow">caminho ate a operacao</span>
              <h2 id="implantacao-title">O que esta pronto e o que vem depois</h2>
              <p className="muted">
                O PostgreSQL continua sendo a fonte de maturidade. Esta visao apenas traduz os gates para o trabalho diario.
              </p>
            </div>
            <span className="pill">Ambiente: {environmentLabel(dashboard.activeEnvironment)}</span>
          </div>
          <ol className="deployment-gate-grid">
            {deploymentGates.map((gate, index) => (
              <li className={`deployment-gate ${gate.state}`} key={gate.gateKey}>
                <span className="deployment-gate-number" aria-hidden="true">{index + 1}</span>
                <div>
                  <div className="deployment-gate-head">
                    <strong>{gate.label}</strong>
                    <span>{deploymentGateStateLabel(gate.state)}</span>
                  </div>
                  <p>{gate.description}</p>
                  <small>Comprovacao: {gate.evidence}</small>
                </div>
              </li>
            ))}
          </ol>
          <div className="deployment-next-step">
            <strong>Proximo marco global</strong>
            <span>{nextDeploymentMilestone(dashboard.activeEnvironment)}</span>
          </div>
        </section>

        <section className="architecture-overview" id="mapa" aria-labelledby="mapa-title">
          <div className="architecture-heading">
            <div>
              <span className="eyebrow">visao do sistema</span>
              <h2 id="mapa-title">Da fundacao ao controle</h2>
              <p className="muted">
                Cada bloco tem um dono, depende apenas dos blocos indicados e avanca por gates auditados.
              </p>
            </div>
            <div className="architecture-legend" aria-label="Legenda de maturidade">
              <span><i className="map-dot technical"></i> Tecnica</span>
              <span><i className="map-dot business"></i> Negocio</span>
              <span><i className="map-dot operational"></i> Operacional</span>
              <span><i className="map-dot blocked"></i> Bloqueado</span>
            </div>
          </div>

          <div className="architecture-lanes">
            {SYSTEM_MAP_LANES.map((lane) => (
              <article className="architecture-lane" key={lane.laneKey}>
                <div className="architecture-lane-title">
                  <strong>{lane.label}</strong>
                  <span>{lane.description}</span>
                </div>
                <div className="architecture-node-grid">
                  {lane.moduleKeys.map((moduleKey) => {
                    const detail = getSystemModuleDetail(moduleKey);
                    const current = dashboard.modules.find((module) => module.moduleKey === moduleKey);
                    if (!detail) return null;
                    const maturity = moduleMaturityPercent(current?.lifecycle ?? null);
                    return (
                      <a
                        className={`architecture-node ${lifecycleTone(current?.lifecycle ?? null)} ${current?.available ? "available" : "unavailable"}`}
                        href={`#module-${moduleKey}`}
                        key={moduleKey}
                      >
                        <div className="architecture-node-head">
                          <strong>{detail.shortName}</strong>
                          <span className="architecture-node-status">
                            {lifecycleLabel(current?.lifecycle ?? null)}
                          </span>
                        </div>
                        <p>{detail.description}</p>
                        <div className="architecture-node-progress" aria-label={`Maturidade de ${detail.shortName}: ${lifecycleLabel(current?.lifecycle ?? null)}`}>
                          <span style={{ width: `${maturity}%` }}></span>
                        </div>
                        <span className="architecture-node-meta">
                          {detail.dependencies.filter((dependency) => dependency.required).length} dependencia(s) obrigatoria(s)
                        </span>
                        <span className="architecture-node-next">
                          <strong>Proxima validacao:</strong>{" "}
                          {moduleNextStep(detail.primaryRoute, current?.lifecycle ?? null, current?.available ?? false, dashboard.activeEnvironment)}
                        </span>
                      </a>
                    );
                  })}
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="architecture-flows" aria-labelledby="fluxos-title">
          <div className="architecture-heading compact">
            <div>
              <span className="eyebrow">fluxos ponta a ponta</span>
              <h2 id="fluxos-title">Como os blocos trabalham juntos</h2>
            </div>
            <span className="architecture-note">A seta indica dependencia de processo, nao permissao de escrita direta.</span>
          </div>
          <div className="architecture-flow-list">
            {SYSTEM_FLOWS.map((flow) => (
              <article className="architecture-flow" key={flow.flowKey}>
                <div className="architecture-flow-title">
                  <strong>{flow.title}</strong>
                  <span>{flow.description}</span>
                </div>
                <div className="architecture-flow-steps">
                  {flow.moduleKeys.map((moduleKey, index) => {
                    const detail = getSystemModuleDetail(moduleKey);
                    return (
                      <div className="architecture-flow-step" key={`${flow.flowKey}:${moduleKey}:${index}`}>
                        {index > 0 ? <span className="architecture-arrow" aria-hidden="true">&rarr;</span> : null}
                        <a href={`#module-${moduleKey}`}>{detail?.shortName ?? moduleKey}</a>
                      </div>
                    );
                  })}
                </div>
              </article>
            ))}
          </div>
        </section>

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
                  <tr id={`module-${module.moduleKey}`} key={module.moduleKey}>
                    <td>
                      <strong>{module.displayName}</strong>
                      <span className="table-subtext">{module.moduleKey} - dono: {module.ownerDomain}</span>
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

type DeploymentGateState = "complete" | "current" | "next" | "pending";
type DeploymentModule = { isCore: boolean; lifecycle: ModuleLifecycle | null };

function deploymentGateState(
  gateKey: SystemDeploymentGateKey,
  activeEnvironment: SystemEnvironment,
  modules: readonly DeploymentModule[]
): DeploymentGateState {
  const businessModules = modules.filter((module) => !module.isCore);
  const allBusinessReady = businessModules.length > 0 && businessModules.every((module) =>
    module.lifecycle === "pilot" || module.lifecycle === "operational"
  );
  const hasPilot = businessModules.some((module) => module.lifecycle === "pilot");

  switch (gateKey) {
    case "architecture":
      return "complete";
    case "local_validation":
      if (activeEnvironment === "test" || activeEnvironment === "staging" || activeEnvironment === "production") return "complete";
      return activeEnvironment === "development" ? "current" : "next";
    case "business_validation":
      if (allBusinessReady) return "complete";
      return activeEnvironment === "unconfigured" ? "pending" : "current";
    case "staging":
      if (activeEnvironment === "production") return "complete";
      if (activeEnvironment === "staging") return "current";
      return activeEnvironment === "test" ? "next" : "pending";
    case "pilot":
      if (activeEnvironment === "production") return "complete";
      if (hasPilot) return "current";
      return activeEnvironment === "staging" ? "next" : "pending";
    case "production":
      return activeEnvironment === "production" ? "current" : "pending";
  }
}

function deploymentGateStateLabel(state: DeploymentGateState): string {
  const labels: Record<DeploymentGateState, string> = {
    complete: "Concluido",
    current: "Em andamento",
    next: "Proximo",
    pending: "Pendente"
  };
  return labels[state];
}

function nextDeploymentMilestone(activeEnvironment: SystemEnvironment): string {
  if (activeEnvironment === "unconfigured") return "Configurar o ambiente autoritativo antes de liberar modulos.";
  if (activeEnvironment === "development") return "Concluir os testes locais e registrar o ambiente de teste.";
  if (activeEnvironment === "test") return "Publicar uma homologacao online separada, sem dados operacionais reais.";
  if (activeEnvironment === "staging") return "Homologar os fluxos ponta a ponta e iniciar o piloto controlado.";
  return "Monitorar a operacao e promover cada modulo somente por rollout auditado.";
}

function moduleNextStep(
  primaryRoute: string | null,
  lifecycle: ModuleLifecycle | null,
  available: boolean,
  activeEnvironment: SystemEnvironment
): string {
  if (!available) return "Liberar as dependencias obrigatorias indicadas no catalogo.";
  if (!lifecycle || lifecycle === "construction") return "Concluir implementacao e validacao tecnica local.";
  if (lifecycle === "technical_validation") {
    return primaryRoute
      ? "Revisar a tela e executar o fluxo real com o responsavel do negocio."
      : "Construir a tela dedicada e executar a validacao tecnica.";
  }
  if (lifecycle === "business_validation") return "Homologar cenarios reais e registrar as pendencias encontradas.";
  if (lifecycle === "pilot") return "Executar o piloto com usuarios definidos e monitorar falhas.";
  if (lifecycle === "suspended") return "Resolver o motivo da suspensao antes de nova promocao.";
  if (activeEnvironment !== "production") return "Repetir a homologacao no ambiente cloud antes da liberacao final.";
  return "Monitorar indicadores, auditoria, backup e incidentes.";
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

function lifecycleTone(value: ModuleLifecycle | null): string {
  if (value === "operational" || value === "pilot") return "operational";
  if (value === "business_validation") return "business";
  if (value === "technical_validation" || value === "construction") return "technical";
  return "blocked";
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
