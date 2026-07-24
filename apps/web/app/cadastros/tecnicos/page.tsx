import Link from "next/link";

import { CatalogShell } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

export const dynamic = "force-dynamic";

export default async function TechnicalCatalogOverviewPage() {
  const catalog = await getTechnicalCatalog();
  const pendingMaterials = catalog.materials.filter((item) => item.status === "pending_review").length;
  const productsWithoutVariants = catalog.products.filter(
    (product) => !catalog.saleItems.some((item) => item.productId === product.id)
  ).length;

  return (
    <CatalogShell
      active="overview"
      title="Cadastros da produção"
      description="Escolha o cadastro que deseja consultar ou alterar."
      source={catalog.source}
      error={catalog.error}
      actions={<Link className="primary-button" href="/cadastros/materias-primas#nova-mp">Cadastrar matéria-prima</Link>}
    >
      <section className="technical-entry-section" aria-labelledby="technical-entry-title">
        <div className="technical-entry-header">
          <span className="eyebrow">Acesso rápido</span>
          <h2 id="technical-entry-title">O que você precisa cadastrar?</h2>
        </div>
        <div className="technical-action-grid">
          <Link href="/cadastros/materias-primas">
            <strong>Matérias-primas</strong>
            <small>Insumos usados nas fórmulas e controlados no estoque.</small>
            {pendingMaterials > 0 ? <span>{pendingMaterials} para revisar</span> : null}
          </Link>
          <Link href="/cadastros/embalagens">
            <strong>Embalagens</strong>
            <small>Frascos, caixas, tampas e outros materiais de envase.</small>
          </Link>
          <Link href="/cadastros/produtos">
            <strong>Produtos PA/PI</strong>
            <small>Produtos intermediários, acabados e suas apresentações.</small>
            {productsWithoutVariants > 0 ? <span>{productsWithoutVariants} sem apresentação</span> : null}
          </Link>
          <Link href="/cadastros/grupos-produto">
            <strong>Grupos de produto</strong>
            <small>Famílias usadas para organizar produtos e relatórios.</small>
          </Link>
        </div>
      </section>

      <section className="two-column technical-lists">
        <article className="panel">
          <div className="panel-header">
            <h2>Configurações de produção</h2>
          </div>
          <nav className="technical-plain-links" aria-label="Configurações de produção">
            <Link href="/cadastros/unidades">
              <strong>Unidades de medida</strong>
              <span>kg, L e UN, com suas conversões.</span>
            </Link>
            <Link href="/cadastros/tipos-insumo">
              <strong>Tipos de insumo</strong>
              <span>Classificação usada nas matérias-primas.</span>
            </Link>
            <Link href="/producao/formulas">
              <strong>Fórmulas e garantias</strong>
              <span>Receitas e especificações dos produtos.</span>
            </Link>
          </nav>
        </article>
        <article className="panel">
          <div className="panel-header">
            <h2>Revisões pendentes</h2>
            {pendingMaterials > 0 ? (
              <Link href="/cadastros/materias-primas?status=pending_review">Abrir revisões</Link>
            ) : null}
          </div>
          <div className="compact-list">
            {pendingMaterials === 0 && productsWithoutVariants === 0 ? (
              <p className="empty-state">Nenhuma revisão pendente.</p>
            ) : (
              <>
                {pendingMaterials > 0 ? <p><strong>{pendingMaterials}</strong><span>matérias-primas aguardam revisão.</span></p> : null}
                {productsWithoutVariants > 0 ? <p><strong>{productsWithoutVariants}</strong><span>produtos ainda não possuem apresentação.</span></p> : null}
              </>
            )}
          </div>
        </article>
      </section>
    </CatalogShell>
  );
}
