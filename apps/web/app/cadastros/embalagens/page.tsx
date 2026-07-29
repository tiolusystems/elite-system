import Link from "next/link";

import { createEmbalagemAction } from "@/app/cadastros/actions";
import { PackageMaintenancePanel } from "@/app/cadastros/embalagens/package-maintenance-panel";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";
import { dataOriginLabel } from "@/lib/master-data-governance";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PackagesPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const query = (singleParam(params.q) ?? "").trim().toLocaleLowerCase("pt-BR");
  const mode = singleParam(params.modo);
  const selectedId = Number(singleParam(params.selected) ?? "");
  const filtered = catalog.packages.filter((item) =>
    !query || `${item.description} ${item.legacyCode ?? ""} ${item.materialLabel ?? ""}`.toLocaleLowerCase("pt-BR").includes(query)
  );
  const activeUnits = catalog.units.filter((unit) => unit.status === "active");
  const selectedPackage = catalog.packages.find((item) => item.id === selectedId) ?? null;
  const selectedVersions = selectedPackage
    ? catalog.packageVersions.filter((item) => item.packageId === selectedPackage.id)
    : [];
  const selectedVersionIds = new Set(selectedVersions.map((item) => item.id));
  const selectedComponents = catalog.packageComponents.filter((item) => selectedVersionIds.has(item.packageVersionId));
  const isCreating = mode === "novo";
  const isViewing = selectedPackage !== null && !isCreating;
  const isListing = !isCreating && !isViewing;
  const listHref = buildListHref(singleParam(params.q));

  return (
    <CatalogShell
      active="packages"
      title="Embalagens"
      description="Volumes comerciais e embalagens controladas como insumo da producao."
      source={catalog.source}
      error={catalog.error}
      actions={
        isListing ? (
          <Link className="primary-button" href="/cadastros/embalagens?modo=novo#nova-embalagem">Nova embalagem</Link>
        ) : (
          <Link className="secondary-button" href={listHref}>Voltar à consulta</Link>
        )
      }
    >
      <CatalogFeedback result={singleParam(params.result)} />

      <div className="catalog-workbench">
      {isListing ? (
      <section className="catalog-list-view" aria-label="Consulta de embalagens">
      <form className="catalog-filter single-search" method="get" aria-label="Filtro de embalagens">
        <label>Buscar<input name="q" defaultValue={singleParam(params.q) ?? ""} placeholder="Descricao, codigo ou MP vinculada" /></label>
        <button className="secondary-button" type="submit">Filtrar</button>
      </form>

      <section className="panel" aria-labelledby="packages-title">
        <div className="panel-header">
          <h2 id="packages-title">Catalogo de embalagens</h2>
          <span className="pill">{filtered.length}</span>
        </div>
        <div className="responsive-record-grid package-grid">
          {filtered.map((item) => (
            <article key={item.id}>
              <div><strong>{item.description}</strong><StatusChip value={item.status} /></div>
              <dl>
                <div><dt>Capacidade</dt><dd>{item.volumeLiters === null ? item.unit : `${formatNumber(item.volumeLiters)} L`}</dd></div>
                <div><dt>Estoque</dt><dd>{item.controlsStock ? "Controlado" : "Nao controlado"}</dd></div>
                <div><dt>MP vinculada</dt><dd>{item.materialLabel ?? "-"}</dd></div>
                <div><dt>Origem</dt><dd>{dataOriginLabel(item.source)}</dd></div>
              </dl>
              <Link className="record-open-link" href={`/cadastros/embalagens?selected=${item.id}#editar-embalagem`}>Abrir ficha</Link>
            </article>
          ))}
          {filtered.length === 0 ? <p className="empty-state">Nenhuma embalagem encontrada.</p> : null}
        </div>
      </section>
      </section>
      ) : null}

      {isViewing ? (
      <section className="catalog-detail-view">
      <PackageMaintenancePanel
        packageRecord={selectedPackage}
        versions={selectedVersions}
        components={selectedComponents}
        materials={catalog.materials}
        units={catalog.units}
      />
      </section>
      ) : null}

      {isCreating ? (
      <section className="panel form-panel catalog-create-view" id="nova-embalagem" aria-labelledby="new-package-title">
        <div className="panel-header"><div><span className="eyebrow">Novo registro</span><h2 id="new-package-title">Cadastrar embalagem</h2></div></div>
        <form action={createEmbalagemAction}>
          <input type="hidden" name="return_to" value="/cadastros/embalagens" />
          <div className="form-grid">
            <label>Descricao<input name="descricao" placeholder="Bombona 20 L" required /></label>
            <label>
              Unidade
              <select name="unidade" defaultValue="UN" required>
                {activeUnits.filter((unit) => unit.code.toUpperCase() === "UN").map((unit) => <option key={unit.id} value="UN">UN · {unit.name}</option>)}
              </select>
            </label>
            <label>Volume em litros<input name="volume_litros" inputMode="decimal" required /></label>
            <label>Codigo legado<input name="codigo_legado" /></label>
            <label>
              MP de estoque
              <select name="materia_prima_id" defaultValue="">
                <option value="">Nenhuma</option>
                {catalog.materials.filter((item) => item.status === "active").map((item) => (
                  <option key={item.id} value={item.id}>{item.sku} · {item.name}</option>
                ))}
              </select>
            </label>
            <label>
              Status
              <select name="status" defaultValue="active">
                <option value="active">Ativa</option>
                <option value="pending_review">Em revisao</option>
                <option value="inactive">Inativa</option>
              </select>
            </label>
            <label className="checkbox-line"><input name="controla_estoque" type="checkbox" value="1" />Controlar como insumo</label>
          </div>
          <div className="form-footer">
            <span>Embalagem controlada em estoque exige uma MP vinculada.</span>
            <button className="primary-button" type="submit">Salvar embalagem</button>
          </div>
        </form>
      </section>
      ) : null}
      </div>
    </CatalogShell>
  );
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function buildListHref(query: string | null): string {
  return query ? `/cadastros/embalagens?q=${encodeURIComponent(query)}` : "/cadastros/embalagens";
}
