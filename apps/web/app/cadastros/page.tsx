import { getMasterDataDashboard } from "@/lib/master-data";
import { getRuntimeStatus } from "@/lib/runtime";

export default async function CadastrosPage() {
  const runtime = getRuntimeStatus();
  const dashboard = await getMasterDataDashboard();
  const pendingCount = dashboard.validationIssues.length;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Cadastros mestres</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/cadastros" aria-current="page">
            Cadastros
          </a>
          <a href="#validacao">Validacao</a>
          <a href="#credito">Credito</a>
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
            <h1>Cadastros mestres</h1>
            <p className="muted">
              Operacao inicial para revisar, cadastrar e auditar clientes, pessoas comerciais, MP, produtos,
              embalagens e credito.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de cadastro">
            <a className="secondary-button" href="#validacao">
              Fila
            </a>
            <a className="primary-button" href="#novo-cadastro">
              Novo cadastro
            </a>
          </div>
        </div>

        <section className="summary-grid" aria-label="Resumo dos cadastros">
          <div className="summary-card">
            <span>Modulos prontos</span>
            <strong>{dashboard.modules.length}</strong>
          </div>
          <div className="summary-card">
            <span>Alertas pendentes</span>
            <strong>{pendingCount}</strong>
          </div>
          <div className="summary-card">
            <span>Fonte</span>
            <strong>{dashboard.source === "supabase" ? "Supabase" : "Aguardando ambiente"}</strong>
          </div>
          <div className="summary-card">
            <span>Alcadas</span>
            <strong>Autonomia inicial</strong>
          </div>
        </section>

        {dashboard.error ? (
          <section className="notice-panel" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel" aria-labelledby="modulos-title">
            <div className="panel-header">
              <h2 id="modulos-title">Modulos de cadastro</h2>
              <span className="pill">cad_*</span>
            </div>
            <div className="module-list">
              {dashboard.modules.map((module) => {
                const metric = dashboard.metrics.find((item) => item.moduleKey === module.key);
                return (
                  <article className="module-card" key={module.key}>
                    <div className="module-card-main">
                      <h3>{module.title}</h3>
                      <span>{module.table}</span>
                    </div>
                    <div className="module-card-meta">
                      <span>{module.owner}</span>
                      <strong>{metric?.count ?? "sem conexao"}</strong>
                    </div>
                    <p>{module.audit}</p>
                    <div className="tag-row" aria-label={`Campos obrigatorios de ${module.title}`}>
                      {module.requiredFields.map((field) => (
                        <span className="tag" key={field}>
                          {field}
                        </span>
                      ))}
                    </div>
                  </article>
                );
              })}
            </div>
          </section>

          <section className="panel" id="validacao" aria-labelledby="validacao-title">
            <div className="panel-header">
              <h2 id="validacao-title">Fila de validacao</h2>
              <span className="pill">{pendingCount} pendente(s)</span>
            </div>
            {dashboard.validationIssues.length > 0 ? (
              <div className="issue-list">
                {dashboard.validationIssues.map((issue) => (
                  <article className={`issue-row ${issue.severity}`} key={issue.id}>
                    <div>
                      <strong>{issue.entity}</strong>
                      <span>{issue.entity_key ?? "sem chave"}</span>
                    </div>
                    <p>{issue.message}</p>
                    <span className="tag">{issue.code}</span>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhum alerta carregado</strong>
                <span>
                  Quando Supabase estiver configurado, esta lista mostrara duplicidades, SKU de MP para revisar e
                  cadastros pendentes.
                </span>
              </div>
            )}
          </section>
        </section>

        <section className="panel form-panel" id="novo-cadastro" aria-labelledby="novo-title">
          <div className="panel-header">
            <h2 id="novo-title">Entrada controlada</h2>
            <span className="pill">auditavel</span>
          </div>
          <div className="form-grid">
            <label>
              Tipo
              <select defaultValue="cliente">
                <option value="cliente">Cliente</option>
                <option value="pessoa">Pessoa comercial</option>
                <option value="materia-prima">Materia-prima</option>
                <option value="produto">Produto</option>
                <option value="embalagem">Embalagem</option>
              </select>
            </label>
            <label>
              Nome principal
              <input placeholder="Nome do cadastro" />
            </label>
            <label>
              Codigo
              <input placeholder="Codigo legado ou novo codigo" />
            </label>
            <label>
              Status
              <select defaultValue="active">
                <option value="active">active</option>
                <option value="pending_review">pending_review</option>
                <option value="inactive">inactive</option>
              </select>
            </label>
          </div>
          <div className="form-footer">
            <span>Gravacao definitiva sera liberada via service auditavel com actor_user_id.</span>
            <button className="primary-button" type="button" disabled>
              Salvar
            </button>
          </div>
        </section>

        <section className="panel" id="credito" aria-labelledby="credito-title">
          <div className="panel-header">
            <h2 id="credito-title">Credito e alcadas</h2>
            <span className="pill">controle inicial</span>
          </div>
          <dl className="status-list">
            <div className="status-row">
              <dt>Vendedor</dt>
              <dd>Cria rascunho, ve limite autorizado e nao aprova bloqueio.</dd>
            </div>
            <div className="status-row">
              <dt>Gerente</dt>
              <dd>Aprova excecoes conforme alcada e acompanha equipe/regiao.</dd>
            </div>
            <div className="status-row">
              <dt>Financeiro</dt>
              <dd>Define limite manual, bloqueio, reducao e motivo auditado.</dd>
            </div>
            <div className="status-row">
              <dt>Auditoria</dt>
              <dd>Compara snapshot de credito, pedido, recebimento, comissao e devolucao.</dd>
            </div>
          </dl>
        </section>
      </section>
    </main>
  );
}
