import { createClienteAction, createPessoaComercialAction } from "@/app/cadastros/actions";
import { getMasterDataDashboard } from "@/lib/master-data";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CadastrosPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getMasterDataDashboard();
  const pendingCount = dashboard.validationIssues.length;
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);

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

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
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
            <h2 id="novo-title">Novo cliente</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createClienteAction}>
            <div className="form-grid">
              <label>
                Tipo
                <select name="tipo" defaultValue="cliente">
                  <option value="cliente">Cliente</option>
                </select>
              </label>
              <label>
                Nome principal
                <input name="nome" placeholder="Nome do cliente" required />
              </label>
              <label>
                Codigo legado
                <input name="codigo_legado" placeholder="Codigo do Excel, se houver" />
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                Cidade
                <input name="cidade" placeholder="Cidade" required />
              </label>
              <label>
                UF
                <input name="uf" placeholder="SP" required maxLength={2} />
              </label>
              <label className="wide-field">
                Apelidos e grafias
                <input name="apelidos" placeholder="Separar por virgula, ponto e virgula ou linha" />
              </label>
            </div>
            <div className="form-footer">
              <span>Salvar chama funcao PostgreSQL auditavel e registra `action_logs`.</span>
              <button className="primary-button" type="submit">
                Salvar cliente
              </button>
            </div>
          </form>
        </section>

        <section className="panel form-panel" aria-labelledby="nova-pessoa-title">
          <div className="panel-header">
            <h2 id="nova-pessoa-title">Nova pessoa comercial</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createPessoaComercialAction} id="nova-pessoa">
            <div className="form-grid">
              <label>
                Nome
                <input name="nome" placeholder="Nome da pessoa" required />
              </label>
              <label>
                Codigo legado
                <input name="codigo_legado" placeholder="Codigo, se houver" />
              </label>
              <label>
                Tipo comercial
                <select name="tipo_comercial" defaultValue="vendedor_direto_elite">
                  <option value="funcionario_elite">funcionario_elite</option>
                  <option value="agente_vinculado">agente_vinculado</option>
                  <option value="agente_direto_elite">agente_direto_elite</option>
                  <option value="vendedor_direto_elite">vendedor_direto_elite</option>
                  <option value="tecnico_campo">tecnico_campo</option>
                  <option value="entregador">entregador</option>
                  <option value="gerente">gerente</option>
                  <option value="vendedor_gerente">vendedor_gerente</option>
                </select>
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                Vendedor responsavel
                <input name="vendedor_responsavel_id" placeholder="Obrigatorio para agente vinculado" type="number" />
              </label>
              <label className="wide-field">
                Apelidos
                <input name="apelidos" placeholder="Separar por virgula, ponto e virgula ou linha" />
              </label>
              <label className="wide-field">
                Grafias incorretas
                <input name="grafias_incorretas" placeholder="Grafias usadas historicamente" />
              </label>
            </div>
            <fieldset className="check-grid">
              <legend>Papeis</legend>
              <label>
                <input name="papeis" type="checkbox" value="vendedor" defaultChecked />
                Vendedor
              </label>
              <label>
                <input name="papeis" type="checkbox" value="agente" />
                Agente
              </label>
              <label>
                <input name="papeis" type="checkbox" value="gerente" />
                Gerente
              </label>
              <label>
                <input name="papeis" type="checkbox" value="tecnico_campo" />
                Tecnico campo
              </label>
              <label>
                <input name="papeis" type="checkbox" value="entregador" />
                Entregador
              </label>
              <label>
                <input name="papeis" type="checkbox" value="comissionado" defaultChecked />
                Comissionado
              </label>
            </fieldset>
            <div className="form-footer">
              <span>Entregador nao vira vendedor automaticamente; papeis ficam separados para auditoria.</span>
              <button className="primary-button" type="submit">
                Salvar pessoa
              </button>
            </div>
          </form>
        </section>

        <section className="panel form-panel" aria-labelledby="proximos-formularios-title">
          <div className="panel-header">
            <h2 id="proximos-formularios-title">Proximos formularios</h2>
            <span className="pill">MP / produto / embalagem</span>
          </div>
          <div className="module-list">
            <article className="module-card">
              <div className="module-card-main">
                <h3>MP, produto e embalagem</h3>
                <span>SKU corrigido, produto + embalagem e estoque de insumo</span>
              </div>
              <div className="module-card-meta">
                <span>Service pronto</span>
                <strong>cad_*</strong>
              </div>
              <p>Esses formularios entram na proxima etapa com conversoes, garantias e bloqueios de duplicidade.</p>
            </article>
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

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    cliente_created: {
      kind: "ok",
      title: "Cliente salvo",
      detail: "Cadastro criado via funcao auditavel. A fila e as contagens serao atualizadas pelo Supabase."
    },
    pessoa_created: {
      kind: "ok",
      title: "Pessoa comercial salva",
      detail: "Cadastro criado via funcao auditavel com papeis separados para venda, entrega, gerencia e comissao."
    },
    duplicated: {
      kind: "warning",
      title: "Cadastro duplicado",
      detail: "O codigo legado ou chave unica ja existe. Revise antes de tentar novamente."
    },
    invalid_status: {
      kind: "warning",
      title: "Status invalido",
      detail: "Use active, pending_review ou inactive."
    },
    invalid_uf: {
      kind: "warning",
      title: "UF invalida",
      detail: "UF deve ter exatamente duas letras."
    },
    missing_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Nome, cidade e UF sao obrigatorios para cliente."
    },
    missing_person_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Nome e ao menos um papel sao obrigatorios para pessoa comercial."
    },
    invalid_commercial_type: {
      kind: "warning",
      title: "Tipo comercial invalido",
      detail: "Use um dos tipos comerciais aprovados no dicionario de cadastros."
    },
    missing_responsible_seller: {
      kind: "warning",
      title: "Vendedor responsavel obrigatorio",
      detail: "Agente vinculado precisa apontar para um vendedor responsavel Elite."
    },
    invalid_responsible_seller: {
      kind: "warning",
      title: "Vendedor responsavel invalido",
      detail: "Informe o ID numerico do vendedor responsavel."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure as variaveis de ambiente antes de gravar cadastros reais ou de teste."
    },
    permission_denied: {
      kind: "warning",
      title: "Permissao negada",
      detail: "Usuario precisa estar autenticado e autorizado para gravar cadastros."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "O cadastro nao foi gravado. Consulte logs do Supabase para o detalhe tecnico."
    }
  };
  return messages[result] ?? messages.save_failed;
}
