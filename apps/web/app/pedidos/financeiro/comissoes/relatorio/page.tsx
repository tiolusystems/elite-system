import Link from "next/link";
import { redirect } from "next/navigation";

import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { ExportMenu } from "@/app/workspace-components";
import { PrintButton } from "@/app/pedidos/financeiro/comissoes/relatorio/print-button";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { FilterActions, SearchToolbar } from "@/app/corporate-search/search-controls";
import { commissionRoleLabel, financeDateDefaults, money } from "@/app/pedidos/financeiro/presenters";
import { getAuthStatus } from "@/lib/auth";
import { getBuildInfo } from "@/lib/build-info";
import { getCommissionReport, getFinanceAccess } from "@/lib/finance";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function CommissionReportPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getFinanceAccess();
  if (!access.commissionsView) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const defaults = financeDateDefaults();
  const query = single(params.q) ?? "";
  const role = single(params.papel) ?? "";
  const cutoffDate = single(params.corte) ?? defaults.cutoffDate;
  const onlyPositive = single(params.saldo) !== "all";
  const [reportResult, auth] = await Promise.all([
    getCommissionReport(query, role, cutoffDate, onlyPositive),
    getAuthStatus(),
  ]);
  const rows = reportResult.data;
  const totals = rows.reduce(
    (result, row) => ({
      predicted: result.predicted + row.predicted,
      released: result.released + row.released,
      payments: result.payments + row.payments,
      reversals: result.reversals + row.reversals,
      adjustments: result.adjustments + row.adjustments,
      balance: result.balance + row.balance,
    }),
    { predicted: 0, released: 0, payments: 0, reversals: 0, adjustments: 0, balance: 0 }
  );
  const build = getBuildInfo();
  const runtime = getRuntimeStatus();
  const generatedAt = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date());
  const exportQuery = new URLSearchParams({
    q: query,
    papel: role,
    corte: cutoffDate,
    saldo: onlyPositive ? "positive" : "all",
  });

  return (
    <FinanceWorkspace
      access={access}
      current="report"
      eyebrow="Posição financeira"
      title="Relatório de comissões a pagar"
      description="Posição integral por pessoa na data de corte, sem alterar a conta corrente."
      actions={
        <div className="finance-page-actions">
          <Link className="secondary-button" href="/pedidos/financeiro/comissoes">Voltar às comissões</Link>
          {access.commissionsExport ? (
            <ExportMenu
              items={[
                {
                  label: "Excel (.xlsx)",
                  href: `/pedidos/financeiro/comissoes/relatorio/export?${exportQuery.toString()}&formato=xlsx`,
                  description: "Planilha com valores numéricos pronta para análise no Excel.",
                  primary: true,
                },
                {
                  label: "CSV (.csv)",
                  href: `/pedidos/financeiro/comissoes/relatorio/export?${exportQuery.toString()}&formato=csv`,
                  description: "Formato simples para integração e tratamento técnico.",
                },
              ]}
            />
          ) : null}
          <PrintButton />
        </div>
      }
    >
      {reportResult.error ? (
        <section className="notice-panel warning no-print" role="alert">
          <strong>Relatório indisponível</strong>
          <span>{reportResult.error}</span>
        </section>
      ) : null}
      <SearchToolbar className="panel finance-report-filters no-print">
        <EntityLookup entity="pessoas" name="pessoa" labelName="q" label="Pessoa" placeholder="Abra a lista ou pesquise por nome" defaultLabel={query} />
        <label>
          Papel
          <select name="papel" defaultValue={role}>
            <option value="">Todos</option>
            <option value="vendedor">Vendedor</option>
            <option value="agente">Agente</option>
            <option value="gerente">Gerente</option>
            <option value="tecnico_campo">Técnico de campo</option>
            <option value="campanha">Campanha</option>
            <option value="outro">Outro</option>
          </select>
        </label>
        <label>Posição em<input name="corte" type="date" defaultValue={cutoffDate} /></label>
        <label>
          Saldo
          <select name="saldo" defaultValue={onlyPositive ? "positive" : "all"}>
            <option value="positive">Somente a pagar</option>
            <option value="all">Todos</option>
          </select>
        </label>
        <FilterActions clearHref="/pedidos/financeiro/comissoes/relatorio" submitLabel="Aplicar filtros" />
      </SearchToolbar>

      {!reportResult.error ? <section className="panel finance-report-document">
        <header className="finance-report-heading">
          <div><span className="eyebrow">Relatório financeiro</span><h2>Comissões a pagar</h2></div>
          <div><strong>Data de corte</strong><span>{cutoffDate.split("-").reverse().join("/")}</span></div>
        </header>
        <dl className="finance-summary-grid finance-summary-six">
          <div><dt>Previsto</dt><dd>{money(totals.predicted)}</dd></div>
          <div><dt>Liberado</dt><dd>{money(totals.released)}</dd></div>
          <div><dt>Pagamentos</dt><dd>{money(totals.payments)}</dd></div>
          <div><dt>Estornos</dt><dd>{money(totals.reversals)}</dd></div>
          <div><dt>Ajustes</dt><dd>{money(totals.adjustments)}</dd></div>
          <div><dt>Total a pagar</dt><dd>{money(totals.balance)}</dd></div>
        </dl>
        <div className="finance-report-table">
          <table>
            <thead>
              <tr><th>Pessoa</th><th>Papéis</th><th>Previsto</th><th>Liberado</th><th>Pagamentos</th><th>Estornos</th><th>Ajustes</th><th>Saldo</th></tr>
            </thead>
            <tbody>
              {rows.length ? rows.map((row) => (
                <tr key={row.personId}>
                  <td>{row.personName}</td>
                  <td>{row.roles.map(commissionRoleLabel).join(", ") || "Não informado"}</td>
                  <td>{money(row.predicted)}</td>
                  <td>{money(row.released)}</td>
                  <td>{money(row.payments)}</td>
                  <td>{money(row.reversals)}</td>
                  <td>{money(row.adjustments)}</td>
                  <td><strong>{money(row.balance)}</strong></td>
                </tr>
              )) : <tr><td colSpan={8}>Nenhuma comissão encontrada para os filtros informados.</td></tr>}
            </tbody>
          </table>
        </div>
        <footer className="finance-report-footer">
          <span>Ambiente: {runtime.databaseLabel}</span>
          <span>Emitido por: {auth.profile?.displayName || auth.email || "Usuário autenticado"}</span>
          <span>Gerado em: {generatedAt}</span>
          <span>Versão {build.version} · {build.release}</span>
        </footer>
      </section> : null}
    </FinanceWorkspace>
  );
}

function single(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}
