import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { CommissionAssignmentForm } from "@/app/pedidos/financeiro/finance-forms";
import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { FilterActions, PaginatedResultList, SearchToolbar } from "@/app/corporate-search/search-controls";
import { commissionRoleLabel, money, orderStatusLabel } from "@/app/pedidos/financeiro/presenters";
import { getCommissionOrderById, getFinanceAccess, searchCommissionOrders } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CommissionAssignmentPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!access.commissionAssign) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const query = single(params.q) ?? "";
  const page = positive(single(params.pagina)) || 1;
  const selectedId = positive(single(params.pedido));

  const [ordersResult, selectedResult] = await Promise.all([
    searchCommissionOrders(query, page),
    selectedId ? getCommissionOrderById(selectedId) : Promise.resolve({ data: null, error: null }),
  ]);
  const orders = ordersResult.data;
  const selected = selectedResult.data;

  return (
    <FinanceWorkspace
      access={access}
      current="assignment"
      eyebrow="Vendas liberadas"
      title="Comissionamento da venda"
      description="Revise participantes e percentuais de vendas liberadas. Novos participantes podem ser incluídos mesmo após recebimentos."
    >
      {ordersResult.error ? (
        <section className="notice-panel warning" role="alert">
          <strong>Consulta indisponível</strong>
          <span>{ordersResult.error}</span>
        </section>
      ) : null}

      {selectedId && selectedResult.error ? (
        <section className="notice-panel warning" role="alert">
          <strong>Não foi possível abrir o pedido</strong>
          <span>{selectedResult.error}</span>
        </section>
      ) : null}

      {selected ? (
        <>
          <Link className="secondary-button finance-back-link" href={listHref(query, page)}>Voltar às vendas</Link>

          <section className="panel finance-record-summary">
            <div className="panel-header">
              <div>
                <span className="eyebrow">{selected.code}</span>
                <h2>{selected.clientName}</h2>
                <p>
                  {orderStatusLabel(selected.status)} · total {money(selected.total)}
                  {selected.received > 0 ? ` · recebido ${money(selected.received)}` : ""}
                </p>
              </div>
              <strong>{selected.totalPercentage.toLocaleString("pt-BR")}% em taxas registradas</strong>
            </div>

            <div className="finance-assignment-list">
              {selected.assignments.length ? selected.assignments.map((assignment) => (
                <article key={`${assignment.personId}-${assignment.role}-${assignment.expectedValue}`}>
                  <span>
                    <strong>{assignment.personName}</strong>
                    <small>
                      {commissionRoleLabel(assignment.role)} · {assignment.percentage.toLocaleString("pt-BR")}%
                      {assignment.origin ? ` · ${assignmentOriginLabel(assignment.origin)}` : ""}
                    </small>
                  </span>
                  <strong>{money(assignment.expectedValue)}</strong>
                </article>
              )) : (
                <div className="empty-state compact-empty">
                  <strong>Nenhum comissionado definido</strong>
                  <span>Inclua a primeira pessoa autorizada para esta venda.</span>
                </div>
              )}
            </div>
          </section>

          {!selected.eligible ? (
            <section className="notice-panel warning" role="alert">
              <strong>Pedido não elegível para comissionamento</strong>
              <span>{selected.ineligibilityReason ?? "A situação atual do pedido não permite esta operação."}</span>
            </section>
          ) : (
            <section className="panel form-panel">
              <div className="panel-header">
                <div>
                  <h2>Incluir participante</h2>
                  <p>A inclusão pode ocorrer antes ou depois de recebimentos. A gravação final exige revisão e segunda confirmação.</p>
                </div>
                <span className="pill">dupla confirmação</span>
              </div>
              <CommissionAssignmentForm order={selected} requestKey={randomUUID()} />
            </section>
          )}
        </>
      ) : (
        <>
          <SearchToolbar className="panel">
            <EntityLookup
              entity="pedidos-comissionamento"
              name="pedido"
              labelName="q"
              label="Venda ou cliente"
              placeholder="Abra a lista ou pesquise a venda"
              defaultValue={selectedId}
              defaultLabel={query}
            />
            <FilterActions clearHref="/pedidos/financeiro/comissionamento" submitLabel="Localizar" />
          </SearchToolbar>

          <section className="panel">
            <div className="panel-header">
              <div>
                <h2>Vendas elegíveis</h2>
                <p>Pedidos de venda liberados, com ou sem recebimentos financeiros.</p>
              </div>
              <span className="pill">{orders[0]?.totalCount ?? 0}</span>
            </div>
            <div className="finance-result-list">
              {orders.length ? orders.map((order) => (
                <Link key={order.id} href={`/pedidos/financeiro/comissionamento?q=${encodeURIComponent(query)}&pagina=${page}&pedido=${order.id}`}>
                  <span><strong>{order.code}</strong><small>{order.clientName}</small></span>
                  <span><small>{orderStatusLabel(order.status)}</small><strong>{money(order.total)}</strong></span>
                </Link>
              )) : ordersResult.error ? null : (
                <div className="empty-state">
                  <strong>Nenhuma venda elegível</strong>
                  <span>Revise a busca ou confirme se o pedido já foi liberado.</span>
                </div>
              )}
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

function assignmentOriginLabel(value: string) {
  const labels: Record<string, string> = {
    legado: "Regra anterior",
    automatica_politica: "Automática",
    estrutura_comercial: "Estrutura comercial",
    manual_adicional: "Inclusão manual",
    revisao_estrutural: "Revisão estrutural",
  };
  return labels[value] ?? value;
}

function single(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function positive(value?: string) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}
