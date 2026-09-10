import { getAuthStatus, type AuthStatus } from "@/lib/auth";
import { getMasterDataDashboard } from "@/lib/master-data";
import { getModuleRuntimeDashboard, moduleRuntimeFor } from "@/lib/modules";
import { getOrdersDashboard } from "@/lib/orders";
import { getReportsDashboard } from "@/lib/reports";
import { getImportacaoXmlDashboard } from "@/lib/importacao-xml";
import { getKanbanDashboard } from "@/lib/kanban";
import { getPcpDashboard } from "@/lib/pcp";
import { getRomaneioDashboard } from "@/lib/romaneios";
import { getSecurityDashboard } from "@/lib/security";
import { internalValueLabel } from "@/lib/labels-ptbr";
import { getNavigationAccess, type NavigationAccess } from "@/lib/navigation-access";
import { moduleMaturityPercent } from "@/lib/system-map";

export const dynamic = "force-dynamic";

const OPERATIONAL_HOME_PATHS = [
  "/modulos",
  "/producao",
  "/romaneios",
  "/importacao-xml",
  "/importacao-historica/mp",
  "/relatorios",
  "/seguranca",
  "/pedidos/financeiro",
  "/qualidade/pops",
  "/qualidade/rastreabilidade",
  "/custos-precos",
  "/pedidos/listas-precos"
] as const;

const AUDIT_STEPS = [
  "Cada gravacao critica passa por funcao SQL auditavel.",
  "Banco operacional, teste e homologacao aparecem no topo da tela.",
  "Recebimentos e comissoes guardam snapshot proporcional.",
  "NF XML entra em staging e so gera lote depois de confirmacao.",
  "Producao baixa estoque apenas na finalizacao de OP com CQ.",
  "Romaneio baixa PA apenas na confirmacao com reserva fechada.",
  "Login Supabase identifica o usuario por sessao e perfil.",
  "Rollout de modulos e dependencias e governado no PostgreSQL."
];

type HomeDashboard = {
  cadastros: Awaited<ReturnType<typeof getMasterDataDashboard>> | null;
  pedidos: Awaited<ReturnType<typeof getOrdersDashboard>> | null;
  relatorios: Awaited<ReturnType<typeof getReportsDashboard>> | null;
  importacaoXml: Awaited<ReturnType<typeof getImportacaoXmlDashboard>> | null;
  kanban: Awaited<ReturnType<typeof getKanbanDashboard>> | null;
  pcp: Awaited<ReturnType<typeof getPcpDashboard>> | null;
  romaneios: Awaited<ReturnType<typeof getRomaneioDashboard>> | null;
  seguranca: Awaited<ReturnType<typeof getSecurityDashboard>> | null;
  moduleRuntime: Awaited<ReturnType<typeof getModuleRuntimeDashboard>> | null;
};

export default async function HomePage() {
  const auth = await getAuthStatus();
  const navigationAccess = auth.isAuthenticated ? await getNavigationAccess() : {};

  if (!hasOperationalHomeAccess(navigationAccess)) {
    return auth.isAuthenticated
      ? <CommercialHome auth={auth} navigationAccess={navigationAccess} />
      : <LimitedHome />;
  }

  const dashboard = await getOperationalDashboard(navigationAccess);
  return <OperationalHome auth={auth} navigationAccess={navigationAccess} dashboard={dashboard} />;
}

function hasOperationalHomeAccess(navigationAccess: NavigationAccess): boolean {
  return OPERATIONAL_HOME_PATHS.some((path) => navigationAccess[path] === true);
}

async function getOperationalDashboard(navigationAccess: NavigationAccess): Promise<HomeDashboard> {
  const [cadastros, pedidos, relatorios, importacaoXml, kanban, pcp, romaneios, seguranca, moduleRuntime] = await Promise.all([
    navigationAccess["/cadastros"] ? getMasterDataDashboard() : Promise.resolve(null),
    navigationAccess["/pedidos"] ? getOrdersDashboard() : Promise.resolve(null),
    navigationAccess["/relatorios"] ? getReportsDashboard() : Promise.resolve(null),
    navigationAccess["/importacao-xml"] ? getImportacaoXmlDashboard() : Promise.resolve(null),
    navigationAccess["/kanban"] ? getKanbanDashboard() : Promise.resolve(null),
    navigationAccess["/producao"] ? getPcpDashboard() : Promise.resolve(null),
    navigationAccess["/romaneios"] ? getRomaneioDashboard() : Promise.resolve(null),
    navigationAccess["/seguranca"] ? getSecurityDashboard() : Promise.resolve(null),
    navigationAccess["/modulos"] ? getModuleRuntimeDashboard() : Promise.resolve(null)
  ]);

  return { cadastros, pedidos, relatorios, importacaoXml, kanban, pcp, romaneios, seguranca, moduleRuntime };
}

