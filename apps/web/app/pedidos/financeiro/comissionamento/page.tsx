import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { CommissionAssignmentForm } from "@/app/pedidos/financeiro/finance-forms";
import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { commissionRoleLabel, money, orderStatusLabel } from "@/app/pedidos/financeiro/presenters";
import { getCommissionPeople, getFinanceAccess, searchCommissionOrders } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CommissionAssignmentPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!access.commissionAssign) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const query = single(params.q) ?? "";
  const personQuery = single(params.pessoa_q) ?? "";
  const page = positive(single(params.pagina)) || 1;
  const selectedId = positive(single(params.pedido));
  const [ordersResult, peopleResult] = await Promise.all([
    searchCommissionOrders(query, page),
    selectedId ? getCommissionPeople(personQuery) : Promise.resolve({ data: [], error: null }),
  ]);
  const orders = ordersResult.data;
  const people = peopleResult.data;
  const selected = selectedId ? orders.find((order) => order.id === selectedId) ?? null : null;

  return (
    <FinanceWorkspace
      access={access}
      current="assignment"
      eyebrow="Pedidos aprovados"
      title="Comissionamento da venda"
      description="Defina pessoas e percentuais somente depois da liberação e antes do primeiro recebimento."
    >
      {ordersResult.error || peopleResult.error ? (
        <section className="notice-panel warning" role="alert">
          <strong>Consulta indisponível</strong>
          <span>{ordersResult.error || peopleResult.error}</span>
        </section>
      ) : null}
      {selected ? (
        <>
          <Link className="secondary-button finance-back-link" href={listHref(query, page)}>Voltar aos pedidos elegíveis</Link>
          <section className="panel finance-record-summary">
            <div className="panel-header">
              <div><span className="eyebrow">{selected.code}</span><h2>{selected.clientName}</h2><p>{orderStatusLabel(selected.status)} · total {money(selected.total)}</p></div>
              <strong>{selected.totalPercentage.toLocaleString("pt-BR")}% definidos</strong>
            </div>
            <div className="finance-assignment-list">
              {selected.assignments.length ? selected.assignments.map((assignment) => (
                <article key={`${assignment.personId}-${assignment.role}`}>
                  <span><strong>{assignment.personName}</strong><small>{commissionRoleLabel(assignment.role)} · {assignment.percentage.toLocaleString("pt-BR")}%</small></span>
                  <strong>{money(assignment.expectedValue)}</strong>
                </article>
              )) : <div className="empty-state compact-empty"><strong>Nenhum comissionado definido</strong><span>Inclua a primeira pessoa autorizada para este pedido.</span></div>}
            </div>
          </section>
          <section className="panel form-panel">
            <div className="panel-header"><div><h2>Definir comissionado</h2><p>É possível incluir mais de uma pessoa, uma atribuição por vez.</p></div><span className="pill">antes do recebimento</span></div>
            <form className="finance-search-bar finance-person-search" method="get">
              <input type="hidden" name="q" value={query} />
              <input type="hidden" name="pagina" value={page} />
              <input type="hidden" name="pedido" value={selected.id} />
              <label>Pesquisar pessoa<input name="pessoa_q" defaultValue={personQuery} placeholder="Nome ou papel comercial" /></label>
              <button className="secondary-button">Pesquisar</button>
              {personQuery ? <Link href={`/pedidos/financeiro/comissionamento?q=${encodeURIComponent(query)}&pagina=${page}&pedido=${selected.id}`}>Limpar</Link> : null}
            </form>
            {peopleResult.error ? null : people.length ? (
              <CommissionAssignmentForm order={selected} people={people} requestKey={randomUUID()} />
            ) : (
              <div className="empty-state compact-empty">
                <strong>Nenhuma pessoa elegível encontrada</strong>
                <span>Revise a busca ou confirme se a pessoa está ativa e possui cadastro comercial.</span>
              </div>
            )}
          </section>
        </>
      ) : (
        <>
          <form className="panel finance-search-bar" method="get">
            <label>Pesquisar pedido<input name="q" defaultValue={query} placeholder="Código do pedido ou cliente" /></label>
            <button className="secondary-button">Pesquisar</button>
            {query ? <Link href="/pedidos/financeiro/comissionamento">Limpar</Link> : null}
          </form>
          <section className="panel">
            <div className="panel-header"><div><h2>Pedidos elegíveis</h2><p>Liberados e ainda sem recebimento financeiro.</p></div><span className="pill">{orders[0]?.totalCount ?? 0}</span></div>
            <div className="finance-result-list">
              {orders.length ? orders.map((order) => (
                <Link key={order.id} href={`/pedidos/financeiro/comissionamento?q=${encodeURIComponent(query)}&pagina=${page}&pedido=${order.id}`}>
                  <span><strong>{order.code}</strong><small>{order.clientName}</small></span>
                  <span><small>{orderStatusLabel(order.status)}</small><strong>{money(order.total)}</strong></span>
                </Link>
              )) : ordersResult.error ? null : <div className="empty-state"><strong>Nenhum pedido elegível</strong><span>Revise a busca ou confirme se o pedido já recebeu algum valor.</span></div>}
            </div>
          </section>
          <Pagination current={page} total={orders[0]?.totalCount ?? 0} query={query} />
        </>
      )}
    </FinanceWorkspace>
  );
}

function Pagination({ current, total, query }: { current: number; total: number; query: string }) {
  const pages = Math.max(Math.ceil(total / 20), 1);
  if (pages <= 1) return null;
  return <nav className="pagination" aria-label="Paginação"><span>{current > 1 ? <Link className="secondary-button" href={listHref(query, current - 1)}>Anterior</Link> : null}</span><span>Página {current} de {pages}</span><span>{current < pages ? <Link className="secondary-button" href={listHref(query, current + 1)}>Próxima</Link> : null}</span></nav>;
}

function listHref(query: string, page: number) {
  return `/pedidos/financeiro/comissionamento?q=${encodeURIComponent(query)}&pagina=${page}`;
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function positive(value?: string) { const parsed = Number(value); return Number.isInteger(parsed) && parsed > 0 ? parsed : null; }
