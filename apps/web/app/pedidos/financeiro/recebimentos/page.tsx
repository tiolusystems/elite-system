import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { ReceiptForm } from "@/app/pedidos/financeiro/finance-forms";
import { FinancePermissionState, FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { FilterActions, PaginatedResultList, SearchToolbar } from "@/app/corporate-search/search-controls";
import { date, fiscalReferenceTypeLabel, money, orderStatusLabel } from "@/app/pedidos/financeiro/presenters";
import { getFinanceAccess, searchReceiptOrders } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ReceiptsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!(access.receiptsView || access.receiptsRegister)) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const query = single(params.q) ?? "";
  const page = positive(single(params.pagina)) || 1;
  const selectedId = positive(single(params.pedido));
  const ordersResult = await searchReceiptOrders(query, page);
  const orders = ordersResult.data;
  const selected = selectedId ? orders.find((order) => order.id === selectedId) ?? null : null;

  return (
    <FinanceWorkspace
      access={access}
      current="receipts"
      eyebrow="Recebimentos"
      title="Recebimentos de clientes"
      description="Pesquise o pedido, confira o saldo e registre o documento que comprova o valor recebido."
    >
      {ordersResult.error ? <QueryError message={ordersResult.error} /> : null}
      {selected ? (
        <>
          <Link className="secondary-button finance-back-link" href={listHref(query, page)}>Voltar aos pedidos com saldo</Link>
          <section className="panel finance-record-summary">
            <div className="panel-header">
              <div><span className="eyebrow">{selected.code}</span><h2>{selected.clientName}</h2><p>{selected.propertyName || "Local de entrega não informado"} · {orderStatusLabel(selected.status)}</p></div>
              <strong>{money(selected.open)} em aberto</strong>
            </div>
            <dl className="finance-summary-grid">
              <div><dt>Valor do pedido</dt><dd>{money(selected.total)}</dd></div>
              <div><dt>Já recebido</dt><dd>{money(selected.received)}</dd></div>
              <div><dt>Saldo atual</dt><dd>{money(selected.open)}</dd></div>
            </dl>
            <div className="finance-detail-columns">
              <div><h3>Referências fiscais externas</h3>{selected.fiscalReferences.length ? selected.fiscalReferences.map((reference, index) => <p key={`${reference.numero}-${index}`}><strong>{reference.numero || "Número não informado"}</strong><span>{fiscalReferenceTypeLabel(reference.tipo)}</span></p>) : <p className="muted">Nenhuma referência fiscal registrada. Isso não impede um recebimento documentado.</p>}</div>
              <div><h3>Recebimentos anteriores</h3>{selected.previousReceipts.length ? selected.previousReceipts.map((receipt) => <p key={receipt.id}><strong>{money(receipt.value)} · {date(receipt.date)}</strong><span>{receipt.documentReference || "Não informado no registro original"}</span></p>) : <p className="muted">Nenhum recebimento anterior.</p>}</div>
            </div>
          </section>
          {access.receiptsRegister ? (
            <section className="panel form-panel">
              <div className="panel-header"><div><h2>Novo recebimento</h2><p>A confirmação gera evento financeiro e libera comissão proporcional.</p></div><span className="pill">evento auditado</span></div>
              <ReceiptForm order={selected} requestKey={randomUUID()} />
            </section>
          ) : <FinancePermissionState detail="Você pode consultar recebimentos e saldos, mas não possui alçada para registrar um novo valor." />}
        </>
      ) : (
        <>
          <SearchToolbar className="panel">
            <EntityLookup entity="pedidos" name="pedido" labelName="q" label="Pedido ou cliente" placeholder="Abra a lista ou pesquise por pedido" defaultValue={selectedId} defaultLabel={query} helpText="Também é possível localizar por cliente e documento na lista de resultados." />
            <FilterActions clearHref="/pedidos/financeiro/recebimentos" submitLabel="Localizar" />
          </SearchToolbar>
          <section className="panel">
            <div className="panel-header"><div><h2>Pedidos com saldo financeiro</h2><p>Resultados paginados; os totalizadores da visão financeira permanecem integrais.</p></div><span className="pill">{orders[0]?.totalCount ?? 0}</span></div>
            <div className="finance-result-list">
              {orders.length ? orders.map((order) => (
                <Link key={order.id} href={`/pedidos/financeiro/recebimentos?q=${encodeURIComponent(query)}&pagina=${page}&pedido=${order.id}`}>
                  <span><strong>{order.code}</strong><small>{order.clientName} · {order.propertyName || "Sem local informado"}</small></span>
                  <span><small>Saldo aberto</small><strong>{money(order.open)}</strong></span>
                </Link>
              )) : ordersResult.error ? null : <div className="empty-state"><strong>Nenhum pedido com saldo encontrado</strong><span>Pesquise por outro código, cliente, documento, referência fiscal ou local de entrega.</span></div>}
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

function QueryError({ message }: { message: string }) {
  return <section className="notice-panel warning" role="alert"><strong>Consulta indisponível</strong><span>{message}</span></section>;
}


function listHref(query: string, page: number) { return `/pedidos/financeiro/recebimentos?q=${encodeURIComponent(query)}&pagina=${page}`; }
function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function positive(value?: string) { const parsed = Number(value); return Number.isInteger(parsed) && parsed > 0 ? parsed : null; }
