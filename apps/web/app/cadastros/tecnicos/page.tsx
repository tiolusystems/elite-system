import Link from "next/link";

import { CatalogShell, StatusChip } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

export default async function TechnicalCatalogOverviewPage() {
  const catalog = await getTechnicalCatalog();
  const pendingMaterials = catalog.materials.filter((item) => item.status === "pending_review").length;
  const stockPackages = catalog.packages.filter((item) => item.controlsStock).length;
  const productsWithoutVariants = catalog.products.filter(
    (product) => !catalog.saleItems.some((item) => item.productId === product.id)
  ).length;

  return (
    <CatalogShell
      active="overview"
      title="Base tecnica da operacao"
      description="Cadastros que alimentam formulas, estoque, ordens de producao, pedidos e rastreabilidade."
      source={catalog.source}
      error={catalog.error}
      actions={<Link className="primary-button" href="/cadastros/materias-primas#nova-mp">Nova materia-prima</Link>}
    >
      <section className="technical-kpis" aria-label="Resumo dos catalogos tecnicos">
        <article>
          <span>Unidades canonicas</span>
          <strong>{catalog.units.length}</strong>
          <small>{catalog.conversions.length} conversoes de MP</small>
        </article>
        <article>
          <span>Materias-primas</span>
          <strong>{catalog.materials.length}</strong>
          <small>{pendingMaterials} em revisao</small>
        </article>
        <article>
          <span>Embalagens</span>
          <strong>{catalog.packages.length}</strong>
          <small>{stockPackages} controladas em estoque</small>
        </article>
        <article>
          <span>Produtos PA/PI</span>
          <strong>{catalog.products.length}</strong>
          <small>{productsWithoutVariants} sem item vendavel</small>
        </article>
      </section>

      <section className="panel technical-sequence" aria-labelledby="technical-sequence-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Sequencia operacional</span>
            <h2 id="technical-sequence-title">Da unidade aprovada ao lote produzido</h2>
          </div>
          <StatusChip value={catalog.source === "supabase" ? "active" : "pending_review"} />
        </div>
        <div className="technical-flow-grid">
          <Link href="/cadastros/unidades">
            <span>01</span>
            <strong>Unidades e conversoes</strong>
            <small>Base de medida para XML, estoque e formula.</small>
          </Link>
          <Link href="/cadastros/materias-primas">
            <span>02</span>
            <strong>Materias-primas</strong>
            <small>SKU, unidade, densidade, estoque e regulatorio.</small>
          </Link>
          <Link href="/cadastros/embalagens">
            <span>03</span>
            <strong>Embalagens</strong>
            <small>Volume e vinculo opcional ao estoque de insumos.</small>
          </Link>
          <Link href="/cadastros/produtos">
            <span>04</span>
            <strong>Produtos PA/PI</strong>
            <small>Produto-base, validade e variantes vendaveis.</small>
          </Link>
          <Link href="/cadastros/grupos-produto">
            <span>05</span>
            <strong>Grupos de produto</strong>
            <small>Familias relacionais para produtos e relatorios.</small>
          </Link>
          <Link href="/producao/formulas">
            <span>06</span>
            <strong>Formulas e garantias</strong>
            <small>Versoes de producao, MAPA e composicao tecnica.</small>
          </Link>
          <Link href="/producao#ops">
            <span>07</span>
            <strong>OP, CQ e lotes</strong>
            <small>Reserva, consumo, producao, bloqueio e liberacao.</small>
          </Link>
        </div>
      </section>

      <section className="two-column technical-lists">
        <article className="panel">
          <div className="panel-header">
            <h2>Pendencias tecnicas</h2>
            <Link href="/cadastros/materias-primas?status=pending_review">Abrir fila</Link>
          </div>
          <div className="compact-list">
            {pendingMaterials === 0 && productsWithoutVariants === 0 ? (
              <p className="empty-state">Nenhuma pendencia estrutural identificada.</p>
            ) : (
              <>
                {pendingMaterials > 0 ? <p><strong>{pendingMaterials}</strong> materias-primas aguardam revisao.</p> : null}
                {productsWithoutVariants > 0 ? <p><strong>{productsWithoutVariants}</strong> produtos ainda nao possuem embalagem vendavel.</p> : null}
              </>
            )}
          </div>
        </article>
        <article className="panel">
          <div className="panel-header">
            <h2>Producao</h2>
            <Link href="/producao">Abrir modulo</Link>
          </div>
          <div className="compact-list">
            <p><strong>Formula</strong><span>Versao imutavel e receita ativa.</span></p>
            <p><strong>OP</strong><span>Reserva, consumo e produto gerado.</span></p>
            <p><strong>CQ</strong><span>Resultado, bloqueio e liberacao auditada.</span></p>
          </div>
        </article>
      </section>
    </CatalogShell>
  );
}
