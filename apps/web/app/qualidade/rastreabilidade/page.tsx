import Link from "next/link";

import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { ActiveFilterChips, FilterActions, SearchField, SearchToolbar } from "@/app/corporate-search/search-controls";
import { getRecall, getTraceability, hasTraceFilter, type TraceFilters } from "@/lib/traceability";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function TraceabilityPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const filters = parseFilters(params);
  const trace = await getTraceability(filters);
  const recallType = value(params.recall_tipo).toUpperCase();
  const recallLotCode = value(params.recall_lote);
  const recall = await getRecall(recallType, recallLotCode);
  const exportQuery = new URLSearchParams({
    tipo: filters.type, codigo: filters.code, direcao: filters.direction,
    cliente: filters.customerId ? String(filters.customerId) : "", pedido: filters.orderId ? String(filters.orderId) : "",
    romaneio: filters.shipmentId ? String(filters.shipmentId) : "", referencia: filters.fiscalReference
  });

  return <main className="app-shell">
    <section className="workspace technical-workspace traceability-workspace">
      <div className="toolbar technical-toolbar">
        <div><span className="eyebrow">Qualidade e autocontrole</span><h1>Rastreabilidade total</h1><p className="muted">Genealogia derivada dos consumos, produções, envases e expedições realmente registrados.</p></div>
        <div className="toolbar-actions"><Link className="secondary-button" href="/producao/qualidade">CQ e finalização</Link>{trace.edges.length ? <a className="primary-button" href={`/qualidade/rastreabilidade/export?${exportQuery.toString()}`}>Exportar CSV</a> : null}</div>
      </div>

      <section className="panel form-panel trace-filter-form">
        <div className="panel-header"><div><h2>Localizar cadeia</h2><p className="muted">Use um identificador relacional. Códigos são apenas a forma de pesquisa.</p></div><span className="pill">somente leitura</span></div>
        <SearchToolbar>
          <label>Tipo<select name="tipo" defaultValue={filters.type}><option value="">Qualquer tipo</option><option value="MP">Lote de matéria-prima</option><option value="EMBALAGEM">Lote de embalagem</option><option value="PI">Lote de produto intermediário</option><option value="PA">Lote de produto acabado</option><option value="OP">Ordem de produção</option><option value="ENVASE">Ordem de envase</option><option value="PEDIDO">Pedido</option><option value="ROMANEIO">Romaneio</option></select></label>
          <SearchField name="codigo" label="Código conhecido" defaultValue={filters.code} placeholder="Lote, OP, pedido ou Romaneio" wide />
          <label>Direção<select name="direcao" defaultValue={filters.direction}><option value="ambas">Para frente e para trás</option><option value="frente">Para frente</option><option value="tras">Para trás</option></select></label>
          <details className="corporate-advanced-filters" open={Boolean(filters.customerId || filters.orderId || filters.shipmentId || filters.fiscalReference)}>
            <summary>Seleção assistida</summary>
            <div className="corporate-advanced-filter-grid">
              <EntityLookup entity="clientes" name="cliente_id" labelName="cliente" label="Cliente" placeholder="Abra a lista ou pesquise" defaultValue={filters.customerId} defaultLabel={filters.customerQuery} />
              <EntityLookup entity="pedidos" name="pedido_id" labelName="pedido" label="Pedido" placeholder="Abra a lista ou pesquise" defaultValue={filters.orderId} defaultLabel={filters.orderQuery} />
              <EntityLookup entity="romaneios" name="romaneio_id" labelName="romaneio" label="Romaneio" placeholder="Abra a lista ou pesquise" defaultValue={filters.shipmentId} defaultLabel={filters.shipmentQuery} />
              <label><span>Referência fiscal externa</span><input name="referencia" defaultValue={filters.fiscalReference} placeholder="Número da NF de remessa" /></label>
            </div>
          </details>
          <FilterActions clearHref="/qualidade/rastreabilidade" submitLabel="Consultar cadeia" />
        </SearchToolbar>
        <ActiveFilterChips filters={traceFilterChips(filters)} clearHref="/qualidade/rastreabilidade" />
      </section>

      {trace.error ? <section className="notice-panel warning"><strong>Consulta não concluída</strong><span>{trace.error}</span></section> : null}
      {!hasTraceFilter(filters) ? <section className="empty-state"><strong>Informe o ponto de partida</strong><span>O sistema percorrerá somente os elos relacionados ao filtro informado.</span></section> : null}
      {hasTraceFilter(filters) && !trace.error && !trace.edges.length ? <section className="empty-state"><strong>Nenhum elo encontrado</strong><span>Revise o código ou confirme se o processo operacional já gerou movimentos.</span></section> : null}
      {trace.edges.length ? <section className="panel"><div className="panel-header"><div><h2>Cadeia encontrada</h2><p className="muted">Cada linha indica um fato de origem, destino e quantidade.</p></div><span className="pill">{trace.edges.length} elo(s)</span></div><div className="trace-edge-list">{trace.edges.map((edge, index) => <article className={`trace-edge ${edge.active ? "" : "trace-inactive"}`} key={`${edge.sourceType}-${edge.sourceId}-${edge.targetType}-${edge.targetId}-${index}`}><span className="trace-depth">Etapa {edge.depth}</span><div><small>{nodeTypeLabel(edge.sourceType)}</small><strong>{edge.sourceCode}</strong></div><span className="trace-arrow" aria-hidden="true">→</span><div><small>{nodeTypeLabel(edge.targetType)}</small><strong>{edge.targetCode}</strong></div><div className="trace-quantity"><strong>{formatQuantity(edge.quantity, edge.unit)}</strong><small>{eventLabel(edge.event)} · {formatDate(edge.occurredAt)}</small></div></article>)}</div></section> : null}

      <details className="panel form-panel" open={Boolean(recallLotCode)}><summary><strong>Simular recolhimento</strong><span>não bloqueia nem movimenta lotes</span></summary><form className="form-grid" method="get"><input type="hidden" name="simular" value="1" /><label>Tipo do lote<select name="recall_tipo" defaultValue={recallType}><option value="MP">Matéria-prima</option><option value="EMBALAGEM">Embalagem</option><option value="PI">Produto intermediário</option><option value="PA">Produto acabado</option></select></label><label>Código do lote<input name="recall_lote" defaultValue={recallLotCode} placeholder="Código apresentado do lote" required /></label><div className="form-footer wide-field"><span>A simulação mostra somente destinos com expedição líquida ativa.</span><button className="secondary-button" type="submit">Simular impacto</button></div></form></details>
      {recall.error ? <section className="notice-panel warning"><strong>Simulação não concluída</strong><span>{recall.error}</span></section> : null}
      {recallLotCode && !recall.error ? <section className="panel"><div className="panel-header"><h2>Clientes e cargas impactados</h2><span className="pill">{recall.destinations.length} destino(s)</span></div>{recall.destinations.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Lote PA / produto</th><th>Estoque atual</th><th>Romaneio</th><th>Pedido</th><th>Cliente / propriedade</th><th>Contato</th><th>Quantidade expedida</th><th>Referência fiscal</th></tr></thead><tbody>{recall.destinations.map((item) => <tr key={`${item.finishedLotId}-${item.shipmentId}`}><td><strong>{item.finishedLotCode}</strong><span className="table-subtext">{item.product}</span></td><td>{formatQuantity(item.currentBalance, "UN")}<span className="table-subtext">{lotStatusLabel(item.lotStatus)}</span></td><td>{item.shipmentCode}</td><td>{item.orderCode}</td><td><strong>{item.customerName}</strong><span className="table-subtext">{item.propertyName ?? "Sem propriedade vinculada"}</span></td><td>{item.contacts.length ? item.contacts.map((contact) => <span className="table-subtext" key={`${contact.name}-${contact.email ?? contact.phone ?? contact.role}`}>{contact.name} · {contact.phone ?? contact.email ?? contact.role}</span>) : "Não informado"}</td><td>{formatQuantity(item.quantity, "UN")}</td><td>{item.fiscalReference ?? "Não informada"}</td></tr>)}</tbody></table></div> : <div className="empty-state"><strong>Nenhum destino ativo</strong><span>O lote não alcançou cliente em expedição ativa.</span></div>}</section> : null}
    </section>
  </main>;
}

