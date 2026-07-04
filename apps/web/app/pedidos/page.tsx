import {
  createPedidoRascunhoAction,
  registrarCreditoPedidoAction,
  registrarRecebimentoPedidoAction
} from "@/app/pedidos/actions";
import { getOrdersDashboard, type OrderLookupOption, type OrderLookups } from "@/lib/orders";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PedidosPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getOrdersDashboard();
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Pedidos</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/">Inicio</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos" aria-current="page">
            Pedidos
          </a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp">PCP</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/login">Login</a>
          <a href="#novo-pedido">Novo pedido</a>
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
            <h1>Pedidos</h1>
            <p className="muted">
              Camada comercial auditavel: pedido em rascunho, item vendavel, credito e comissao prevista.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de pedido">
            <a className="secondary-button" href="/cadastros">
              Cadastros
            </a>
            <a className="primary-button" href="#novo-pedido">
              Novo pedido
            </a>
          </div>
        </div>

        <LookupDatalists lookups={dashboard.lookups} />

        <section className="summary-grid" aria-label="Resumo dos pedidos">
          <div className="summary-card">
            <span>Total de pedidos</span>
            <strong>{valueOrDash(dashboard.metrics.totalPedidos)}</strong>
          </div>
          <div className="summary-card">
            <span>Rascunhos</span>
            <strong>{valueOrDash(dashboard.metrics.rascunhos)}</strong>
          </div>
          <div className="summary-card">
            <span>Abertos</span>
            <strong>{valueOrDash(dashboard.metrics.abertos)}</strong>
          </div>
          <div className="summary-card">
            <span>Bloqueados</span>
            <strong>{valueOrDash(dashboard.metrics.bloqueados)}</strong>
          </div>
          <div className="summary-card">
            <span>Faturamento previsto</span>
            <strong>{moneyOrDash(dashboard.metrics.faturamentoPrevisto)}</strong>
          </div>
          <div className="summary-card">
            <span>Total recebido</span>
            <strong>{moneyOrDash(dashboard.metrics.totalRecebido)}</strong>
          </div>
          <div className="summary-card">
            <span>Comissao liberada</span>
            <strong>{moneyOrDash(dashboard.metrics.comissaoLiberada)}</strong>
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
          <section className="panel form-panel" id="novo-pedido" aria-labelledby="novo-pedido-title">
            <div className="panel-header">
              <h2 id="novo-pedido-title">Novo pedido</h2>
              <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
            </div>
            <form action={createPedidoRascunhoAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Cliente
                  <input name="cliente_id" list="clientes-options" placeholder="Buscar cliente" required />
                </label>
                <label className="wide-field">
                  Propriedade
                  <input name="propriedade_id" list="propriedades-options" placeholder="Opcional: fazenda/propriedade do cliente" />
                </label>
                <label className="wide-field">
                  Item vendavel
                  <input name="produto_embalagem_id" list="itens-vendaveis-options" placeholder="Produto + embalagem" required />
                </label>
                <label>
                  Tipo
                  <select name="tipo_pedido" defaultValue="venda">
                    <option value="venda">venda</option>
                    <option value="bonificacao">bonificacao</option>
                    <option value="devolucao">devolucao</option>
                  </select>
                </label>
                <label>
                  Status inicial
                  <select name="status" defaultValue="draft">
                    <option value="draft">draft</option>
                    <option value="open">open</option>
                    <option value="blocked">blocked</option>
                  </select>
                </label>
                <label>
                  Data
                  <input name="data_pedido" type="date" defaultValue={today} required />
                </label>
                <label>
                  Quantidade
                  <input name="quantidade" placeholder="1" inputMode="decimal" required />
                </label>
                <label>
                  Valor unitario
                  <input name="valor_unitario" placeholder="0,00" inputMode="decimal" required />
                </label>
                <label>
                  Vendedor/comissionado
                  <input name="vendedor_id" list="pessoas-comerciais-options" placeholder="Opcional" />
                </label>
                <label>
                  % comissao
                  <input name="percentual_comissao" placeholder="0" inputMode="decimal" />
                </label>
                <label className="wide-field">
                  Observacao
                  <input name="observacao" placeholder="Condicao, restricao ou historico relevante" />
                </label>
              </div>
              <div className="form-footer">
                <span>Pedido por propriedade recebe sequencia propria. Rascunho nao baixa estoque.</span>
                <button className="primary-button" type="submit">
                  Salvar pedido
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="fluxo-title">
            <div className="panel-header">
              <h2 id="fluxo-title">Regras iniciais</h2>
              <span className="pill">sem baixa de estoque</span>
            </div>
            <dl className="status-list">
              <div className="status-row">
                <dt>draft</dt>
                <dd>Pedido em rascunho. Nao baixa estoque e pode ser revisado.</dd>
              </div>
              <div className="status-row">
                <dt>open</dt>
                <dd>Pedido aberto para seguir ao romaneio, credito e faturamento.</dd>
              </div>
              <div className="status-row">
                <dt>blocked</dt>
                <dd>Pedido parado por credito, cadastro ou regra operacional.</dd>
              </div>
              <div className="status-row">
                <dt>Comissao</dt>
                <dd>Prevista no pedido e liberada apenas conforme recebimento futuro.</dd>
              </div>
            </dl>
          </section>
        </section>

        <section className="two-column">
          <section className="panel form-panel" id="credito-pedido" aria-labelledby="credito-pedido-title">
            <div className="panel-header">
              <h2 id="credito-pedido-title">Credito do pedido</h2>
              <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
            </div>
            <form action={registrarCreditoPedidoAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Pedido
                  <input name="pedido_id" list="pedidos-options" placeholder="Buscar pedido" required />
                </label>
                <label>
                  Decisao
                  <select name="decisao" defaultValue="liberado">
                    <option value="liberado">liberado</option>
                    <option value="bloqueado">bloqueado</option>
                    <option value="pendente_aprovacao">pendente_aprovacao</option>
                  </select>
                </label>
                <label>
                  Limite disponivel
                  <input name="limite_disponivel_snapshot" placeholder="0,00" inputMode="decimal" />
                </label>
                <label>
                  Inadimplencia
                  <input name="inadimplencia_snapshot" placeholder="0,00" inputMode="decimal" />
                </label>
                <label className="wide-field">
                  Motivo
                  <input name="motivo" placeholder="Obrigatorio para bloqueio ou aprovacao pendente" />
                </label>
                <label className="wide-field">
                  Observacao
                  <input name="observacao_credito" placeholder="Contexto da analise de credito" />
                </label>
              </div>
              <div className="form-footer">
                <span>Credito liberado abre o pedido. Bloqueio ou aprovacao pendente trava antes de faturamento.</span>
                <button className="primary-button" type="submit">
                  Registrar credito
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="credito-recente-title">
            <div className="panel-header">
              <h2 id="credito-recente-title">Decisoes recentes</h2>
              <span className="pill">{dashboard.recentCreditDecisions.length} registro(s)</span>
            </div>
            {dashboard.recentCreditDecisions.length > 0 ? (
              <div className="module-list">
                {dashboard.recentCreditDecisions.map((decision) => (
                  <article className="module-card" key={decision.id}>
                    <div className="module-card-main">
                      <h3>Pedido #{decision.pedidoId}</h3>
                      <span>{decision.decisao}</span>
                    </div>
                    <div className="module-card-meta">
                      <span>{decision.statusAnterior}</span>
                      <strong>{decision.statusResultante}</strong>
                    </div>
                    <p>{decision.motivo ?? "sem motivo obrigatorio"}</p>
                    <div className="tag-row">
                      <span className="tag">limite: {moneyOrDash(decision.limiteDisponivelSnapshot)}</span>
                      <span className="tag">inad: {moneyOrDash(decision.inadimplenciaSnapshot)}</span>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma decisao carregada</strong>
                <span>Quando Supabase estiver configurado, esta lista mostrara liberacoes e bloqueios recentes.</span>
              </div>
            )}
          </section>
        </section>

        <section className="two-column">
          <section className="panel form-panel" id="recebimento-pedido" aria-labelledby="recebimento-pedido-title">
            <div className="panel-header">
              <h2 id="recebimento-pedido-title">Recebimento do pedido</h2>
              <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
            </div>
            <form action={registrarRecebimentoPedidoAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Pedido
                  <input name="pedido_id" list="pedidos-options" placeholder="Buscar pedido aberto" required />
                </label>
                <label>
                  Valor recebido
                  <input name="valor_recebido" placeholder="0,00" inputMode="decimal" required />
                </label>
                <label>
                  Data
                  <input name="data_recebimento" type="date" defaultValue={today} required />
                </label>
                <label>
                  Forma
                  <input name="forma_recebimento" placeholder="PIX, boleto, TED..." />
                </label>
                <label className="wide-field">
                  Observacao
                  <input name="observacao_recebimento" placeholder="Historico do recebimento" />
                </label>
              </div>
              <div className="form-footer">
                <span>Recebimento parcial libera comissao proporcional. Bonificacao nao entra nesse fluxo.</span>
                <button className="primary-button" type="submit">
                  Registrar recebimento
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="recebimentos-recentes-title">
            <div className="panel-header">
              <h2 id="recebimentos-recentes-title">Recebimentos recentes</h2>
              <span className="pill">{dashboard.recentReceipts.length} registro(s)</span>
            </div>
            {dashboard.recentReceipts.length > 0 ? (
              <div className="module-list">
                {dashboard.recentReceipts.map((receipt) => (
                  <article className="module-card" key={receipt.id}>
                    <div className="module-card-main">
                      <h3>Pedido #{receipt.pedidoId}</h3>
                      <span>{receipt.dataRecebimento}</span>
                    </div>
                    <div className="module-card-meta">
                      <span>{receipt.formaRecebimento ?? "sem forma"}</span>
                      <strong>{moneyOrDash(receipt.valorRecebido)}</strong>
                    </div>
                    <p>Recebimento #{receipt.id}</p>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhum recebimento carregado</strong>
                <span>Quando Supabase estiver configurado, esta lista mostrara os ultimos recebimentos.</span>
              </div>
            )}
          </section>
        </section>

        <section className="panel" aria-labelledby="comissoes-liberadas-title">
          <div className="panel-header">
            <h2 id="comissoes-liberadas-title">Comissoes liberadas</h2>
            <span className="pill">{dashboard.recentCommissionReleases.length} registro(s)</span>
          </div>
          {dashboard.recentCommissionReleases.length > 0 ? (
            <div className="module-list">
              {dashboard.recentCommissionReleases.map((release) => (
                <article className="module-card" key={release.id}>
                  <div className="module-card-main">
                    <h3>Pessoa #{release.pessoaId}</h3>
                    <span>Pedido #{release.pedidoId} / Recebimento #{release.recebimentoId}</span>
                  </div>
                  <div className="module-card-meta">
                    <span>{release.status}</span>
                    <strong>{moneyOrDash(release.valorLiberado)}</strong>
                  </div>
                  <p>{percentOrDash(release.percentualRecebidoSnapshot)} do pedido recebido no snapshot.</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma comissao liberada</strong>
              <span>Recebimentos de venda com comissao prevista geram liberacao proporcional aqui.</span>
            </div>
          )}
        </section>

        <section className="panel" aria-labelledby="recentes-title">
          <div className="panel-header">
            <h2 id="recentes-title">Pedidos recentes</h2>
            <span className="pill">{dashboard.source === "supabase" ? "Supabase" : "sem conexao"}</span>
          </div>
          {dashboard.recentOrders.length > 0 ? (
            <div className="module-list">
              {dashboard.recentOrders.map((order) => (
                <article className="module-card" key={order.id}>
                  <div className="module-card-main">
                    <h3>{order.codigoPedido}</h3>
                    <span>
                      Cliente #{order.clienteId}
                      {order.propriedadeId ? ` / Propriedade #${order.propriedadeId}` : ""}
                    </span>
                  </div>
                  <div className="module-card-meta">
                    <span>{order.status}</span>
                    <strong>{moneyOrDash(order.valorTotal)}</strong>
                  </div>
                  <p>
                    {order.tipoPedido} / {order.dataPedido}
                  </p>
                  <div className="tag-row">
                    <span className="tag">pedido_id: {order.id}</span>
                    <span className="tag">seq: {order.sequenciaPropriedade ?? "-"}</span>
                    <span className="tag">{order.status}</span>
                    <span className="tag">{order.tipoPedido}</span>
                  </div>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhum pedido carregado</strong>
              <span>Quando Supabase estiver configurado, esta lista mostrara os ultimos pedidos criados.</span>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

function LookupDatalists({ lookups }: { lookups: OrderLookups }) {
  return (
    <>
      <LookupDatalist id="clientes-options" options={lookups.clientes} />
      <LookupDatalist id="propriedades-options" options={lookups.propriedades} />
      <LookupDatalist id="itens-vendaveis-options" options={lookups.itensVendaveis} />
      <LookupDatalist id="pessoas-comerciais-options" options={lookups.pessoasComerciais} />
      <LookupDatalist id="pedidos-options" options={lookups.pedidos} />
    </>
  );
}

function LookupDatalist({ id, options }: { id: string; options: OrderLookupOption[] }) {
  return (
    <datalist id={id}>
      {options.map((option) => (
        <option key={option.id} value={lookupValue(option)} />
      ))}
    </datalist>
  );
}

function lookupValue(option: OrderLookupOption): string {
  return option.detail ? `${option.id} | ${option.label} | ${option.detail}` : `${option.id} | ${option.label}`;
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
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

function percentOrDash(value: number | null): string {
  if (value === null) {
    return "sem conexao";
  }
  return new Intl.NumberFormat("pt-BR", {
    style: "percent",
    maximumFractionDigits: 2
  }).format(value);
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    pedido_created: {
      kind: "ok",
      title: "Pedido salvo",
      detail: "Pedido criado via funcao auditavel com item e comissao prevista quando aplicavel."
    },
    credit_decision_registered: {
      kind: "ok",
      title: "Credito registrado",
      detail: "Decisao de credito gravada com snapshot e status do pedido atualizado."
    },
    receipt_registered: {
      kind: "ok",
      title: "Recebimento registrado",
      detail: "Recebimento gravado e comissao proporcional liberada quando aplicavel."
    },
    missing_order_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Cliente, item, data, quantidade e valor unitario sao obrigatorios."
    },
    missing_credit_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Pedido e decisao de credito sao obrigatorios."
    },
    missing_credit_reason: {
      kind: "warning",
      title: "Motivo obrigatorio",
      detail: "Bloqueio ou aprovacao pendente precisa de motivo auditavel."
    },
    missing_receipt_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Pedido, valor recebido e data do recebimento sao obrigatorios."
    },
    invalid_positive_number: {
      kind: "warning",
      title: "Numero invalido",
      detail: "Informe um numero maior que zero."
    },
    invalid_non_negative_number: {
      kind: "warning",
      title: "Numero invalido",
      detail: "Informe zero ou um numero positivo."
    },
    invalid_order_type: {
      kind: "warning",
      title: "Tipo invalido",
      detail: "Use venda, bonificacao ou devolucao."
    },
    invalid_initial_status: {
      kind: "warning",
      title: "Status inicial invalido",
      detail: "Use draft, open ou blocked."
    },
    invalid_credit_decision: {
      kind: "warning",
      title: "Decisao invalida",
      detail: "Use liberado, bloqueado ou pendente_aprovacao."
    },
    invalid_order_status: {
      kind: "warning",
      title: "Status do pedido invalido",
      detail: "Pedidos cancelados ou concluidos nao aceitam nova decisao de credito."
    },
    invalid_receipt_order: {
      kind: "warning",
      title: "Recebimento nao permitido",
      detail: "Apenas pedidos de venda abertos podem receber baixa financeira neste fluxo."
    },
    receipt_exceeds_balance: {
      kind: "warning",
      title: "Recebimento acima do saldo",
      detail: "O valor informado ultrapassa o saldo pendente do pedido."
    },
    missing_related_record: {
      kind: "warning",
      title: "Cadastro vinculado nao encontrado",
      detail: "Revise cliente, item vendavel ou vendedor informado."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure as variaveis de ambiente antes de gravar pedidos reais ou de teste."
    },
    permission_denied: {
      kind: "warning",
      title: "Permissao negada",
      detail: "Usuario precisa estar autenticado e autorizado para gravar pedidos."
    },
    duplicated: {
      kind: "warning",
      title: "Duplicidade",
      detail: "O pedido conflitou com uma chave unica existente. Tente novamente."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "O pedido nao foi gravado. Consulte logs do Supabase para detalhe tecnico."
    }
  };
  return messages[result] ?? messages.save_failed;
}
