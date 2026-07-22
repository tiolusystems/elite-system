import Link from "next/link";

import { ajustarLimiteCreditoAction, criarPedidoVendedorAction, decidirPedidoGerencialAction } from "@/app/pedidos/actions";
import { OrderItemsEditor } from "@/app/pedidos/order-items-editor";
import { getOrderWorkspace } from "@/lib/orders";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PedidosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const search = single(params.busca) ?? "";
  const selectedLink = Number(single(params.cliente) ?? 0);
  const result = single(params.result);
  const workspace = await getOrderWorkspace(search || null);
  const selected = workspace.clients.find((client) => client.linkId === selectedLink) ?? null;
  const visibleOrders = selected
    ? workspace.orders.filter((order) => order.clientId === selected.clientId)
    : workspace.orders;
  const message = resultMessage(result);

  return (
    <main className="orders-workspace">
      <header className="orders-heading">
        <div><span className="eyebrow">Comercial</span><h1>Pedidos</h1><p>Venda pela carteira, com crédito visível e liberação gerencial auditada.</p></div>
        <Link className="secondary-button" href="/manuais/pedidos">Como usar</Link>
      </header>

      {message ? <div className={`notice-panel ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></div> : null}
      {workspace.error ? <div className="notice-panel warning"><strong>Não foi possível carregar</strong><span>{workspace.error}</span></div> : null}

      <section className="orders-flow" aria-label="Fluxo do pedido">
        <span className="is-active">1. Cliente</span><span>2. Itens</span><span>3. Enviar</span><span>4. Liberação gerencial</span>
      </section>

      <section className="orders-seller-layout">
        <section className="panel orders-portfolio">
          <div className="panel-header"><div><h2>Carteira comercial</h2><p>Vendedor: clientes próprios. Gerente: clientes próprios e da equipe.</p></div></div>
          <form className="orders-search" method="get">
            <label><span>Nome do cliente</span><input name="busca" defaultValue={search} minLength={2} placeholder="Digite pelo menos 2 letras" /></label>
            <button className="secondary-button" type="submit">Pesquisar</button>
          </form>
          <div className="orders-client-list">
            {workspace.clients.length ? workspace.clients.map((client) => (
              <Link className={client.linkId === selectedLink ? "is-selected" : ""} href={`/pedidos?busca=${encodeURIComponent(search)}&cliente=${client.linkId}#novo-pedido`} key={client.linkId}>
                <strong>{client.clientName}</strong><span>{client.propertyName ?? "Cadastro geral do cliente"}</span>
                <small>Limite disponível: {money(client.availableLimit)} · {creditLabel(client.creditStatus)}</small>
              </Link>
            )) : <div className="empty-state"><strong>{search.trim().length < 2 ? "Pesquise um cliente" : "Nenhum cliente encontrado"}</strong><span>{search.trim().length < 2 ? "Digite pelo menos duas letras para consultar a carteira." : "O cliente precisa estar ativo e pertencer à sua carteira ou equipe."}</span></div>}
          </div>
        </section>

        <section className="panel orders-entry" id="novo-pedido">
          <div className="panel-header"><div><h2>Novo pedido</h2><p>{selected ? selected.clientName : "Selecione um cliente da carteira para começar."}</p></div><span className="status-chip status-pending_review">Aguardará liberação</span></div>
          {selected ? (
            <form action={criarPedidoVendedorAction}>
              <input type="hidden" name="cliente_vendedor_vinculo_id" value={selected.linkId} />
              <div className="orders-credit-strip"><div><span>Limite disponível</span><strong>{money(selected.availableLimit)}</strong></div><div><span>Situação</span><strong>{creditLabel(selected.creditStatus)}</strong></div><div><span>Propriedade</span><strong>{selected.propertyName ?? "Geral"}</strong></div></div>
              <OrderItemsEditor items={workspace.items} />
              <div className="form-grid orders-form-grid">
                <label>Data do pedido<input name="data_pedido" type="date" defaultValue={new Date().toISOString().slice(0, 10)} required /></label>
                <label className="wide-field">Observação comercial<textarea name="observacao" rows={3} placeholder="Condição ou informação relevante" /></label>
              </div>
              <div className="form-footer"><span>O vendedor não altera limite nem libera o próprio pedido.</span><button className="primary-button" type="submit">Enviar para liberação</button></div>
            </form>
          ) : <div className="empty-state"><strong>Cliente ainda não selecionado</strong><span>Use a pesquisa ao lado; o limite aparecerá antes do preenchimento.</span></div>}
        </section>
      </section>

      <section className="panel orders-approvals" id="aprovacoes">
        <div className="panel-header"><div><h2>Liberações gerenciais</h2><p>Pedidos próprios do gerente e de vendedores subordinados.</p></div><span className="pill">{workspace.approvals.length} pendente(s)</span></div>
        {workspace.approvals.length ? <div className="approval-list">{workspace.approvals.map((order) => (
          <article key={order.id}>
            <div className="approval-summary"><div><strong>{order.code}</strong><span>{order.clientName} · {order.sellerName}</span></div><div><strong>{money(order.total)}</strong><span>Limite: {money(order.availableLimit)}</span></div></div>
            <form className="approval-decision" action={decidirPedidoGerencialAction}>
              <input type="hidden" name="pedido_id" value={order.id} /><label>Justificativa<input name="justificativa" minLength={10} required placeholder="Fundamente a decisão" /></label>
              <button name="decisao" value="liberado" className="primary-button">Liberar</button><button name="decisao" value="bloqueado" className="secondary-button">Reprovar</button>
            </form>
            <details><summary>Ajustar limite do cliente</summary><form className="approval-limit" action={ajustarLimiteCreditoAction}><input type="hidden" name="cliente_id" value={order.clientId} /><label>Novo limite<input name="limite_novo" inputMode="decimal" required /></label><label>Justificativa<input name="justificativa_limite" minLength={10} required /></label><button className="secondary-button">Registrar limite</button></form></details>
          </article>
        ))}</div> : <div className="empty-state"><strong>Nenhum pedido aguardando sua liberação</strong><span>A fila mostra somente pedidos dentro da sua hierarquia comercial.</span></div>}
      </section>

      <section className="panel" id="historico"><div className="panel-header"><div><h2>{selected ? `Histórico de ${selected.clientName}` : "Pedidos recentes no seu escopo"}</h2><p>{selected ? "Somente pedidos do cliente selecionado." : "Vendedor: carteira própria. Gerente: carteira própria e equipe."}</p></div><span className="pill">{visibleOrders.length} pedido(s)</span></div>
        {visibleOrders.length ? <div className="orders-history"><div className="orders-history-head"><span>Pedido</span><span>Cliente</span><span>Vendedor</span><span>Situação</span><span>Total</span></div>{visibleOrders.map((order) => <article key={order.id}><strong>{order.code}</strong><span>{order.clientName}<small>{order.propertyName ?? "Sem propriedade específica"}</small></span><span>{order.sellerName ?? "Não informado"}</span><span className="status-chip">{statusLabel(order.status)}</span><strong>{money(order.total)}</strong></article>)}</div> : <div className="empty-state"><strong>{selected ? "Este cliente ainda não possui pedidos visíveis" : "Nenhum pedido no seu escopo"}</strong><span>Pedidos de outras carteiras não são exibidos.</span></div>}
      </section>
    </main>
  );
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function money(value: number | null) { return value === null ? "Não informado" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value); }
function statusLabel(value: string) { return ({ draft: "Rascunho", open: "Liberado", blocked: "Aguardando liberação", cancelled: "Cancelado", fulfilled: "Atendido" } as Record<string, string>)[value] ?? "Em análise"; }
function creditLabel(value: string) { return ({ liberado: "Liberado", reduzido: "Reduzido", bloqueado: "Bloqueado", pendente_aprovacao: "Pendente de aprovação" } as Record<string, string>)[value] ?? "Pendente de análise"; }
function resultMessage(result?: string) {
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    pedido_pending_approval: { kind: "ok", title: "Pedido enviado", detail: "O gerente responsável já pode analisar a liberação." },
    order_approved: { kind: "ok", title: "Pedido liberado", detail: "O pedido está aberto para as próximas etapas operacionais." },
    order_rejected: { kind: "warning", title: "Pedido reprovado", detail: "A justificativa ficou registrada no histórico." },
    credit_limit_adjusted: { kind: "ok", title: "Limite atualizado", detail: "A alteração e a justificativa foram auditadas." },
    invalid_manager_decision: { kind: "warning", title: "Decisão incompleta", detail: "Informe uma justificativa com pelo menos 10 caracteres." },
    invalid_credit_limit: { kind: "warning", title: "Limite inválido", detail: "Informe valor não negativo e justificativa completa." },
    permission_denied: { kind: "warning", title: "Operação não autorizada", detail: "Este cliente ou pedido não pertence ao seu escopo comercial." },
    save_failed: { kind: "warning", title: "Não foi possível gravar", detail: "Revise os dados e tente novamente." }
  };
  return result ? messages[result] ?? null : null;
}