function parseFilters(params: SearchParams): TraceFilters {
  return { type: value(params.tipo).toUpperCase(), code: value(params.codigo), customerId: positive(params.cliente_id), customerQuery: value(params.cliente), orderId: positive(params.pedido_id), orderQuery: value(params.pedido), shipmentId: positive(params.romaneio_id), shipmentQuery: value(params.romaneio), fiscalReference: value(params.referencia), direction: value(params.direcao) || "ambas" };
}
function value(raw: string | string[] | undefined) { return (Array.isArray(raw) ? raw[0] : raw ?? "").trim(); }
function positive(raw: string | string[] | undefined) { const parsed = Number(value(raw)); return Number.isInteger(parsed) && parsed > 0 ? parsed : null; }
function formatQuantity(quantity: number | null, unit: string | null) { return quantity == null ? "Não informado" : `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(quantity)}${unit ? ` ${unit}` : ""}`; }
function formatDate(raw: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(raw)); }
function nodeTypeLabel(type: string) { return ({ MP: "Matéria-prima", EMBALAGEM: "Embalagem", PI: "Produto intermediário", PA: "Produto acabado", OP: "Ordem de produção", ENVASE: "Ordem de envase", ROMANEIO: "Romaneio", PEDIDO: "Pedido", CLIENTE: "Cliente", PROPRIEDADE: "Propriedade", REFERENCIA_FISCAL: "Referência fiscal" } as Record<string, string>)[type] ?? "Registro operacional"; }
function eventLabel(event: string) { return ({ consumo_real: "Consumo real", producao_lote: "Lote produzido", consumo_envase: "Consumo no envase", producao_envase: "Lote envasado", expedicao_confirmada: "Expedição confirmada", expedicao_estornada: "Expedição estornada", romaneio_do_pedido: "Atendimento do pedido", pedido_do_cliente: "Cliente do pedido", pedido_da_propriedade: "Propriedade do pedido", referencia_fiscal_externa: "Referência fiscal externa" } as Record<string, string>)[event] ?? "Evento operacional"; }
function lotStatusLabel(status: string) { return ({ disponivel: "Disponível", bloqueado: "Bloqueado", esgotado: "Esgotado", vencido: "Vencido" } as Record<string, string>)[status] ?? "Situação não reconhecida"; }

