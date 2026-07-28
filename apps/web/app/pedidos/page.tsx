import { randomUUID } from "node:crypto";

import Link from "next/link";

import { criarPedidoComercialAction, decidirPedidoGerencialAction } from "@/app/pedidos/actions";
import { OrderEntryEditor } from "@/app/pedidos/order-entry-editor";
import { getOrderDeliveryLocations, getOrderWorkspace } from "@/lib/orders";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PedidosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const search = single(params.busca) ?? "";
  const page = Math.max(0, Number(single(params.pagina) ?? 0) || 0);
  const selectedLink = Number(single(params.cliente) ?? 0);
  const result = single(params.result);
  const workspace = await getOrderWorkspace(search || null, page);
  const selected = workspace.clients.find((client) => client.linkId === selectedLink) ?? null;
  const deliveryLocations = selected ? await getOrderDeliveryLocations(selected.clientId) : [];
  const visibleOrders = selected
    ? workspace.orders.filter((order) => order.clientId === selected.clientId)
    : workspace.orders;
  const message = resultMessage(result);
  const orderRequestKey = randomUUID();

  return (
    <main className="orders-workspace">
      <header className="orders-heading">
        <div><span className="eyebrow">Comercial</span><h1>Pedidos</h1><p>Venda pela carteira, com entrega programada, crédito visível e liberação auditada.</p></div>
      </header>

      {message ? <div className={`notice-panel ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></div> : null}
      {workspace.error ? <div className="notice-panel warning"><strong>Não foi possível carregar</strong><span>{workspace.error}</span></div> : null}

      <section className="orders-flow" aria-label="Fluxo do pedido">
        <span className="is-active">1. Cliente</span><span>2. Local de entrega</span><span>3. Itens</span><span>4. Entregas</span><span>5. Revisão</span><span>6. Liberação</span>
      </section>

      <section className="orders-seller-layout">
        <section className="panel orders-portfolio">
          <div className="panel-header"><div><h2>1. Sua carteira de clientes</h2><p>Pesquise por nome, razão social, nome fantasia, documento, município, propriedade ou estabelecimento.</p></div></div>
          <form className="orders-search" method="get">
            <label>
              <span>Pesquisar cliente</span>
              <input
                name="busca"
                defaultValue={search}
                placeholder="Nome, documento, município, propriedade ou estabelecimento"
                role="combobox"
                aria-expanded="true"
                aria-controls="orders-client-options"
                autoComplete="off"
              />
            </label>
            <button className="secondary-button" type="submit">Pesquisar</button>
          </form>
          <div className="orders-client-list" id="orders-client-options" role="listbox" aria-label="Clientes encontrados">
            {workspace.clients.length ? workspace.clients.map((client) => (
              <Link
                className={client.linkId === selectedLink ? "is-selected" : ""}
                href={`/pedidos?busca=${encodeURIComponent(search)}&pagina=${page}&cliente=${client.linkId}#novo-pedido`}
                key={client.linkId}
                role="option"
                aria-selected={client.linkId === selectedLink}
              >
                <strong>{client.clientName}</strong>
                {client.tradeName && client.tradeName !== client.clientName ? <span>{client.tradeName}</span> : null}
                <span>{client.document ?? "Documento não informado"} · {[client.city, client.state].filter(Boolean).join("/") || "Município não informado"}</span>
                <small>{clientStatusLabel(client.status)} · Limite disponível: {money(client.availableLimit)} · {creditLabel(client.creditStatus)}</small>
              </Link>
            )) : <div className="empty-state"><strong>Nenhum cliente encontrado</strong><span>O cliente precisa estar ativo e pertencer à sua carteira ou equipe autorizada.</span></div>}
          </div>
          <div className="orders-pagination">
            {page > 0 ? <Link className="secondary-button" href={`/pedidos?busca=${encodeURIComponent(search)}&pagina=${page - 1}`}>Página anterior</Link> : <span />}
            <span>Página {page + 1}</span>
            {workspace.clients.length === 20 ? <Link className="secondary-button" href={`/pedidos?busca=${encodeURIComponent(search)}&pagina=${page + 1}`}>Próxima página</Link> : <span />}
          </div>
        </section>

        <section className="panel orders-entry" id="novo-pedido">
          <div className="panel-header"><div><h2>Novo pedido</h2><p>{selected ? selected.clientName : "Selecione um cliente da carteira para começar."}</p></div><span className="status-chip status-pending_review">Aguardará liberação</span></div>
          {selected ? (
            <form action={criarPedidoComercialAction}>
              <input type="hidden" name="idempotency_key" value={orderRequestKey} />
              <input type="hidden" name="cliente_vendedor_vinculo_id" value={selected.linkId} />
              <input type="hidden" name="cliente_id" value={selected.clientId} />
              <input type="hidden" name="return_search" value={search} />
              <input type="hidden" name="return_page" value={page} />
              <div className="orders-credit-strip">
                <div><span>Limite disponível</span><strong>{money(selected.availableLimit)}</strong></div>
                <div><span>Situação do crédito</span><strong>{creditLabel(selected.creditStatus)}</strong></div>
                <div><span>Vendedor responsável</span><strong>{selected.sellerName}</strong></div>
              </div>
              <OrderEntryEditor
                client={selected}
                items={workspace.items}
                locations={deliveryLocations}
                result={result}
                exchangeItems={workspace.exchangeItems.filter((item) => item.clientId === selected.clientId)}
              />
            </form>
          ) : <div className="empty-state"><strong>Cliente ainda não selecionado</strong><span>Pesquise ou escolha um cliente da lista; o limite aparecerá antes do preenchimento.</span></div>}
        </section>
      </section>

      <section className="panel orders-approvals" id="aprovacoes">
        <div className="panel-header"><div><h2>Liberações gerenciais</h2><p>Pedidos próprios do gerente e de vendedores subordinados conforme alçada.</p></div><span className="pill">{workspace.approvals.length} pendente(s)</span></div>
        {workspace.approvals.length ? <div className="approval-list">{workspace.approvals.map((order) => (
          <article key={order.id}>
            <div className="approval-summary"><div><strong>{order.code}</strong><span>{order.clientName} · {order.sellerName}</span></div><div><strong>{money(order.total)}</strong><span>Limite: {money(order.availableLimit)}</span></div></div>
            <form className="approval-decision" action={decidirPedidoGerencialAction}>
              <input type="hidden" name="idempotency_key" value={randomUUID()} />
              <input type="hidden" name="pedido_id" value={order.id} /><label><span>Justificativa</span><input name="justificativa" minLength={10} required placeholder="Fundamente a decisão" /></label>
              <button name="decisao" value="liberado" className="primary-button">Liberar</button><button name="decisao" value="bloqueado" className="secondary-button">Reprovar</button>
            </form>
            <p className="table-subtext">A decisão deste pedido não altera o limite cadastral do cliente.</p>
            <Link className="secondary-button" href={`/cadastros?grupo=clientes&cliente=${order.clientId}&secao=credito#credito-cliente`}>
              Consultar crédito do cliente
            </Link>
          </article>
        ))}</div> : <div className="empty-state"><strong>Nenhum pedido aguardando sua liberação</strong><span>A fila mostra somente pedidos dentro da hierarquia comercial e alçada efetiva.</span></div>}
      </section>

      <section className="panel" id="historico"><div className="panel-header"><div><h2>{selected ? `Histórico de ${selected.clientName}` : "Pedidos recentes no seu escopo"}</h2><p>{selected ? "Somente pedidos do cliente selecionado." : "Vendedor: carteira própria. Gerente: carteira própria e equipe autorizada."}</p></div><span className="pill">{visibleOrders.length} pedido(s)</span></div>
        {visibleOrders.length ? <div className="orders-history"><div className="orders-history-head"><span>Pedido</span><span>Cliente</span><span>Vendedor</span><span>Situação</span><span>Total</span><span>Documento</span></div>{visibleOrders.map((order) => <article key={order.id}><strong>{order.code}</strong><span>{order.clientName}<small>{order.propertyName ?? "Entrega definida na programação"}</small></span><span>{order.sellerName ?? "Não informado"}</span><span className="status-chip">{statusLabel(order.status)}</span><strong>{money(order.total)}</strong>{["open", "fulfilled"].includes(order.status) ? <Link className="secondary-button" href={`/pedidos/${order.id}/contrato`} target="_blank">Exportar PDF</Link> : <span className="orders-document-pending">Disponível após aprovação</span>}</article>)}</div> : <div className="empty-state"><strong>{selected ? "Este cliente ainda não possui pedidos visíveis" : "Nenhum pedido no seu escopo"}</strong><span>Pedidos de outras carteiras não são exibidos.</span></div>}
      </section>
    </main>
  );
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function money(value: number | null) { return value === null ? "Não informado" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value); }
function statusLabel(value: string) { return ({ draft: "Rascunho", open: "Liberado", blocked: "Aguardando liberação", cancelled: "Cancelado", fulfilled: "Atendido" } as Record<string, string>)[value] ?? "Em análise"; }
function creditLabel(value: string) { return ({ liberado: "Liberado", reduzido: "Reduzido", bloqueado: "Bloqueado", pendente_aprovacao: "Pendente de aprovação" } as Record<string, string>)[value] ?? "Pendente de análise"; }
function clientStatusLabel(value: string) { return ({ ativa: "Cadastro ativo", active: "Cadastro ativo", nao_verificada: "Situação não verificada", suspensa: "Cadastro suspenso", inativa: "Cadastro inativo", inactive: "Cadastro inativo" } as Record<string, string>)[value] ?? "Situação não reconhecida"; }
function resultMessage(result?: string) {
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    pedido_pending_approval: { kind: "ok", title: "Pedido enviado", detail: "O responsável com alçada já pode analisar a liberação." },
    order_approved: { kind: "ok", title: "Pedido liberado", detail: "O pedido está aberto para as próximas etapas operacionais." },
    order_rejected: { kind: "warning", title: "Pedido reprovado", detail: "A justificativa ficou registrada no histórico." },
    credit_limit_adjusted: { kind: "ok", title: "Limite atualizado", detail: "A alteração e a justificativa foram auditadas." },
    invalid_manager_decision: { kind: "warning", title: "Decisão incompleta", detail: "Informe uma justificativa com pelo menos 10 caracteres." },
    invalid_credit_limit: { kind: "warning", title: "Limite inválido", detail: "Informe valor não negativo e justificativa completa." },
    missing_bonus_reason: { kind: "warning", title: "Justificativa obrigatória", detail: "Explique a bonificação com pelo menos 10 caracteres." },
    permission_denied: { kind: "warning", title: "Operação não autorizada", detail: "Este cliente ou pedido não pertence ao seu escopo comercial." },
    missing_order_required: { kind: "warning", title: "Pedido incompleto", detail: "Revise os campos indicados e mantenha ao menos um item válido." },
    missing_delivery_schedule: { kind: "warning", title: "Programação incompleta", detail: "Informe local, data e distribuição integral das quantidades." },
    invalid_delivery_date: { kind: "warning", title: "Data de entrega inválida", detail: "A previsão não pode ser anterior à data do pedido." },
    invalid_delivery_location: { kind: "warning", title: "Local de entrega inválido", detail: "Escolha um local ativo pertencente ao cliente selecionado." },
    invalid_sale_item: { kind: "warning", title: "Apresentação indisponível", detail: "Revise o produto e escolha uma apresentação ativa e comercializável." },
    idempotency_conflict: { kind: "warning", title: "Pedido alterado durante o envio", detail: "Os dados foram preservados. Revise e envie novamente." },
    duplicated: { kind: "warning", title: "Registro já existente", detail: "A solicitação já foi registrada ou contém um item repetido." },
    save_failed: { kind: "warning", title: "Não foi possível gravar", detail: "Os dados foram preservados. Use a referência exibida para o suporte se o problema continuar." }
  };
  return result ? messages[result] ?? null : null;
}
