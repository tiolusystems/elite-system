import Link from "next/link";

import {
  deactivateMateriaPrimaAction,
  updateMateriaPrimaIdentityAction,
  updateMateriaPrimaRegulatoryAction,
  updateMateriaPrimaSkuAction,
  updateMateriaPrimaStockPolicyAction,
  updateMateriaPrimaTechnicalAction
} from "@/app/cadastros/actions";
import { createGovernedMaterialAction, setMaterialInputTypeAction } from "@/app/cadastros/tipos-insumo/actions";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function MaterialsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const query = (singleParam(params.q) ?? "").trim().toLocaleLowerCase("pt-BR");
  const status = singleParam(params.status) ?? "all";
  const requestedId = Number(singleParam(params.selected));
  const activeUnits = catalog.units.filter((unit) => unit.status === "active");
  const activeInputTypes = catalog.inputTypes.filter((item) => item.status === "active");
  const filteredMaterials = catalog.materials.filter((material) => {
    const matchesQuery = !query || `${material.sku} ${material.name} ${material.legacyCode ?? ""}`.toLocaleLowerCase("pt-BR").includes(query);
    const matchesStatus = status === "all" || material.status === status;
    return matchesQuery && matchesStatus;
  });
  const selectedMaterial =
    catalog.materials.find((material) => material.id === requestedId) ?? filteredMaterials[0] ?? null;

  return (
    <CatalogShell
      active="materials"
      title="Matérias-primas e insumos"
      description="Identidade, classificação governada, unidade, densidade, estoque mínimo e informações regulatórias."
      source={catalog.source}
      error={catalog.error}
      actions={<a className="primary-button" href="#nova-mp">Nova MP</a>}
    >
      <CatalogFeedback result={singleParam(params.result)} />

      <form className="catalog-filter" method="get" aria-label="Filtros de matérias-primas">
        <label>
          Buscar
          <input name="q" defaultValue={singleParam(params.q) ?? ""} placeholder="SKU, nome ou código legado" />
        </label>
        <label>
          Status
          <select name="status" defaultValue={status}>
            <option value="all">Todos</option>
            <option value="active">Ativos</option>
            <option value="pending_review">Em revisao</option>
            <option value="inactive">Inativos</option>
          </select>
        </label>
        <button className="secondary-button" type="submit">Filtrar</button>
        <Link href="/cadastros/materias-primas">Limpar</Link>
      </form>

      <section className="catalog-split">
        <article className="panel catalog-list-panel">
          <div className="panel-header">
            <h2>Catalogo</h2>
            <span className="pill">{filteredMaterials.length}</span>
          </div>
          <div className="catalog-record-list">
            {filteredMaterials.map((material) => (
              <Link
                key={material.id}
                href={{ pathname: "/cadastros/materias-primas", query: { q: singleParam(params.q) ?? "", status, selected: material.id } }}
                aria-current={selectedMaterial?.id === material.id ? "page" : undefined}
              >
                <span>
                  <strong>{material.sku}</strong>
                  <small>{material.name}</small>
                </span>
                <span className="catalog-record-meta">
                  <StatusChip value={material.status} />
                  <small>{material.baseUnit}</small>
                </span>
              </Link>
            ))}
            {filteredMaterials.length === 0 ? <div className="empty-state"><strong>Nenhuma matéria-prima encontrada</strong><span>Ajuste os filtros ou cadastre uma nova matéria-prima.</span></div> : null}
          </div>
        </article>

        <article className="panel catalog-detail-panel" id="editar">
          {selectedMaterial ? (
            <>
              <div className="panel-header catalog-detail-header">
                <div>
                  <span className="eyebrow">{selectedMaterial.sku}</span>
                  <h2>{selectedMaterial.name}</h2>
                  <p>{selectedMaterial.inputTypeName} · {selectedMaterial.baseUnit}</p>
                </div>
                <StatusChip value={selectedMaterial.status} />
              </div>

              <div className="detail-facts">
                <p><span>Densidade</span><strong>{formatNumber(selectedMaterial.density)}</strong></p>
                <p><span>Estoque minimo</span><strong>{formatNumber(selectedMaterial.minimumStock)}</strong></p>
                <p><span>Tipo de insumo</span><strong>{selectedMaterial.inputTypeName}</strong></p>
                <p><span>NCM</span><strong>{selectedMaterial.ncm ?? "-"}</strong></p>
                <p><span>Atualizada</span><strong>{formatDate(selectedMaterial.updatedAt)}</strong></p>
              </div>

              <div className="catalog-editors">
                <details open>
                  <summary>Identidade</summary>
                  <form action={updateMateriaPrimaIdentityAction} className="compact-edit-form">
                    <TechnicalReturnInput />
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <input type="hidden" name="tipo" value={selectedMaterial.type ?? ""} />
                    <label>Nome<input name="nome" defaultValue={selectedMaterial.name} required /></label>
                    <label className="wide-field">Motivo<input name="motivo" required placeholder="Motivo da alteracao" /></label>
                    <button className="primary-button" type="submit">Salvar identidade</button>
                  </form>
                </details>

                <details open id="classificacao">
                  <summary>Classificação do insumo</summary>
                  <form action={setMaterialInputTypeAction} className="compact-edit-form">
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <label className="wide-field">
                      Tipo de insumo
                      <select name="tipo_insumo_id" defaultValue={selectedMaterial.inputTypeId ?? ""}>
                        <option value="">Tipo de insumo não definido</option>
                        {catalog.inputTypes
                          .filter((item) => item.status === "active" || item.id === selectedMaterial.inputTypeId)
                          .map((item) => <option key={item.id} value={item.id}>{item.name}{item.status === "inactive" ? " (inativo)" : ""}</option>)}
                      </select>
                    </label>
                    <label className="wide-field">Motivo<input name="motivo" required placeholder="Justificativa obrigatória" /></label>
                    <button className="primary-button" type="submit">Salvar classificação</button>
                  </form>
                  {selectedMaterial.inputTypeId === null ? <div className="notice-panel warning compact-notice"><strong>Classificação pendente</strong><span>Esta matéria-prima ainda não possui tipo de insumo definido.</span></div> : null}
                </details>

                <details>
                  <summary>SKU e legado</summary>
                  <form action={updateMateriaPrimaSkuAction} className="compact-edit-form">
                    <TechnicalReturnInput />
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <label>SKU<input name="sku_corrigido" defaultValue={selectedMaterial.sku} required /></label>
                    <label>Codigo legado<input name="codigo_legado" defaultValue={selectedMaterial.legacyCode ?? ""} /></label>
                    <label className="wide-field">Motivo<input name="motivo" required placeholder="Motivo da alteracao" /></label>
                    <button className="primary-button" type="submit">Salvar codigos</button>
                  </form>
                </details>

                <details>
                  <summary>Dados tecnicos</summary>
                  <form action={updateMateriaPrimaTechnicalAction} className="compact-edit-form">
                    <TechnicalReturnInput />
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <label>
                      Unidade base
                      <select name="unidade_base_estoque" defaultValue={selectedMaterial.baseUnit} required>
                        {activeUnits.map((unit) => <option key={unit.id} value={unit.code}>{unit.code} · {unit.name}</option>)}
                      </select>
                    </label>
                    <label>Densidade<input name="densidade" inputMode="decimal" defaultValue={selectedMaterial.density ?? ""} /></label>
                    <label className="wide-field">Motivo<input name="motivo" required placeholder="Motivo da alteracao" /></label>
                    <button className="primary-button" type="submit">Salvar dados tecnicos</button>
                  </form>
                </details>

                <details>
                  <summary>Politica de estoque</summary>
                  <form action={updateMateriaPrimaStockPolicyAction} className="compact-edit-form">
                    <TechnicalReturnInput />
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <label>Estoque minimo<input name="estoque_minimo" inputMode="decimal" defaultValue={selectedMaterial.minimumStock ?? 0} required /></label>
                    <label className="wide-field">Motivo<input name="motivo" required placeholder="Motivo da alteracao" /></label>
                    <button className="primary-button" type="submit">Salvar politica</button>
                  </form>
                </details>

                <details>
                  <summary>Regulatorio</summary>
                  <form action={updateMateriaPrimaRegulatoryAction} className="compact-edit-form">
                    <TechnicalReturnInput />
                    <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                    <label>NCM<input name="ncm" inputMode="numeric" defaultValue={selectedMaterial.ncm ?? ""} /></label>
                    <label>IBAMA<input name="ibama" defaultValue={selectedMaterial.ibama ?? ""} /></label>
                    <label>Codigo ADS<input name="codigo_ads" defaultValue={selectedMaterial.adsCode ?? ""} /></label>
                    <label>Motivo<input name="motivo" required placeholder="Motivo da alteracao" /></label>
                    <button className="primary-button" type="submit">Salvar regulatorio</button>
                  </form>
                </details>

                {selectedMaterial.status !== "inactive" ? (
                  <details className="danger-zone">
                    <summary>Desativar materia-prima</summary>
                    <form action={deactivateMateriaPrimaAction} className="compact-edit-form">
                      <TechnicalReturnInput />
                      <input type="hidden" name="materia_prima_id" value={selectedMaterial.id} />
                      <label className="wide-field">Motivo<input name="motivo" required placeholder="Motivo da desativacao" /></label>
                      <button className="danger-button" type="submit">Desativar</button>
                    </form>
                  </details>
                ) : null}
              </div>
            </>
          ) : (
            <div className="empty-state"><strong>Selecione uma matéria-prima</strong><span>Os detalhes e ações aparecerão aqui.</span></div>
          )}
        </article>
      </section>

      <section className="panel form-panel" id="nova-mp" aria-labelledby="nova-mp-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Novo registro</span>
            <h2 id="nova-mp-title">Cadastrar matéria-prima</h2>
          </div>
        </div>
        <form action={createGovernedMaterialAction}>
          <TechnicalReturnInput />
          <div className="form-grid">
            <label>SKU<input name="sku_corrigido" placeholder="MP-0001" required /></label>
            <label>Nome<input name="nome" required /></label>
            <label>Código legado<input name="codigo_legado" /></label>
            <label>
              Tipo de insumo
              <select name="tipo_insumo_id" defaultValue="">
                <option value="">Tipo de insumo não definido</option>
                {activeInputTypes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
              </select>
            </label>
            <label>
              Unidade base
              <select name="unidade_base_estoque" defaultValue="KG" required>
                {activeUnits.map((unit) => <option key={unit.id} value={unit.code}>{unit.code} · {unit.name}</option>)}
              </select>
            </label>
            <label>Densidade<input name="densidade" inputMode="decimal" /></label>
            <label>Estoque minimo<input name="estoque_minimo" inputMode="decimal" /></label>
            <label>
              Status
              <select name="status" defaultValue="active">
                <option value="active">Ativo</option>
                <option value="pending_review">Em revisao</option>
                <option value="inactive">Inativo</option>
              </select>
            </label>
            <label>NCM<input name="ncm" inputMode="numeric" /></label>
            <label>IBAMA<input name="ibama" /></label>
            <label>Codigo ADS<input name="codigo_ads" /></label>
          </div>
          <div className="form-footer">
            <span>Sem classificação, o registro ficará visível como pendência de revisão.</span>
            <button className="primary-button" type="submit">Salvar matéria-prima</button>
          </div>
        </form>
      </section>
    </CatalogShell>
  );
}

function TechnicalReturnInput() {
  return <input type="hidden" name="return_to" value="/cadastros/materias-primas" />;
}

function formatNumber(value: number | null): string {
  return value === null ? "-" : new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}
