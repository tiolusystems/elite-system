import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { CommissionAssignmentForm } from "@/app/pedidos/financeiro/finance-forms";
import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { FilterActions, PaginatedResultList, SearchToolbar } from "@/app/corporate-search/search-controls";
import { commissionRoleLabel, money, orderStatusLabel } from "@/app/pedidos/financeiro/presenters";
import { getFinanceAccess, searchCommissionOrders } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CommissionAssignmentPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!access.commissionAssign) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const query = single(params.q) ?? "";
  const page = positive(single(params.pagina)) || 1;
  const selectedId = positive(single(params.pedido));
  const ordersResult = await searchCommissionOrders(query, page);
  const orders = ordersResult.data;
  const selected = selectedId ? orders.find((order) => order.id === selectedId) ?? null : null;

  return (
    <FinanceWorkspace
      access={access}
      current="assignment"
      eyebrow="Pedidos aprovados"
      title="Comissionamento da venda"
      description="Defina pessoas e percentuais somente depois da liberação e antes do primeiro recebimento."
    >
      {ordersResult.error ? (
        <section className="notice-panel warning" role="alert">
          <strong>Consulta indisponível</strong>
          <span>{ordersResult.error}</span>
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
            <CommissionAssignmentForm order={selected} requestKey={randomUUID()} />
          </section>
        </>
      ) : (
        <>
          <SearchToolbar className="panel">
            <EntityLookup entity="pedidos" name="pedido" labelName="q" label="Pedido ou cliente" placeholder="Abra a lista ou pesquise o pedido" defaultValue={selectedId} defaultLabel={query} />
            <FilterActions clearHref="/pedidos/financeiro/comissionamento" submitLabel="Localizar" />
          </SearchToolbar>
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
          <PaginatedResultList
            page={page}
            total={orders[0]?.totalCount ?? 0}
            pageSize={20}
            previousHref={page > 1 ? listHref(query, page - 1) : null}
            nextHref={page * 20 < (orders[0]?.totalCount ?? 0) ? listHref(query, page + 1) : null}
          />
        </>
      )}
    </FinanceWorkspace>
  );
}


function listHref(query: string, page: number) {
  return `/pedidos/financeiro/comissionamento?q=${encodeURIComponent(query)}&pagina=${page}`;
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function positive(value?: string) { const parsed = Number(value); return Number.isInteger(parsed) && parsed > 0 ? parsed : null; }