function traceFilterChips(filters: TraceFilters) {
  const reset = (key: keyof TraceFilters) => {
    const values = new URLSearchParams({ tipo: filters.type, codigo: filters.code, direcao: filters.direction, cliente_id: filters.customerId ? String(filters.customerId) : "", cliente: filters.customerQuery, pedido_id: filters.orderId ? String(filters.orderId) : "", pedido: filters.orderQuery, romaneio_id: filters.shipmentId ? String(filters.shipmentId) : "", romaneio: filters.shipmentQuery, referencia: filters.fiscalReference });
    const paired = ({ customerId: ["cliente_id", "cliente"], orderId: ["pedido_id", "pedido"], shipmentId: ["romaneio_id", "romaneio"] } as Partial<Record<keyof TraceFilters, string[]>>)[key];
    if (paired) paired.forEach((name) => values.delete(name));
    else values.delete(({ type: "tipo", code: "codigo", fiscalReference: "referencia", direction: "direcao" } as Partial<Record<keyof TraceFilters, string>>)[key] ?? String(key));
    for (const [name, current] of [...values.entries()]) if (!current) values.delete(name);
    return `/qualidade/rastreabilidade?${values.toString()}`;
  };
  return [
    filters.type ? { label: "Tipo", value: nodeTypeLabel(filters.type), href: reset("type") } : null,
    filters.code ? { label: "Código", value: filters.code, href: reset("code") } : null,
    filters.customerId ? { label: "Cliente", value: filters.customerQuery, href: reset("customerId") } : null,
    filters.orderId ? { label: "Pedido", value: filters.orderQuery, href: reset("orderId") } : null,
    filters.shipmentId ? { label: "Romaneio", value: filters.shipmentQuery, href: reset("shipmentId") } : null,
    filters.fiscalReference ? { label: "Referência", value: filters.fiscalReference, href: reset("fiscalReference") } : null,
  ].filter((item): item is { label: string; value: string; href: string } => Boolean(item));
}
