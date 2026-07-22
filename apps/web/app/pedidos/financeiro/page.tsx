import { adjustCommissionAction, assignOrderCommissionAction, payCommissionAction, registerReceiptAction } from "@/app/pedidos/financeiro/actions";
import { getFinanceDashboard } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function FinancePage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getFinanceDashboard();
  const result = single(params.result);
  const message = messageFor(result);
  const today = new Date().toISOString().slice(0, 10);

  return <main className="app-shell"><section className="workspace dashboard-workspace finance-workspace">
    <div className="dashboard-header"><div><span className="eyebrow">Financeiro auditado</span><h1>Recebimentos e comissoes</h1><p className="muted">O recebimento libera a comissao proporcional; pagamentos e ajustes entram na conta corrente sem apagar historico.</p></div></div>
    <section className="kpi-grid finance-kpis" aria-label="Resumo financeiro">
      <article className="kpi-card accent-amber"><span>Saldo de pedidos</span><strong>{money(dashboard.totals.openReceivables)}</strong><p>Somente vendas liberadas ou atendidas.</p></article>
      <article className="kpi-card accent-green"><span>Recebimentos ativos</span><strong>{money(dashboard.totals.received)}</strong><p>Eventos recentes carregados na tela.</p></article>
      <article className="kpi-card accent-blue"><span>Comissao a pagar</span><strong>{money(dashboard.totals.commissionBalance)}</strong><p>Saldo atual da conta corrente.</p></article>
    </section>
    {dashboard.error ? <section className="notice-panel warning"><strong>Consulta indisponivel</strong><span>{dashboard.error}</span></section> : null}
    {message ? <section className={`notice-panel ${message.kind}`} role="status"><strong>{message.title}</strong><span>{message.detail}</span></section> : null}

    <section className="panel form-panel" id="previsoes"><div className="panel-header"><div><h2>Definir comissionados da venda</h2><p>O gerente pode atribuir vendedor, agente ou gerente depois da liberacao e antes do primeiro recebimento.</p></div><span className="pill">manual e flexivel</span></div>
      <form action={assignOrderCommissionAction}><div className="form-grid finance-adjust-grid">
        <label>Pedido aprovado<select name="pedido_id" defaultValue="" required><option value="" disabled>Selecione</option>{dashboard.orders.map((order) => <option key={order.id} value={order.id}>{order.code} - {order.clientName}</option>)}</select></label>
        <label>Comissionado<select name="pessoa_id" defaultValue="" required><option value="" disabled>Selecione</option>{dashboard.commissions.map((item) => <option key={item.personId} value={item.personId}>{item.personName}</option>)}</select></label>
        <label>Papel<select name="papel_comissao" defaultValue="vendedor"><option value="vendedor">Vendedor</option><option value="agente">Agente</option><option value="gerente">Gerente</option><option value="outro">Outro</option></select></label>
        <label>Percentual<input name="percentual_comissao" inputMode="decimal" min="0.0001" max="100" step="0.0001" required /></label>
        <label className="wide-field">Justificativa<input name="justificativa" minLength={10} placeholder="Regra comercial aprovada para este pedido" required /></label>
      </div><div className="form-footer"><span>Podem existir varios comissionados. A previsao fica congelada antes do recebimento.</span><button className="primary-button">Definir comissao</button></div></form>
    </section>

    <section className="finance-columns">
      <section className="panel form-panel" id="recebimentos"><div className="panel-header"><div><h2>Registrar recebimento</h2><p>Escolha um pedido com saldo financeiro aberto.</p></div><span className="pill">liberacao proporcional</span></div>
        <form action={registerReceiptAction}><div className="form-grid finance-form-grid">
          <label className="wide-field">Pedido<select name="pedido_id" defaultValue="" required><option value="" disabled>Selecione o pedido</option>{dashboard.orders.map((order) => <option key={order.id} value={order.id}>{order.code} - {order.clientName} - saldo {money(order.open)}</option>)}</select></label>
          <label>Valor recebido<input name="valor_recebido" inputMode="decimal" min="0.01" step="0.01" required /></label>
          <label>Data<input name="data_recebimento" type="date" defaultValue={today} required /></label>
          <label>Forma<select name="forma_recebimento" defaultValue="transferencia"><option value="transferencia">Transferencia</option><option value="pix">Pix</option><option value="boleto">Boleto</option><option value="cheque">Cheque</option><option value="dinheiro">Dinheiro</option><option value="outro">Outro</option></select></label>
          <label className="wide-field">Referencia ou observacao<input name="observacao" placeholder="Documento, parcela ou conciliacao" /></label>
        </div><div className="form-footer"><span>O banco recusa valor acima do saldo e impede liberacao duplicada.</span><button className="primary-button" disabled={!dashboard.orders.length}>Registrar recebimento</button></div></form>
      </section>

      <section className="panel" id="comissoes"><div className="panel-header"><div><h2>Conta corrente de comissoes</h2><p>Selecione uma pessoa somente quando houver saldo.</p></div><span className="pill">append-only</span></div>
        <div className="finance-balance-list">{dashboard.commissions.length ? dashboard.commissions.map((item) => <article key={item.personId}><span>{item.personName}</span><strong>{money(item.balance)}</strong></article>) : <div className="empty-state compact-empty"><strong>Nenhum saldo carregado</strong><span>As comissoes aparecem apos recebimentos de pedidos com previsao.</span></div>}</div>
        <form action={payCommissionAction}><div className="form-grid finance-form-grid">
          <label className="wide-field">Comissionado<select name="pessoa_id" defaultValue="" required><option value="" disabled>Selecione</option>{dashboard.commissions.filter((item) => item.balance > 0).map((item) => <option key={item.personId} value={item.personId}>{item.personName} - {money(item.balance)}</option>)}</select></label>
          <label>Valor pago<input name="valor_pago" inputMode="decimal" min="0.01" step="0.01" required /></label><label>Data<input name="data_pagamento" type="date" defaultValue={today} required /></label>
          <label>Forma de pagamento<input name="forma_pagamento" placeholder="Pix, transferencia..." /></label><label className="wide-field">Referencia<input name="referencia_pagamento" placeholder="Lote de pagamento ou comprovante" /></label>
        </div><div className="form-footer"><span>Nunca e permitido pagar acima do saldo.</span><button className="primary-button">Registrar pagamento</button></div></form>
      </section>
    </section>

    <section className="panel form-panel" id="ajustes"><div className="panel-header"><div><h2>Ajuste manual de comissao</h2><p>Uso excepcional, com alçada alta e motivo fechado.</p></div><span className="pill">justificativa auditada</span></div>
      <form action={adjustCommissionAction}><div className="form-grid finance-adjust-grid">
        <label>Comissionado<select name="pessoa_id" defaultValue="" required><option value="" disabled>Selecione</option>{dashboard.commissions.map((item) => <option key={item.personId} value={item.personId}>{item.personName}</option>)}</select></label>
        <label>Valor do ajuste<input name="valor_ajuste" inputMode="decimal" step="0.01" placeholder="Positivo ou negativo" required /></label>
        <label>Motivo<select name="motivo_codigo" defaultValue="correcao_calculo"><option value="correcao_calculo">Correcao de calculo</option><option value="estorno_devolucao">Estorno por devolucao</option><option value="acordo_comercial">Acordo comercial</option><option value="compensacao_futura">Compensacao futura</option><option value="outro">Outro</option></select></label>
        <label className="wide-field">Detalhamento<input name="motivo_detalhe" minLength={10} placeholder="Obrigatorio para Outro; recomendado nos demais" /></label>
      </div><div className="form-footer"><span>Valor positivo credita; valor negativo debita. O movimento original nao e editado.</span><button className="secondary-button">Registrar ajuste</button></div></form>
    </section>

    <section className="finance-columns"><section className="panel"><div className="panel-header"><h2>Recebimentos recentes</h2><span className="pill">{dashboard.receipts.length}</span></div><div className="finance-event-list">{dashboard.receipts.slice(0, 12).map((row) => <article key={row.id}><span>Pedido {row.orderId ?? "multiplos"}<small>{date(row.date)} · {row.method ?? "Forma nao informada"}</small></span><strong>{money(row.value)}</strong></article>)}</div></section>
      <section className="panel"><div className="panel-header"><h2>Movimentos de comissao</h2><span className="pill">{dashboard.movements.length}</span></div><div className="finance-event-list">{dashboard.movements.slice(0, 12).map((row) => <article key={row.id}><span>{movementLabel(row.type)}<small>{dateTime(row.createdAt)} · pessoa {row.personId}</small></span><strong className={row.value < 0 ? "finance-debit" : "finance-credit"}>{money(row.value)}</strong></article>)}</div></section></section>
  </section></main>;
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function money(value: number) { return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value); }
function date(value: string) { return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)); }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value)); }
function movementLabel(value: string) { return ({ credito_liberacao: "Comissao liberada", debito_pagamento: "Pagamento", debito_estorno: "Estorno", compensacao_futura: "Compensacao futura", ajuste_manual: "Ajuste manual" } as Record<string, string>)[value] ?? "Movimento financeiro"; }
function messageFor(value?: string) {
  return ({
    commission_assigned: { kind: "success", title: "Comissao definida", detail: "A previsao ficou registrada antes do recebimento." },
    receipt_registered: { kind: "success", title: "Recebimento registrado", detail: "A alocacao e a liberacao proporcional foram processadas." },
    commission_paid: { kind: "success", title: "Pagamento registrado", detail: "O saldo da conta corrente foi atualizado." },
    commission_adjusted: { kind: "success", title: "Ajuste registrado", detail: "O motivo e os valores ficaram auditados." },
    not_allowed: { kind: "warning", title: "Operacao nao autorizada", detail: "Seu perfil nao possui a alcada necessaria." },
    receipt_exceeds_balance: { kind: "warning", title: "Valor acima do saldo", detail: "Revise o saldo aberto do pedido." },
    payment_exceeds_balance: { kind: "warning", title: "Pagamento acima do saldo", detail: "Revise a conta corrente do comissionado." },
    already_processed: { kind: "warning", title: "Evento ja processado", detail: "Nenhum valor foi duplicado." },
    invalid_assignment: { kind: "warning", title: "Atribuicao incompleta", detail: "Informe pedido, pessoa, papel, percentual e justificativa." },
    invalid_adjustment: { kind: "warning", title: "Ajuste incompleto", detail: "Informe pessoa, valor e motivo valido." },
    invalid_payment: { kind: "warning", title: "Pagamento incompleto", detail: "Revise pessoa, valor e data." },
    invalid_receipt: { kind: "warning", title: "Recebimento incompleto", detail: "Revise pedido, valor e data." },
    operation_failed: { kind: "warning", title: "Operacao nao concluida", detail: "Os dados foram preservados. Revise os campos ou sua permissao." },
  } as Record<string, { kind: string; title: string; detail: string }>)[value ?? ""] ?? null;
}