function CommercialHome({ auth, navigationAccess }: { auth: AuthStatus; navigationAccess: NavigationAccess }) {
  const canUseOrders = navigationAccess["/pedidos"] === true;
  const canUseKanban = navigationAccess["/kanban"] === true;
  const canUseClients = navigationAccess["/cadastros"] === true;
  const displayName = auth.profile?.displayName ?? auth.email ?? "Usuario";

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">area comercial</span>
            <h1>Meu trabalho</h1>
            <p className="muted">Ola, {displayName}. Acompanhe somente as atividades comerciais disponiveis para sua conta.</p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes comerciais">
            {canUseOrders ? <a className="primary-button" href="/pedidos?nova=1">Novo pedido</a> : null}
            {canUseOrders ? <a className="secondary-button" href="/pedidos">Pedidos</a> : null}
            {canUseKanban ? <a className="secondary-button" href="/kanban">Kanban</a> : null}
          </div>
        </div>

        <section className="dashboard-grid compact" aria-label="Atalhos comerciais">
          {canUseOrders ? <CommercialShortcut title="Meus pedidos" detail="Consulte e acompanhe os pedidos dentro da sua carteira comercial." href="/pedidos" label="Abrir pedidos" primary /> : null}
          {canUseKanban ? <CommercialShortcut title="Meu Kanban" detail="Acompanhe os pedidos visiveis no seu fluxo comercial." href="/kanban" label="Abrir Kanban" /> : null}
          {canUseClients ? <CommercialShortcut title="Clientes" detail="Consulte os clientes liberados para sua atuacao comercial." href="/cadastros" label="Abrir clientes" /> : null}
        </section>

        {!canUseOrders && !canUseKanban && !canUseClients ? (
          <section className="notice-panel warning" role="status">
            <strong>Nenhuma atividade comercial liberada</strong>
            <span>Solicite ao responsavel o perfil de acesso adequado para continuar.</span>
          </section>
        ) : null}
      </section>
    </main>
  );
}

function CommercialShortcut({ title, detail, href, label, primary = false }: { title: string; detail: string; href: string; label: string; primary?: boolean }) {
  return <article className="panel"><div className="panel-header"><h2>{title}</h2></div><p className="muted">{detail}</p><a className={primary ? "primary-button" : "secondary-button"} href={href}>{label}</a></article>;
}

function LimitedHome() {
  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <section className="notice-panel warning" role="status">
          <strong>Acesso necessario</strong>
          <span>Entre na sua conta para ver as atividades liberadas para voce.</span>
          <a className="primary-button" href="/login">Entrar</a>
        </section>
      </section>
    </main>
  );
}

