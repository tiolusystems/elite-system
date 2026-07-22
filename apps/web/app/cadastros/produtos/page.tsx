import Link from "next/link";

import { createProdutoBaseAction, createProdutoEmbalagemAction } from "@/app/cadastros/actions";
import { ProductMaintenancePanel } from "@/app/cadastros/produtos/product-maintenance-panel";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const query = (singleParam(params.q) ?? "").trim().toLocaleLowerCase("pt-BR");
  const selectedId = Number(singleParam(params.selected) ?? "");
  const filteredProducts = catalog.products.filter((item) =>
    !query || `${item.code} ${item.name} ${item.group ?? ""}`.toLocaleLowerCase("pt-BR").includes(query)
  );
  const variantsByProduct = new Map<number, typeof catalog.saleItems>();
  for (const item of catalog.saleItems) {
    const current = variantsByProduct.get(item.productId) ?? [];
    current.push(item);
    variantsByProduct.set(item.productId, current);
  }
  const selectedProduct = catalog.products.find((item) => item.id === selectedId) ?? null;

  return (
    <CatalogShell
      active="products"
      title="Produtos PA/PI"
      description="Produto-base, prazo de validade, registro tecnico e apresentacoes comerciais por embalagem."
      source={catalog.source}
      error={catalog.error}
      actions={
        <>
          <a className="secondary-button" href="#novo-item-vendavel">Nova apresentacao</a>
          <a className="primary-button" href="#novo-produto">Novo produto</a>
        </>
      }
    >
      <CatalogFeedback result={singleParam(params.result)} />

      <form className="catalog-filter single-search" method="get" aria-label="Filtro de produtos">
        <label>Buscar<input name="q" defaultValue={singleParam(params.q) ?? ""} placeholder="Codigo, nome ou grupo" /></label>
        <button className="secondary-button" type="submit">Filtrar</button>
      </form>

      <section className="panel" aria-labelledby="products-title">
        <div className="panel-header">
          <h2 id="products-title">Catalogo de produtos</h2>
          <span className="pill">{filteredProducts.length}</span>
        </div>
        <div className="responsive-record-grid product-grid">
          {filteredProducts.map((product) => {
            const variants = variantsByProduct.get(product.id) ?? [];
            return (
              <article key={product.id} className={selectedProduct?.id === product.id ? "selected-record" : undefined}>
                <div><span><small>{product.code}</small><strong>{product.name}</strong></span><StatusChip value={product.status} /></div>
                <dl>
                  <div><dt>Grupo</dt><dd>{product.group ?? "-"}</dd></div>
                  <div><dt>Validade</dt><dd>{product.shelfLifeMonths ? `${product.shelfLifeMonths} meses` : "Nao definida"}</dd></div>
                  <div><dt>Registro MAPA</dt><dd>{product.mapaRegistration ?? "-"}</dd></div>
                  <div><dt>Apresentacoes</dt><dd>{variants.length}</dd></div>
                </dl>
                <div className="variant-list">
                  {variants.map((variant) => (
                    <span key={variant.id}><strong>{variant.code}</strong>{variant.packageLabel}</span>
                  ))}
                  {variants.length === 0 ? <span className="pending-variant">Sem item vendavel</span> : null}
                </div>
                <Link className="record-open-link" href={`/cadastros/produtos?selected=${product.id}#editar-produto`}>Abrir produto</Link>
              </article>
            );
          })}
          {filteredProducts.length === 0 ? <p className="empty-state">Nenhum produto encontrado.</p> : null}
        </div>
      </section>

      <ProductMaintenancePanel
        product={selectedProduct}
        groups={catalog.productGroups}
        variants={selectedProduct ? variantsByProduct.get(selectedProduct.id) ?? [] : []}
      />

      <section className="two-column catalog-form-columns">
        <article className="panel form-panel" id="novo-produto">
          <div className="panel-header"><div><span className="eyebrow">Produto-base</span><h2>Novo produto</h2></div></div>
          <form action={createProdutoBaseAction}>
            <input type="hidden" name="return_to" value="/cadastros/produtos" />
            <div className="form-grid single-field-grid">
              <label>Codigo<input name="codigo_produto" placeholder="0001" inputMode="numeric" required /></label>
              <label>Nome<input name="nome" required /></label>
              <label>
                Grupo
                <select name="grupo_id" defaultValue="">
                  <option value="">Sem grupo</option>
                  {catalog.productGroups.filter((item) => item.status === "active").map((item) => (
                    <option key={item.id} value={item.id}>{item.code} · {item.name}</option>
                  ))}
                </select>
                <Link className="field-help-link" href="/cadastros/grupos-produto">Gerenciar grupos</Link>
              </label>
              <label>Validade em meses<input name="prazo_validade_meses" inputMode="numeric" /></label>
              <label>Densidade kg/L<input name="densidade_kg_l" inputMode="decimal" /></label>
              <label>Registro MAPA<input name="reg_mapa" /></label>
              <label>NCM<input name="ncm" inputMode="numeric" /></label>
              <label>IBAMA<input name="ibama" /></label>
              <label>ADS<input name="ads" /></label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">Ativo</option>
                  <option value="pending_review">Em revisao</option>
                  <option value="inactive">Inativo</option>
                </select>
              </label>
            </div>
            <div className="form-footer"><span>Codigo de 0001 a 9999.</span><button className="primary-button" type="submit">Salvar produto</button></div>
          </form>
        </article>

        <article className="panel form-panel" id="novo-item-vendavel">
          <div className="panel-header"><div><span className="eyebrow">Produto + embalagem</span><h2>Nova apresentacao</h2></div></div>
          <form action={createProdutoEmbalagemAction}>
            <input type="hidden" name="return_to" value="/cadastros/produtos" />
            <div className="form-grid single-field-grid">
              <label>
                Produto
                <select name="produto_id" defaultValue="" required>
                  <option value="" disabled>Selecione</option>
                  {catalog.products.filter((item) => item.status === "active").map((item) => (
                    <option key={item.id} value={item.id}>{item.code} · {item.name}</option>
                  ))}
                </select>
              </label>
              <label>
                Embalagem
                <select name="embalagem_id" defaultValue="" required>
                  <option value="" disabled>Selecione</option>
                  {catalog.packages.filter((item) => item.status === "active").map((item) => (
                    <option key={item.id} value={item.id}>{item.description}</option>
                  ))}
                </select>
              </label>
              <label>Codigo do item<input name="codigo_item" placeholder="0001-20L" required /></label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">Ativo</option>
                  <option value="pending_review">Em revisao</option>
                  <option value="inactive">Inativo</option>
                </select>
              </label>
            </div>
            <div className="form-footer"><span>Este codigo sera usado em pedido e estoque PA.</span><button className="primary-button" type="submit">Salvar apresentacao</button></div>
          </form>
        </article>
      </section>

      <section className="panel production-next-band">
        <div><span className="eyebrow">Proxima dependencia</span><h2>Formula, garantias e producao</h2><p>Produtos ativos podem receber receitas de producao e MAPA, gerar OP e originar lotes PA ou PI.</p></div>
        <div className="toolbar-actions"><Link className="secondary-button" href="/producao/garantias">Garantias</Link><Link className="primary-button" href="/producao/formulas">Abrir formulas</Link></div>
      </section>
    </CatalogShell>
  );
}
