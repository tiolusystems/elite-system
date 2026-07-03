import { getRuntimeStatus } from "@/lib/runtime";

export default function HomePage() {
  const runtime = getRuntimeStatus();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Operacao web</span>
        </div>
        <span className="topbar-status">Next.js + Supabase PostgreSQL</span>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace">
        <div className="toolbar">
          <div>
            <h1>Painel operacional</h1>
            <p className="muted">Base inicial para login, alcadas, auditoria e modulos do Elite System.</p>
          </div>
          <button className="primary-button" type="button">
            Entrar
          </button>
        </div>

        <section className="summary-grid" aria-label="Resumo do ambiente">
          <div className="summary-card">
            <span>Banco</span>
            <strong>PostgreSQL</strong>
          </div>
          <div className="summary-card">
            <span>Backend</span>
            <strong>Supabase</strong>
          </div>
          <div className="summary-card">
            <span>Frontend</span>
            <strong>Next.js</strong>
          </div>
          <div className="summary-card">
            <span>Deploy</span>
            <strong>Vercel</strong>
          </div>
        </section>

        <section className="panel" aria-labelledby="status-title">
          <div className="panel-header">
            <h2 id="status-title">Condicao tecnica</h2>
            <span className="pill">{runtime.supabaseConfigured ? "configurado" : "pendente"}</span>
          </div>
          <dl className="status-list">
            <div className="status-row">
              <dt>Supabase</dt>
              <dd>{runtime.supabaseConfigured ? "Variaveis configuradas" : "Aguardando variaveis de ambiente"}</dd>
            </div>
            <div className="status-row">
              <dt>Host</dt>
              <dd>{runtime.supabaseUrlHost}</dd>
            </div>
            <div className="status-row">
              <dt>Auditoria</dt>
              <dd>Modelo inicial preparado em migration PostgreSQL</dd>
            </div>
            <div className="status-row">
              <dt>Historico</dt>
              <dd>Nucleo Python permanece responsavel por migracao e reconciliacao</dd>
            </div>
          </dl>
        </section>
      </section>
    </main>
  );
}