function OperationalHome({ auth, navigationAccess, dashboard }: { auth: AuthStatus; navigationAccess: NavigationAccess; dashboard: HomeDashboard }) {
  const { cadastros, pedidos, relatorios, importacaoXml, kanban, pcp, romaneios, seguranca, moduleRuntime } = dashboard;
  const cadastrosProntos = cadastros?.modules.filter((module) => module.status === "ready").length;
  const rolloutModules = moduleRuntime?.modules.filter((module) => !module.isCore) ?? [];
  const maturityWidth = (moduleKey: string) => `${moduleMaturityPercent(moduleRuntime ? moduleRuntimeFor(moduleRuntime, moduleKey)?.lifecycle ?? null : null)}%`;
  const errors = [cadastros?.error, pedidos?.error, relatorios?.error, importacaoXml?.error, kanban?.error, pcp?.error, romaneios?.error, seguranca?.error, moduleRuntime?.error, auth.error].filter(Boolean);

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div><span className="eyebrow">operacao auditavel</span><h1>Centro de controle</h1><p className="muted">Visao operacional limitada as capacidades efetivas da sua conta.</p></div>
          <div className="toolbar-actions" aria-label="Acoes principais">
            {navigationAccess["/cadastros"] ? <a className="secondary-button" href="/cadastros">Cadastros</a> : null}
            {navigationAccess["/pedidos"] ? <a className="primary-button" href="/pedidos">Pedidos</a> : null}
            {navigationAccess["/relatorios"] ? <a className="secondary-button" href="/relatorios">Relatorios</a> : null}
          </div>
        </div>

        <section className="kpi-grid" aria-label="Resumo operacional">
          {cadastros ? <article className="kpi-card accent-blue"><span>Cadastros prontos</span><strong>{cadastrosProntos}/{cadastros.modules.length}</strong><p>Base mestre com funcoes auditaveis e validacoes iniciais.</p></article> : null}
          {pedidos ? <article className="kpi-card accent-green"><span>Pedidos abertos</span><strong>{valueOrDash(pedidos.metrics.abertos)}</strong><p>Pedidos aptos a seguir para credito, romaneio e faturamento.</p></article> : null}
          {importacaoXml ? <article className="kpi-card accent-amber"><span>XML pendente</span><strong>{valueOrDash(importacaoXml.metrics.itensPendentes)}</strong><p>Itens de NF XML aguardando MP e conversao.</p></article> : null}
          {pcp ? <article className="kpi-card accent-red"><span>OP abertas</span><strong>{valueOrDash(pcp.metrics.opsAbertas)}</strong><p>Producao em rascunho, planejada ou em processo.</p></article> : null}
        </section>

        {(moduleRuntime || romaneios || pcp || relatorios) ? <section className="dashboard-grid">
          {moduleRuntime ? <article className="panel command-panel"><div className="panel-header"><h2>Fluxo de implantacao</h2><span className="pill">passo a passo</span></div><div className="flow-board">{rolloutModules.map((step, index) => <div className="flow-step" key={step.moduleKey}><div className="flow-marker">{index + 1}</div><div><div className="flow-title"><strong>{step.displayName}</strong><span>{step.effectiveAccess === "read_write" ? "operacao" : step.effectiveAccess === "read_only" ? "leitura" : "bloqueado"}</span></div><p>{step.description} · {step.lifecycle ? internalValueLabel(step.lifecycle) : "Sem liberacao definida"}</p></div></div>)}</div></article> : null}
          {(romaneios || pcp || relatorios) ? <article className="panel"><div className="panel-header"><h2>Fila critica</h2><span className="pill">decisao</span></div><div className="queue-list">{romaneios ? <QueueRow title="Romaneio" detail="Tela operacional criada com multi-item, reserva PA e confirmacao auditada." tone="ok" /> : null}{pcp ? <QueueRow title="Producao" detail="Tela inicial codada para formula, OP, reserva, CQ e geracao de PA/PI." tone="ok" /> : null}{relatorios ? <QueueRow title="Relatorios" detail="Catalogo de relatorios e reconciliacao operacional." tone="danger" /> : null}</div></article> : null}
        </section> : null}

        {(moduleRuntime || cadastros || pedidos || importacaoXml || kanban || pcp || romaneios || relatorios || seguranca) ? <section className="dashboard-grid compact">
          <article className="panel"><div className="panel-header"><h2>Modulos ativos</h2>{moduleRuntime ? <span className="pill">{moduleRuntime.metrics.available}/{moduleRuntime.metrics.total}</span> : null}</div><div className="module-radar">
            {moduleRuntime ? <ModuleTile href="/modulos" title="Implantacao" detail={`${moduleRuntime.metrics.readWrite} modulo(s) com escrita`} width={`${moduleRuntime.metrics.total === 0 ? 0 : Math.round((moduleRuntime.metrics.available / moduleRuntime.metrics.total) * 100)}%`} /> : null}
            {cadastros ? <ModuleTile href="/cadastros" title="Cadastros" detail={`${cadastrosProntos} blocos prontos`} width={maturityWidth("cadastros")} /> : null}
            {pedidos ? <ModuleTile href="/pedidos" title="Pedidos" detail={`${moneyOrDash(pedidos.metrics.faturamentoPrevisto)} previsto`} width={maturityWidth("pedidos")} /> : null}
            {importacaoXml ? <ModuleTile href="/importacao-xml" title="XML MP" detail={`${valueOrDash(importacaoXml.metrics.itensPendentes)} item(ns) pendente(s)`} width={maturityWidth("importacao")} /> : null}
            {kanban ? <ModuleTile href="/kanban" title="Kanban" detail={`${valueOrDash(kanban.metrics.total)} pedido(s) no quadro`} width={maturityWidth("pedidos")} /> : null}
            {pcp ? <ModuleTile href="/producao" title="Producao" detail={`${valueOrDash(pcp.metrics.opsAbertas)} OP(s) aberta(s)`} width={maturityWidth("pcp")} /> : null}
            {romaneios ? <ModuleTile href="/romaneios" title="Romaneio" detail={`${valueOrDash(romaneios.metrics.romaneiosSeparacao)} em separacao`} width={maturityWidth("expedicao")} /> : null}
            {relatorios ? <ModuleTile href="/relatorios" title="Relatorios" detail={`${valueOrDash(relatorios.metrics.catalogados)} catalogados`} width={maturityWidth("relatorios")} /> : null}
            {seguranca ? <ModuleTile href="/seguranca" title="Seguranca" detail={`${valueOrDash(seguranca.metrics.activeProfiles)} perfil(is) ativo(s)`} width={maturityWidth("seguranca")} /> : null}
          </div></article>
          {seguranca ? <article className="panel"><div className="panel-header"><h2>Trilha de auditoria</h2><span className="pill">{auth.isAuthenticated ? "sessao ativa" : "sem sessao"}</span></div><ol className="audit-list">{AUDIT_STEPS.map((step) => <li key={step}>{step}</li>)}</ol></article> : null}
        </section> : null}

        {errors.length ? <section className="notice-panel warning" role="status"><strong>Conexao parcial</strong><span>{errors[0]}</span></section> : null}
      </section>
    </main>
  );
}

function QueueRow({ title, detail, tone }: { title: string; detail: string; tone: "ok" | "danger" }) {
  return <div className="queue-row"><span className={`queue-status ${tone}`} /><div><strong>{title}</strong><p>{detail}</p></div></div>;
}

function ModuleTile({ href, title, detail, width }: { href: string; title: string; detail: string; width: string }) {
  return <a className="module-tile" href={href}><strong>{title}</strong><span>{detail}</span><div className="progress-rail"><span style={{ width }} /></div></a>;
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function moneyOrDash(value: number | null): string {
  if (value === null) return "sem conexao";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}
