import Link from "next/link";
import { redirect } from "next/navigation";

import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { date, financeDateDefaults, money, receiptMethodLabel } from "@/app/pedidos/financeiro/presenters";
import { getFinanceAccess, getFinanceOverview } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function FinancePage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!access.any) redirect("/modulo-indisponivel?module=financeiro&reason=permission");
  if (!(access.dashboardView || access.receiptsView || access.receiptsRegister || access.commissionsView || access.commissionsPay || access.commissionsAdjust)) {
    redirect("/pedidos/financeiro/comissionamento");
  }

  const defaults = financeDateDefaults();
  const filters = {
    startDate: single(params.inicio) || defaults.startDate,
    endDate: single(params.fim) || defaults.endDate,
    cutoffDate: single(params.corte) || defaults.cutoffDate,
  };
  const overview = await getFinanceOverview(filters, access);

  return (
    <FinanceWorkspace
      access={access}
      current="overview"
      eyebrow="Financeiro"
      title="Visão financeira"
      description="Posição atual e movimentos do período calculados sobre toda a base autorizada."
    >
      <form className="panel finance-filter-bar" method="get" aria-label="Filtros da visão financeira">
        <label>Data inicial<input name="inicio" type="date" defaultValue={filters.startDate} /></label>
        <label>Data final<input name="fim" type="date" defaultValue={filters.endDate} /></label>
        <label>Posição em<input name="corte" type="date" defaultValue={filters.cutoffDate} /></label>
        <button className="secondary-button">Atualizar visão</button>
      </form>

      {overview.error ? <section className="notice-panel warning" role="status"><strong>Consulta indisponível</strong><span>{overview.error}</span></section> : null}

      <section className="kpi-grid finance-kpis" aria-label="Resumo financeiro integral">
        <Kpi
          label="Saldo a receber"
          value={kpiValue(overview.error, overview.totals.openReceivables, money)}
          detail={`Posição em ${date(filters.cutoffDate)}.`}
          href={access.receiptsView || access.receiptsRegister ? "/pedidos/financeiro/recebimentos" : null}
        />
        <Kpi
          label="Recebido no período"
          value={kpiValue(overview.error, overview.totals.receivedPeriod, money)}
          detail={`${date(filters.startDate)} a ${date(filters.endDate)}.`}
          href={access.receiptsView || access.receiptsRegister ? "/pedidos/financeiro/recebimentos" : null}
        />
        <Kpi
          label="Comissões a pagar"
          value={kpiValue(overview.error, overview.totals.commissionBalance, money)}
          detail={`Saldo da conta corrente em ${date(filters.cutoffDate)}.`}
          href={access.commissionsView || access.commissionsPay || access.commissionsAdjust ? "/pedidos/financeiro/comissoes" : null}
        />
        <Kpi
          label="Pedidos com saldo"
          value={kpiValue(overview.error, overview.totals.ordersWithBalance, String)}
          detail="Quantidade integral, independente da paginação."
          href={access.receiptsView || access.receiptsRegister ? "/pedidos/financeiro/recebimentos" : null}
        />
      </section>

      <section className="finance-shortcuts" aria-label="Operações financeiras autorizadas">
        {access.commissionAssign ? <Shortcut href="/pedidos/financeiro/comissionamento" title="Comissionamento" detail="Definir pessoas e percentuais antes do primeiro recebimento." /> : null}
        {access.receiptsView || access.receiptsRegister ? <Shortcut href="/pedidos/financeiro/recebimentos" title="Recebimentos" detail="Pesquisar pedidos, conferir saldo e registrar pagamentos recebidos." /> : null}
        {access.commissionsView || access.commissionsPay || access.commissionsAdjust ? <Shortcut href="/pedidos/financeiro/comissoes" title="Conta corrente" detail="Consultar liberações, pagamentos, estornos e ajustes." /> : null}
      </section>

      <section className="panel">
        <div className="panel-header">
          <div><h2>Pendências operacionais</h2><p>Itens que exigem continuidade nos fluxos autorizados.</p></div>
        </div>
        <div className="finance-pending-list">
          {overview.totals.ordersWithBalance !== null ? (
            <Pending
              href={access.receiptsView || access.receiptsRegister ? "/pedidos/financeiro/recebimentos" : null}
              title="Pedidos com saldo financeiro"
              detail="Localize o pedido e confira os recebimentos anteriores."
              value={String(overview.totals.ordersWithBalance)}
            />
          ) : null}
          {overview.totals.commissionBalance !== null ? (
            <Pending
              href={access.commissionsView || access.commissionsPay || access.commissionsAdjust ? "/pedidos/financeiro/comissoes" : null}
              title="Comissões com saldo a pagar"
              detail="Consulte a conta corrente antes de registrar o pagamento."
              value={money(overview.totals.commissionBalance)}
            />
          ) : null}
        </div>
      </section>

      {access.receiptsView || access.receiptsRegister ? (
        <section className="panel">
          <div className="panel-header">
            <div><h2>Recebimentos recentes</h2><p>Últimos eventos ativos disponíveis para sua alçada.</p></div>
            <Link className="secondary-button" href="/pedidos/financeiro/recebimentos">Abrir recebimentos</Link>
          </div>
          <div className="finance-event-list">
            {overview.receipts.length ? overview.receipts.map((receipt) => (
              <article key={receipt.id}>
                <span>
                  <strong>{receipt.clientName}</strong>
                  <small>{date(receipt.date)} · {receipt.method ? receiptMethodLabel(receipt.method) : "Forma não informada"}</small>
                  <small>{receipt.documentReference || "Não informado no registro original"}</small>
                </span>
                <strong>{money(receipt.value)}</strong>
              </article>
            )) : <div className="empty-state compact-empty"><strong>Nenhum recebimento recente</strong><span>Os registros aparecerão aqui após a confirmação governada.</span></div>}
          </div>
        </section>
      ) : null}
    </FinanceWorkspace>
  );
}

function Kpi({ label, value, detail, href }: { label: string; value: string; detail: string; href: string | null }) {
  const content = <><span>{label}</span><strong>{value}</strong><p>{detail}</p></>;
  return href ? <Link className="kpi-card finance-kpi-link" href={href}>{content}</Link> : <article className="kpi-card">{content}</article>;
}

function Shortcut({ href, title, detail }: { href: string; title: string; detail: string }) {
  return <Link href={href}><strong>{title}</strong><span>{detail}</span></Link>;
}

function Pending({ href, title, detail, value }: { href: string | null; title: string; detail: string; value: string }) {
  const content = <><span><strong>{title}</strong><small>{detail}</small></span><strong>{value}</strong></>;
  return href ? <Link href={href}>{content}</Link> : <article>{content}</article>;
}

function single(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function kpiValue(error: string | null, value: number | null, format: (value: number) => string) {
  if (error) return "Indisponível";
  return value === null ? "Sem alçada" : format(value);
}
