import Link from "next/link";

import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { QualityOpSearch } from "@/app/producao/qualidade/quality-op-search";
import { getPcpQualityQueue } from "@/lib/pcp";
import { productionStatusLabel } from "@/lib/production-labels";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionQualityPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const query = singleProductionParam(params.q) ?? "";
  const view = singleProductionParam(params.visao) === "historico" ? "history" : "queue";
  const status = singleProductionParam(params.status) ?? "";
  const page = Math.max(1, Number(singleProductionParam(params.pagina) ?? "1") || 1);
  const queue = await getPcpQualityQueue({ query, view, status, page });
  const pageCount = Math.max(1, Math.ceil(queue.total / queue.pageSize));

  return (
    <ProductionShell
      active="qualidade"
      title="Controle de Qualidade"
      description="Consulte a fila de OPs e abra somente a ordem que será analisada ou finalizada."
      source={queue.source}
      error={queue.error}
      actions={<Link className="secondary-button" href="/producao/ordens">Ordens de Produção</Link>}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      <nav className="segmented-tabs" aria-label="Visões do Controle de Qualidade">
        <Link className={view === "queue" ? "active" : ""} href="/producao/qualidade">Fila operacional</Link>
        <Link className={view === "history" ? "active" : ""} href="/producao/qualidade?visao=historico">Histórico</Link>
      </nav>

      <section className="panel lookup-surface" aria-labelledby="quality-list-title">
        <div className="panel-header">
          <div>
            <h2 id="quality-list-title">{view === "history" ? "OPs finalizadas" : "OPs aguardando CQ"}</h2>
            <span>{queue.total} resultado(s)</span>
          </div>
        </div>
        <form className="filter-bar" method="get">
          {view === "history" ? <input type="hidden" name="visao" value="historico" /> : null}
          <QualityOpSearch defaultValue={query} view={view} />
          {view === "history" ? (
            <label>
              Resultado do CQ
              <select name="status" defaultValue={status}>
                <option value="">Todos</option>
                <option value="aprovado">Aprovado</option>
                <option value="bloqueado">Bloqueado</option>
                <option value="reprovado">Reprovado</option>
              </select>
            </label>
          ) : null}
          <button className="secondary-button" type="submit">Pesquisar</button>
          {(query || status) ? <Link className="text-link" href={view === "history" ? "/producao/qualidade?visao=historico" : "/producao/qualidade"}>Limpar</Link> : null}
        </form>

        {queue.items.length > 0 ? (
          <div className="record-table-wrap">
            <table className="record-table">
              <thead><tr><th>OP</th><th>Produto</th><th>Planejado</th><th>Situação</th><th>Data</th><th><span className="sr-only">Ação</span></th></tr></thead>
              <tbody>
                {queue.items.map((op) => (
                  <tr key={op.id}>
                    <td><strong>{op.codigoOp}</strong><small>{opTypeLabel(op.tipoOp)}</small></td>
                    <td>{op.produtoLabel}</td>
                    <td>{op.quantidadePlanejada === null ? "Não informado" : formatNumber(op.quantidadePlanejada)}</td>
                    <td><span className={`status-chip ${op.cqStatus ?? op.status}`}>{qualityStatusLabel(op.cqStatus, op.status)}</span></td>
                    <td>{shortDate(view === "history" ? op.completedAt : op.startedAt)}</td>
                    <td><Link className="secondary-button compact" href={`/producao/qualidade/${op.id}`}>{view === "history" ? "Consultar" : "Abrir CQ"}</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty-state"><strong>Nenhuma OP encontrada</strong><span>Ajuste os filtros ou consulte a outra visão.</span></div>
        )}

        <nav className="pagination" aria-label="Paginação">
          <PageLink disabled={page <= 1} page={page - 1} query={query} status={status} view={view}>Anterior</PageLink>
          <span>Página {Math.min(page, pageCount)} de {pageCount}</span>
          <PageLink disabled={page >= pageCount} page={page + 1} query={query} status={status} view={view}>Próxima</PageLink>
        </nav>
      </section>
    </ProductionShell>
  );
}

function PageLink({ disabled, page, query, status, view, children }: { disabled: boolean; page: number; query: string; status: string; view: "queue" | "history"; children: string }) {
  if (disabled) return <span className="secondary-button compact disabled" aria-disabled="true">{children}</span>;
  const params = new URLSearchParams();
  if (view === "history") params.set("visao", "historico");
  if (query) params.set("q", query);
  if (status) params.set("status", status);
  params.set("pagina", String(page));
  return <Link className="secondary-button compact" href={`/producao/qualidade?${params.toString()}`}>{children}</Link>;
}

function qualityStatusLabel(cqStatus: string | null, status: string): string {
  if (cqStatus) return productionStatusLabel(cqStatus);
  return status === "in_process" ? "Aguardando CQ" : productionStatusLabel(status);
}

function opTypeLabel(value: string): string {
  return ({ estoque: "Produção para estoque", experimental: "Experimental", desenvolvimento: "Desenvolvimento", reprocessamento: "Reprocessamento", mapa_documental: "MAPA documental" } as Record<string, string>)[value] ?? "Tipo não reconhecido";
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function shortDate(value: string | null): string {
  return value ? new Intl.DateTimeFormat("pt-BR").format(new Date(value)) : "Não informado";
}
