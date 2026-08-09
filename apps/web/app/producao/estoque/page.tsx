import { randomUUID } from "node:crypto";
import Link from "next/link";

import { SmartSearchField } from "@/app/corporate-search/smart-lookup";
import { registerValuedMpEntryAction } from "@/app/producao/estoque/actions";
import {
  StockWorkbench,
} from "@/app/producao/estoque/stock-workbench";
import { ProductionFeedback, ProductionShell, singleProductionParam } from "@/app/producao/production-shell";
import { getStockPresentations, getStockProducts, getTargetStockLots } from "@/lib/stock";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductionStockPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const query = singleProductionParam(params.q)?.trim() ?? "";
  const family = singleProductionParam(params.familia) ?? "all";
  const page = Math.max(1, Number(singleProductionParam(params.pagina) ?? 1) || 1);
  const productId = Number(singleProductionParam(params.produto) ?? 0);
  const targetId = Number(singleProductionParam(params.alvo) ?? 0);
  const today = new Date().toISOString().slice(0, 10);
  const products = await getStockProducts(query, family);
  const selectedProduct = products.find((product) => product.id === productId) ?? null;
  const presentations = selectedProduct?.family === "PA" ? await getStockPresentations(productId) : [];
  const effectiveTarget = selectedProduct && selectedProduct.family !== "PA" ? selectedProduct.id : targetId;
  const workspace = selectedProduct && effectiveTarget
    ? await getTargetStockLots(selectedProduct.family, effectiveTarget, page)
    : { lots: [], total: 0, page: 1, pageSize: 24, source: "supabase" as const, error: null };
  const pageCount = Math.max(1, Math.ceil(workspace.total / workspace.pageSize));

  return (
    <ProductionShell
      active="estoque"
      title="Lotes e estoque"
      description="Consulta operacional dos saldos fisico, reservado e disponivel por lote de MP, PA e PI."
      source={workspace.source}
      error={workspace.error}
      actions={(
        <>
          <Link className="secondary-button" href="/producao/ordens">Ordens</Link>
          <Link className="primary-button" href="/producao/transformacoes">Transformacoes</Link>
        </>
      )}
    >
      <ProductionFeedback result={singleProductionParam(params.result)} />

      {selectedProduct?.family === "MP" ? (
        <details className="panel form-panel" id="entrada-mp">
          <summary><strong>Registrar entrada e custo da matéria-prima</strong><span>movimento auditado</span></summary>
          <form action={registerValuedMpEntryAction} className="form-grid inventory-entry-form">
            <input type="hidden" name="idempotency_key" value={randomUUID()} />
            <input type="hidden" name="materia_prima_id" value={selectedProduct.id} />
            <input type="hidden" name="return_query" value={stockReturnQuery(params)} />
            <div className="wide-field field-note"><strong>{selectedProduct.name}</strong><span>{selectedProduct.code}</span></div>
            <label>Lote do fornecedor<input name="codigo_lote_fornecedor" required /></label>
            <label>Quantidade<input name="quantidade" inputMode="decimal" min="0.000001" step="any" required /></label>
            <label>Unidade de origem<input name="unidade_origem" defaultValue="UN_BASE" required /></label>
            <label>Situação de qualidade<select name="status_lote" defaultValue="bloqueado"><option value="bloqueado">Bloqueado até liberação do CQ</option><option value="disponivel">Disponível</option></select></label>
            <label>Fabricação<input name="data_fabricacao" type="date" /></label>
            <label>Validade<input name="data_validade" type="date" /></label>
            <label>Documento de entrada<input name="documento_ref" placeholder="Número do documento externo" required /></label>
            <label>Data do documento<input name="data_documento" type="date" /></label>
            <label>Valor da matéria-prima<input name="valor_materia_prima" inputMode="decimal" min="0" step="0.01" defaultValue="0" required /></label>
            <label>Frete<input name="frete" inputMode="decimal" min="0" step="0.01" defaultValue="0" /></label>
            <label>DIFAL de ICMS<input name="difal_icms" inputMode="decimal" min="0" step="0.01" defaultValue="0" /></label>
            <label>Situação do DIFAL<select name="difal_status" defaultValue="not_applicable"><option value="not_applicable">Não aplicável</option><option value="informed">Informado</option><option value="pending_review">Pendente de revisão</option></select></label>
            <label>UF do emitente<input name="uf_emitente" maxLength={2} placeholder="SP" /></label>
            <label>Outras despesas<input name="outras_despesas" inputMode="decimal" min="0" step="0.01" defaultValue="0" /></label>
            <label className="wide-field">Motivo da pendência do DIFAL<input name="difal_motivo" /></label>
            <label className="wide-field">Observação<input name="observacao" /></label>
            <div className="form-footer wide-field"><span>A gravação cria o lote, a entrada física e a camada de custo na mesma transação.</span><button className="primary-button" type="submit">Registrar entrada</button></div>
          </form>
        </details>
      ) : null}

      <form className="catalog-filter inventory-filter" method="get">
        <SmartSearchField
          name="q"
          label="Produto ou matéria-prima"
          defaultValue={singleProductionParam(params.q) ?? ""}
          placeholder="Nome, SKU ou código do produto"
          source={{ kind: "remote", entity: "estoque-itens" }}
          required
        />
        <label>
          Familia
          <select name="familia" defaultValue={family}>
            <option value="all">MP, PA e PI</option>
            <option value="MP">Materia-prima</option>
            <option value="PA">Produto acabado</option>
            <option value="PI">Produto intermediario</option>
          </select>
        </label>
        <button className="secondary-button" type="submit">Pesquisar</button>
        <Link href="/producao/estoque">Limpar</Link>
      </form>

      {query && !selectedProduct ? <section className="inventory-product-grid" aria-label="Produtos encontrados">
        {products.map((product) => <Link className="inventory-product-card" key={`${product.family}-${product.id}`} href={selectionHref(params, product.id, product.family === "PA" ? 0 : product.id)}>
          <span className="eyebrow">{product.family}</span><strong>{product.name}</strong><small>{product.code}</small>
          <div><span>{product.presentations} apresentacao(oes)</span><span>{product.lots} lote(s) disponivel(is)</span></div>
        </Link>)}
        {!products.length ? <div className="empty-state"><strong>Nenhum produto encontrado</strong><span>Revise o nome, SKU ou codigo informado.</span></div> : null}
      </section> : null}

      {selectedProduct?.family === "PA" && !targetId ? <section className="inventory-product-grid" aria-label="Apresentacoes do produto">
        {presentations.map((item) => <Link className="inventory-product-card" key={item.id} href={selectionHref(params, productId, item.id)}>
          <span className="eyebrow">Apresentacao</span><strong>{item.description}</strong><small>{item.code}</small>
          <div><span>{item.lots} lote(s)</span><span>{new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(item.available)} disponivel</span></div>
        </Link>)}
      </section> : null}

      {selectedProduct && effectiveTarget ? <><div className="section-heading inventory-results-heading">
        <div>
          <span className="eyebrow">Livro de estoque derivado</span>
          <h2>{workspace.total} lote(s) encontrado(s)</h2>
        </div>
        <span className="pill">pagina {workspace.page} de {pageCount}</span>
      </div>
      <StockWorkbench lots={workspace.lots} today={today} />
      {pageCount > 1 ? <nav className="pagination" aria-label="Paginas do estoque">
        {workspace.page > 1 ? <Link className="secondary-button" href={pageHref(params, workspace.page - 1)}>Anterior</Link> : <span />}
        <span>{workspace.page} de {pageCount}</span>
        {workspace.page < pageCount ? <Link className="secondary-button" href={pageHref(params, workspace.page + 1)}>Proxima</Link> : <span />}
      </nav> : null}</> : !query ? <section className="empty-state inventory-query-required">
        <strong>Pesquise primeiro o produto</strong>
        <span>Os lotes serao exibidos somente depois de informar um produto, apresentacao, materia-prima ou SKU.</span>
      </section> : null}
    </ProductionShell>
  );
}

function pageHref(params: SearchParams, page: number) {
  const next = new URLSearchParams();
  for (const [key, raw] of Object.entries(params)) {
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (value && key !== "pagina") next.set(key, value);
  }
  next.set("pagina", String(page));
  return `/producao/estoque?${next.toString()}`;
}

function selectionHref(params: SearchParams, productId: number, targetId: number) {
  const next = new URLSearchParams();
  for (const key of ["q", "familia"]) {
    const raw = params[key];
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (value) next.set(key, value);
  }
  next.set("produto", String(productId));
  if (targetId) next.set("alvo", String(targetId));
  return `/producao/estoque?${next.toString()}`;
}

function stockReturnQuery(params: SearchParams) {
  const next = new URLSearchParams();
  for (const key of ["q", "familia", "produto", "alvo"]) {
    const raw = params[key];
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (value) next.set(key, value);
  }
  return next.toString();
}
