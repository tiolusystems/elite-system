import { getMasterDataDashboard } from "@/lib/master-data";
import { getOrdersDashboard } from "@/lib/orders";
import { getRuntimeStatus } from "@/lib/runtime";

const FLOW_STEPS = [
  {
    title: "Cadastros",
    status: "em uso",
    detail: "Clientes, pessoas comerciais, MP, produtos, embalagens, credito e conversoes."
  },
  {
    title: "Pedidos",
    status: "codando",
    detail: "Rascunho, credito, recebimento parcial e comissao proporcional."
  },
  {
    title: "Romaneio",
    status: "proximo",
    detail: "Separacao parcial ou total, reserva de lote e confirmacao para baixa de PA."
  },
  {
    title: "Estoque",
    status: "fila",
    detail: "Entradas MP, saidas MP, producao, PI/PA e saldos auditaveis."
  }
];

const AUDIT_STEPS = [
  "Cada gravacao critica passa por funcao SQL auditavel.",
  "Banco operacional, teste e homologacao aparecem no topo da tela.",
  "Recebimentos e comissoes guardam snapshot proporcional.",
  "Proxima etapa: reconciliacao de valores contra Excel."
];

export default async function HomePage() {
  const runtime = getRuntimeStatus();
  const [cadastros, pedidos] = await Promise.all([getMasterDataDashboard(), getOrdersDashboard()]);
  const cadastrosProntos = cadastros.modules.filter((module) => module.status === "ready").length;
  const alertasPendentes = cadastros.validationIssues.length;
  const pedidosAbertos = pedidos.metrics.abertos;
  const totalRecebido = pedidos.metrics.totalRecebido;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Painel operacional</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/" aria-current="page">
            Inicio
          </a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

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
            <span>Recebido</span>
            <strong>{moneyOrDash(totalRecebido)}</strong>
            <p>Base para liberacao proporcional de comissoes.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Alertas</span>
            <strong>{alertasPendentes}</strong>
            <p>Pendencias de validacao de cadastro carregadas do banco.</p>
          </article>
        </section>

        <section className="dashboard-grid">
          <article className="panel command-panel">
            <div className="panel-header">
              <h2>Fluxo de implantacao</h2>
              <span className="pill">passo a passo</span>
            </div>
            <div className="flow-board">
              {FLOW_STEPS.map((step, index) => (
                <div className="flow-step" key={step.title}>
                  <div className="flow-marker">{index + 1}</div>
                  <div>
                    <div className="flow-title">
                      <strong>{step.title}</strong>
                      <span>{step.status}</span>
                    </div>
                    <p>{step.detail}</p>
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
                <span className="queue-status warning"></span>
                <div>
                  <strong>Romaneio</strong>
                  <p>Construir tela de separacao com reserva e baixa apenas na confirmacao.</p>
                </div>
              </div>
              <div className="queue-row">
                <span className="queue-status ok"></span>
                <div>
                  <strong>Comissao por recebimento</strong>
                  <p>Primeira versao codada com proporcionalidade e snapshot.</p>
                </div>
              </div>
              <div className="queue-row">
                <span className="queue-status danger"></span>
                <div>
                  <strong>Devolucao e abatimento</strong>
                  <p>Proximo ajuste financeiro: estorno auditado e compensacao futura.</p>
                </div>
              </div>
            </div>
          </article>
        </section>

        <section className="dashboard-grid compact">
          <article className="panel">
            <div className="panel-header">
              <h2>Modulos ativos</h2>
              <span className="pill">{cadastros.source === "supabase" ? "Supabase" : "preview"}</span>
            </div>
            <div className="module-radar">
              <a className="module-tile" href="/cadastros">
                <strong>Cadastros</strong>
                <span>{cadastrosProntos} blocos prontos</span>
                <div className="progress-rail">
                  <span style={{ width: `${Math.round((cadastrosProntos / cadastros.modules.length) * 100)}%` }}></span>
                </div>
              </a>
              <a className="module-tile" href="/pedidos">
                <strong>Pedidos</strong>
                <span>{moneyOrDash(pedidos.metrics.faturamentoPrevisto)} previsto</span>
                <div className="progress-rail">
                  <span style={{ width: "42%" }}></span>
                </div>
              </a>
              <div className="module-tile muted-tile">
                <strong>Romaneio</strong>
                <span>tela e migration na proxima etapa</span>
                <div className="progress-rail">
                  <span style={{ width: "12%" }}></span>
                </div>
              </div>
              <div className="module-tile muted-tile">
                <strong>Auditorias</strong>
                <span>reconciliacao por valor e quantidade</span>
                <div className="progress-rail">
                  <span style={{ width: "18%" }}></span>
                </div>
              </div>
            </div>
          </article>

          <article className="panel">
            <div className="panel-header">
              <h2>Trilha de auditoria</h2>
              <span className="pill">controle</span>
            </div>
            <ol className="audit-list">
              {AUDIT_STEPS.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </article>
        </section>

        {(cadastros.error || pedidos.error) && (
          <section className="notice-panel warning" role="status">
            <strong>Conexao parcial</strong>
            <span>{cadastros.error ?? pedidos.error}</span>
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
