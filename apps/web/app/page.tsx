import { getAuthStatus } from "@/lib/auth";
import { getMasterDataDashboard } from "@/lib/master-data";
import { getModuleRuntimeDashboard, moduleRuntimeFor } from "@/lib/modules";
import { getOrdersDashboard } from "@/lib/orders";
import { getReportsDashboard } from "@/lib/reports";
import { getImportacaoXmlDashboard } from "@/lib/importacao-xml";
import { getKanbanDashboard } from "@/lib/kanban";
import { getPcpDashboard } from "@/lib/pcp";
import { getRomaneioDashboard } from "@/lib/romaneios";
import { getSecurityDashboard } from "@/lib/security";
import { moduleMaturityPercent } from "@/lib/system-map";

export const dynamic = "force-dynamic";

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

export default async function HomePage() {
  const [auth, cadastros, pedidos, relatorios, importacaoXml, kanban, pcp, romaneios, seguranca, moduleRuntime] = await Promise.all([
    getAuthStatus(),
    getMasterDataDashboard(),
    getOrdersDashboard(),
    getReportsDashboard(),
    getImportacaoXmlDashboard(),
    getKanbanDashboard(),
    getPcpDashboard(),
    getRomaneioDashboard(),
    getSecurityDashboard(),
    getModuleRuntimeDashboard()
  ]);
  const cadastrosProntos = cadastros.modules.filter((module) => module.status === "ready").length;
  const pedidosAbertos = pedidos.metrics.abertos;
  const pendentesXml = importacaoXml.metrics.itensPendentes;
  const opsAbertas = pcp.metrics.opsAbertas;
  const rolloutModules = moduleRuntime.modules.filter((module) => !module.isCore);
  const maturityWidth = (moduleKey: string) =>
    `${moduleMaturityPercent(moduleRuntimeFor(moduleRuntime, moduleKey)?.lifecycle ?? null)}%`;

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">operacao auditavel</span>
            <h1>Centro de controle</h1>
            <p className="muted">
              Visao inicial para acompanhar construcao, banco conectado, cadastros, pedidos, recebimentos e proximos
              blocos do Elite System.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes principais">
            <a className="secondary-button" href="/cadastros">
              Cadastros
            </a>
            <a className="primary-button" href="/pedidos">
              Pedidos
            </a>
            <a className="secondary-button" href="/relatorios">
              Relatorios
            </a>
          </div>
        </div>

        <section className="kpi-grid" aria-label="Resumo operacional">
          <article className="kpi-card accent-blue">
            <span>Cadastros prontos</span>
            <strong>
              {cadastrosProntos}/{cadastros.modules.length}
            </strong>
            <p>Base mestre com funcoes auditaveis e validacoes iniciais.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Pedidos abertos</span>
            <strong>{valueOrDash(pedidosAbertos)}</strong>
            <p>Pedidos aptos a seguir para credito, romaneio e faturamento.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>XML pendente</span>
            <strong>{valueOrDash(pendentesXml)}</strong>
            <p>Itens de NF XML aguardando MP e conversao.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>OP abertas</span>
            <strong>{valueOrDash(opsAbertas)}</strong>
            <p>Producao em rascunho, planejada ou em processo.</p>
          </article>
        </section>

        <section className="dashboard-grid">
          <article className="panel command-panel">
            <div className="panel-header">
              <h2>Fluxo de implantacao</h2>
              <span className="pill">passo a passo</span>
            </div>
            <div className="flow-board">
              {rolloutModules.map((step, index) => (
                <div className="flow-step" key={step.moduleKey}>
                  <div className="flow-marker">{index + 1}</div>
                  <div>
                    <div className="flow-title">
                      <strong>{step.displayName}</strong>
                      <span>{step.effectiveAccess === "read_write" ? "operacao" : step.effectiveAccess === "read_only" ? "leitura" : "bloqueado"}</span>
                    </div>
                    <p>{step.description} · {step.lifecycle ?? "sem rollout"}</p>
                  </div>
                </div>
              ))}
            </div>
          </article>

          <article className="panel">
            <div className="panel-header">
              <h2>Fila critica</h2>
              <span className="pill">decisao</span>
            </div>
            <div className="queue-list">
              <div className="queue-row">
                <span className="queue-status ok"></span>
                <div>
                <strong>Romaneio</strong>
                <p>Tela operacional criada com multi-item, reserva PA e confirmacao auditada.</p>
                </div>
              </div>
              <div className="queue-row">
                <span className="queue-status ok"></span>
                <div>
                  <strong>Producao</strong>
                  <p>Tela inicial codada para formula, OP, reserva, CQ e geracao de PA/PI.</p>
                </div>
              </div>
              <div className="queue-row">
                <span className="queue-status danger"></span>
                <div>
                  <strong>Relatorios do Tio Lu XLSX</strong>
                  <p>Mapear as dezenas de telas historicas para catalogo, filtros e reconciliacao.</p>
                </div>
              </div>
            </div>
          </article>
        </section>

        <section className="dashboard-grid compact">
          <article className="panel">
            <div className="panel-header">
              <h2>Modulos ativos</h2>
              <span className="pill">{moduleRuntime.metrics.available}/{moduleRuntime.metrics.total}</span>
            </div>
            <div className="module-radar">
              <a className="module-tile" href="/modulos">
                <strong>Implantacao</strong>
                <span>{moduleRuntime.metrics.readWrite} modulo(s) com escrita</span>
                <div className="progress-rail">
                  <span style={{ width: `${moduleRuntime.metrics.total === 0 ? 0 : Math.round((moduleRuntime.metrics.available / moduleRuntime.metrics.total) * 100)}%` }}></span>
                </div>
              </a>
              <a className="module-tile" href="/cadastros">
                <strong>Cadastros</strong>
                <span>{cadastrosProntos} blocos prontos</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("cadastros") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/pedidos">
                <strong>Pedidos</strong>
                <span>{moneyOrDash(pedidos.metrics.faturamentoPrevisto)} previsto</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("pedidos") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/importacao-xml">
                <strong>XML MP</strong>
                <span>{valueOrDash(importacaoXml.metrics.itensPendentes)} item(ns) pendente(s)</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("importacao") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/importacao-historica/mp">
                <strong>Historico MP</strong>
                <span>Conciliar aliases, lotes, frete e DIFAL</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("auditoria") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/kanban">
                <strong>Kanban</strong>
                <span>{valueOrDash(kanban.metrics.total)} pedido(s) no quadro</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("pedidos") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/producao">
                <strong>Producao</strong>
                <span>{valueOrDash(pcp.metrics.opsAbertas)} OP(s) aberta(s)</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("pcp") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/romaneios">
                <strong>Romaneio</strong>
                <span>{valueOrDash(romaneios.metrics.romaneiosSeparacao)} em separacao</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("expedicao") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/relatorios">
                <strong>Relatorios</strong>
                <span>{valueOrDash(relatorios.metrics.catalogados)} catalogados</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("relatorios") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/login">
                <strong>Login</strong>
                <span>{auth.profile?.displayName ?? auth.email ?? "entrar no sistema"}</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("seguranca") }}></span>
                </div>
              </a>
              <a className="module-tile" href="/seguranca">
                <strong>Seguranca</strong>
                <span>{valueOrDash(seguranca.metrics.activeProfiles)} perfil(is) ativo(s)</span>
                <div className="progress-rail">
                  <span style={{ width: maturityWidth("seguranca") }}></span>
                </div>
              </a>
            </div>
          </article>

          <article className="panel">
            <div className="panel-header">
              <h2>Trilha de auditoria</h2>
              <span className="pill">{auth.isAuthenticated ? "sessao ativa" : "sem sessao"}</span>
            </div>
            <ol className="audit-list">
              {AUDIT_STEPS.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </article>
        </section>

        {(cadastros.error ||
          pedidos.error ||
          relatorios.error ||
          importacaoXml.error ||
          kanban.error ||
          pcp.error ||
          romaneios.error ||
          seguranca.error ||
          moduleRuntime.error ||
          auth.error) && (
          <section className="notice-panel warning" role="status">
            <strong>Conexao parcial</strong>
            <span>
              {cadastros.error ??
                pedidos.error ??
                relatorios.error ??
                importacaoXml.error ??
                kanban.error ??
                pcp.error ??
                romaneios.error ??
                seguranca.error ??
                moduleRuntime.error ??
                auth.error}
            </span>
          </section>
        )}
      </section>
    </main>
  );
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function moneyOrDash(value: number | null): string {
  if (value === null) {
    return "sem conexao";
  }
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL"
  }).format(value);
}
