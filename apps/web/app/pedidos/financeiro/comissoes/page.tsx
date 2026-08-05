import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { CommissionAdjustmentForm, CommissionPaymentForm } from "@/app/pedidos/financeiro/finance-forms";
import { FinancePermissionState, FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { ActiveFilterChips, FilterActions, SearchToolbar } from "@/app/corporate-search/search-controls";
import { commissionMovementLabel, commissionRoleLabel, dateTime, financeDateDefaults, money, personStatusLabel } from "@/app/pedidos/financeiro/presenters";
import { getCommissionMovements, getFinanceAccess, searchCommissionAccounts } from "@/lib/finance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CommissionsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!(access.commissionsView || access.commissionsPay || access.commissionsAdjust)) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const defaults = financeDateDefaults();
  const query = single(params.q) ?? "";
  const role = single(params.papel) ?? "";
  const status = single(params.saldo) ?? "positive";
  const cutoffDate = single(params.corte) ?? defaults.cutoffDate;
  const startDate = single(params.inicio) ?? defaults.startDate;
  const endDate = single(params.fim) ?? defaults.endDate;
  const page = positive(single(params.pagina)) || 1;
  const personId = positive(single(params.pessoa));
  const accountsResult = await searchCommissionAccounts(query, status, cutoffDate, page, role);
  const accounts = accountsResult.data;
  const selected = personId ? accounts.find((account) => account.personId === personId) ?? null : null;
  const movementsResult = selected
    ? await getCommissionMovements(selected.personId, startDate, endDate)
    : { data: [], error: null };
  const movements = movementsResult.data;

  return (
    <FinanceWorkspace
      access={access}
      current="commissions"
      eyebrow="Conta corrente"
      title="Comissões"
      description="Consulte créditos liberados, pagamentos, estornos e ajustes sem alterar movimentos anteriores."
      actions={access.commissionsView ? <Link className="secondary-button" href="/pedidos/financeiro/comissoes/relatorio">Relatório a pagar</Link> : null}
    >
      {accountsResult.error || movementsResult.error ? (
        <section className="notice-panel warning" role="alert">
          <strong>Consulta indisponível</strong>
          <span>{accountsResult.error || movementsResult.error}</span>
        </section>
      ) : null}
      {selected ? (
        <>
          <Link className="secondary-button finance-back-link" href={listHref(query, role, status, cutoffDate, page)}>Voltar às contas correntes</Link>
          <section className="panel finance-record-summary">
            <div className="panel-header">
              <div><span className="eyebrow">{personStatusLabel(selected.status)}</span><h2>{selected.personName}</h2><p>{selected.roles.map(commissionRoleLabel).join(" · ") || "Papel não informado"}</p></div>
              <strong>{money(selected.balance)} a pagar</strong>
            </div>
            <dl className="finance-summary-grid finance-summary-six">
              <div><dt>Previsto</dt><dd>{money(selected.predicted)}</dd></div>
              <div><dt>Liberado</dt><dd>{money(selected.released)}</dd></div>
              <div><dt>Pagamentos</dt><dd>{money(selected.payments)}</dd></div>
              <div><dt>Estornos</dt><dd>{money(selected.reversals)}</dd></div>
              <div><dt>Ajustes</dt><dd>{money(selected.adjustments)}</dd></div>
              <div><dt>Saldo</dt><dd>{money(selected.balance)}</dd></div>
            </dl>
          </section>

          <section className="panel">
            <div className="panel-header"><div><h2>Histórico cronológico</h2><p>Movimentos append-only vinculados a pedidos e referências disponíveis.</p></div><span className="pill">{movements.length}</span></div>
            <form className="finance-filter-bar finance-ledger-filters" method="get">
              <input type="hidden" name="q" value={query} />
              <input type="hidden" name="papel" value={role} />
              <input type="hidden" name="saldo" value={status} />
              <input type="hidden" name="corte" value={cutoffDate} />
              <input type="hidden" name="pagina" value={page} />
              <input type="hidden" name="pessoa" value={selected.personId} />
              <label>Data inicial<input name="inicio" type="date" defaultValue={startDate} /></label>
              <label>Data final<input name="fim" type="date" defaultValue={endDate} /></label>
              <button className="secondary-button">Aplicar período</button>
            </form>
            <div className="finance-ledger-list">
              {movements.length ? movements.map((movement) => (
                <article key={movement.id}>
                  <span><strong>{commissionMovementLabel(movement.type)}</strong><small>{dateTime(movement.createdAt)} · {movement.orderCode ? `Pedido ${movement.orderCode}` : "Sem pedido associado"}</small><small>{movement.reference || movement.reason || "Sem referência complementar"}</small><small>{movement.createdBy ? `Registrado por ${movement.createdBy}` : "Responsável não identificado no registro original"}</small></span>
                  <strong className={movement.value < 0 ? "finance-debit" : "finance-credit"}>{money(movement.value)}</strong>
                </article>
              )) : <div className="empty-state compact-empty"><strong>Nenhum movimento</strong><span>A conta ainda não possui eventos no período consultado.</span></div>}
            </div>
          </section>

          {access.commissionsPay && !movementsResult.error ? (
            <section className="panel form-panel">
              <div className="panel-header"><div><h2>Registrar pagamento</h2><p>O pagamento reduz o saldo por um novo movimento auditado.</p></div><span className="pill">operação normal</span></div>
              <CommissionPaymentForm account={selected} requestKey={randomUUID()} />
            </section>
          ) : <FinancePermissionState detail="Você pode consultar a conta corrente, mas não possui alçada para registrar pagamentos." />}

          {access.commissionsAdjust && !movementsResult.error ? (
            <details className="panel finance-exception-panel">
              <summary><span><strong>Ajuste manual excepcional</strong><small>Abra somente quando existir correção formalmente justificada.</small></span></summary>
              <CommissionAdjustmentForm account={selected} requestKey={randomUUID()} />
            </details>
          ) : null}
        </>
      ) : (
        <>
          <SearchToolbar className="panel finance-commission-filters">
            <EntityLookup entity="pessoas" name="pessoa" labelName="q" label="Pessoa" placeholder="Abra a lista ou pesquise por nome" defaultValue={personId} defaultLabel={query} />
            <label>Papel<select name="papel" defaultValue={role}><option value="">Todos</option><option value="vendedor">Vendedor</option><option value="agente">Agente</option><option value="gerente">Gerente</option><option value="tecnico_campo">Técnico de campo</option><option value="campanha">Campanha</option><option value="outro">Outro</option></select></label>
            <label>Saldo<select name="saldo" defaultValue={status}><option value="positive">Somente positivo</option><option value="all">Todos</option><option value="zero">Zerado</option><option value="negative">Negativo</option></select></label>
            <label>Posição em<input name="corte" type="date" defaultValue={cutoffDate} /></label>
            <FilterActions clearHref="/pedidos/financeiro/comissoes" submitLabel="Aplicar filtros" />
          </SearchToolbar>
          <ActiveFilterChips filters={commissionFilters(query, role, status, cutoffDate, defaults.cutoffDate)} clearHref="/pedidos/financeiro/comissoes" />
          <section className="panel">
            <div className="panel-header"><div><h2>Contas correntes</h2><p>Selecione uma pessoa para consultar o histórico e as operações autorizadas.</p></div><span className="pill">{accounts[0]?.totalCount ?? 0}</span></div>
            <div className="finance-result-list">
              {accounts.length ? accounts.map((account) => (
                <Link key={account.personId} href={`${listHref(query, role, status, cutoffDate, page)}&pessoa=${account.personId}`}>
                  <span><strong>{account.personName}</strong><small>{account.roles.map(commissionRoleLabel).join(" · ") || "Papel não informado"}</small></span>
                  <span><small>Saldo em {cutoffDate.split("-").reverse().join("/")}</small><strong className={account.balance < 0 ? "finance-debit" : ""}>{money(account.balance)}</strong></span>
                </Link>
              )) : accountsResult.error ? null : <div className="empty-state"><strong>Nenhuma conta encontrada</strong><span>Revise a busca ou altere o filtro de saldo.</span></div>}
            </div>
          </section>
          <Pagination current={page} total={accounts[0]?.totalCount ?? 0} query={query} role={role} status={status} cutoff={cutoffDate} />
        </>
      )}
    </FinanceWorkspace>
  );
}

function Pagination({ current, total, query, role, status, cutoff }: { current: number; total: number; query: string; role: string; status: string; cutoff: string }) {
  const pages = Math.max(Math.ceil(total / 30), 1);
  if (pages <= 1) return null;
  return <nav className="pagination" aria-label="Paginação"><span>{current > 1 ? <Link className="secondary-button" href={listHref(query, role, status, cutoff, current - 1)}>Anterior</Link> : null}</span><span>Página {current} de {pages}</span><span>{current < pages ? <Link className="secondary-button" href={listHref(query, role, status, cutoff, current + 1)}>Próxima</Link> : null}</span></nav>;
}

function listHref(query: string, role: string, status: string, cutoff: string, page: number) { return `/pedidos/financeiro/comissoes?q=${encodeURIComponent(query)}&papel=${encodeURIComponent(role)}&saldo=${encodeURIComponent(status)}&corte=${cutoff}&pagina=${page}`; }
function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function positive(value?: string) { const parsed = Number(value); return Number.isInteger(parsed) && parsed > 0 ? parsed : null; }

function commissionFilters(query: string, role: string, status: string, cutoff: string, defaultCutoff: string) {
  const base = { q: query, papel: role, saldo: status, corte: cutoff };
  const href = (changes: Partial<typeof base>) => listHref(changes.q ?? base.q, changes.papel ?? base.papel, changes.saldo ?? base.saldo, changes.corte ?? base.corte, 1);
  return [
    query ? { label: "Pessoa", value: query, href: href({ q: "" }) } : null,
    role ? { label: "Papel", value: commissionRoleLabel(role), href: href({ papel: "" }) } : null,
    status !== "positive" ? { label: "Saldo", value: status === "all" ? "Todos" : status === "zero" ? "Zerado" : "Negativo", href: href({ saldo: "positive" }) } : null,
    cutoff !== defaultCutoff ? { label: "Posição", value: cutoff.split("-").reverse().join("/"), href: href({ corte: defaultCutoff }) } : null,
  ].filter((item): item is { label: string; value: string; href: string } => Boolean(item));
}
